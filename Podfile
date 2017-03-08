source 'https://github.com/CocoaPods/Specs.git'

# ignore all warnings from all pods, namely uservoice-iphone-sdk
use_frameworks!
# inhibit_all_warnings!

target "Vast" do
    pod 'AEXML'
    pod 'Signals', '~> 4.0'
end


post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['SWIFT_VERSION'] = '3.0'
        end
    end
end
