require 'json'
package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name         = "react-native-mgit"
  s.version      = package['version']
  s.summary      = package['description']
  s.license      = package['license']
  s.authors      = package['author']
  s.homepage     = package['homepage']
  s.platform     = :ios, "11.0"
  s.source       = { :git => "https://github.com/yourusername/react-native-mgit.git", :tag => "v#{s.version}" }
  
  # Native source files
  s.source_files = "*.{h,m}"
  
  # Bundle mgit binaries as resources
  s.resource_bundles = {
    'MGitBinaries' => ['binaries/*']
  }
  
  # React Native dependency (libgit2 dependency removed!)
  s.dependency "React-Core"
  
  # Prepare command to set up binaries at build time
  s.prepare_command = <<-CMD
    echo "Setting up mgit binaries for iOS..."
    
    # Ensure binaries directory exists
    mkdir -p binaries
    
    # Make binaries executable (in case permissions were lost)
    if [ -f "binaries/mgit-ios-arm64" ]; then
      chmod +x binaries/mgit-ios-arm64
      echo "✓ iOS device binary ready"
    fi
    
    if [ -f "binaries/mgit-ios-simulator" ]; then
      chmod +x binaries/mgit-ios-simulator  
      echo "✓ iOS simulator binary ready"
    fi
    
    echo "✓ mgit binaries prepared"
  CMD
  
  # Compiler flags for the new shell-based implementation
  s.compiler_flags = '-DMGIT_SHELL_EXECUTION=1'
end