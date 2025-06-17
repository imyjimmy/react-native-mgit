#import "MGitModule.h"
#import <React/RCTLog.h>
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

@implementation MGitModule {
    NSString *_mgitBinaryPath;
    BOOL _binarySetupComplete;
}

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

- (instancetype)init {
    self = [super init];
    if (self) {
        _binarySetupComplete = NO;
        _mgitBinaryPath = nil;
    }
    return self;
}

#pragma mark - Binary Management

- (NSString *)getMgitBinaryPath {
    RCTLogInfo(@"🔍 getMgitBinaryPath called");
    
    if (_mgitBinaryPath && _binarySetupComplete) {
        RCTLogInfo(@"✅ Binary already set up: %@", _mgitBinaryPath);
        return _mgitBinaryPath;
    }
    
    RCTLogInfo(@"🔧 Setting up mgit binary...");
    if (![self setupMgitBinaryInternal]) {
        RCTLogError(@"❌ setupMgitBinaryInternal failed");
        return nil;
    }
    
    RCTLogInfo(@"✅ Binary setup complete: %@", _mgitBinaryPath);
    return _mgitBinaryPath;
}

- (BOOL)setupMgitBinaryInternal {
    if (_binarySetupComplete && _mgitBinaryPath) {
        RCTLogInfo(@"✅ Binary already set up, skipping");
        return YES;
    }
    
    RCTLogInfo(@"🔧 Setting up mgit binary...");
    
    // Determine which binary to use based on device/simulator
    NSString *binaryName;
    
#if TARGET_OS_SIMULATOR
    binaryName = @"mgit-ios-simulator";
    RCTLogInfo(@"📱 Using iOS Simulator binary");
#else
    binaryName = @"mgit-ios-arm64";
    RCTLogInfo(@"📱 Using iOS Device binary");
#endif
    
    // Get binary directly from main app bundle (no separate resource bundle)
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundledBinaryPath = [bundle pathForResource:binaryName ofType:nil];
    
    if (!bundledBinaryPath) {
        RCTLogError(@"❌ Binary %@ not found in main bundle: %@", binaryName, bundle.bundlePath);
        
        // List available resources for debugging
        NSArray *allResources = [bundle pathsForResourcesOfType:nil inDirectory:nil];
        NSMutableArray *mgitResources = [NSMutableArray array];
        for (NSString *resource in allResources) {
            if ([resource.lastPathComponent containsString:@"mgit"]) {
                [mgitResources addObject:resource];
            }
        }
        RCTLogInfo(@"📋 Available mgit-related resources: %@", mgitResources);
        
        return NO;
    }
    
    RCTLogInfo(@"✅ Found binary in bundle: %@", bundledBinaryPath);
    
    // Copy binary to app's Documents directory for execution
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *executablePath = [documentsDirectory stringByAppendingPathComponent:@"mgit"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    // Remove existing binary if present
    if ([fileManager fileExistsAtPath:executablePath]) {
        [fileManager removeItemAtPath:executablePath error:nil];
        RCTLogInfo(@"🗑️ Removed existing binary");
    }
    
    // Copy binary to executable location
    if (![fileManager copyItemAtPath:bundledBinaryPath toPath:executablePath error:&error]) {
        RCTLogError(@"❌ Failed to copy mgit binary: %@", error.localizedDescription);
        return NO;
    }
    
    RCTLogInfo(@"📋 Copied binary to: %@", executablePath);
    
    // Make executable
    NSDictionary *attributes = @{NSFilePosixPermissions: @(0755)};
    if (![fileManager setAttributes:attributes ofItemAtPath:executablePath error:&error]) {
        RCTLogError(@"❌ Failed to set executable permissions: %@", error.localizedDescription);
        return NO;
    }
    
    RCTLogInfo(@"✅ Set executable permissions");
    
    _mgitBinaryPath = executablePath;
    _binarySetupComplete = YES;
    
    RCTLogInfo(@"🎉 MGit binary setup complete: %@", _mgitBinaryPath);
    return YES;
}

#pragma mark - Shell Execution Helper

- (NSDictionary *)executeMgitCommand:(NSArray<NSString *> *)arguments 
                         workingDir:(NSString *)workingDir 
                              error:(NSError **)error {
    
    NSString *binaryPath = [self getMgitBinaryPath];
    if (!binaryPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"MGitModule" 
                                         code:1001 
                                     userInfo:@{NSLocalizedDescriptionKey: @"mgit binary not available"}];
        }
        return nil;
    }
    
    // Prepare arguments for posix_spawn
    NSMutableArray *allArgs = [NSMutableArray arrayWithObject:@"mgit"];
    [allArgs addObjectsFromArray:arguments];
    
    // Convert NSString arguments to char* array
    char **argv = malloc(sizeof(char*) * (allArgs.count + 1));
    for (NSUInteger i = 0; i < allArgs.count; i++) {
        NSString *arg = allArgs[i];
        argv[i] = strdup([arg UTF8String]);
    }
    argv[allArgs.count] = NULL;
    
    // Set up environment
    char **envp = NULL; // Use inherited environment
    
    // Create pipes for stdout and stderr
    int stdout_pipe[2], stderr_pipe[2];
    if (pipe(stdout_pipe) == -1 || pipe(stderr_pipe) == -1) {
        if (error) {
            *error = [NSError errorWithDomain:@"MGitModule" 
                                         code:1002 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create pipes"}];
        }
        // Clean up allocated memory
        for (NSUInteger i = 0; i < allArgs.count; i++) {
            free(argv[i]);
        }
        free(argv);
        return nil;
    }
    
    // Set up posix_spawn file actions
    posix_spawn_file_actions_t file_actions;
    posix_spawn_file_actions_init(&file_actions);
    posix_spawn_file_actions_adddup2(&file_actions, stdout_pipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&file_actions, stderr_pipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&file_actions, stdout_pipe[0]);
    posix_spawn_file_actions_addclose(&file_actions, stdout_pipe[1]);
    posix_spawn_file_actions_addclose(&file_actions, stderr_pipe[0]);
    posix_spawn_file_actions_addclose(&file_actions, stderr_pipe[1]);
    
    // Set up spawn attributes
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    
    // Set working directory if provided
    if (workingDir) {
        const char *cwd = [workingDir UTF8String];
        // Note: posix_spawn doesn't have built-in cwd support, we'll chdir temporarily
    }
    
    RCTLogInfo(@"Executing mgit: %@ %@", binaryPath, [arguments componentsJoinedByString:@" "]);
    
    // Save current directory if we need to change it
    char *originalCwd = NULL;
    if (workingDir) {
        originalCwd = getcwd(NULL, 0);
        chdir([workingDir UTF8String]);
    }
    
    // Spawn the process
    pid_t pid;
    int spawn_result = posix_spawn(&pid, [binaryPath UTF8String], &file_actions, &attr, argv, envp);
    
    // Restore original directory
    if (workingDir && originalCwd) {
        chdir(originalCwd);
        free(originalCwd);
    }
    
    // Close write ends of pipes
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);
    
    // Clean up spawn attributes and file actions
    posix_spawn_file_actions_destroy(&file_actions);
    posix_spawnattr_destroy(&attr);
    
    if (spawn_result != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MGitModule" 
                                         code:1003 
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to spawn mgit process: %s", strerror(spawn_result)]}];
        }
        // Clean up
        for (NSUInteger i = 0; i < allArgs.count; i++) {
            free(argv[i]);
        }
        free(argv);
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        return nil;
    }
    
    // Read stdout and stderr
    NSMutableData *stdoutData = [NSMutableData data];
    NSMutableData *stderrData = [NSMutableData data];
    
    char buffer[4096];
    ssize_t bytesRead;
    
    // Read stdout
    while ((bytesRead = read(stdout_pipe[0], buffer, sizeof(buffer))) > 0) {
        [stdoutData appendBytes:buffer length:bytesRead];
    }
    
    // Read stderr  
    while ((bytesRead = read(stderr_pipe[0], buffer, sizeof(buffer))) > 0) {
        [stderrData appendBytes:buffer length:bytesRead];
    }
    
    // Close read ends of pipes
    close(stdout_pipe[0]);
    close(stderr_pipe[0]);
    
    // Wait for process to complete
    int status;
    waitpid(pid, &status, 0);
    
    int exitCode = WEXITSTATUS(status);
    
    // Convert output to strings
    NSString *output = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *errorOutput = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
    
    // Clean up allocated memory
    for (NSUInteger i = 0; i < allArgs.count; i++) {
        free(argv[i]);
    }
    free(argv);
    
    return @{
        @"exitCode": @(exitCode),
        @"stdout": output,
        @"stderr": errorOutput
    };
}

