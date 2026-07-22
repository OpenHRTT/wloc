use_frameworks!

workspace 'WLocApp'
project 'WLocApp.xcodeproj'

target 'WLocApp-iOS' do
  platform :ios, '12.0'
  pod 'SwiftProtobuf', '1.19.0'
  pod 'SnapKit', '5.6.0'
  pod 'IQKeyboardManagerSwift', '6.5.16'
  pod 'GCDWebServer', '~> 3.5'
end

target 'WLocTunnel-iOS' do
  platform :ios, '12.0'
  pod 'SwiftProtobuf', '1.19.0'
end

target 'WLocApp-macOS' do
  platform :osx, '10.12'
  pod 'SwiftProtobuf', '1.19.0'
  pod 'SnapKit', '5.6.0'
  pod 'GCDWebServer', '~> 3.5'
end

target 'WLocTunnel-macOS' do
  platform :osx, '10.12'
  pod 'SwiftProtobuf', '1.19.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      end
      if config.build_settings['MACOSX_DEPLOYMENT_TARGET']
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.12'
      end
    end
  end
end
