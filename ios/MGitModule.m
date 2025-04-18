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
                           [authorName UTF8String] ?: "Git User", 
                           [authorEmail UTF8String] ?: "git@example.com", 
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
  
  git_oid commit_id;
  
  if (error == 0) {
    // We have a HEAD reference
    const git_oid *head_oid = git_reference_target(head_ref);
    git_commit *parent = NULL;
    error = git_commit_lookup(&parent, repo, head_oid);
    
    if (error == 0) {
      // Create the commit with parent
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
      
      git_commit_free(parent);
    } else {
      // No parent commit (first commit in repo)
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
    }
  } else {
    // No HEAD yet (empty repository)
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
  }
  
  if (error < 0) {
    if (head_ref) git_reference_free(head_ref);
    git_tree_free(tree);
    git_index_free(index);
    git_signature_free(author);
    git_signature_free(committer);
    git_repository_free(repo);
    
    const git_error *libgitError = git_error_last();
    reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
    return;
  }
  
  // Get hash as string
  char hash_string[GIT_OID_HEXSZ + 1] = {0};
  git_oid_fmt(hash_string, &commit_id);
  NSString *commitHash = [NSString stringWithUTF8String:hash_string];
  
  // Clean up resources
  if (head_ref) git_reference_free(head_ref);
  git_tree_free(tree);
  git_index_free(index);
  git_signature_free(author);
  git_signature_free(committer);
  git_repository_free(repo);
  
  // Resolve with success and hash information
  resolve(@{
    @"hash": commitHash,
    @"success": @YES
  });
}

/**
* mgit Core Functions
*/

/**
  Uses libgit2 to read the Git repository data
  Looks up the corresponding MGit hash and nostr pubkey from the mappings file
  Formats the output to match the example you provided
  Generates a Git diff for the changes
  Returns the formatted text output
*/
RCT_EXPORT_METHOD(mgitShow:(NSString *)repositoryPath
                  commitRef:(NSString *)commitRef
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  if (!commitRef) {
    commitRef = @"HEAD"; // Default to HEAD if no commit reference provided
  }
  
  // Open the repository
  git_repository *repo = NULL;
  int error = git_repository_open(&repo, [repositoryPath UTF8String]);
  if (error < 0) {
    const git_error *libgitError = git_error_last();
    reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
    return;
  }
  
  // Resolve the reference (can be branch name, tag, or commit hash)
  git_object *obj = NULL;
  error = git_revparse_single(&obj, repo, [commitRef UTF8String]);
  if (error < 0) {
    git_repository_free(repo);
    const git_error *libgitError = git_error_last();
    reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
    return;
  }
  
  // Get the commit from the resolved object
  git_commit *commit = NULL;
  error = git_commit_lookup(&commit, repo, git_object_id(obj));
  git_object_free(obj);
  
  if (error < 0) {
    git_repository_free(repo);
    const git_error *libgitError = git_error_last();
    reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
    return;
  }
  
  // Get the commit details
  const git_signature *author = git_commit_author(commit);
  const char *message = git_commit_message(commit);
  
  // Get Git hash
  NSString *gitHash = [self gitOidToString:git_commit_id(commit)];
  
  // Look up the MGit hash and nostr pubkey
  NSString *mgitHash = @"";
  NSString *nostrPubkey = @"";
  NSArray *parentMGitHashes = @[];
  
  // Load hash mappings file
  NSString *mappingsPath = [repositoryPath stringByAppendingPathComponent:@".mgit/mappings/hash_mappings.json"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:mappingsPath]) {
    NSData *mappingsData = [NSData dataWithContentsOfFile:mappingsPath];
    if (mappingsData) {
      NSError *jsonError;
      NSArray *mappings = [NSJSONSerialization JSONObjectWithData:mappingsData options:0 error:&jsonError];
      
      if (!jsonError) {
        // Find matching mapping for this commit
        for (NSDictionary *mapping in mappings) {
          if ([mapping[@"git_hash"] isEqualToString:gitHash]) {
            mgitHash = mapping[@"mgit_hash"];
            nostrPubkey = mapping[@"pubkey"];
            break;
          }
        }
        
        // Now find parent mappings
        NSMutableArray *parentMGits = [NSMutableArray array];
        int parentCount = git_commit_parentcount(commit);
        
        for (int i = 0; i < parentCount; i++) {
          git_commit *parent = NULL;
          git_commit_parent(&parent, commit, i);
          
          if (parent) {
            NSString *parentGitHash = [self gitOidToString:git_commit_id(parent)];
            
            // Find MGit hash for this parent
            for (NSDictionary *mapping in mappings) {
              if ([mapping[@"git_hash"] isEqualToString:parentGitHash]) {
                [parentMGits addObject:mapping[@"mgit_hash"]];
                break;
              }
            }
            
            git_commit_free(parent);
          }
        }
        
        parentMGitHashes = [NSArray arrayWithArray:parentMGits];
      }
    }
  }
  
  // Prepare output format similar to the Go implementation
  NSMutableString *output = [NSMutableString string];
  
  // If we found an MGit hash, use that as primary
  if (mgitHash.length > 0) {
    [output appendFormat:@"commit %@\n", mgitHash];
    [output appendFormat:@"git-commit %@\n", gitHash];
  } else {
    // Otherwise use Git hash
    [output appendFormat:@"commit %@\n", gitHash];
  }
  
  // Add author info with nostr pubkey if available
  if (nostrPubkey.length > 0) {
    [output appendFormat:@"Author: %s <%s> <%@>\n", author->name, author->email, nostrPubkey];
  } else {
    [output appendFormat:@"Author: %s <%s>\n", author->name, author->email];
  }
  
  // Add date
  NSDate *date = [NSDate dateWithTimeIntervalSince1970:author->when.time];
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setDateFormat:@"EEE MMM d HH:mm:ss yyyy Z"];
  [output appendFormat:@"Date:   %@\n\n", [formatter stringFromDate:date]];
  
  // Add commit message
  [output appendFormat:@"    %s\n", message];
  
  // Add parent information if available
  if (parentMGitHashes.count > 0) {
    [output appendString:@"\nParents:\n"];
    for (NSString *parentHash in parentMGitHashes) {
      [output appendFormat:@"  %@\n", parentHash];
    }
    [output appendString:@"\n"];
  }
  
  // Generate diff
  git_tree *commitTree = NULL;
  error = git_commit_tree(&commitTree, commit);
  
  if (error == 0) {
    git_tree *parentTree = NULL;
    
    // Get parent tree if available
    if (git_commit_parentcount(commit) > 0) {
      git_commit *parent = NULL;
      git_commit_parent(&parent, commit, 0);
      git_commit_tree(&parentTree, parent);
      git_commit_free(parent);
    }
    
    // Create diff options
    git_diff_options diff_opts = GIT_DIFF_OPTIONS_INIT;
    
    // Create the diff
    git_diff *diff = NULL;
    if (parentTree) {
      error = git_diff_tree_to_tree(&diff, repo, parentTree, commitTree, &diff_opts);
    } else {
      error = git_diff_tree_to_tree(&diff, repo, NULL, commitTree, &diff_opts);
    }
    
    if (error == 0) {
      // Convert diff to patch format
      git_patch *patches[1024]; // Assuming no more than 1024 files changed
      size_t patchCount = 0;
      
      error = git_diff_get_patches(patches, &patchCount, diff, 1024);
      
      if (error == 0) {
        // Add each patch to output
        for (size_t i = 0; i < patchCount; i++) {
          git_buf patchBuf = {0};
          git_patch_to_buf(&patchBuf, patches[i]);
          
          [output appendFormat:@"%s", patchBuf.ptr];
          
          git_buf_dispose(&patchBuf);
          git_patch_free(patches[i]);
        }
      }
      
      git_diff_free(diff);
    }
    
    if (parentTree) git_tree_free(parentTree);
    git_tree_free(commitTree);
  }
  
  // Clean up
  git_commit_free(commit);
  git_repository_free(repo);
  
  // Return the formatted output
  resolve(@{
    @"output": output,
    @"success": @YES
  });
}

