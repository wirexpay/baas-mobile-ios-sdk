Pod::Spec.new do |s|
  s.name          = 'WirexMobileSDK'
  s.version       = '0.3.1'
  s.summary       = 'Wirex card details, card entry and wallet top-up for iOS apps.'
  s.description   = 'Shows cardholders their own card details and takes a card they are entering without ' \
                    'the host app handling the values, and hosts the Wirex wallet top-up checkout.'
  s.homepage      = 'https://github.com/wirexpay/baas-mobile-ios-sdk'
  s.license       = { :type => 'Proprietary', :text => File.read(File.join(__dir__, 'LICENSE')) }
  s.author        = 'Wirex'
  s.source        = {
    :http   => "https://github.com/wirexpay/baas-mobile-ios-sdk/releases/download/#{s.version}/WirexMobileSDK.xcframework.zip",
    :sha256 => '52550b971e9d2cd67a2afe62e503589c34e0c7fafb894b15dc8586fcbe7c0a06'
  }

  s.platform            = :ios, '13.0'
  s.swift_version       = '5.9'
  s.vendored_frameworks = 'WirexMobileSDK.xcframework'
end