#pragma mark - Utility Methods

- (NSDictionary *)errorObjectFromNSError:(NSError *)error {
    return @{
        @"code": @(error.code),
        @"domain": error.domain,
        @"message": error.localizedDescription,
        @"userInfo": error.userInfo ?: @{}
    };
}

- (void)rejectWithMgitError:(RCTPromiseRejectBlock)reject 
                 exitCode:(int)exitCode 
                   stderr:(NSString *)stderr 
                   stdout:(NSString *)stdout {
    
    NSString *errorMessage = stderr.length > 0 ? stderr : @"mgit command failed";
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
        NSLocalizedDescriptionKey: errorMessage,
        @"exitCode": @(exitCode),
        @"stderr": stderr ?: @"",
        @"stdout": stdout ?: @""
    }];
    
    NSError *error = [NSError errorWithDomain:@"MGitError" 
                                         code:exitCode 
                                     userInfo:userInfo];
    
    reject(@"MGIT_ERROR", errorMessage, error);
}

#pragma mark - React Native Exported Methods

RCT_EXPORT_METHOD(clone:(NSString *)url
                  localPath:(NSString *)localPath
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    RCTLogInfo(@"🚀 MGit clone starting...");
    RCTLogInfo(@"📊 URL: %@", url);
    RCTLogInfo(@"📊 Local path: %@", localPath);
    RCTLogInfo(@"📊 Options: %@", options);
    
    NSString *binaryPath = [self getMgitBinaryPath];
    if (!binaryPath) {
        RCTLogError(@"❌ Failed to setup mgit binary");
        reject(@"BINARY_SETUP_ERROR", @"Failed to setup mgit binary", nil);
        return;
    }
    
    RCTLogInfo(@"✅ Binary path: %@", binaryPath);
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"clone", nil];
    
    // Add JWT token if provided
    NSString *token = options[@"token"];
    if (token) {
        [args addObjectsFromArray:@[@"-jwt", token]];
    }
    
    [args addObject:url];
    [args addObject:localPath];
    
    NSError *error;
    NSDictionary *result = [self executeMgitCommand:args workingDir:nil error:&error];
    
    if (error) {
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", error);
        return;
    }
    
    int exitCode = [result[@"exitCode"] intValue];
    if (exitCode == 0) {
        resolve(@{
            @"success": @YES,
            @"output": result[@"stdout"]
        });
    } else {
        [self rejectWithMgitError:reject 
                         exitCode:exitCode 
                           stderr:result[@"stderr"] 
                           stdout:result[@"stdout"]];
    }
}

