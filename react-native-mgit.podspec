require 'json'
package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = "react-native-mgit"
  s.version      = package['version']
  s.summary      = package['description']
  s.license      = package['license']
  s.authors      = package['author']
  s.homepage     = package['homepage']
  s.platform     = :ios, "11.0"
  s.source       = { :git => "https://github.com/yourusername/react-native-mgit.git", :tag => "v#{s.version}" }

  # Native source files - relative to podspec directory
  s.source_files = "ios/MGitModule.{h,m}"

  # Include mgit binaries directly as app resources - relative to podspec directory  
  s.resources = ['ios/binaries/*']

  # React Native dependency (libgit2 dependency removed!)
  s.dependency "React-Core"

  # Remove prepare_command for now to debug the basic file issues
  # s.prepare_command = ...

  # Compiler flags for the new shell-based implementation
  s.compiler_flags = '-DMGIT_SHELL_EXECUTION=1'
end
