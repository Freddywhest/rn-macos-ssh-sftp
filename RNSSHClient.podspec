require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name             = 'RNSSHClient'
  s.version          = package['version']
  s.summary          = package['description']
  s.license          = package['license']
  s.homepage         = package['homepage']
  s.authors          = package['author']['name']
  s.source           = { :git => package['repository']['url'], :tag => s.version }
  s.source_files     = 'macos/**/*.{h,m}'
  s.requires_arc     = true
  s.platforms        = { :osx => '13.0' }

  # 👇 REQUIRED for NMSSH
  s.frameworks = [
    'Foundation',
    'Security',
    'CFNetwork'
  ]

  s.osx.vendored_libraries = 'Vendor/Libraries/lib/libssh2.a', 'Vendor/Libraries/lib/libssl.a', 'Vendor/Libraries/lib/libcrypto.a'
  s.osx.source_files       = 'Vendor', 'Vendor/Libraries/**/*.h'
  s.osx.public_header_files  = 'Vendor/Libraries/**/*.h'

  s.xcconfig = {
    "OTHER_LDFLAGS" => "-ObjC",
  }

  s.libraries = 'z'

  s.dependency 'React'
end