RCT_EXPORT_METHOD(mockClone:(NSString *)url
                  localPath:(NSString *)localPath
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    // // Just create a fake success response
    // RCTLogInfo(@"🎭 Mock clone: %@ -> %@", url, localPath);
    
    // // Create the directory structure to simulate a real clone
    // NSFileManager *fileManager = [NSFileManager defaultManager];
    // NSError *error;
    
    // if (![fileManager createDirectoryAtPath:localPath 
    //             withIntermediateDirectories:YES 
    //                              attributes:nil 
    //                                   error:&error]) {
    //     reject(@"MOCK_ERROR", @"Failed to create mock directory", error);
    //     return;
    // }
    
    // // Create a fake README file
    // NSString *readmePath = [localPath stringByAppendingPathComponent:@"README.md"];
    // NSString *content = @"# Mock Medical Records\nThis is a simulated clone for testing.";
    // [content writeToFile:readmePath 
    //           atomically:YES 
    //             encoding:NSUTF8StringEncoding 
    //                error:nil];
    
    // resolve(@{
    //     @"success": @YES,
    //     @"output": @"Mock clone completed successfully",
    //     @"path": localPath
    // });
    /* ABOVE: SUCCESS CASE */

    // VERY obvious logs that should show up
    NSLog(@"🎭🎭🎭 MOCK CLONE METHOD CALLED 🎭🎭🎭");
    RCTLogError(@"🎭🎭🎭 MOCK CLONE ERROR LOG 🎭🎭🎭");
    
    NSLog(@"URL: %@", url);
    NSLog(@"Path: %@", localPath);
    NSLog(@"Options: %@", options);
    
    // Always reject with a obvious message for testing
    reject(@"MOCK_TEST", @"This is the mock method being called!", nil);
}

