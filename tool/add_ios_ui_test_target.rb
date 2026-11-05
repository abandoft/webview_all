#!/usr/bin/env ruby

# CocoaPods provides xcodeproj on the Apple build hosts. Keep the UI automation
# target generated so regular example builds do not acquire test-only settings.
require 'pathname'
begin
  require 'xcodeproj'
rescue LoadError
  # Homebrew isolates CocoaPods' gems from the system Ruby environment.
  prefix = IO.popen(['brew', '--prefix', 'cocoapods'], err: File::NULL, &:read).strip
  abort 'Run this tool with the Ruby environment used by CocoaPods' if prefix.empty?
  gems = File.join(prefix, 'libexec')
  Gem.use_paths(gems, [gems, *Gem.path])
  require 'xcodeproj'
end

integration = ARGV.length == 4 && ARGV.last == '--integration'
abort 'Usage: add_ios_ui_test_target.rb PROJECT APP_TARGET TESTS_DIRECTORY [--integration]' unless ARGV.length == 3 || integration

project_path, app_name, source_directory = ARGV.first(3)
project_path = File.expand_path(project_path)
source_directory = File.expand_path(source_directory)
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == app_name }
abort "App target not found: #{app_name}" unless app
sources = Dir.glob(File.join(source_directory, integration ? '*.m' : '*.swift')).sort
abort "No test sources in #{source_directory}" if sources.empty?

name = integration ? 'WebViewResourceIntegrationTests' : 'WebViewGestureUITests'
target = project.targets.find { |value| value.name == name }
unless target
  target = project.new_target(integration ? :unit_test_bundle : :ui_test_bundle, name, :ios, '17.0')
  target.add_dependency(app)
end
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(
    'TEST_TARGET_NAME' => app_name,
    'PRODUCT_NAME' => name,
    'PRODUCT_MODULE_NAME' => name,
    'PRODUCT_BUNDLE_IDENTIFIER' => integration ? 'com.abandoft.webviewall.ResourceIntegrationTests' : 'com.abandoft.webviewall.GestureUITests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'SWIFT_VERSION' => '5.0',
    'CODE_SIGNING_ALLOWED' => 'NO'
  )
  if integration
    app_config = app.build_configurations.find { |value| value.name == configuration.name }
    configuration.base_configuration_reference = app_config.base_configuration_reference
    configuration.build_settings.merge!(
      'TEST_HOST' => "$(BUILT_PRODUCTS_DIR)/#{app_name}.app/#{app_name}",
      'BUNDLE_LOADER' => '$(TEST_HOST)',
      'CLANG_ENABLE_MODULES' => 'YES',
      'CLANG_ENABLE_OBJC_ARC' => 'YES',
      'HEADER_SEARCH_PATHS' => ['$(inherited)', '$(FLUTTER_ROOT)/packages/integration_test/ios/integration_test/Sources/integration_test/include']
    )
  end
end
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][target.uuid] = { 'TestTargetID' => app.uuid }
group = project.main_group.find_subpath(name, true)
sources.each do |source|
  relative_path = Pathname.new(source).relative_path_from(Pathname.new(File.dirname(project_path))).to_s
  reference = group.files.find { |file| file.path == relative_path } || group.new_file(relative_path)
  unless target.source_build_phase.files_references.include?(reference)
    target.add_file_references([reference])
  end
end

project.save
original = File.join(project_path, 'xcshareddata', 'xcschemes', "#{app_name}.xcscheme")
scheme = Xcodeproj::XCScheme.new(original)
unless scheme.test_action.testables.any? { |test| test.buildable_references.any? { |ref| ref.target_uuid == target.uuid } }
  scheme.add_build_target(target)
  scheme.add_test_target(target)
end
scheme.save_as(project_path, name, true)
puts "Prepared #{name}"
