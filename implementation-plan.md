# Implementation Plan for react-native-mgit

Here's a summary of the remaining work organized into two batches:

## Batch One: Read-Only MGit Operations

This batch focuses on implementing the core functionality for viewing MGit commit information:

1. **MGit Show**
   - Implement the ability to display detailed information about an mcommit
   - Show both Git and MGit hash information
   - Include Nostr pubkey information in the output
   - Display commit diffs using libgit2

2. **MGit Log**
   - Add support for viewing commit history with MGit hashes
   - Include Nostr pubkey information in commit history display
   - Support filtering and formatting options similar to the Go implementation
   - Traverse the MGit commit chain rather than just Git commits

Technical considerations:
- These operations are read-only and don't modify the repository
- They rely heavily on proper mapping between Git and MGit hashes
- The core libgit2 implementation needs to be extended with MGit-specific metadata handling

## Batch Two: MGit Repository Operations

This batch focuses on repository-level operations that include managing MGit metadata:

1. **MGit Clone**
   - Extend standard Git clone to include MGit metadata
   - Set up proper .mgit directory structure
   - Transfer and reconstruct hash mappings
   - Ensure Nostr pubkey information is preserved

2. **MGit Push**
   - Implement functionality to push both Git changes and MGit metadata
   - Handle authentication with Nostr integration
   - Ensure both Git objects and MGit mappings are synchronized

3. **Nostr Mappings Management**
   - Implement comprehensive tools for handling the .mgit directory
   - Add functionality to read, write, and synchronize mapping files
   - Handle conflicts and merges of mapping data
   - Support different storage formats and backward compatibility

Technical considerations:
- These operations require both read and write access to repositories
- They involve network operations and authentication
- The implementation needs to handle errors and edge cases robustly
- Synchronization between Git objects and MGit metadata is critical

When you start a new chat, you can pick one of these batches to focus on and continue the implementation where we left off. The foundation for MGit hash calculation and commit creation is already in place, so these batches build upon that core functionality.