RCT_EXPORT_METHOD(pull:(NSString *)repositoryPath
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    NSArray *args = @[@"pull"];
    
    NSError *error;
    NSDictionary *result = [self executeMgitCommand:args workingDir:repositoryPath error:&error];
    
    if (error) {
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", error);
        return;
    }
    
    int exitCode = [result[@"exitCode"] intValue];
    if (exitCode == 0) {
        resolve(@{
            @"success": @YES,
            @"output": result[@"stdout"]
        });
    } else {
        [self rejectWithMgitError:reject 
                         exitCode:exitCode 
                           stderr:result[@"stderr"] 
                           stdout:result[@"stdout"]];
    }
}

RCT_EXPORT_METHOD(commit:(NSString *)repositoryPath
                  message:(NSString *)message
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"commit", @"-m", message, nil];
    
    NSError *error;
    NSDictionary *result = [self executeMgitCommand:args workingDir:repositoryPath error:&error];
    
    if (error) {
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", error);
        return;
    }
    
    int exitCode = [result[@"exitCode"] intValue];
    if (exitCode == 0) {
        // Parse output to extract commit hash if available
        NSString *output = result[@"stdout"];
        NSString *hash = @"";
        
        // Look for commit hash in output (mgit should return this)
        NSRegularExpression *hashRegex = [NSRegularExpression regularExpressionWithPattern:@"[a-f0-9]{40}" 
                                                                                   options:0 
                                                                                     error:nil];
        if (hashRegex) {
            NSTextCheckingResult *match = [hashRegex firstMatchInString:output 
                                                                options:0 
                                                                  range:NSMakeRange(0, output.length)];
            if (match) {
                hash = [output substringWithRange:match.range];
            }
        }
        
        resolve(@{
            @"success": @YES,
            @"hash": hash,
            @"output": output
        });
    } else {
        [self rejectWithMgitError:reject 
                         exitCode:exitCode 
                           stderr:result[@"stderr"] 
                           stdout:result[@"stdout"]];
    }
}

RCT_EXPORT_METHOD(createMCommit:(NSString *)repositoryPath
                  message:(NSString *)message
                  authorName:(NSString *)authorName
                  authorEmail:(NSString *)authorEmail
                  nostrPubkey:(NSString *)nostrPubkey
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    // This would need to be implemented in your mgit Go binary
    // For now, using regular commit with additional metadata
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"commit", @"-m", message, nil];
    
    // You might want to add flags for nostr pubkey to mgit binary
    // e.g., @"-nostr-pubkey", nostrPubkey
    
    NSError *error;
    NSDictionary *result = [self executeMgitCommand:args workingDir:repositoryPath error:&error];
    
    if (error) {
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", error);
        return;
    }
    
    int exitCode = [result[@"exitCode"] intValue];
    if (exitCode == 0) {
        resolve(@{
            @"success": @YES,
            @"output": result[@"stdout"],
            @"nostrPubkey": nostrPubkey
        });
    } else {
        [self rejectWithMgitError:reject 
                         exitCode:exitCode 
                           stderr:result[@"stderr"] 
                           stdout:result[@"stdout"]];
    }
}

RCT_EXPORT_METHOD(help:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogInfo(@"[MGit] Starting help command test...");
    NSLog(@"[MGit] NSLog test - help method called");
    
    NSArray *args = @[@"help"];
    
    NSError *error;
    NSDictionary *result = [self executeMgitCommand:args workingDir:nil error:&error];
    
    if (error) {
        RCTLogError(@"[MGit] Help command failed with error: %@", error);
        NSLog(@"[MGit] NSLog ERROR - help failed: %@", error);
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", error);
        return;
    }
    
    int exitCode = [result[@"exitCode"] intValue];
    NSString *stdout = result[@"stdout"] ?: @"";
    NSString *stderr = result[@"stderr"] ?: @"";
    
    RCTLogInfo(@"[MGit] Help exit code: %d", exitCode);
    RCTLogInfo(@"[MGit] Help stdout length: %lu", (unsigned long)stdout.length);
    NSLog(@"[MGit] NSLog - stdout preview: %@", [stdout substringToIndex:MIN(100, stdout.length)]);
    
    if (exitCode == 0) {
        // Get first 100 characters for preview
        NSString *preview = stdout.length > 100 ? 
            [[stdout substringToIndex:100] stringByAppendingString:@"..."] : 
            stdout;
            
        resolve(@{
            @"success": @YES,
            @"output": stdout,           // Full output
            @"preview": preview,         // First 100 chars
            @"outputLength": @(stdout.length),
            @"version": @"MGit v1.0.0",
            @"testMath": @(2 + 2),
            @"logTest": @"All logging methods tested"
        });
    } else {
        RCTLogError(@"[MGit] Help command non-zero exit: %d", exitCode);
        [self rejectWithMgitError:reject 
                         exitCode:exitCode 
                           stderr:stderr 
                           stdout:stdout];
    }
}

