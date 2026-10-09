cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "webview_all_linux")
project(${PROJECT_NAME} LANGUAGES CXX C)

cmake_policy(VERSION 3.10...3.24)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")
set(SENDER_EXTENSION_NAME "${PROJECT_NAME}_sender_extension")

find_package(PkgConfig REQUIRED)
pkg_check_modules(WEBKIT REQUIRED IMPORTED_TARGET webkit2gtk-4.1)
pkg_check_modules(WEBKIT_WEB_EXTENSION REQUIRED IMPORTED_TARGET
  webkit2gtk-web-extension-4.1)

add_library(${PLUGIN_NAME} SHARED
  "src/common/method_channel_utils.cc"
  "src/platform/flutter_view.cc"
  "src/plugin/webview_all_linux_plugin.cc"
  "src/plugin/root_channel.cc"
  "src/webview/linux_webview.cc"
  "src/webview/download_policy.cc"
  "src/webview/webview_javascript.cc"
  "src/webview/webview_method_handler.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::WEBKIT)
target_link_libraries(${PLUGIN_NAME} PRIVATE ${CMAKE_DL_LIBS})

# The web-process extension that defines each JavaScript channel object and
# reports each message's sending document. WebKitGTK loads every library in a
# web-extension folder into the web process, so this one installs alone into a
# folder of its own (see the `install` rule below), never the bundle's `lib/`.
add_library(${SENDER_EXTENSION_NAME} SHARED
  "src/extension/channel_sender_extension.c"
)
apply_standard_settings(${SENDER_EXTENSION_NAME})
# It links only system libraries, so it installs with no RUNPATH instead of
# the runner's `$ORIGIN/lib`.
set_target_properties(${SENDER_EXTENSION_NAME} PROPERTIES
  C_VISIBILITY_PRESET hidden
  INSTALL_RPATH ""
)
target_link_libraries(${SENDER_EXTENSION_NAME} PRIVATE
  PkgConfig::WEBKIT_WEB_EXTENSION
)

# Installs the extension alone into its folder of the app bundle; the relative
# destination resolves against the bundle at install time. Names are literal:
# a deferred call runs in the runner's directory, where this file's variables
# are unset. The folder must match `kWebExtensionsDirectoryName` in
# `src/plugin/webview_all_linux_plugin.cc`.
function(webview_all_linux_install_web_extension)
  install(TARGETS webview_all_linux_sender_extension
    LIBRARY DESTINATION "lib/webview_all_linux_web_extensions"
    COMPONENT Runtime
  )
endfunction()

# The runner, the directory that adds this one, empties the bundle in its
# first install rule. From CMake 3.19 the rule above is deferred to the end of
# the runner's directory, so it runs after that wipe whatever the runner's
# CMP0082 or INSTALL_PARALLEL setting. Older CMake has no DEFER: the rule runs
# after the wipe only while the runner keeps CMP0082 unset (OLD), as Flutter's
# Linux app template (`cmake_minimum_required(VERSION 3.13)`) does.
if(CMAKE_VERSION VERSION_LESS 3.19)
  webview_all_linux_install_web_extension()
else()
  get_directory_property(RUNNER_DIRECTORY PARENT_DIRECTORY)
  cmake_language(DEFER DIRECTORY "${RUNNER_DIRECTORY}"
    CALL webview_all_linux_install_web_extension
  )
endif()
