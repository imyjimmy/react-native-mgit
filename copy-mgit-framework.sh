#!/bin/zsh

# Script to copy MGitBridge.xcframework from mgit-ios-bridge to react-native-mgit
# Run this from the react-native-mgit directory

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Configuration
RN_MGIT_DIR="$(pwd)"
MGIT_IOS_BRIDGE_DIR="../mgit-ios-bridge"  # Adjust this path to your mgit-ios-bridge location
FRAMEWORKS_DIR="$RN_MGIT_DIR/ios/frameworks"
FRAMEWORK_NAME="MGitBridge.xcframework"

log_info "Copying MGit iOS framework to react-native-mgit..."

# Check if we're in the right directory
if [ ! -f "$RN_MGIT_DIR/react-native-mgit.podspec" ]; then
    log_error "react-native-mgit.podspec not found. Are you in the react-native-mgit directory?"
    exit 1
fi

# Check if mgit-ios-bridge repo exists
if [ ! -d "$MGIT_IOS_BRIDGE_DIR" ]; then
    log_error "mgit-ios-bridge directory not found at: $MGIT_IOS_BRIDGE_DIR"
    echo "Please adjust the MGIT_IOS_BRIDGE_DIR path in this script"
    exit 1
fi

# Check if framework exists
FRAMEWORK_PATH="$MGIT_IOS_BRIDGE_DIR/$FRAMEWORK_NAME"
if [ ! -d "$FRAMEWORK_PATH" ]; then
    log_error "MGitBridge.xcframework not found at: $FRAMEWORK_PATH"
    echo "Please build the framework first:"
    echo "  cd $MGIT_IOS_BRIDGE_DIR"
    echo "  gomobile bind -target ios -o $FRAMEWORK_NAME ."
    exit 1
fi

# Verify framework structure
log_info "Verifying framework structure..."
if [ ! -f "$FRAMEWORK_PATH/Info.plist" ]; then
    log_error "Invalid framework: Info.plist not found"
    exit 1
fi

# Check for expected architectures
EXPECTED_ARCHS=("ios-arm64" "ios-arm64_x86_64-simulator")
for arch in "${EXPECTED_ARCHS[@]}"; do
    if [ ! -d "$FRAMEWORK_PATH/$arch" ]; then
        log_warn "Expected architecture '$arch' not found in framework"
    else
        log_info "Found architecture: $arch"
    fi
done

# Create frameworks directory
log_info "Creating frameworks directory..."
mkdir -p "$FRAMEWORKS_DIR"

# Remove old framework if it exists
OLD_FRAMEWORK="$FRAMEWORKS_DIR/$FRAMEWORK_NAME"
if [ -d "$OLD_FRAMEWORK" ]; then
    log_info "Removing old framework..."
    rm -rf "$OLD_FRAMEWORK"
fi

# Copy framework
log_info "Copying MGitBridge.xcframework..."
cp -R "$FRAMEWORK_PATH" "$FRAMEWORKS_DIR/"

# Verify copy
log_info "Verifying copied framework..."
if [ -d "$OLD_FRAMEWORK" ] && [ -f "$OLD_FRAMEWORK/Info.plist" ]; then
    log_success "MGitBridge.xcframework copied successfully!"
    
    echo
    echo "Framework details:"
    echo "Source:      $FRAMEWORK_PATH"
    echo "Destination: $OLD_FRAMEWORK"
    echo "Size:        $(du -sh "$OLD_FRAMEWORK" | awk '{print $1}')"
    
    # Show framework info
    echo
    echo "Framework architectures:"
    find "$OLD_FRAMEWORK" -name "*.framework" -type d | while read -r fw; do
        arch_dir=$(dirname "$fw" | xargs basename)
        fw_name=$(basename "$fw")
        echo "  $arch_dir/$fw_name"
        
        # Try to show binary info if available
        binary_path="$fw/MGitBridge"
        if [ -f "$binary_path" ]; then
            file_info=$(file "$binary_path" 2>/dev/null || echo "Unable to determine file type")
            echo "    Binary: $file_info"
        fi
    done
    
    echo
    echo "Framework is ready for use in react-native-mgit!"
    echo
    echo "Next steps:"
    echo "1. The framework is now in ios/frameworks/MGitBridge.xcframework"
    echo "2. The podspec should reference it with: s.vendored_frameworks = \"ios/frameworks/MGitBridge.xcframework\""
    echo "3. Build your React Native project to test the integration"
    
else
    log_error "Framework copy verification failed"
    exit 1
fi

# Check if old binaries exist and suggest cleanup
BINARIES_DIR="$RN_MGIT_DIR/ios/binaries"
if [ -d "$BINARIES_DIR" ]; then
    echo
    log_warn "Old binaries directory still exists: $BINARIES_DIR"
    echo "Since you're now using the framework approach, you can remove the old binaries:"
    echo "  rm -rf $BINARIES_DIR"
    echo "  # Also update podspec to remove resource_bundles reference"
fi

log_success "Framework copy complete! Ready to build and test."