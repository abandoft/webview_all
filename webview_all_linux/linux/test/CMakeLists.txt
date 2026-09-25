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
# Download policy tests do not use the desktop accessibility service.
set_tests_properties(download_policy PROPERTIES
  TIMEOUT 60
  ENVIRONMENT "NO_AT_BRIDGE=1"
)