RCT_EXPORT_METHOD(showMCommit:(NSString *)repositoryPath
                  commitRef:(NSString *)commitRef
                  nostrPubkey:(NSString *)nostrPubkey
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    NSArray *args = @[@"show", commitRef];
    
    NSError *error;
    NSDictionary *result = [self executeMgitCommand:args workingDir:repositoryPath error:&error];
    
    if (error) {
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", error);
        return;
    }
    
    int exitCode = [result[@"exitCode"] intValue];
    if (exitCode == 0) {
        resolve(@{
            @"success": @YES,
            @"output": result[@"stdout"],
            @"commitRef": commitRef,
            @"nostrPubkey": nostrPubkey
        });
    } else {
        [self rejectWithMgitError:reject 
                         exitCode:exitCode 
                           stderr:result[@"stderr"] 
                           stdout:result[@"stdout"]];
    }
}

RCT_EXPORT_METHOD(testMCommitHash:(NSString *)repositoryPath
                  commitHash:(NSString *)commitHash
                  nostrPubkey:(NSString *)nostrPubkey
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    // Execute mgit show to get commit info and compare hashes
    NSArray *args = @[@"show", commitHash];
    
    NSError *error;
    NSDictionary *result = [self executeMgitCommand:args workingDir:repositoryPath error:&error];
    
    if (error) {
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", error);
        return;
    }
    
    int exitCode = [result[@"exitCode"] intValue];
    if (exitCode == 0) {
        NSString *mgitOutput = result[@"stdout"];
        
        // For now, return basic comparison - you'll want to enhance this
        // to extract and compare the actual mgit hash vs git hash
        resolve(@{
            @"success": @YES,
            @"match": @YES,  // Placeholder - implement actual hash comparison
            @"mgitOutput": mgitOutput,
            @"mgitCommandHash": commitHash,
            @"libgit2Hash": commitHash,  // This was the old libgit2 hash
            @"nostrPubkey": nostrPubkey
        });
    } else {
        [self rejectWithMgitError:reject 
                         exitCode:exitCode 
                           stderr:result[@"stderr"] 
                           stdout:result[@"stdout"]];
    }
}

RCT_EXPORT_METHOD(setupMgitBinary:(RCTPromiseResolveBlock)resolve
                           reject:(RCTPromiseRejectBlock)reject) {
    
    BOOL success = [self setupMgitBinaryInternal];
    
    if (success) {
        resolve(@{
            @"success": @YES,
            @"binaryPath": _mgitBinaryPath ?: @"",
            @"message": @"mgit binary setup successful"
        });
    } else {
        reject(@"SETUP_ERROR", @"Failed to setup mgit binary", nil);
    }
}

RCT_EXPORT_METHOD(testMethod:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject) {
    resolve(@{
        @"message": @"Test method works!",
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    });
}

RCT_EXPORT_METHOD(setupMgitBinarySimple:(RCTPromiseResolveBlock)resolve
                                 reject:(RCTPromiseRejectBlock)reject) {
    resolve(@{@"message": @"setup method works"});
}

RCT_EXPORT_METHOD(readFile:(NSString *)repoPath 
                 fileName:(NSString *)fileName
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    NSString *fullPath = [repoPath stringByAppendingPathComponent:fileName];
    
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:fullPath 
                                                  encoding:NSUTF8StringEncoding 
                                                     error:&error];
    
    if (error) {
        reject(@"READ_ERROR", @"Failed to read file", error);
    } else {
        resolve(content);
    }
}
@end