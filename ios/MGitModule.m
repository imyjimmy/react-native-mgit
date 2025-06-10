#import "MGitModule.h"
#import <React/RCTLog.h>
#import <Foundation/Foundation.h>

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
    if (_mgitBinaryPath && _binarySetupComplete) {
        return _mgitBinaryPath;
    }
    
    if (![self setupMgitBinary]) {
        return nil;
    }
    
    return _mgitBinaryPath;
}

- (BOOL)setupMgitBinary {
    if (_binarySetupComplete && _mgitBinaryPath) {
        return YES;
    }
    
    RCTLogInfo(@"Setting up mgit binary...");
    
    // Get the resource bundle
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSBundle *mgitBundle = [NSBundle bundleWithPath:[bundle pathForResource:@"MGitBinaries" ofType:@"bundle"]];
    
    if (!mgitBundle) {
        RCTLogError(@"MGitBinaries bundle not found");
        return NO;
    }
    
    // Determine which binary to use based on device/simulator
    NSString *binaryName;
    
#if TARGET_OS_SIMULATOR
    binaryName = @"mgit-ios-simulator";
    RCTLogInfo(@"Using iOS Simulator binary");
#else
    binaryName = @"mgit-ios-arm64";
    RCTLogInfo(@"Using iOS Device binary");
#endif
    
    NSString *bundledBinaryPath = [mgitBundle pathForResource:binaryName ofType:nil];
    if (!bundledBinaryPath) {
        RCTLogError(@"Binary %@ not found in bundle", binaryName);
        return NO;
    }
    
    // Copy binary to app's Documents directory for execution
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *executablePath = [documentsDirectory stringByAppendingPathComponent:@"mgit"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    // Remove existing binary if present
    if ([fileManager fileExistsAtPath:executablePath]) {
        [fileManager removeItemAtPath:executablePath error:nil];
    }
    
    // Copy binary to executable location
    if (![fileManager copyItemAtPath:bundledBinaryPath toPath:executablePath error:&error]) {
        RCTLogError(@"Failed to copy mgit binary: %@", error.localizedDescription);
        return NO;
    }
    
    // Make executable
    NSDictionary *attributes = @{NSFilePosixPermissions: @(0755)};
    if (![fileManager setAttributes:attributes ofItemAtPath:executablePath error:&error]) {
        RCTLogError(@"Failed to make mgit binary executable: %@", error.localizedDescription);
        return NO;
    }
    
    _mgitBinaryPath = executablePath;
    _binarySetupComplete = YES;
    
    RCTLogInfo(@"mgit binary ready at: %@", executablePath);
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
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = binaryPath;
    task.arguments = arguments;
    
    if (workingDir) {
        task.currentDirectoryPath = workingDir;
    }
    
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;
    
    NSFileHandle *outputHandle = [outputPipe fileHandleForReading];
    NSFileHandle *errorHandle = [errorPipe fileHandleForReading];
    
    RCTLogInfo(@"Executing mgit: %@ %@", binaryPath, [arguments componentsJoinedByString:@" "]);
    
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"MGitModule" 
                                         code:1002 
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to execute mgit: %@", exception.reason]}];
        }
        return nil;
    }
    
    NSData *outputData = [outputHandle readDataToEndOfFile];
    NSData *errorData = [errorHandle readDataToEndOfFile];
    
    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] ?: @"";
    
    int exitCode = [task terminationStatus];
    
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

@end