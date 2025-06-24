#import "MGitModule.h"
#import <React/RCTLog.h>
#import <Foundation/Foundation.h>
#import <MGitBridge/MGitBridge.h>  // Import the Go framework

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

#pragma mark - React Native Exported Methods

RCT_EXPORT_METHOD(help:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogInfo(@"MGitModule: help() called");
    NSLog(@"MGitModule: help() - testing NSLog");
    
    @try {
        // Call the Go framework directly
        NSString *helpText = MGitBridgeHelp();
        
        RCTLogInfo(@"MGitModule: help() succeeded, length: %lu", (unsigned long)[helpText length]);
        NSLog(@"MGitModule: help() succeeded, length: %lu", (unsigned long)[helpText length]);
        
        resolve(@{
            @"success": @YES,
            @"helpText": helpText,
            @"source": @"framework"
        });
        
    } @catch (NSException *exception) {
        RCTLogError(@"MGitModule: help() failed with exception: %@", exception.reason);
        NSLog(@"MGitModule: help() failed with exception: %@", exception.reason);
        
        reject(@"FRAMEWORK_ERROR", 
               [NSString stringWithFormat:@"Failed to call Go framework: %@", exception.reason], 
               nil);
    }
}

RCT_EXPORT_METHOD(testLogging:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogInfo(@"MGitModule: testLogging() called");
    NSLog(@"MGitModule: testLogging() - testing NSLog");
    
    @try {
        // Call the Go framework test logging function
        NSString *result = MGitBridgeTestLogging();
        
        RCTLogInfo(@"MGitModule: testLogging() succeeded");
        NSLog(@"MGitModule: testLogging() succeeded");
        
        resolve(@{
            @"success": @YES,
            @"result": result,
            @"source": @"framework"
        });
        
    } @catch (NSException *exception) {
        RCTLogError(@"MGitModule: testLogging() failed with exception: %@", exception.reason);
        NSLog(@"MGitModule: testLogging() failed with exception: %@", exception.reason);
        
        reject(@"FRAMEWORK_ERROR", 
               [NSString stringWithFormat:@"Failed to call Go framework: %@", exception.reason], 
               nil);
    }
}

RCT_EXPORT_METHOD(simpleAdd:(int)a
                  b:(int)b
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogInfo(@"MGitModule: simpleAdd(%d, %d) called", a, b);
    NSLog(@"MGitModule: simpleAdd(%d, %d) called", a, b);
    
    @try {
        // Call the Go framework simple add function
        long result = MGitBridgeSimpleAdd(a, b);
        
        RCTLogInfo(@"MGitModule: simpleAdd() succeeded, result: %ld", result);
        NSLog(@"MGitModule: simpleAdd() succeeded, result: %ld", result);
        
        resolve(@{
            @"success": @YES,
            @"result": @(result),
            @"source": @"framework"
        });
        
    } @catch (NSException *exception) {
        RCTLogError(@"MGitModule: simpleAdd() failed with exception: %@", exception.reason);
        NSLog(@"MGitModule: simpleAdd() failed with exception: %@", exception.reason);
        
        reject(@"FRAMEWORK_ERROR", 
               [NSString stringWithFormat:@"Failed to call Go framework: %@", exception.reason], 
               nil);
    }
}

RCT_EXPORT_METHOD(add:(NSString *)repoPath 
                 filePaths:(NSString *)filePaths
                 resolve:(RCTPromiseResolveBlock)resolve 
                 reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogInfo(@"MGitModule: add(%@, %@) called", repoPath, filePaths);
    NSLog(@"MGitModule: add(%@, %@) called", repoPath, filePaths);
    
    @try {
        // Call the Go framework Add function
        MgitiosbridgeAddResult *result = MgitiosbridgeAdd(repoPath, filePaths);
        
        if (result.success) {
            RCTLogInfo(@"MGitModule: add() succeeded: %@", result.message);
            NSLog(@"MGitModule: add() succeeded: %@", result.message);
            
            resolve(@{
                @"success": @YES,
                @"message": result.message,
                @"source": @"framework"
            });
        } else {
            RCTLogError(@"MGitModule: add() failed: %@", result.error);
            NSLog(@"MGitModule: add() failed: %@", result.error);
            
            reject(@"ADD_FAILED", result.error, nil);
        }
        
    } @catch (NSException *exception) {
        RCTLogError(@"MGitModule: add() failed with exception: %@", exception.reason);
        NSLog(@"MGitModule: add() failed with exception: %@", exception.reason);
        
        reject(@"FRAMEWORK_ERROR", 
               [NSString stringWithFormat:@"Failed to call Go framework: %@", exception.reason], 
               nil);
    }
}

