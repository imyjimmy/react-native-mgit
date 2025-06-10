#!/bin/zsh

# Script to copy mgit iOS binaries from mgit repo to react-native-mgit repo
# Run this from the react-native-mgit directory

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
RN_MGIT_DIR="$(pwd)"
MGIT_REPO_DIR="../mgit"  # Adjust this path to your mgit repo location
BINARIES_DIR="$RN_MGIT_DIR/ios/binaries"

log_info "Copying mgit iOS binaries to react-native-mgit..."

# Check if mgit repo exists
if [ ! -d "$MGIT_REPO_DIR" ]; then
    log_error "mgit repo not found at: $MGIT_REPO_DIR"
    echo "Please adjust the MGIT_REPO_DIR path in this script"
    exit 1
fi

# Check if iOS binaries exist
IOS_DEVICE_BINARY="$MGIT_REPO_DIR/dist/ios-arm64/mgit"
IOS_SIM_BINARY="$MGIT_REPO_DIR/dist/ios-simulator/mgit"

if [ ! -f "$IOS_DEVICE_BINARY" ]; then
    log_error "iOS device binary not found at: $IOS_DEVICE_BINARY"
    echo "Please build iOS binaries first: cd ../mgit && ./build/ios-build.sh"
    exit 1
fi

if [ ! -f "$IOS_SIM_BINARY" ]; then
    log_error "iOS simulator binary not found at: $IOS_SIM_BINARY"
    echo "Please build iOS binaries first: cd ../mgit && ./build/ios-build.sh"
    exit 1
fi

# Create binaries directory
log_info "Creating binaries directory..."
mkdir -p "$BINARIES_DIR"

# Copy binaries with appropriate names
log_info "Copying iOS device binary..."
cp "$IOS_DEVICE_BINARY" "$BINARIES_DIR/mgit-ios-arm64"

log_info "Copying iOS simulator binary..."
cp "$IOS_SIM_BINARY" "$BINARIES_DIR/mgit-ios-simulator"

# Make them executable
chmod +x "$BINARIES_DIR/mgit-ios-arm64"
chmod +x "$BINARIES_DIR/mgit-ios-simulator"

# Verify copy
log_info "Verifying copied binaries..."
if [ -x "$BINARIES_DIR/mgit-ios-arm64" ] && [ -x "$BINARIES_DIR/mgit-ios-simulator" ]; then
    log_success "iOS binaries copied successfully!"
    
    echo
    echo "Binary details:"
    echo "iOS Device:    $(ls -lh "$BINARIES_DIR/mgit-ios-arm64" | awk '{print $5}')"
    echo "iOS Simulator: $(ls -lh "$BINARIES_DIR/mgit-ios-simulator" | awk '{print $5}')"
    
    file "$BINARIES_DIR/mgit-ios-arm64"
    file "$BINARIES_DIR/mgit-ios-simulator"
else
    log_error "Binary copy verification failed"
    exit 1
fi

log_success "Ready to proceed with podspec and native code updates!"