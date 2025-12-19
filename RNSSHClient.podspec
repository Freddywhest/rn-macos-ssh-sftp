require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name             = 'RNSSHClient'
  s.version          = package['version']
  s.summary          = package['description']
  s.license          = package['license']
  s.homepage         = package['homepage']
  s.authors          = package['author']
  s.source           = { :git => package['repository']['url'], :tag => s.version }
  s.requires_arc     = true
  s.platforms        = { :osx => '13.0' }

  # Frameworks needed
  s.frameworks = ['Foundation', 'Security', 'CFNetwork']
  s.libraries = 'z'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-ObjC' }

  # React dependency
  s.dependency 'React'

  # Include all your source files
  s.source_files = 'macos/**/*.{h,m}', 'macos/Vendor/**/*.{h,m}'

  # Make NMSSH and your vendor headers public
  s.public_header_files = 'macos/NMSSH/**/*.h', 'macos/Vendor/**/*.h'

  # Include static libraries
  s.vendored_libraries = 'macos/Vendor/Libraries/lib/*.a'
end
