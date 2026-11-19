cmake_minimum_required(VERSION 3.15)
project(povarnya_reserved_modules LANGUAGES CXX)

# Build the vendored library as a shared object so the Dart FFI spell-check
# service can load it from the APK.
set(BUILD_SHARED_LIBS ON)
add_subdirectory(
  "${CMAKE_CURRENT_LIST_DIR}/../../../../../third_party/hunspell"
  "${CMAKE_BINARY_DIR}/hunspell"
)
