#import "MGitModule.h"
#import <git2.h>
#import <React/RCTLog.h>
#import <CommonCrypto/CommonDigest.h> // For SHA-1 calculation

@implementation MGitModule

RCT_EXPORT_MODULE();

// Required for RCTEventEmitter
- (NSArray<NSString *> *)supportedEvents {
  return @[@"MGitProgress", @"MGitError"];
}

- (dispatch_queue_t)methodQueue {
  return dispatch_queue_create("com.mgitmodule.queue", DISPATCH_QUEUE_SERIAL);
}

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

// Initialize libgit2 when the module loads
- (instancetype)init {
  self = [super init];
  if (self) {
    git_libgit2_init();
  }
  return self;
}

// Cleanup libgit2 when the module is deallocated
- (void)dealloc {
  git_libgit2_shutdown();
}

#pragma mark - Utility Methods

// Convert NSError to JS object
- (NSDictionary *)errorObjectFromNSError:(NSError *)error {
  return @{
    @"code": @(error.code),
    @"domain": error.domain,
    @"message": error.localizedDescription,
    @"userInfo": error.userInfo ?: @{}
  };
}

// Handle libgit2 errors
- (NSError *)errorFromGitResult:(int)result {
  if (result >= 0) {
    return nil;
  }
  
  const git_error *error = git_error_last();
  NSString *message = error ? @(error->message) : @"Unknown git error";
  
  return [NSError errorWithDomain:@"MGitErrorDomain"
                             code:result
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - Git Operations

RCT_EXPORT_METHOD(clone:(NSString *)url
                  localPath:(NSString *)localPath
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  // Check parameters
  if (!url || !localPath) {
    reject(@"INVALID_PARAMS", @"URL and local path are required", nil);
    return;
  }
  
  // Create repo directory if it doesn't exist
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSURL *directoryURL = [NSURL fileURLWithPath:localPath];
  
  NSError *dirError;
  BOOL success = [fileManager createDirectoryAtURL:directoryURL
                      withIntermediateDirectories:YES
                                       attributes:nil
                                            error:&dirError];
  if (!success) {
    reject(@"DIR_ERROR", @"Failed to create directory", dirError);
    return;
  }
  
  // Create repository with libgit2
  git_repository *repo = NULL;
  git_clone_options clone_opts = GIT_CLONE_OPTIONS_INIT;
  
  // Setup clone options
  BOOL bareRepo = [options[@"bare"] boolValue];
  if (bareRepo) {
    clone_opts.bare = 1;
  }
  
  // Setup progress callback
  git_clone_options_init(&clone_opts, GIT_CLONE_OPTIONS_VERSION);
  clone_opts.fetch_opts.callbacks.transfer_progress = ^int(const git_transfer_progress *stats, void *payload) {
    // Report progress to JS
    [self sendEventWithName:@"MGitProgress" body:@{
      @"receivedObjects": @(stats->received_objects),
      @"totalObjects": @(stats->total_objects),
      @"indexedObjects": @(stats->indexed_objects),
      @"receivedBytes": @(stats->received_bytes)
    }];
    return 0;
  };
  
  // Perform the clone operation
  int result = git_clone(&repo, [url UTF8String], [localPath UTF8String], &clone_opts);
  
  if (result != 0) {
    NSError *error = [self errorFromGitResult:result];
    reject(@"CLONE_ERROR", @"Failed to clone repository", error);
    return;
  }
  
  // Free resources
  git_repository_free(repo);
  
  resolve(@{
    @"path": localPath,
    @"success": @YES
  });
}

RCT_EXPORT_METHOD(pull:(NSString *)repositoryPath
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  // Implementation of pull would go here
  // This would involve:
  // 1. Opening the repository
  // 2. Setting up fetch options
  // 3. Fetching from remote
  // 4. Merging or rebasing the changes
  
  // For brevity, I'm showing a simplified version
  NSTask *task = [[NSTask alloc] init];
  [task setCurrentDirectoryPath:repositoryPath];
  [task setLaunchPath:@"/usr/bin/git"];
  [task setArguments:@[@"pull"]];
  
  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:pipe];
  
  NSError *error;
  [task launchAndReturnError:&error];
  
  if (error) {
    reject(@"PULL_ERROR", @"Failed to pull changes", error);
    return;
  }
  
  NSFileHandle *file = [pipe fileHandleForReading];
  NSData *data = [file readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  
  resolve(@{
    @"output": output,
    @"success": @YES
  });
}

RCT_EXPORT_METHOD(commit:(NSString *)repositoryPath
                  message:(NSString *)message
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  
  NSString *authorName = options[@"authorName"] ?: options[@"author"];
  NSString *authorEmail = options[@"authorEmail"] ?: options[@"email"];
  NSString *nostrPubkey = options[@"nostrPubkey"];

  // If nostrPubkey is provided, use MGit commit
  if (nostrPubkey && nostrPubkey.length > 0) {
    [self createMCommit:repositoryPath
               message:message
            authorName:authorName
           authorEmail:authorEmail
          nostrPubkey:nostrPubkey
              resolver:resolve
              rejecter:reject];
    return;
  }

  NSTask *task = [[NSTask alloc] init];
  [task setCurrentDirectoryPath:repositoryPath];
  [task setLaunchPath:@"/usr/bin/git"];
  
  NSMutableArray *args = [NSMutableArray arrayWithObjects:@"commit", @"-m", message, nil];
  
  // Handle author if provided
  if (options[@"authorName"] && options[@"authorEmail"]) {
    NSString *author = [NSString stringWithFormat:@"%@<%@>", 
                        options[@"authorName"], 
                        options[@"authorEmail"]];
    [args addObject:@"--author"];
    [args addObject:author];
  }
  
  [task setArguments:args];
  
  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:pipe];
  
  NSError *error;
  [task launchAndReturnError:&error];
  
  if (error) {
    reject(@"COMMIT_ERROR", @"Failed to commit changes", error);
    return;
  }
  
  NSFileHandle *file = [pipe fileHandleForReading];
  NSData *data = [file readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  
  resolve(@{
    @"output": output,
    @"success": @YES
  });
}

// MGit specific command for show
RCT_EXPORT_METHOD(mgitShow:(NSString *)repositoryPath
                  commitRef:(NSString *)commitRef
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  if (!commitRef) {
    commitRef = @"HEAD"; // Default to HEAD if no commit reference provided
  }
  
  NSTask *task = [[NSTask alloc] init];
  [task setCurrentDirectoryPath:repositoryPath];
  
  // Use mgit executable path - would need to be configured or discovered
  NSString *mgitPath = options[@"mgitPath"] ?: @"/usr/local/bin/mgit";
  [task setLaunchPath:mgitPath];
  [task setArguments:@[@"show", commitRef]];
  
  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:pipe];
  
  NSError *error;
  [task launchAndReturnError:&error];
  
  if (error) {
    reject(@"SHOW_ERROR", @"Failed to show commit", error);
    return;
  }
  
  NSFileHandle *file = [pipe fileHandleForReading];
  NSData *data = [file readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  
  resolve(@{
    @"output": output,
    @"success": @YES
  });
}

// Calculate mcommit hash with Nostr pubkey
- (NSString *)calculateMCommitHash:(git_commit *)commit 
                    parentMGitHashes:(NSArray<NSString *> *)parentMGitHashes 
                    pubkey:(NSString *)pubkey {
    // Create SHA-1 hasher
    NSMutableData *hashData = [NSMutableData data];
    
    // Include the tree hash (similar to the Go implementation)
    const git_oid *treeHash = git_commit_tree_id(commit);
    [hashData appendBytes:treeHash->id length:20]; // SHA-1 is 20 bytes
    
    // Include all parent MGit hashes
    for (NSString *parentHashStr in parentMGitHashes) {
        // Convert hex string to bytes
        NSMutableData *parentHashData = [NSMutableData dataWithLength:20];
        char bytes[20];
        [self hexToBytes:parentHashStr bytes:bytes];
        [hashData appendBytes:bytes length:20];
    }
    
    // Include the author information with pubkey
    const git_signature *author = git_commit_author(commit);
    NSString *authorStr = [NSString stringWithFormat:@"%s <%s> %lld %@", 
                          author->name, 
                          author->email, 
                          (long long)author->when.time,
                          pubkey];
    [hashData appendData:[authorStr dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Include committer information
    const git_signature *committer = git_commit_committer(commit);
    NSString *committerStr = [NSString stringWithFormat:@"%s <%s> %lld %@", 
                             committer->name, 
                             committer->email, 
                             (long long)committer->when.time,
                             pubkey];
    [hashData appendData:[committerStr dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Include the commit message
    const char *message = git_commit_message(commit);
    [hashData appendData:[[NSString stringWithUTF8String:message] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Calculate SHA-1 hash
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(hashData.bytes, (CC_LONG)hashData.length, digest);
    
    // Convert to hex string
    NSMutableString *hexString = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hexString appendFormat:@"%02x", digest[i]];
    }
    
    return hexString;
}

// Helper: Convert hex string to bytes
- (void)hexToBytes:(NSString *)hexString bytes:(char *)bytes {
    NSUInteger length = hexString.length;
    char buffer[3] = {'\0', '\0', '\0'};
    
    for (NSUInteger i = 0; i < length / 2; i++) {
        buffer[0] = [hexString characterAtIndex:i * 2];
        buffer[1] = [hexString characterAtIndex:i * 2 + 1];
        bytes[i] = strtol(buffer, NULL, 16);
    }
}

// Create an MGit commit with Nostr pubkey
RCT_EXPORT_METHOD(createMCommit:(NSString *)repositoryPath
                  message:(NSString *)message
                  authorName:(NSString *)authorName
                  authorEmail:(NSString *)authorEmail
                  nostrPubkey:(NSString *)nostrPubkey
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Check parameters
    if (!repositoryPath || !message || !authorName || !authorEmail) {
        reject(@"INVALID_PARAMS", @"Required parameters missing", nil);
        return;
    }
    
    // Create git repository object
    git_repository *repo = NULL;
    int error = git_repository_open(&repo, [repositoryPath UTF8String]);
    if (error < 0) {
        const git_error *libgitError = git_error_last();
        reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
        return;
    }
    
    // Create signature for author and committer
    git_signature *author = NULL;
    git_signature *committer = NULL;
    time_t currentTime = time(NULL);
    
    // Create signature using current time
    error = git_signature_new(&author, 
                             [authorName UTF8String], 
                             [authorEmail UTF8String], 
                             currentTime, 
                             0); // Offset from UTC in minutes
    
    if (error < 0) {
        git_repository_free(repo);
        const git_error *libgitError = git_error_last();
        reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
        return;
    }
    
    // Use same signature for committer
    error = git_signature_dup(&committer, author);
    if (error < 0) {
        git_signature_free(author);
        git_repository_free(repo);
        const git_error *libgitError = git_error_last();
        reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
        return;
    }
    
    // Get the index (staging area)
    git_index *index = NULL;
    error = git_repository_index(&index, repo);
    if (error < 0) {
        git_signature_free(author);
        git_signature_free(committer);
        git_repository_free(repo);
        const git_error *libgitError = git_error_last();
        reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
        return;
    }
    
    // Write the index tree
    git_oid tree_id;
    error = git_index_write_tree(&tree_id, index);
    if (error < 0) {
        git_index_free(index);
        git_signature_free(author);
        git_signature_free(committer);
        git_repository_free(repo);
        const git_error *libgitError = git_error_last();
        reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
        return;
    }
    
    // Get the tree object
    git_tree *tree = NULL;
    error = git_tree_lookup(&tree, repo, &tree_id);
    if (error < 0) {
        git_index_free(index);
        git_signature_free(author);
        git_signature_free(committer);
        git_repository_free(repo);
        const git_error *libgitError = git_error_last();
        reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
        return;
    }
    
    // Get the parent commits
    git_reference *head_ref = NULL;
    error = git_repository_head(&head_ref, repo);
    
    NSMutableArray<NSString *> *parentMGitHashes = [NSMutableArray array];
    git_oid parent_id;
    git_commit *parent = NULL;
    
    if (error == 0) {
        // We have a HEAD reference
        const git_oid *head_oid = git_reference_target(head_ref);
        error = git_commit_lookup(&parent, repo, head_oid);
        
        if (error == 0) {
            // Create the standard Git commit
            git_oid commit_id;
            error = git_commit_create(&commit_id, 
                                    repo, 
                                    "HEAD", 
                                    author, 
                                    committer, 
                                    "UTF-8", 
                                    [message UTF8String], 
                                    tree, 
                                    1, 
                                    (const git_commit **)&parent);
            
            if (error == 0) {
                // Get the newly created commit
                git_commit *new_commit = NULL;
                git_commit_lookup(&new_commit, repo, &commit_id);
                
                // Calculate MGit hash
                NSString *gitHash = [self gitOidToString:&commit_id];
                
                // We would look up parent MGit hashes here from storage
                // For now, just use git hashes as placeholder
                [parentMGitHashes addObject:[self gitOidToString:git_commit_parent_id(new_commit, 0)]];
                
                NSString *mgitHash = [self calculateMCommitHash:new_commit
                                                 parentMGitHashes:parentMGitHashes
                                                 pubkey:nostrPubkey];
                
                // Here we would store the mapping between Git hash and MGit hash
                [self storeMGitMapping:gitHash mgitHash:mgitHash pubkey:nostrPubkey inRepo:repositoryPath];
                
                // Clean up
                git_commit_free(new_commit);
                
                // Resolve with success and hash information
                resolve(@{
                    @"gitHash": gitHash,
                    @"mgitHash": mgitHash,
                    @"success": @YES
                });
            } else {
                const git_error *libgitError = git_error_last();
                reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
            }
            
            git_commit_free(parent);
        } else {
            // No parent commit (first commit in repo)
            git_oid commit_id;
            error = git_commit_create(&commit_id, 
                                    repo, 
                                    "HEAD", 
                                    author, 
                                    committer, 
                                    "UTF-8", 
                                    [message UTF8String], 
                                    tree, 
                                    0, 
                                    NULL);
                                    
            if (error == 0) {
                // Get the newly created commit
                git_commit *new_commit = NULL;
                git_commit_lookup(&new_commit, repo, &commit_id);
                
                // Calculate MGit hash
                NSString *gitHash = [self gitOidToString:&commit_id];
                NSString *mgitHash = [self calculateMCommitHash:new_commit
                                                 parentMGitHashes:@[]
                                                 pubkey:nostrPubkey];
                
                // Store mapping
                [self storeMGitMapping:gitHash mgitHash:mgitHash pubkey:nostrPubkey inRepo:repositoryPath];
                
                // Clean up
                git_commit_free(new_commit);
                
                // Resolve with success and hash information
                resolve(@{
                    @"gitHash": gitHash,
                    @"mgitHash": mgitHash,
                    @"success": @YES
                });
            } else {
                const git_error *libgitError = git_error_last();
                reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
            }
        }
    } else {
        // No HEAD yet (empty repository)
        git_oid commit_id;
        error = git_commit_create(&commit_id, 
                                repo, 
                                "HEAD", 
                                author, 
                                committer, 
                                "UTF-8", 
                                [message UTF8String], 
                                tree, 
                                0, 
                                NULL);
                                
        if (error == 0) {
            // Get the newly created commit
            git_commit *new_commit = NULL;
            git_commit_lookup(&new_commit, repo, &commit_id);
            
            // Calculate MGit hash
            NSString *gitHash = [self gitOidToString:&commit_id];
            NSString *mgitHash = [self calculateMCommitHash:new_commit
                                             parentMGitHashes:@[]
                                             pubkey:nostrPubkey];
            
            // Store mapping
            [self storeMGitMapping:gitHash mgitHash:mgitHash pubkey:nostrPubkey inRepo:repositoryPath];
            
            // Clean up
            git_commit_free(new_commit);
            
            // Resolve with success and hash information
            resolve(@{
                @"gitHash": gitHash,
                @"mgitHash": mgitHash,
                @"success": @YES
            });
        } else {
            const git_error *libgitError = git_error_last();
            reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
        }
    }
    
    // Clean up resources
    if (head_ref) git_reference_free(head_ref);
    git_tree_free(tree);
    git_index_free(index);
    git_signature_free(author);
    git_signature_free(committer);
    git_repository_free(repo);
}

// Helper: Convert git_oid to NSString
- (NSString *)gitOidToString:(const git_oid *)oid {
    char hash_string[GIT_OID_HEXSZ + 1] = {0};
    git_oid_fmt(hash_string, oid);
    return [NSString stringWithUTF8String:hash_string];
}

// Store mapping between Git hash and MGit hash
- (void)storeMGitMapping:(NSString *)gitHash 
                mgitHash:(NSString *)mgitHash 
                  pubkey:(NSString *)pubkey 
                  inRepo:(NSString *)repoPath {
    // Create .mgit/mappings directory
    NSString *mgitDir = [repoPath stringByAppendingPathComponent:@".mgit"];
    NSString *mappingsDir = [mgitDir stringByAppendingPathComponent:@"mappings"];
    NSString *mappingsFile = [mappingsDir stringByAppendingPathComponent:@"hash_mappings.json"];
    
    // Create directories if they don't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:mgitDir]) {
        [fileManager createDirectoryAtPath:mgitDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![fileManager fileExistsAtPath:mappingsDir]) {
        [fileManager createDirectoryAtPath:mappingsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // Load existing mappings if available
    NSMutableArray *mappings = [NSMutableArray array];
    if ([fileManager fileExistsAtPath:mappingsFile]) {
        NSData *data = [NSData dataWithContentsOfFile:mappingsFile];
        if (data) {
            mappings = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!mappings) {
                mappings = [NSMutableArray array];
            }
        }
    }
    
    // Create new mapping
    NSDictionary *mapping = @{
        @"git_hash": gitHash,
        @"mgit_hash": mgitHash,
        @"pubkey": pubkey
    };
    
    // Check if mapping already exists
    BOOL foundExisting = NO;
    for (NSUInteger i = 0; i < mappings.count; i++) {
        NSDictionary *existingMapping = mappings[i];
        if ([existingMapping[@"git_hash"] isEqualToString:gitHash] ||
            [existingMapping[@"mgit_hash"] isEqualToString:mgitHash]) {
            mappings[i] = mapping;
            foundExisting = YES;
            break;
        }
    }
    
    // Add new mapping if not found
    if (!foundExisting) {
        [mappings addObject:mapping];
    }
    
    // Save the mappings
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:mappings options:NSJSONWritingPrettyPrinted error:nil];
    [jsonData writeToFile:mappingsFile atomically:YES];
    
    // Also save to nostr_mappings.json for compatibility
    NSString *nostrMappingsFile = [mgitDir stringByAppendingPathComponent:@"nostr_mappings.json"];
    [jsonData writeToFile:nostrMappingsFile atomically:YES];
}

@end
