#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pauza_screen_time.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pauza_screen_time'
  s.version          = '0.6.1'
  s.summary          = 'Flutter plugin for app usage monitoring, restriction, and parental controls.'
  s.description      = <<-DESC
A Flutter plugin that provides app usage monitoring, restriction, and parental controls
using iOS Screen Time API (FamilyControls, ManagedSettings, DeviceActivity frameworks).
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Explicit extensions so nested Swift files are included.
  s.source_files = 'Classes/**/*.{h,m,swift}'
  s.dependency 'Flutter'
  
  # iOS 16.0+ required for FamilyControls individual authorization
  # iOS 15.0 only supports child accounts in Family Sharing
  s.platform = :ios, '16.0'
  
  # Required frameworks for Screen Time API
  s.frameworks = 'FamilyControls', 'ManagedSettings', 'ManagedSettingsUI', 'DeviceActivity'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'pauza_screen_time_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
