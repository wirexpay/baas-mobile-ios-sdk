Pod::Spec.new do |s|
  s.name          = 'WirexMobileSDK'
  s.version       = '0.3.14'
  s.summary       = 'Wirex card details, card entry and wallet top-up for iOS apps.'
  s.description   = 'Shows cardholders their own card details and takes a card they are entering without ' \
                    'the host app handling the values, and hosts the Wirex wallet top-up checkout.'
  s.homepage      = 'https://github.com/wirexpay/baas-mobile-ios-sdk'
  s.license       = { :type => 'Proprietary', :text => File.read(File.join(__dir__, 'LICENSE')) }
  s.author        = 'Wirex'
  s.source        = {
    :http   => "https://github.com/wirexpay/baas-mobile-ios-sdk/releases/download/#{s.version}/WirexMobileSDK.xcframework.zip",
    :sha256 => '29b7b11de2ce65728e34d0fc6d6886c2526f47acb63c1ca371ed5ed1bb829707'
  }

  s.platform            = :ios, '13.0'
  s.swift_version       = '5.9'
  s.vendored_frameworks = 'WirexMobileSDK.xcframework'
end
