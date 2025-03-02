import MGit from '../index';

/**
 * Test functions for MGit
 */
class MGitTests {
  /**
   * Test MGit hash generation against the mgit command line tool
   * 
   * @param {string} repositoryPath - Path to repository to test with
   * @param {string} commitHash - Git commit hash to test
   * @param {string} nostrPubkey - Nostr pubkey to use for testing
   * @returns {Promise<Object>} Test results
   */
  static async testMCommitHash(repositoryPath, commitHash, nostrPubkey) {
    try {
      const result = await MGit.testMCommitHash(repositoryPath, commitHash, nostrPubkey);
      
      console.log('=== MGit Hash Test Results ===');
      console.log(`Repository: ${repositoryPath}`);
      console.log(`Commit: ${commitHash}`);
      console.log(`Nostr Pubkey: ${nostrPubkey}`);
      console.log(`Match: ${result.match ? 'YES ✓' : 'NO ✗'}`);
      console.log(`libgit2 hash: ${result.libgit2Hash}`);
      console.log(`mgit hash: ${result.mgitCommandHash}`);
      
      if (!result.match) {
        console.warn('WARNING: Hashes do not match!');
        console.log('mgit output:');
        console.log(result.mgitOutput);
      }
      
      return result;
    } catch (error) {
      console.error('Error running MGit hash test:', error);
      throw error;
    }
  }
  
  /**
   * Run a basic test suite
   * 
   * @param {Object} options Test options
   * @param {string} options.repositoryPath Repository path
   * @param {string} options.commitHash Commit hash to test
   * @param {string} options.nostrPubkey Nostr pubkey to test
   * @returns {Promise<Object>} Test results
   */
  static async runTests(options) {
    console.log('Starting MGit tests...');
    
    const results = {
      hashTest: await this.testMCommitHash(
        options.repositoryPath,
        options.commitHash,
        options.nostrPubkey
      )
    };
    
    console.log('Tests completed.');
    return results;
  }
}

export default MGitTests;