// Get MGit commit log directly from MGit storage (.mgit)
RCT_EXPORT_METHOD(mgitLog:(NSString *)repositoryPath
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  // Check if the .mgit directory exists
  NSString *mgitDir = [repositoryPath stringByAppendingPathComponent:@".mgit"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:mgitDir]) {
    reject(@"MGIT_ERROR", @"Not an MGit repository or .mgit directory not found", nil);
    return;
  }
  
  // Get the HEAD reference
  NSString *headPath = [mgitDir stringByAppendingPathComponent:@"HEAD"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:headPath]) {
    reject(@"MGIT_ERROR", @"MGit HEAD not found", nil);
    return;
  }
  
  // Read the HEAD file
  NSString *headContent = [NSString stringWithContentsOfFile:headPath encoding:NSUTF8StringEncoding error:nil];
  NSString *headRef;
  NSString *headHash;
  
  if ([headContent hasPrefix:@"ref: "]) {
    // HEAD points to a branch reference
    headRef = [headContent substringFromIndex:5]; // Skip "ref: "
    NSString *refPath = [mgitDir stringByAppendingPathComponent:headRef];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:refPath]) {
      headHash = [NSString stringWithContentsOfFile:refPath encoding:NSUTF8StringEncoding error:nil];
    }
  } else {
    // HEAD is detached and points directly to a commit
    headHash = headContent;
  }
  
  if (!headHash) {
    reject(@"MGIT_ERROR", @"Failed to resolve MGit HEAD reference", nil);
    return;
  }
  
  // Get max count if specified
  NSInteger maxCount = [options[@"maxCount"] integerValue];
  if (maxCount <= 0) {
    maxCount = 100; // Default to 100 commits
  }
  
  // Start traversing from HEAD
  NSMutableArray *commits = [NSMutableArray array];
  NSMutableSet *visitedHashes = [NSMutableSet set];
  NSMutableArray *queue = [NSMutableArray arrayWithObject:headHash];
  
  while (queue.count > 0 && commits.count < maxCount) {
    NSString *currentHash = queue[0];
    [queue removeObjectAtIndex:0];
    
    // Skip if already visited
    if ([visitedHashes containsObject:currentHash]) {
      continue;
    }
    
    [visitedHashes addObject:currentHash];
    
    // Get the MGit commit object
    NSString *objectDir = [mgitDir stringByAppendingPathComponent:@"objects"];
    NSString *prefixDir = [objectDir stringByAppendingPathComponent:[currentHash substringToIndex:2]];
    NSString *objectPath = [prefixDir stringByAppendingPathComponent:[currentHash substringFromIndex:2]];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:objectPath]) {
      NSData *objectData = [NSData dataWithContentsOfFile:objectPath];
      
      if (objectData) {
        NSError *jsonError;
        NSDictionary *mgitCommit = [NSJSONSerialization JSONObjectWithData:objectData options:0 error:&jsonError];
        
        if (mgitCommit && !jsonError) {
          // Add to commits array
          [commits addObject:mgitCommit];
          
          // Add parent hashes to queue
          NSArray *parents = mgitCommit[@"parent_hashes"];
          if (parents) {
            [queue addObjectsFromArray:parents];
          }
        }
      }
    }
  }
  
  resolve(@{@"commits": commits});
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

