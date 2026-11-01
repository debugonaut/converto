cmake_minimum_required(VERSION 3.14)
project(converto LANGUAGES CXX)

set(BINARY_NAME "converto")

cmake_policy(SET CMP0079 NEW)

# Set build type to Release by default if not set
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Release" CACHE
      STRING "Choose the type of build." FORCE)
endif()

# Compiler options
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure build paths
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIRECTORY}/runner")

# Include Flutter library
include(flutter/generated_plugins.cmake OPTIONAL)

# Runner executable sources
set(RUNNER_SOURCES
  "runner/flutter_window.cpp"
  "runner/main.cpp"
  "runner/utils.cpp"
  "runner/win32_window.cpp"
  "runner/Runner.rc"
  "runner/runner.exe.manifest"
)

add_executable(${BINARY_NAME} WIN32
  ${RUNNER_SOURCES}
)

target_compile_definitions(${BINARY_NAME} PRIVATE
  "_UNICODE"
  "UNICODE"
)

target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/runner"
)

set_target_properties(${BINARY_NAME} PROPERTIES
  OUTPUT_NAME "converto"
)

