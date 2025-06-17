# react-native-mgit

A React Native module that integrates MGit (Medical Git) functionality into iOS applications using a Go framework. MGit enables secure, self-custodial medical data management with Nostr public key authentication.

## Overview

`react-native-mgit` bridges MGit's Go implementation with React Native iOS apps through a compiled Go framework (`MGitBridge.xcframework`). This approach provides:

- Direct Go function calls (no binary execution)
- Full logging visibility for debugging
- Secure execution within the iOS app sandbox
- Comprehensive MGit functionality for medical record management

## Architecture

```
React Native App
    ↓
react-native-mgit (Bridge)
    ↓ 
MGitBridge.xcframework (Go Framework)
    ↓
MGit Go Implementation
```

## Prerequisites

- **iOS Development**: Xcode, CocoaPods
- **Go Development**: Go 1.21+, `gomobile` tool
- **React Native**: 0.60+ (autolinking support)
- **MGit Framework**: Pre-built `MGitBridge.xcframework`

## Installation

### 1. Install the Module

Since this is a local development module:

```bash
# Using yarn (recommended)
yarn add file:../react-native-mgit

# Using npm
npm install --save ../react-native-mgit
```

### 2. iOS Framework Setup

The module requires `MGitBridge.xcframework` to be present in `ios/frameworks/`:

```bash
# From react-native-mgit directory
./copy-mgit-framework.sh
```

This copies the framework from `../mgit-ios-bridge/MGitBridge.xcframework` to the correct location.

### 3. iOS Project Integration

For React Native 0.60+, autolinking handles most setup. If needed, manually add to your iOS project:

```ruby
# ios/Podfile - usually handled automatically
pod 'react-native-mgit', :path => '../node_modules/react-native-mgit'
```

## Framework Development

### Building the Go Framework

The `MGitBridge.xcframework` is built from the `mgit-ios-bridge` package:

```bash
# In mgit-ios-bridge directory
go mod tidy
gomobile bind -target ios -o MGitBridge.xcframework .
```

### Updating the Framework

When MGit functionality changes:

1. Update `mgit-ios-bridge/bridge.go` with new functions
2. Rebuild framework: `gomobile bind -target ios -o MGitBridge.xcframework .`
3. Copy to react-native-mgit: `./copy-mgit-framework.sh`
4. Test in your React Native app

## Usage

### Basic Framework Testing

```javascript
import { NativeModules } from 'react-native';

const MGitModule = NativeModules.MGitModule;

// Test framework integration
async function testFramework() {
  try {
    // Get MGit help text
    const helpResult = await MGitModule.help();
    console.log('Help text:', helpResult.helpText);
    
    // Test logging functionality
    const logResult = await MGitModule.testLogging();
    console.log('Logging test:', logResult.result);
    
    // Test basic computation
    const mathResult = await MGitModule.simpleAdd(2, 2);
    console.log('2 + 2 =', mathResult.result); // Should be 4
    
  } catch (error) {
    console.error('Framework test failed:', error);
  }
}
```

### MGit Service Integration

```javascript
import MGitService from 'react-native-mgit/src/services/MGitService';

async function testMGitConnection() {
  try {
    const isConnected = await MGitService.testConnection();
    console.log('MGit module connected:', isConnected);
  } catch (error) {
    console.error('Connection test failed:', error);
  }
}
```

## Available Methods

### Framework Test Methods

- **`help()`** - Returns MGit help text and usage information
- **`testLogging()`** - Comprehensive logging test for debugging
- **`simpleAdd(a, b)`** - Basic arithmetic test (returns a + b)

### MGit Operations (Future)

The following methods are planned for implementation:

- **`clone(url, localPath, options)`** - Clone MGit repositories
- **`commit(repositoryPath, message, options)`** - Create commits with Nostr signatures
- **`pull(repositoryPath, options)`** - Pull changes from remote repositories
- **`createMCommit(...)`** - Create medical commits with enhanced metadata

## Development Workflow

### 1. Framework Development

```bash
# Work on Go functionality
cd mgit-ios-bridge
# Edit bridge.go to add new functions
gomobile bind -target ios -o MGitBridge.xcframework .
```

### 2. Integration Testing

```bash
# Update React Native module
cd react-native-mgit
./copy-mgit-framework.sh

# Test in your app
cd your-app
npx expo run:ios
```

### 3. Debugging

#### iOS Logs
View native logs in Xcode Console (Window > Devices and Simulators > Select Device > Open Console).

#### JavaScript Logs
```javascript
// Enable comprehensive logging
const result = await MGitModule.testLogging();
// Check both console.log and Xcode Console for output
```

## Project Structure

```
react-native-mgit/
├── ios/
│   ├── MGitModule.h               # Native module header
│   ├── MGitModule.m               # Native module implementation
│   └── frameworks/                # Framework location
│       └── MGitBridge.xcframework # Go framework
├── src/
│   └── services/
│       └── MGitService.ts         # JavaScript service layer
├── copy-mgit-framework.sh         # Framework update script
├── react-native-mgit.podspec      # iOS dependency configuration
└── package.json
```

## Troubleshooting

### Common Issues

**Framework not found:**
```bash
# Ensure framework is in correct location
ls ios/frameworks/MGitBridge.xcframework

# If missing, copy from mgit-ios-bridge
./copy-mgit-framework.sh
```

**Build errors:**
```bash
# Clean build
cd ios && rm -rf build/ Pods/ Podfile.lock
cd .. && npx expo run:ios
```

**No native logs:**
- Check Xcode Console (not Simulator console)
- Filter by "MGitModule" or "MedicalBinder"
- Ensure device/simulator is selected in Console app

### Verification Steps

1. **Module loads**: `NativeModules.MGitModule` should not be undefined
2. **Framework works**: `await MGitModule.help()` should return help text
3. **Logging visible**: Check Xcode Console for "MGitModule:" messages

## Contributing

### Adding New MGit Functions

1. **Go side**: Add function to `mgit-ios-bridge/bridge.go`
2. **Framework**: Rebuild with `gomobile bind`
3. **Native side**: Add RCT_EXPORT_METHOD to `MGitModule.m`
4. **JavaScript side**: Add method to `MGitService.ts`
5. **Test**: Verify end-to-end functionality

### Testing

```javascript
// Template for testing new methods
async function testNewMethod() {
  try {
    const result = await MGitModule.yourNewMethod(params);
    console.log('Success:', result);
  } catch (error) {
    console.error('Error:', error);
  }
}
```

## Requirements

- **iOS**: 11.0+
- **React Native**: 0.60+
- **Go**: 1.21+ (for framework development)
- **Xcode**: Latest stable version

## License

[Add your license information here]

## Related Projects

- **MGit**: Core Git implementation for medical records
- **mgit-ios-bridge**: Go package providing iOS framework
- **MedicalBinder**: Reference React Native app using this module