// MGit clone implementation - performs Git clone and sets up MGit metadata
RCT_EXPORT_METHOD(mgitClone:(NSString *)url
                  localPath:(NSString *)localPath
                  token:(NSString *)token
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Check parameters
    if (!url || !localPath) {
        reject(@"INVALID_PARAMS", @"URL and local path are required", nil);
        return;
    }
    
    // Extract repo ID from URL
    NSString *repoId = [self extractRepoIdFromURL:url];
    NSString *serverBaseURL = [self extractServerBaseURLFromURL:url];
    
    if (!repoId) {
        reject(@"INVALID_URL", @"Could not extract repository ID from URL", nil);
        return;
    }
    
    // Set up progress tracking
    __block BOOL cloneCompleted = NO;
    __block NSError *cloneError = nil;
    
    // Step 1: Fetch repository information
    [self sendEventWithName:@"MGitProgress" body:@{
        @"stage": @"metadata",
        @"message": @"Fetching repository metadata..."
    }];
    
    [self fetchRepositoryInfo:serverBaseURL repoId:repoId token:token completion:^(NSDictionary *repoInfo, NSError *error) {
        if (error) {
            reject(@"FETCH_ERROR", @"Failed to fetch repository information", error);
            return;
        }
        
        // Step 2: Clone the Git repository
        [self sendEventWithName:@"MGitProgress" body:@{
            @"stage": @"clone",
            @"message": @"Cloning Git repository..."
        }];
        
        // Create repository with libgit2
        git_repository *repo = NULL;
        git_clone_options clone_opts = GIT_CLONE_OPTIONS_INIT;
        
        // Setup clone options
        BOOL bareRepo = [options[@"bare"] boolValue];
        if (bareRepo) {
            clone_opts.bare = 1;
        }
        
        // Setup authentication if token is provided
        if (token && [token length] > 0) {
            // Add HTTP header for token authentication
            git_strarray custom_headers = {0};
            char *header = NULL;
            
            NSString *authHeader = [NSString stringWithFormat:@"Authorization: Bearer %@", token];
            header = strdup([authHeader UTF8String]);
            
            char *headers[1] = { header };
            custom_headers.strings = headers;
            custom_headers.count = 1;
            
            clone_opts.fetch_opts.custom_headers = custom_headers;
        }
        
        // Setup progress callback
        __block int total_objects = 0;
        __block int received_objects = 0;
        
        git_clone_options_init(&clone_opts, GIT_CLONE_OPTIONS_VERSION);
        clone_opts.fetch_opts.callbacks.transfer_progress = ^int(const git_transfer_progress *stats, void *payload) {
            // Report progress to JS
            total_objects = stats->total_objects;
            received_objects = stats->received_objects;
            
            [self sendEventWithName:@"MGitProgress" body:@{
                @"stage": @"download",
                @"receivedObjects": @(stats->received_objects),
                @"totalObjects": @(stats->total_objects),
                @"indexedObjects": @(stats->indexed_objects),
                @"receivedBytes": @(stats->received_bytes)
            }];
            return 0;
        };
        
        // Prepare Git URL
        NSString *gitURL = [NSString stringWithFormat:@"%@/api/mgit/repos/%@", serverBaseURL, repoId];
        
        // Perform the clone operation
        int result = git_clone(&repo, [gitURL UTF8String], [localPath UTF8String], &clone_opts);
        
        // Clean up custom headers
        if (token && [token length] > 0) {
            free(clone_opts.fetch_opts.custom_headers.strings[0]);
        }
        
        if (result != 0) {
            NSError *error = [self errorFromGitResult:result];
            reject(@"CLONE_ERROR", @"Failed to clone repository", error);
            return;
        }
        
        // Step 3: Fetch MGit metadata
        [self sendEventWithName:@"MGitProgress" body:@{
            @"stage": @"metadata",
            @"message": @"Fetching MGit metadata..."
        }];
        
        [self fetchMGitMetadata:serverBaseURL repoId:repoId token:token completion:^(NSData *mappingsData, NSError *error) {
            if (error) {
                // Even if metadata fetch fails, we still have the Git repository
                NSLog(@"Warning: Failed to fetch MGit metadata: %@", error);
            }
            
            // Step 4: Set up MGit structure
            [self sendEventWithName:@"MGitProgress" body:@{
                @"stage": @"setup",
                @"message": @"Setting up MGit repository structure..."
            }];
            
            // Free Git repository
            git_repository_free(repo);
            
            // Setup MGit directories and files
            [self setupMGitStructure:localPath withMappings:mappingsData repoInfo:repoInfo completion:^(NSError *error) {
                if (error) {
                    reject(@"SETUP_ERROR", @"Failed to set up MGit repository structure", error);
                    return;
                }
                
                // Step 5: Reconstruct MGit objects
                [self sendEventWithName:@"MGitProgress" body:@{
                    @"stage": @"reconstruct",
                    @"message": @"Reconstructing MGit objects..."
                }];
                
                [self reconstructMGitObjects:localPath completion:^(NSError *error) {
                    if (error) {
                        NSLog(@"Warning: Could not fully reconstruct MGit objects: %@", error);
                    }
                    
                    // Done!
                    [self sendEventWithName:@"MGitProgress" body:@{
                        @"stage": @"complete",
                        @"message": @"Clone completed successfully"
                    }];
                    
                    resolve(@{
                        @"path": localPath,
                        @"repoId": repoId,
                        @"success": @YES
                    });
                }];
            }];
        }];
    }];
}

