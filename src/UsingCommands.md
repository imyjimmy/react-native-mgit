# MGit Clone
Here's how to use MGitClone

```
import MGit from 'react-native-mgit';

// Set up progress listener
const progressSubscription = MGit.onProgress((progress) => {
  console.log(`MGit Clone Progress: ${progress.stage} - ${progress.message}`);
  
  // Update UI based on progress
  if (progress.stage === 'download' && progress.totalObjects > 0) {
    const percent = Math.round((progress.receivedObjects / progress.totalObjects) * 100);
    console.log(`Download progress: ${percent}%`);
  }
});

// Clone an MGit repository
async function cloneRepository() {
  try {
    const result = await MGit.mgitClone(
      'http://localhost:3003/hello-world',
      '/path/to/destination', 
      'your-auth-token',  // From your authentication process
      { bare: false }     // Additional options
    );
    
    console.log('Clone successful!', result);
  } catch (error) {
    console.error('Clone failed:', error);
  } finally {
    // Clean up listener when done
    progressSubscription.remove();
  }
}

cloneRepository();
```
