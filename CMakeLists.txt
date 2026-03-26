cmake_minimum_required(VERSION 3.20)

set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version")

project(yauiclient VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_SKIP_RPATH FALSE)
set(CMAKE_SKIP_INSTALL_RPATH FALSE)
set(CMAKE_BUILD_RPATH_USE_ORIGIN TRUE)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(YAUICLIENT_USE_SYSTEM_MPV "Use system libmpv instead of SDK" OFF)
set(LIBMPV_SDK_DIR "${CMAKE_SOURCE_DIR}/sdk" CACHE PATH
    "Path to libmpv SDK directory (contains include/ and lib/)")

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
if(WIN32)
  set(PLATFORM_WINDOWS TRUE)
elseif(APPLE)
  set(PLATFORM_MACOS TRUE)
elseif(UNIX)
  set(PLATFORM_LINUX TRUE)
endif()

# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
set(SOURCES
    src/AppMain.cpp
    src/LibmpvPlayer.cpp
    src/main.cpp
    src/MediaControl.cpp
    src/MpvCommand.cpp
    src/OverlayRenderer.cpp
    src/stb_image_impl.cpp
    src/UserConfig.cpp
    src/Utility.cpp
)

if(PLATFORM_WINDOWS)
  list(APPEND SOURCES src/WinMain.cpp)
endif()

# ---------------------------------------------------------------------------
# Executable
# ---------------------------------------------------------------------------
if(PLATFORM_WINDOWS)
  add_executable(yauiclient WIN32 ${SOURCES})
else()
  add_executable(yauiclient ${SOURCES})
endif()