// MGit push implementation - pushes both Git changes and MGit metadata
RCT_EXPORT_METHOD(mgitPush:(NSString *)repositoryPath
                  remoteName:(NSString *)remoteName
                  refspec:(NSString *)refspec
                  token:(NSString *)token
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Check parameters
    if (!repositoryPath) {
        reject(@"INVALID_PARAMS", @"Repository path is required", nil);
        return;
    }
    
    if (!remoteName || [remoteName length] == 0) {
        remoteName = @"origin"; // Default remote name
    }
    
    if (!refspec || [refspec length] == 0) {
        refspec = @"HEAD"; // Default to pushing HEAD
    }
    
    // Set up progress tracking
    [self sendEventWithName:@"MGitProgress" body:@{
        @"stage": @"push",
        @"message": @"Preparing to push changes..."
    }];
    
    // Open the repository
    git_repository *repo = NULL;
    int error = git_repository_open(&repo, [repositoryPath UTF8String]);
    if (error != 0) {
        NSError *gitError = [self errorFromGitResult:error];
        reject(@"PUSH_ERROR", @"Failed to open repository", gitError);
        return;
    }
    
    // Lookup the remote
    git_remote *remote = NULL;
    error = git_remote_lookup(&remote, repo, [remoteName UTF8String]);
    if (error != 0) {
        git_repository_free(repo);
        NSError *gitError = [self errorFromGitResult:error];
        reject(@"PUSH_ERROR", @"Failed to lookup remote", gitError);
        return;
    }
    
    // Setup push options
    git_push_options push_opts = GIT_PUSH_OPTIONS_INIT;
    git_push_options_init(&push_opts, GIT_PUSH_OPTIONS_VERSION);
    
    // Configure authentication with token if provided
    if (token && [token length] > 0) {
        // Add HTTP header for token authentication
        git_strarray custom_headers = {0};
        char *header = NULL;
        
        NSString *authHeader = [NSString stringWithFormat:@"Authorization: Bearer %@", token];
        header = strdup([authHeader UTF8String]);
        
        char *headers[1] = { header };
        custom_headers.strings = headers;
        custom_headers.count = 1;
        
        push_opts.headers = custom_headers;
    }
    
    // Set up progress callback
    push_opts.callbacks.transfer_progress = ^int(unsigned int current, unsigned int total, size_t bytes, void *payload) {
        [self sendEventWithName:@"MGitProgress" body:@{
            @"stage": @"upload",
            @"current": @(current),
            @"total": @(total),
            @"bytes": @(bytes)
        }];
        return 0;
    };
    
    // Configure the references to push
    git_strarray refspecs = {0};
    char *refspecStr = strdup([refspec UTF8String]);
    char *refspecsArray[1] = { refspecStr };
    refspecs.strings = refspecsArray;
    refspecs.count = 1;
    
    // Perform the push
    [self sendEventWithName:@"MGitProgress" body:@{
        @"stage": @"push",
        @"message": @"Pushing changes to remote..."
    }];
    
    error = git_remote_push(remote, &refspecs, &push_opts);
    
    // Clean up custom headers if used
    if (token && [token length] > 0) {
        free(push_opts.headers.strings[0]);
    }
    
    // Clean up refspecs
    free(refspecStr);
    
    // Handle push result
    if (error != 0) {
        git_remote_free(remote);
        git_repository_free(repo);
        NSError *gitError = [self errorFromGitResult:error];
        reject(@"PUSH_ERROR", @"Failed to push changes", gitError);
        return;
    }
    
    // Step 2: Push MGit metadata if available
    [self sendEventWithName:@"MGitProgress" body:@{
        @"stage": @"metadata",
        @"message": @"Pushing MGit metadata..."
    }];
    
    // Check if we have MGit metadata to push
    NSString *mgitDir = [repositoryPath stringByAppendingPathComponent:@".mgit"];
    BOOL hasMgitMetadata = [[NSFileManager defaultManager] fileExistsAtPath:mgitDir];
    
    if (hasMgitMetadata) {
        // Get remote URL information
        const char *remoteUrl = git_remote_url(remote);
        if (!remoteUrl) {
            // Clean up and return success with warning
            git_remote_free(remote);
            git_repository_free(repo);
            
            NSLog(@"Warning: Could not get remote URL for pushing MGit metadata");
            resolve(@{
                @"success": @YES,
                @"gitPushSuccess": @YES,
                @"metadataPushSuccess": @NO,
                @"warning": @"Could not push MGit metadata - remote URL not available"
            });
            return;
        }
        
        NSString *remoteUrlStr = [NSString stringWithUTF8String:remoteUrl];
        
        // Parse remote URL to extract server base URL and repo ID
        NSString *serverBaseURL = [self extractServerBaseURLFromURL:remoteUrlStr];
        NSString *repoId = [self extractRepoIdFromURL:remoteUrlStr];
        
        if (!serverBaseURL || !repoId) {
            // Clean up and return success with warning
            git_remote_free(remote);
            git_repository_free(repo);
            
            NSLog(@"Warning: Could not parse remote URL for pushing MGit metadata");
            resolve(@{
                @"success": @YES,
                @"gitPushSuccess": @YES,
                @"metadataPushSuccess": @NO,
                @"warning": @"Could not push MGit metadata - invalid remote URL format"
            });
            return;
        }
        
        // Push the MGit metadata to the server
        [self pushMGitMetadata:repositoryPath 
                 serverBaseURL:serverBaseURL 
                        repoId:repoId 
                         token:token 
                    completion:^(BOOL success, NSError *error) {
            git_remote_free(remote);
            git_repository_free(repo);
            
            if (!success) {
                NSLog(@"Warning: Failed to push MGit metadata: %@", error);
                resolve(@{
                    @"success": @YES,
                    @"gitPushSuccess": @YES,
                    @"metadataPushSuccess": @NO,
                    @"warning": [NSString stringWithFormat:@"Git push succeeded but MGit metadata push failed: %@", error.localizedDescription]
                });
                return;
            }
            
            // Both Git and MGit metadata push succeeded
            [self sendEventWithName:@"MGitProgress" body:@{
                @"stage": @"complete",
                @"message": @"Push completed successfully"
            }];
            
            resolve(@{
                @"success": @YES,
                @"gitPushSuccess": @YES,
                @"metadataPushSuccess": @YES
            });
        }];
    } else {
        // No MGit metadata, just return success for Git push
        git_remote_free(remote);
        git_repository_free(repo);
        
        [self sendEventWithName:@"MGitProgress" body:@{
            @"stage": @"complete",
            @"message": @"Push completed successfully (no MGit metadata)"
        }];
        
        resolve(@{
            @"success": @YES,
            @"gitPushSuccess": @YES,
            @"metadataPushSuccess": @NO,
            @"warning": @"No MGit metadata to push"
        });
    }
}

