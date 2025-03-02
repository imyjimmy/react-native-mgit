import { NativeModules, NativeEventEmitter } from 'react-native';

const { MGitModule } = NativeModules;
const MGitEventEmitter = new NativeEventEmitter(MGitModule);

class MGit {
  /**
   * Clone a repository
   * @param {string} url - The repository URL
   * @param {string} localPath - Local path where the repository will be cloned
   * @param {Object} options - Clone options (e.g., bare, token)
   * @returns {Promise<Object>} - Resolves with success information
   */
  static clone(url, localPath, options = {}) {
    return MGitModule.clone(url, localPath, options);
  }

  /**
   * Pull changes from remote
   * @param {string} repositoryPath - Path to local repository
   * @param {Object} options - Pull options
   * @returns {Promise<Object>} - Resolves with success information
   */
  static pull(repositoryPath, options = {}) {
    return MGitModule.pull(repositoryPath, options);
  }

  /**
   * Commit changes
   * @param {string} repositoryPath - Path to local repository
   * @param {string} message - Commit message
   * @param {Object} options - Commit options (e.g., author)
   * @returns {Promise<Object>} - Resolves with success information
   */
  static commit(repositoryPath, message, options = {}) {
    // If nostrPubkey is provided, use MGit commit functionality
    if (options.nostrPubkey) {
      return MGitModule.createMCommit(
        repositoryPath,
        message,
        options.authorName || options.author || '',
        options.authorEmail || options.email || '',
        options.nostrPubkey
      );
    }

    return MGitModule.commit(repositoryPath, message, options);
  }

  /**
   * Create an MGit commit with a Nostr pubkey
   * @param {string} repositoryPath - Path to local repository
   * @param {string} message - Commit message
   * @param {Object} options - Commit options
   * @param {string} options.authorName - Author name
   * @param {string} options.authorEmail - Author email
   * @param {string} options.nostrPubkey - Nostr public key
   * @returns {Promise<Object>} - Resolves with commit information including both git and mgit hashes
   */
  static createMCommit(repositoryPath, message, options = {}) {
    return MGitModule.createMCommit(
      repositoryPath, 
      message,
      options.authorName || '',
      options.authorEmail || '',
      options.nostrPubkey || ''
    );
  }

  /**
   * Run mgit show command
   * @param {string} repositoryPath - Path to local repository
   * @param {string} commitRef - Commit reference (hash, branch, etc.)
   * @returns {Promise<Object>} - Resolves with commit information
   */
  static show(repositoryPath, commitRef = 'HEAD') {
    return MGitModule.mgitShow(repositoryPath, commitRef);
  }

  /**
   * Listen for git progress events
   * @param {Function} callback - Callback to handle progress events
   * @returns {Object} - Subscription that should be cleaned up
   */
  static onProgress(callback) {
    return MGitEventEmitter.addListener('MGitProgress', callback);
  }

  /**
   * Listen for git error events
   * @param {Function} callback - Callback to handle error events
   * @returns {Object} - Subscription that should be cleaned up
   */
  static onError(callback) {
    return MGitEventEmitter.addListener('MGitError', callback);
  }
}

export default MGit;
