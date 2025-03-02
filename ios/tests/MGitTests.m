/* 
* MGit Tests
*/
#import <Foundation/Foundation.h>
#import "../MGitModule.h"

@interface MGitTests : NSObject

+ (void)testMCommitHash:(NSString *)repositoryPath
             commitHash:(NSString *)commitHash
            nostrPubkey:(NSString *)nostrPubkey
               callback:(void (^)(NSDictionary *result, NSError *error))callback;

@end

@implementation MGitTests

+ (void)testMCommitHash:(NSString *)repositoryPath
             commitHash:(NSString *)commitHash
            nostrPubkey:(NSString *)nostrPubkey
               callback:(void (^)(NSDictionary *result, NSError *error))callback {
  // Open the repository
  git_repository *repo = NULL;
  int error = git_repository_open(&repo, [repositoryPath UTF8String]);
  if (error < 0) {
    const git_error *libgitError = git_error_last();
    NSError *err = [NSError errorWithDomain:@"MGitErrorDomain" 
                                       code:error 
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:libgitError->message]}];
    callback(nil, err);
    return;
  }
  
  // Look up the commit
  git_commit *commit = NULL;
  git_oid commit_oid;
  if (git_oid_fromstr(&commit_oid, [commitHash UTF8String]) != 0 ||
      git_commit_lookup(&commit, repo, &commit_oid) != 0) {
    git_repository_free(repo);
    NSError *err = [NSError errorWithDomain:@"MGitErrorDomain" 
                                       code:-1 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Could not find commit"}];
    callback(nil, err);
    return;
  }
  
  // Get parent MGit hashes
  // For this test, we'll use an empty array for simplicity
  // In a real implementation, you'd look these up from the mappings
  NSArray<NSString *> *parentMGitHashes = @[];
  
  // Create MGitModule instance to use its methods
  MGitModule *mgitModule = [[MGitModule alloc] init];
  
  // Calculate MGit hash using our method
  NSString *mgitHash = [mgitModule calculateMCommitHash:commit
                                     parentMGitHashes:parentMGitHashes
                                             pubkey:nostrPubkey];
  
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
    // This depends on the format of mgit show output
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
  NSDictionary *result = @{
    @"libgit2Hash": mgitHash,
    @"mgitCommandHash": mgitCommandHash,
    @"match": @([mgitHash isEqualToString:mgitCommandHash]),
    @"mgitOutput": mgitOutput
  };
  
  callback(result, nil);
}

@end