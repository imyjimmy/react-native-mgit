#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface MGitModule : RCTEventEmitter <RCTBridgeModule>

// Core mgit operations using shell execution
- (void)clone:(NSString *)url 
    localPath:(NSString *)localPath 
    options:(NSDictionary *)options 
    resolve:(RCTPromiseResolveBlock)resolve 
    reject:(RCTPromiseRejectBlock)reject;

- (void)pull:(NSString *)repositoryPath 
    options:(NSDictionary *)options 
    resolve:(RCTPromiseResolveBlock)resolve 
    reject:(RCTPromiseRejectBlock)reject;

- (void)commit:(NSString *)repositoryPath 
    message:(NSString *)message 
    options:(NSDictionary *)options 
    resolve:(RCTPromiseResolveBlock)resolve 
    reject:(RCTPromiseRejectBlock)reject;

- (void)createMCommit:(NSString *)repositoryPath 
    message:(NSString *)message 
    authorName:(NSString *)authorName 
    authorEmail:(NSString *)authorEmail 
    nostrPubkey:(NSString *)nostrPubkey 
    resolve:(RCTPromiseResolveBlock)resolve 
    reject:(RCTPromiseRejectBlock)reject;

- (void)showMCommit:(NSString *)repositoryPath 
    commitRef:(NSString *)commitRef 
    nostrPubkey:(NSString *)nostrPubkey 
    resolve:(RCTPromiseResolveBlock)resolve 
    reject:(RCTPromiseRejectBlock)reject;

- (void)testMCommitHash:(NSString *)repositoryPath 
    commitHash:(NSString *)commitHash 
    nostrPubkey:(NSString *)nostrPubkey 
    resolve:(RCTPromiseResolveBlock)resolve 
    reject:(RCTPromiseRejectBlock)reject;

// Binary management helpers
- (NSString *)getMgitBinaryPath;
- (BOOL)setupMgitBinary;

@end