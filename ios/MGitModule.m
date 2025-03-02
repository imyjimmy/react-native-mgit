#import "MGitModule.h"
#import <git2.h>
#import <React/RCTLog.h>

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
  // Implementation of commit would go here
  // For brevity, I'm showing the shell command approach
  
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

@end