/**
* mgit Helper functions
*/

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

// Push MGit metadata to the server
- (void)pushMGitMetadata:(NSString *)repositoryPath
           serverBaseURL:(NSString *)serverBaseURL
                  repoId:(NSString *)repoId
                   token:(NSString *)token
              completion:(void (^)(BOOL success, NSError *error))completion {
    // Get the MGit metadata files
    NSString *mappingsPath = [repositoryPath stringByAppendingPathComponent:@".mgit/mappings/hash_mappings.json"];
    
    // Check if mappings file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:mappingsPath]) {
        NSError *error = [NSError errorWithDomain:@"MGitErrorDomain"
                                            code:1005
                                        userInfo:@{NSLocalizedDescriptionKey: @"No MGit mappings file found"}];
        completion(NO, error);
        return;
    }
    
    // Read the mappings file
    NSData *mappingsData = [NSData dataWithContentsOfFile:mappingsPath];
    if (!mappingsData) {
        NSError *error = [NSError errorWithDomain:@"MGitErrorDomain"
                                            code:1006
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to read MGit mappings file"}];
        completion(NO, error);
        return;
    }
    
    // Construct the URL for the metadata push endpoint
    NSString *metadataURLString = [NSString stringWithFormat:@"%@/api/mgit/repos/%@/metadata", serverBaseURL, repoId];
    NSURL *metadataURL = [NSURL URLWithString:metadataURLString];
    
    // Create the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:metadataURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    // Add authorization header if token is provided
    if (token && [token length] > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    
    // Set the request body
    [request setHTTPBody:mappingsData];
    
    // Create and execute the task
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errorMessage = [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode];
            NSError *httpError = [NSError errorWithDomain:@"MGitErrorDomain"
                                                     code:httpResponse.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            completion(NO, httpError);
            return;
        }
        
        // Success
        completion(YES, nil);
    }];
    
    [task resume];
}

// Extract repository ID from a URL
- (NSString *)extractRepoIdFromURL:(NSString *)url {
    // Extract the last path component
    NSArray *pathComponents = [url pathComponents];
    if (pathComponents.count > 0) {
        NSString *lastComponent = pathComponents.lastObject;
        
        // Remove .git suffix if present
        if ([lastComponent hasSuffix:@".git"]) {
            lastComponent = [lastComponent substringToIndex:lastComponent.length - 4];
        }
        
        return lastComponent;
    }
    
    return nil;
}

// Extract server base URL from repository URL
- (NSString *)extractServerBaseURLFromURL:(NSString *)url {
    NSURL *nsurl = [NSURL URLWithString:url];
    if (!nsurl) {
        return nil;
    }
    
    // Get the scheme, host, and port
    NSString *scheme = nsurl.scheme ?: @"http";
    NSString *host = nsurl.host ?: @"localhost";
    NSNumber *port = nsurl.port;
    
    if (port) {
        return [NSString stringWithFormat:@"%@://%@:%@", scheme, host, port];
    } else {
        return [NSString stringWithFormat:@"%@://%@", scheme, host];
    }
}