target_include_directories(yauiclient PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

# ---------------------------------------------------------------------------
# libmpv
# ---------------------------------------------------------------------------
if(YAUICLIENT_USE_SYSTEM_MPV)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(MPV REQUIRED mpv)
  target_include_directories(yauiclient PRIVATE ${MPV_INCLUDE_DIRS})
  target_link_libraries(yauiclient PRIVATE ${MPV_LIBRARIES})
  target_link_directories(yauiclient PRIVATE ${MPV_LIBRARY_DIRS})
elseif(LIBMPV_SDK_DIR)
  if(NOT EXISTS "${LIBMPV_SDK_DIR}/include/mpv/client.h")
    message(FATAL_ERROR
      "libmpv SDK not found at ${LIBMPV_SDK_DIR}\n"
      "Download the SDK tarball from the wiki and extract it to sdk/:\n"
      "  tar xzf libmpv-sdk-vX.X.X-linux-x86_64.tar.gz -C sdk/\n"
      "Or pass -DYAUICLIENT_USE_SYSTEM_MPV=ON to use the system libmpv.")
  endif()
  target_include_directories(yauiclient PRIVATE "${LIBMPV_SDK_DIR}/include")
  if(PLATFORM_WINDOWS)
    target_link_libraries(yauiclient PRIVATE "${LIBMPV_SDK_DIR}/lib/libmpv.lib")
  else()
    target_link_libraries(yauiclient PRIVATE "${LIBMPV_SDK_DIR}/lib/libmpv.so")
  endif()
else()
  message(FATAL_ERROR
    "Set -DLIBMPV_SDK_DIR=/path/to/sdk or -DYAUICLIENT_USE_SYSTEM_MPV=ON")
endif()

# ---------------------------------------------------------------------------
# find_package helpers
# ---------------------------------------------------------------------------
find_package(PkgConfig REQUIRED)

# ---------------------------------------------------------------------------
# fmt
# ---------------------------------------------------------------------------
find_package(fmt QUIET)
if(NOT fmt_FOUND)
  pkg_check_modules(FMT REQUIRED fmt)
  target_include_directories(yauiclient PRIVATE ${FMT_INCLUDE_DIRS})
  target_link_libraries(yauiclient PRIVATE ${FMT_LIBRARIES})
  target_link_directories(yauiclient PRIVATE ${FMT_LIBRARY_DIRS})
else()
  target_link_libraries(yauiclient PRIVATE fmt::fmt)
endif()

# ---------------------------------------------------------------------------
# nlohmann_json (header-only)
# ---------------------------------------------------------------------------
find_package(nlohmann_json QUIET)
if(nlohmann_json_FOUND)
  target_link_libraries(yauiclient PRIVATE nlohmann_json::nlohmann_json)
else()
  pkg_check_modules(NLOHMANN_JSON QUIET nlohmann_json)
  if(NLOHMANN_JSON_FOUND)
    target_include_directories(yauiclient PRIVATE ${NLOHMANN_JSON_INCLUDE_DIRS})
  else()
    find_path(NLOHMANN_JSON_INCLUDE nlohmann/json.hpp
      HINTS /usr/include /usr/local/include /opt/homebrew/include)
    if(NLOHMANN_JSON_INCLUDE)
      target_include_directories(yauiclient PRIVATE ${NLOHMANN_JSON_INCLUDE})
    else()
      message(FATAL_ERROR "nlohmann/json.hpp not found - install nlohmann-json")
    endif()
  endif()
endif()

# ---------------------------------------------------------------------------
# zlib
# ---------------------------------------------------------------------------
find_package(ZLIB REQUIRED)
target_link_libraries(yauiclient PRIVATE ZLIB::ZLIB)

# ---------------------------------------------------------------------------
# GLFW3
# ---------------------------------------------------------------------------
find_package(glfw3 QUIET)
if(glfw3_FOUND)
  target_link_libraries(yauiclient PRIVATE glfw)
else()
  pkg_check_modules(GLFW3 REQUIRED glfw3)
  target_include_directories(yauiclient PRIVATE ${GLFW3_INCLUDE_DIRS})
  target_link_libraries(yauiclient PRIVATE ${GLFW3_LIBRARIES})
  target_link_directories(yauiclient PRIVATE ${GLFW3_LIBRARY_DIRS})
endif()

# ---------------------------------------------------------------------------
# GLEW (Windows only)
# ---------------------------------------------------------------------------
if(PLATFORM_WINDOWS)
  find_package(GLEW REQUIRED)
  target_link_libraries(yauiclient PRIVATE GLEW::GLEW)
  target_compile_definitions(yauiclient PRIVATE GLEW_STATIC)
endif()

# ---------------------------------------------------------------------------
# OpenGL
# ---------------------------------------------------------------------------
find_package(OpenGL REQUIRED)
target_link_libraries(yauiclient PRIVATE OpenGL::GL)

# ---------------------------------------------------------------------------
# cpr + libcurl
# ---------------------------------------------------------------------------
if(PLATFORM_LINUX OR PLATFORM_MACOS)
  find_package(cpr QUIET)
  if(NOT cpr_FOUND)
    message(STATUS "cpr not found as system package - fetching via FetchContent")
    include(FetchContent)
    FetchContent_Declare(
      cpr
      GIT_REPOSITORY https://github.com/libcpr/cpr.git
      GIT_TAG        1.11.0
    )
    set(CPR_USE_SYSTEM_CURL ON CACHE BOOL "" FORCE)
    set(CPR_ENABLE_SSL ON CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(cpr)
  endif()
  target_link_libraries(yauiclient PRIVATE cpr::cpr)
else()
  find_package(cpr REQUIRED)
  target_link_libraries(yauiclient PRIVATE cpr::cpr)
endif()

find_package(CURL REQUIRED)
target_link_libraries(yauiclient PRIVATE CURL::libcurl)

# ---------------------------------------------------------------------------
# Platform-specific
# ---------------------------------------------------------------------------
if(PLATFORM_WINDOWS)
  target_compile_definitions(yauiclient PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _WIN32_WINNT=0x0A00
    UNICODE
    _UNICODE
  )
  target_link_libraries(yauiclient PRIVATE
    dwmapi opengl32 gdi32 user32 shell32 ole32 advapi32
  )
  if(MSVC)
    target_compile_options(yauiclient PRIVATE
      /W3 /utf-8 /Zc:__cplusplus /EHsc
    )
    set_property(TARGET yauiclient PROPERTY
      MSVC_RUNTIME_LIBRARY "MultiThreadedDLL$<$<CONFIG:Debug>:Debug>")
  endif()

elseif(PLATFORM_LINUX)
  target_link_libraries(yauiclient PRIVATE dl pthread)
  pkg_check_modules(LIBBLURAY QUIET libbluray)
  if(LIBBLURAY_FOUND)
    target_link_libraries(yauiclient PRIVATE ${LIBBLURAY_LIBRARIES})
    target_link_directories(yauiclient PRIVATE ${LIBBLURAY_LIBRARY_DIRS})
  else()
    target_link_libraries(yauiclient PRIVATE bluray)
  endif()
  find_package(JPEG QUIET)
  if(JPEG_FOUND)
    target_link_libraries(yauiclient PRIVATE JPEG::JPEG)
  endif()
  target_compile_options(yauiclient PRIVATE -Wall -Wextra -Wno-unused-parameter)
  set_target_properties(yauiclient PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    BUILD_WITH_INSTALL_RPATH TRUE
    SKIP_BUILD_RPATH FALSE
    BUILD_RPATH_USE_ORIGIN TRUE
  )

elseif(PLATFORM_MACOS)
  target_compile_definitions(yauiclient PRIVATE GL_SILENCE_DEPRECATION)
  target_link_libraries(yauiclient PRIVATE
    "-framework Cocoa"
    "-framework CoreVideo"
    "-framework CoreMedia"
    "-framework IOKit"
    "-framework VideoToolbox"
    "-framework AudioToolbox"
  )
  target_compile_options(yauiclient PRIVATE -Wall -Wextra -Wno-unused-parameter)
  set_target_properties(yauiclient PROPERTIES
    INSTALL_RPATH "@executable_path;@executable_path/../lib;@executable_path/../Frameworks"
    BUILD_WITH_INSTALL_RPATH TRUE
  )
endif()

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install(TARGETS yauiclient
  RUNTIME DESTINATION bin
  BUNDLE  DESTINATION .
)