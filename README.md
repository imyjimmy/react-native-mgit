# Testing react-native-mgit

This document provides instructions for testing the `react-native-mgit` module, particularly the mcommit hash generation functionality to ensure it matches the Go implementation.

## Prerequisites

Before running the tests, ensure you have:

1. The `mgit` Go binary installed and available in your PATH
2. A React Native project with the `react-native-mgit` module installed
3. A Git repository with at least one commit that you can use for testing

## Setting Up the Test Environment

### 1. Install react-native-mgit

Since this is a local module under development and not published to npm yet, you'll need to install it from your local filesystem:

```bash
# Using npm with absolute path
npm install --save /path/to/react-native-mgit

# Using npm with relative path
npm install --save ../react-native-mgit

# Using yarn with absolute path (note the file: prefix)
yarn add file:/path/to/react-native-mgit

# Using yarn with relative path
yarn add file:../react-native-mgit
```

This creates a symlink to your local development directory instead of trying to download the package from npm.

### 2. Link the native module (if using React Native < 0.60)

```bash
react-native link react-native-mgit
```

For React Native >= 0.60, autolinking should handle this for you.

### 3. Create a test script

Create a new file in your project (e.g., `MGitTest.js`) with the following content:

```javascript
import React, { useState, useEffect } from 'react';
import { View, Text, Button, ScrollView, StyleSheet } from 'react-native';
import MGit from 'react-native-mgit';
import MGitTests from 'react-native-mgit/src/tests/index.test';

const MGitTestScreen = () => {
  const [testResults, setTestResults] = useState(null);
  const [testStatus, setTestStatus] = useState('idle');
  const [error, setError] = useState(null);

  const runTests = async () => {
    setTestStatus('running');
    setError(null);
    try {
      // Replace these values with your actual test repository
      const results = await MGitTests.runTests({
        repositoryPath: '/path/to/your/test/repo',
        commitHash: 'your-commit-hash',  // e.g., '63a8e0f'
        nostrPubkey: 'your-nostr-pubkey' // e.g., 'npub1...'
      });
      
      setTestResults(results);
      setTestStatus('completed');
    } catch (err) {
      setError(err.message);
      setTestStatus('error');
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>MGit Test Suite</Text>
      
      <Button 
        title="Run Hash Comparison Test" 
        onPress={runTests}
        disabled={testStatus === 'running'}
      />
      
      <View style={styles.statusContainer}>
        <Text>Test Status: {testStatus}</Text>
        {error && <Text style={styles.error}>Error: {error}</Text>}
      </View>
      
      {testResults && (
        <ScrollView style={styles.resultsContainer}>
          <Text style={styles.subtitle}>Hash Test Results</Text>
          <Text>Match: {testResults.hashTest.match ? 'YES ✓' : 'NO ✗'}</Text>
          <Text>libgit2 hash: {testResults.hashTest.libgit2Hash}</Text>
          <Text>mgit hash: {testResults.hashTest.mgitCommandHash}</Text>
          
          <Text style={styles.subtitle}>MGit Output</Text>
          <Text>{testResults.hashTest.mgitOutput}</Text>
        </ScrollView>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#f5f5f5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 16,
  },
  subtitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginTop: 16,
    marginBottom: 8,
  },
  statusContainer: {
    marginVertical: 16,
    padding: 8,
    backgroundColor: '#fff',
    borderRadius: 4,
  },
  error: {
    color: 'red',
    marginTop: 8,
  },
  resultsContainer: {
    flex: 1,
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 4,
  },
});

export default MGitTestScreen;
```

### 4. Add the test screen to your app

Import and add the test screen to your app's navigation. For example:

```javascript
import MGitTestScreen from './MGitTest';

// ... in your navigation code
<Stack.Screen name="MGitTest" component={MGitTestScreen} />
```

## Running the Tests

### Command Line Testing

If you prefer to test via command line, you can create a simple test script (e.g., `test-mgit.js`):

```javascript
const { NativeModules } = require('react-native');
const MGitModule = NativeModules.MGitModule;

async function runTests() {
  try {
    console.log('Starting MGit hash comparison test...');
    
    const result = await MGitModule.testMCommitHash(
      '/path/to/your/test/repo',
      'your-commit-hash',
      'your-nostr-pubkey'
    );
    
    console.log('Test results:');
    console.log('Match:', result.match ? 'YES ✓' : 'NO ✗');
    console.log('libgit2 hash:', result.libgit2Hash);
    console.log('mgit hash:', result.mgitCommandHash);
    
    if (!result.match) {
      console.warn('WARNING: Hashes do not match!');
      console.log('mgit output:');
      console.log(result.mgitOutput);
    }
  } catch (error) {
    console.error('Test failed:', error);
  }
}

runTests();
```

Then run it with:

```bash
node test-mgit.js
```

## Test Parameters

For accurate testing, you need to provide:

1. **repositoryPath**: The full path to a Git repository on your device
2. **commitHash**: A valid Git commit hash in that repository
3. **nostrPubkey**: A valid Nostr public key to use for hash calculation

## Development Setup

If you're actively developing the `react-native-mgit` module, here are some additional approaches for a smoother workflow:

### Using npm link / yarn link

This creates a symbolic link that allows you to use your local version as if it were installed from npm:

```bash
# In the react-native-mgit module directory
cd /path/to/react-native-mgit
npm link
# or
yarn link

# In your React Native project directory
npm link react-native-mgit
# or 
yarn link react-native-mgit
```

### Watching for changes

If you're making frequent changes to the module, you might want to set up a watch process to rebuild automatically:

```bash
# In the react-native-mgit directory
npm install --save-dev nodemon
```

Then add a watch script to your package.json:

```json
"scripts": {
  "watch": "nodemon --watch src --exec 'npm run build'"
}
```

## Troubleshooting

If the tests fail, check:

1. **mgit binary**: Ensure the `mgit` binary is in your PATH by running `which mgit`
2. **Repository access**: Make sure the test has access to read the specified repository
3. **iOS permissions**: If testing on iOS, check if the app has file system permissions
4. **mgit output**: Look at the actual output returned from the mgit command to verify it's in the expected format
5. **Module installation**: Verify that your local module is correctly linked by checking the `node_modules/react-native-mgit` directory

## iOS-Specific Notes

For iOS, the module accesses the file system directly via libgit2 and runs shell commands. To test properly on iOS devices:

1. Use a repository within the app sandbox or a shared container directory
2. If testing on a real device, you may need to adjust permissions
3. For optimal testing, use a simulator which has fewer restrictions

## Log Collection

To collect more detailed logs for troubleshooting, add this function to your test code:

```javascript
function collectLogs(repositoryPath, commitHash) {
  return new Promise((resolve, reject) => {
    const { exec } = require('child_process');
    exec(`mgit show ${commitHash}`, {cwd: repositoryPath}, (error, stdout, stderr) => {
      if (error) {
        reject({error, stderr});
        return;
      }
      resolve({stdout, stderr});
    });
  });
}
```