// Fetch repository information
- (void)fetchRepositoryInfo:(NSString *)serverBaseURL 
                     repoId:(NSString *)repoId 
                      token:(NSString *)token 
                 completion:(void (^)(NSDictionary *repoInfo, NSError *error))completion {
    // Construct the URL for the info endpoint
    NSString *infoURLString = [NSString stringWithFormat:@"%@/api/mgit/repos/%@/info", serverBaseURL, repoId];
    NSURL *infoURL = [NSURL URLWithString:infoURLString];
    
    // Create the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:infoURL];
    [request setHTTPMethod:@"GET"];
    
    // Add authorization header if token is provided
    if (token && [token length] > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    
    // Create and execute the task
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errorMessage = [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode];
            NSError *httpError = [NSError errorWithDomain:@"MGitErrorDomain"
                                                     code:httpResponse.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            completion(nil, httpError);
            return;
        }
        
        // Parse the JSON response
        NSError *jsonError;
        NSDictionary *repoInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            completion(nil, jsonError);
            return;
        }
        
        completion(repoInfo, nil);
    }];
    
    [task resume];
}

// Fetch MGit metadata
- (void)fetchMGitMetadata:(NSString *)serverBaseURL 
                   repoId:(NSString *)repoId 
                    token:(NSString *)token 
               completion:(void (^)(NSData *mappingsData, NSError *error))completion {
    // Construct the URL for the metadata endpoint
    NSString *metadataURLString = [NSString stringWithFormat:@"%@/api/mgit/repos/%@/metadata", serverBaseURL, repoId];
    NSURL *metadataURL = [NSURL URLWithString:metadataURLString];
    
    // Create the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:metadataURL];
    [request setHTTPMethod:@"GET"];
    
    // Add authorization header if token is provided
    if (token && [token length] > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    
    // Create and execute the task
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errorMessage = [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode];
            NSError *httpError = [NSError errorWithDomain:@"MGitErrorDomain"
                                                     code:httpResponse.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            completion(nil, httpError);
            return;
        }
        
        // Return the raw data - we'll parse it when setting up the structure
        completion(data, nil);
    }];
    
    [task resume];
}

