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
  s.source       = { :git => "https://github.com/imyjimmy/react-native-mgit.git", :tag => "v#{s.version}" }
  s.source_files = "*.{h,m}"
  
  s.dependency "React-Core"
  s.dependency "libgit2", "~> 1.3.0"
  s.pod_target_xcconfig = { 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14' }
end
