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

option(YAUI_RPI  "Raspberry Pi family target" OFF)
option(YAUI_LEGL "LibreELEC X11/OpenGL target build (Generic-legacy)" OFF)
option(YAUI_LEGBM "LibreELEC GBM/GLES target build (Generic non-legacy)" OFF)

# Validate — LEGL and LEGBM are mutually exclusive
if(YAUI_LEGL AND YAUI_LEGBM)
  message(FATAL_ERROR "YAUI_LEGL and YAUI_LEGBM are mutually exclusive — pick one")
endif()

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
if(NOT YAUI_LEGBM)
  find_package(glfw3 QUIET)
  if(glfw3_FOUND)
    target_link_libraries(yauiclient PRIVATE glfw)
  else()
    pkg_check_modules(GLFW3 REQUIRED glfw3)
    target_include_directories(yauiclient PRIVATE ${GLFW3_INCLUDE_DIRS})
    target_link_libraries(yauiclient PRIVATE ${GLFW3_LIBRARIES})
    target_link_directories(yauiclient PRIVATE ${GLFW3_LIBRARY_DIRS})
  endif()
else()
  # GBM path: try GLFW with Wayland/EGL backend first (Option A)
  # Falls back gracefully if not found — Option C uses direct GBM/EGL
  find_package(glfw3 QUIET)
  if(glfw3_FOUND)
    target_link_libraries(yauiclient PRIVATE glfw)
    message(STATUS "YAUI_LEGBM: GLFW found — using Wayland/EGL backend (Option A)")
  else()
    pkg_check_modules(GLFW3 QUIET glfw3)
    if(GLFW3_FOUND)
      target_include_directories(yauiclient PRIVATE ${GLFW3_INCLUDE_DIRS})
      target_link_libraries(yauiclient PRIVATE ${GLFW3_LIBRARIES})
      target_link_directories(yauiclient PRIVATE ${GLFW3_LIBRARY_DIRS})
      message(STATUS "YAUI_LEGBM: GLFW found via pkg-config (Option A)")
    else()
      message(STATUS "YAUI_LEGBM: GLFW not found — direct GBM/EGL path (Option C)")
    endif()
  endif()
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
# OpenGL / GLES
# ---------------------------------------------------------------------------
if(YAUI_LEGBM)
  # GBM/GLES path — link EGL, GLESv2, gbm, drm directly
  # These are in the base LE Generic image sysroot, no find_package needed
  pkg_check_modules(GBM   REQUIRED gbm)
  pkg_check_modules(EGL   REQUIRED egl)
  pkg_check_modules(GLES2 REQUIRED glesv2)
  pkg_check_modules(DRM   REQUIRED libdrm)

  target_include_directories(yauiclient PRIVATE
    ${GBM_INCLUDE_DIRS}
    ${EGL_INCLUDE_DIRS}
    ${GLES2_INCLUDE_DIRS}
    ${DRM_INCLUDE_DIRS}
  )
  target_link_libraries(yauiclient PRIVATE
    ${GBM_LIBRARIES}
    ${EGL_LIBRARIES}
    ${GLES2_LIBRARIES}
    ${DRM_LIBRARIES}
  )
  target_link_directories(yauiclient PRIVATE
    ${GBM_LIBRARY_DIRS}
    ${EGL_LIBRARY_DIRS}
    ${GLES2_LIBRARY_DIRS}
    ${DRM_LIBRARY_DIRS}
  )
  target_compile_definitions(yauiclient PRIVATE YAUI_LEGBM)
  message(STATUS "YAUI_LEGBM: GBM/GLES/EGL/DRM linked")
else()
  find_package(OpenGL REQUIRED)
  target_link_libraries(yauiclient PRIVATE OpenGL::GL)
endif()

# ---------------------------------------------------------------------------
# cpr + libcurl
# ---------------------------------------------------------------------------
if(PLATFORM_LINUX OR PLATFORM_MACOS)
  find_package(cpr QUIET)
  if(NOT cpr_FOUND AND NOT YAUI_LEGL AND NOT YAUI_LEGBM)
    message(STATUS "cpr not found as system package - fetching via FetchContent")
    include(FetchContent)
    FetchContent_Declare(
      cpr
      GIT_REPOSITORY https://github.com/libcpr/cpr.git
      GIT_TAG        1.14.2
    )
    set(CPR_USE_SYSTEM_CURL ON CACHE BOOL "" FORCE)
    set(CPR_ENABLE_SSL OFF CACHE BOOL "" FORCE)
    set(CPR_USE_SYSTEM_CURL ON CACHE BOOL "" FORCE)
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

  if(YAUI_LEGL)
    target_compile_definitions(yauiclient PRIVATE YAUI_LEGL)
  endif()

  if(YAUI_RPI)
    target_compile_definitions(yauiclient PRIVATE YAUI_RPI)
  endif()

  target_compile_options(yauiclient PRIVATE -Wall -Wextra -Wno-unused-parameter)
  set_target_properties(yauiclient PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
    BUILD_WITH_INSTALL_RPATH FALSE
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