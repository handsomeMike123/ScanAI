Pod::Spec.new do |s|
  s.name             = 'nanopb'
  s.version          = '3.30910.0'
  s.summary          = 'Protocol buffers with small code size.'
  s.description      = 'Nanopb is a small code-size Protocol Buffers implementation in ansi C.'
  s.homepage         = 'https://github.com/nanopb/nanopb'
  s.license          = { :type => 'zlib', :file => 'LICENSE.txt' }
  s.authors          = { 'Petteri Aimonen' => 'jpa@nanopb.mail.kapsi.fi' }
  s.source           = { :git => 'https://github.com/nanopb/nanopb.git', :tag => '0.3.9.10' }

  s.platform         = :ios, '12.0'
  s.requires_arc     = false

  s.xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) PB_FIELD_32BIT=1 PB_NO_PACKED_STRUCTS=1 PB_ENABLE_MALLOC=1'
  }

  s.source_files        = '*.{h,c}'
  s.public_header_files = '*.h'

  s.resource_bundles = {
    'nanopb_Privacy' => ['spm_resources/PrivacyInfo.xcprivacy']
  }

  s.subspec 'encode' do |ss|
    ss.public_header_files = [
      'pb.h',
      'pb_encode.h',
      'pb_common.h',
    ]
    ss.source_files = [
      'pb.h',
      'pb_common.h',
      'pb_common.c',
      'pb_encode.h',
      'pb_encode.c',
    ]
  end

  s.subspec 'decode' do |ss|
    ss.public_header_files = [
      'pb.h',
      'pb_decode.h',
      'pb_common.h',
    ]
    ss.source_files = [
      'pb.h',
      'pb_common.h',
      'pb_common.c',
      'pb_decode.h',
      'pb_decode.c',
    ]
  end
end
