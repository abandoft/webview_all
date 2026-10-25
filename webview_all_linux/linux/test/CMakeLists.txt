cmake_minimum_required(VERSION 3.10)
project(webview_all_linux_native_tests LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(WEBKIT REQUIRED IMPORTED_TARGET webkit2gtk-4.1)

add_executable(download_policy_test
  download_policy_test.cc
  ../src/webview/download_policy.cc
)
target_include_directories(download_policy_test PRIVATE ../src)
target_link_libraries(download_policy_test PRIVATE PkgConfig::WEBKIT)
target_compile_options(download_policy_test PRIVATE -Wall -Wextra -Werror
  -Wno-unused-parameter)

enable_testing()
add_test(NAME download_policy COMMAND download_policy_test)
add_executable(message_bridge_test message_bridge_test.cc)
target_link_libraries(message_bridge_test PRIVATE PkgConfig::WEBKIT)
target_compile_options(message_bridge_test PRIVATE -Wall -Wextra -Werror
  -Wno-unused-parameter)
add_test(NAME message_bridge COMMAND message_bridge_test)
add_executable(scroll_hook_test scroll_hook_test.cc)
target_link_libraries(scroll_hook_test PRIVATE PkgConfig::WEBKIT)
target_compile_options(scroll_hook_test PRIVATE -Wall -Wextra -Werror
  -Wno-unused-parameter)
add_test(NAME scroll_hook COMMAND scroll_hook_test)
add_executable(environment_test
  environment_test.cc
  ../src/webview/webview_environment.cc
)
target_include_directories(environment_test PRIVATE ../src)
target_link_libraries(environment_test PRIVATE PkgConfig::WEBKIT)
target_compile_options(environment_test PRIVATE -Wall -Wextra -Werror
  -Wno-unused-parameter)
add_test(NAME environment COMMAND environment_test)
# Download policy tests do not use the desktop accessibility service.
set_tests_properties(download_policy message_bridge scroll_hook environment PROPERTIES
  TIMEOUT 60
  ENVIRONMENT "NO_AT_BRIDGE=1"
)
