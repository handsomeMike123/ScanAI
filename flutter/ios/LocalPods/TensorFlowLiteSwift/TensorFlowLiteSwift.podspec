Pod::Spec.new do |s|
  s.name             = 'TensorFlowLiteSwift'
  s.version          = '2.12.0'
  s.authors          = 'Google Inc.'
  s.license          = { :type => 'Apache' }
  s.homepage         = 'https://github.com/tensorflow/tensorflow'
  s.source           = { :git => 'https://github.com/tensorflow/tensorflow.git', :tag => 'v2.12.0' }
  s.summary          = 'TensorFlow Lite for Swift (local)'
  s.description      = 'Local TensorFlowLiteSwift pod that wraps TensorFlowLiteC'
  s.cocoapods_version = '>= 1.9.0'
  s.platform         = :ios, '11.0'
  s.swift_versions   = ['5.0']
  s.module_name      = 'TensorFlowLite'
  s.static_framework = true

  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  s.default_subspecs = 'Core'

  s.subspec 'Core' do |ss|
    ss.dependency 'TensorFlowLiteC', '2.12.0'
    ss.source_files = 'Sources/Core/**/*.swift'
  end

  s.subspec 'CoreML' do |ss|
    ss.dependency 'TensorFlowLiteC/CoreML', '2.12.0'
    ss.dependency 'TensorFlowLiteSwift/Core'
    ss.source_files = 'Sources/CoreML/**/*.swift'
  end

  s.subspec 'Metal' do |ss|
    ss.dependency 'TensorFlowLiteC/Metal', '2.12.0'
    ss.dependency 'TensorFlowLiteSwift/Core'
    ss.source_files = 'Sources/Metal/**/*.swift'
  end
end