// Keep the old pull method for backwards compatibility, but mark it deprecated  
RCT_EXPORT_METHOD(pull:(NSString *)repositoryPath
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogError(@"MGitModule: pull() method not yet implemented with framework");
    reject(@"NOT_IMPLEMENTED", @"Pull method not yet implemented with Go framework", nil);
}

RCT_EXPORT_METHOD(clone:(NSString *)url 
                 localPath:(NSString *)localPath 
                 token:(NSString *)token 
                 resolver:(RCTPromiseResolveBlock)resolve 
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"MGitModule: clone() called with URL: %@, path: %@", url, @"***");
    
    // Call the framework
    MGitBridgeCloneResult *result = MGitBridgeClone(url, localPath, token);
    
    if (result.success) {
        NSDictionary *response = @{
            @"success": @(result.success),
            @"message": result.message ?: @"",
            @"repoID": result.repoID ?: @"",
            @"repoName": result.repoName ?: @"",
            @"localPath": result.localPath ?: @""
        };
        resolve(response);
    } else {
        NSString *errorMessage = result.message ?: @"Clone operation failed";
        reject(@"CLONE_ERROR", errorMessage, nil);
    }
}

RCT_EXPORT_METHOD(commit:(NSString *)repoPath
                  message:(NSString *)message
                  authorName:(NSString *)authorName
                  authorEmail:(NSString *)authorEmail
                  nostrPubkey:(NSString *)nostrPubkey
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogInfo(@"MGitModule: commit() called for repo: %@", repoPath);
    NSLog(@"MGitModule: commit() called for repo: %@", repoPath);
    
    @try {
        // Call the Go framework commit function
        MGitBridgeCommitResult *result = MGitBridgeCommit(repoPath, message, authorName, authorEmail, nostrPubkey);
        
        if (result.success) {
            RCTLogInfo(@"MGitModule: commit() succeeded, MGit hash: %@", result.mGitHash);
            NSLog(@"MGitModule: commit() succeeded, MGit hash: %@", result.mGitHash);
            
            resolve(@{
                @"success": @YES,
                @"message": result.message,
                @"mGitHash": result.mGitHash,
                @"gitHash": result.gitHash,
                @"commitMsg": result.commitMsg
            });
        } else {
            RCTLogError(@"MGitModule: commit() failed: %@", result.message);
            NSLog(@"MGitModule: commit() failed: %@", result.message);
            
            reject(@"COMMIT_FAILED", result.message, nil);
        }
        
    } @catch (NSException *exception) {
        RCTLogError(@"MGitModule: commit() failed with exception: %@", exception.reason);
        NSLog(@"MGitModule: commit() failed with exception: %@", exception.reason);
        
        reject(@"FRAMEWORK_ERROR", 
               [NSString stringWithFormat:@"Failed to call Go framework: %@", exception.reason], 
               nil);
    }
}

RCT_EXPORT_METHOD(push:(NSString *)repoPath
                  token:(NSString *)token
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      // Call the Go bridge Push function
      NSLog(@"MGitModule: push(), token: %@", token);
      MGitBridgePushResult *result = MGitBridgePush(repoPath, token);
      
      // Convert result to JavaScript object with all three fields
      NSDictionary *response = @{
        @"success": @(result.success),
        @"message": result.message ?: @"",
        @"commitHash": result.commitHash ?: @""
      };
      
      resolve(response);
    } @catch (NSException *exception) {
      reject(@"PUSH_ERROR", exception.reason, nil);
    }
  });
}

@end