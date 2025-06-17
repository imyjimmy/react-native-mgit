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
        NSString *helpText = MgitiosbridgeHelp();
        
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
        NSString *result = MgitiosbridgeTestLogging();
        
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
        long result = MgitiosbridgeSimpleAdd(a, b);
        
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

// Keep the old clone method for backwards compatibility, but mark it deprecated
RCT_EXPORT_METHOD(clone:(NSString *)url
                  localPath:(NSString *)localPath
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogError(@"MGitModule: clone() method not yet implemented with framework");
    reject(@"NOT_IMPLEMENTED", @"Clone method not yet implemented with Go framework", nil);
}

// Keep the old pull method for backwards compatibility, but mark it deprecated  
RCT_EXPORT_METHOD(pull:(NSString *)repositoryPath
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    
    RCTLogError(@"MGitModule: pull() method not yet implemented with framework");
    reject(@"NOT_IMPLEMENTED", @"Pull method not yet implemented with Go framework", nil);
}

@end