// Set up MGit directory structure
- (void)setupMGitStructure:(NSString *)repoPath 
              withMappings:(NSData *)mappingsData 
                  repoInfo:(NSDictionary *)repoInfo
                completion:(void (^)(NSError *error))completion {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Create the .mgit directory structure
    NSString *mgitDir = [repoPath stringByAppendingPathComponent:@".mgit"];
    NSString *objectsDir = [mgitDir stringByAppendingPathComponent:@"objects"];
    NSString *refsDir = [mgitDir stringByAppendingPathComponent:@"refs"];
    NSString *refsHeadsDir = [refsDir stringByAppendingPathComponent:@"heads"];
    NSString *refsTags = [refsDir stringByAppendingPathComponent:@"tags"];
    NSString *mappingsDir = [mgitDir stringByAppendingPathComponent:@"mappings"];
    
    // Create all required directories
    NSArray *directories = @[mgitDir, objectsDir, refsDir, refsHeadsDir, refsTags, mappingsDir];
    for (NSString *dir in directories) {
        NSError *dirError;
        if (![fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&dirError]) {
            completion(dirError);
            return;
        }
    }
    
    // Write hash mappings if available
    if (mappingsData) {
        NSString *mappingsPath = [mappingsDir stringByAppendingPathComponent:@"hash_mappings.json"];
        if (![mappingsData writeToFile:mappingsPath atomically:YES]) {
            NSError *writeError = [NSError errorWithDomain:@"MGitErrorDomain"
                                                    code:1001
                                                userInfo:@{NSLocalizedDescriptionKey: @"Failed to write mappings file"}];
            completion(writeError);
            return;
        }
        
        // Also write to nostr_mappings.json for compatibility
        NSString *nostrMappingsPath = [mgitDir stringByAppendingPathComponent:@"nostr_mappings.json"];
        [mappingsData writeToFile:nostrMappingsPath atomically:YES];
    }
    
    // Create an initial HEAD file pointing to refs/heads/master
    NSString *headPath = [mgitDir stringByAppendingPathComponent:@"HEAD"];
    NSString *headContent = @"ref: refs/heads/master";
    
    if (![headContent writeToFile:headPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        NSError *writeError = [NSError errorWithDomain:@"MGitErrorDomain"
                                                code:1002
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to write HEAD file"}];
        completion(writeError);
        return;
    }
    
    // Create MGit config file
    NSString *configPath = [mgitDir stringByAppendingPathComponent:@"config"];
    NSMutableString *configContent = [NSMutableString string];
    [configContent appendString:@"[repository]\n"];
    
    if (repoInfo[@"id"]) {
        [configContent appendFormat:@"\tid = %@\n", repoInfo[@"id"]];
    }
    
    if (repoInfo[@"name"]) {
        [configContent appendFormat:@"\tname = %@\n", repoInfo[@"name"]];
    }
    
    if (![configContent writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        NSError *writeError = [NSError errorWithDomain:@"MGitErrorDomain"
                                                code:1003
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to write config file"}];
        completion(writeError);
        return;
    }
    
    completion(nil);
}

// Reconstruct MGit objects from Git objects using mappings
- (void)reconstructMGitObjects:(NSString *)repoPath completion:(void (^)(NSError *error))completion {
    // Open the Git repository
    git_repository *repo = NULL;
    int error = git_repository_open(&repo, [repoPath UTF8String]);
    
    if (error != 0) {
        NSError *gitError = [self errorFromGitResult:error];
        completion(gitError);
        return;
    }
    
    // Get the mappings file
    NSString *mappingsPath = [repoPath stringByAppendingPathComponent:@".mgit/mappings/hash_mappings.json"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:mappingsPath]) {
        // No mappings file, nothing to reconstruct
        git_repository_free(repo);
        completion(nil);
        return;
    }
    
    // Read the mappings file
    NSData *mappingsData = [NSData dataWithContentsOfFile:mappingsPath];
    if (!mappingsData) {
        NSError *readError = [NSError errorWithDomain:@"MGitErrorDomain"
                                               code:1004
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to read mappings file"}];
        git_repository_free(repo);
        completion(readError);
        return;
    }
    
    // Parse the mappings
    NSError *jsonError;
    NSArray *mappings = [NSJSONSerialization JSONObjectWithData:mappingsData options:0 error:&jsonError];
    
    if (jsonError) {
        git_repository_free(repo);
        completion(jsonError);
        return;
    }
    
    // Process each mapping
    for (NSDictionary *mapping in mappings) {
        NSString *gitHash = mapping[@"git_hash"];
        NSString *mgitHash = mapping[@"mgit_hash"];
        NSString *pubkey = mapping[@"pubkey"];
        
        // Skip if any required field is missing
        if (!gitHash || !mgitHash || !pubkey) {
            continue;
        }
        
        // Convert gitHash string to git_oid
        git_oid git_id;
        if (git_oid_fromstr(&git_id, [gitHash UTF8String]) != 0) {
            continue;
        }
        
        // Look up the commit
        git_commit *commit = NULL;
        if (git_commit_lookup(&commit, repo, &git_id) != 0) {
            continue;
        }
        
        // Create the MGit commit object structure
        NSMutableDictionary *mgitCommit = [NSMutableDictionary dictionary];
        mgitCommit[@"type"] = @"commit";
        mgitCommit[@"mgit_hash"] = mgitHash;
        mgitCommit[@"git_hash"] = gitHash;
        
        // Get tree hash
        const git_oid *tree_id = git_commit_tree_id(commit);
        char tree_str[GIT_OID_HEXSZ + 1] = {0};
        git_oid_fmt(tree_str, tree_id);
        mgitCommit[@"tree_hash"] = [NSString stringWithUTF8String:tree_str];
        
        // Get parent MGit hashes
        NSMutableArray *parentMGitHashes = [NSMutableArray array];
        int parentCount = git_commit_parentcount(commit);
        
        for (int i = 0; i < parentCount; i++) {
            git_commit *parent = NULL;
            git_commit_parent(&parent, commit, i);
            
            if (parent) {
                NSString *parentGitHash = [self gitOidToString:git_commit_id(parent)];
                
                // Find MGit hash for this parent
                BOOL foundParent = NO;
                for (NSDictionary *m in mappings) {
                    if ([m[@"git_hash"] isEqualToString:parentGitHash]) {
                        [parentMGitHashes addObject:m[@"mgit_hash"]];
                        foundParent = YES;
                        break;
                    }
                }
                
                // If no MGit hash found, use Git hash
                if (!foundParent) {
                    [parentMGitHashes addObject:parentGitHash];
                }
                
                git_commit_free(parent);
            }
        }
        
        mgitCommit[@"parent_hashes"] = parentMGitHashes;
        
        // Get author and committer info
        const git_signature *author = git_commit_author(commit);
        const git_signature *committer = git_commit_committer(commit);
        
        mgitCommit[@"author"] = @{
            @"name": @(author->name),
            @"email": @(author->email),
            @"pubkey": pubkey,
            @"when": @(author->when.time)
        };
        
        mgitCommit[@"committer"] = @{
            @"name": @(committer->name),
            @"email": @(committer->email),
            @"pubkey": pubkey,
            @"when": @(committer->when.time)
        };
        
        mgitCommit[@"message"] = @(git_commit_message(commit));
        mgitCommit[@"metadata"] = @{@"version": @"1.0"};
        
        // Store the MGit commit object
        [self storeMGitCommitObject:mgitCommit inRepo:repoPath];
        
        git_commit_free(commit);
    }
    
    // Update branch references
    git_reference_iterator *iter = NULL;
    if (git_reference_iterator_new(&iter, repo) == 0) {
        git_reference *ref = NULL;
        
        while (git_reference_next(&ref, iter) == 0) {
            if (git_reference_is_branch(ref)) {
                NSString *branchName = @(git_reference_shorthand(ref));
                const git_oid *target = git_reference_target(ref);
                NSString *gitHash = [self gitOidToString:target];
                
                // Find MGit hash for this Git hash
                for (NSDictionary *mapping in mappings) {
                    if ([mapping[@"git_hash"] isEqualToString:gitHash]) {
                        NSString *mgitHash = mapping[@"mgit_hash"];
                        NSString *refPath = [NSString stringWithFormat:@"refs/heads/%@", branchName];
                        [self updateMGitRef:refPath toHash:mgitHash inRepo:repoPath];
                        break;
                    }
                }
                
                git_reference_free(ref);
            }
        }
        
        git_reference_iterator_free(iter);
    }
    
    // Get HEAD reference
    git_reference *head = NULL;
    if (git_repository_head(&head, repo) == 0) {
        if (git_reference_is_branch(head)) {
            NSString *branchName = @(git_reference_shorthand(head));
            NSString *headContent = [NSString stringWithFormat:@"ref: refs/heads/%@", branchName];
            NSString *headPath = [repoPath stringByAppendingPathComponent:@".mgit/HEAD"];
            [headContent writeToFile:headPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            // Detached HEAD
            const git_oid *target = git_reference_target(head);
            NSString *gitHash = [self gitOidToString:target];
            
            // Find MGit hash for this Git hash
            for (NSDictionary *mapping in mappings) {
                if ([mapping[@"git_hash"] isEqualToString:gitHash]) {
                    NSString *mgitHash = mapping[@"mgit_hash"];
                    NSString *headPath = [repoPath stringByAppendingPathComponent:@".mgit/HEAD"];
                    [mgitHash writeToFile:headPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    break;
                }
            }
        }
        
        git_reference_free(head);
    }
    
    git_repository_free(repo);
    completion(nil);
}

// Store an MGit commit object
- (void)storeMGitCommitObject:(NSDictionary *)commit inRepo:(NSString *)repoPath {
    NSString *mgitHash = commit[@"mgit_hash"];
    if (!mgitHash || [mgitHash length] < 2) {
        return;
    }
    
    // Get the object directory path
    NSString *prefix = [mgitHash substringToIndex:2];
    NSString *suffix = [mgitHash substringFromIndex:2];
    NSString *objDir = [repoPath stringByAppendingPathComponent:[NSString stringWithFormat:@".mgit/objects/%@", prefix]];
    NSString *objPath = [objDir stringByAppendingPathComponent:suffix];
    
    // Create the directory if it doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createDirectoryAtPath:objDir withIntermediateDirectories:YES attributes:nil error:nil]) {
        return;
    }
    
    // Serialize the commit object to JSON
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:commit options:NSJSONWritingPrettyPrinted error:&jsonError];
    
    if (jsonError) {
        return;
    }
    
    // Write to file
    [jsonData writeToFile:objPath atomically:YES];
}

// Update an MGit reference
- (void)updateMGitRef:(NSString *)refName toHash:(NSString *)hash inRepo:(NSString *)repoPath {
    // Ensure the refs directory exists
    NSString *refsPath = [repoPath stringByAppendingPathComponent:@".mgit"];
    refsPath = [refsPath stringByAppendingPathComponent:refName];
    
    // Create parent directories if needed
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *parentDir = [refsPath stringByDeletingLastPathComponent];
    
    if (![fileManager createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil]) {
        return;
    }
    
    // Write the reference
    [hash writeToFile:refsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
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

// Test method to compare mcommit hash generation with mgit executable
RCT_EXPORT_METHOD(testMCommitHash:(NSString *)repositoryPath
                  commitHash:(NSString *)commitHash
                  nostrPubkey:(NSString *)nostrPubkey
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  // Open the repository
  git_repository *repo = NULL;
  int error = git_repository_open(&repo, [repositoryPath UTF8String]);
  if (error < 0) {
    const git_error *libgitError = git_error_last();
    reject(@"GIT_ERROR", [NSString stringWithUTF8String:libgitError->message], nil);
    return;
  }
  
  // Look up the commit
  git_commit *commit = NULL;
  git_oid commit_oid;
  if (git_oid_fromstr(&commit_oid, [commitHash UTF8String]) != 0 ||
      git_commit_lookup(&commit, repo, &commit_oid) != 0) {
    git_repository_free(repo);
    reject(@"GIT_ERROR", @"Could not find commit", nil);
    return;
  }
  
  // Get parent MGit hashes
  // For this test, we'll use an empty array for simplicity
  NSArray<NSString *> *parentMGitHashes = @[];
  
  // Calculate MGit hash using our method
  NSString *mgitHash = [self calculateMCommitHash:commit parentMGitHashes:parentMGitHashes pubkey:nostrPubkey];
  
  // Now run mgit show to get the hash from the mgit executable
  NSTask *task = [[NSTask alloc] init];
  [task setCurrentDirectoryPath:repositoryPath];
  [task setLaunchPath:@"mgit"]; // Make sure mgit is in the PATH
  [task setArguments:@[@"show", commitHash]];
  
  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:pipe];
  
  NSError *taskError;
  [task launchAndReturnError:&taskError];
  
  NSString *mgitOutput = @"";
  NSString *mgitCommandHash = @"";
  
  if (!taskError) {
    NSFileHandle *file = [pipe fileHandleForReading];
    NSData *data = [file readDataToEndOfFile];
    mgitOutput = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    // Extract the MGit hash from the output
    // Example: "commit <mgit_hash>\n"
    NSArray *lines = [mgitOutput componentsSeparatedByString:@"\n"];
    if (lines.count > 0) {
      NSString *firstLine = lines[0];
      if ([firstLine hasPrefix:@"commit "]) {
        mgitCommandHash = [firstLine substringFromIndex:7]; // Skip "commit "
      }
    }
  }
  
  // Clean up
  git_commit_free(commit);
  git_repository_free(repo);
  
  // Return both hashes for comparison
  resolve(@{
    @"libgit2Hash": mgitHash,
    @"mgitCommandHash": mgitCommandHash,
    @"match": @([mgitHash isEqualToString:mgitCommandHash]),
    @"mgitOutput": mgitOutput
  });
}

@end
