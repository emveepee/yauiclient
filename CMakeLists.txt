cmake_minimum_required(VERSION 3.20)

set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version")

project(yauiclient VERSION 1.0.0 LANGUAGES C CXX)

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
option(YAUI_WAYLAND "Generic Wayland target build (Ubuntu/Debian/Arch desktop, Phase 8)" OFF)
option(YAUI_DEB_LAYOUT "Use Debian package layout for rpath (/usr/lib/yauiclient/lib)" OFF)

# Validate — LEGL, LEGBM and WAYLAND are mutually exclusive
if(YAUI_LEGL AND YAUI_LEGBM)
  message(FATAL_ERROR "YAUI_LEGL and YAUI_LEGBM are mutually exclusive — pick one")
endif()
if(YAUI_WAYLAND AND (YAUI_LEGL OR YAUI_LEGBM OR YAUI_RPI))
  message(FATAL_ERROR
    "YAUI_WAYLAND is mutually exclusive with YAUI_LEGL/YAUI_LEGBM/YAUI_RPI — pick one")
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

if(YAUI_WAYLAND)
  list(APPEND SOURCES src/WaylandIdleInhibit.cpp)
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

  if(NOT YAUI_LEGBM AND NOT YAUI_WAYLAND)
    target_link_libraries(yauiclient PRIVATE X11 Xfixes)
  endif()

  # -------------------------------------------------------------------------
  # YAUI_WAYLAND — Phase 8 generic Wayland desktop build
  # -------------------------------------------------------------------------
  # Targets Ubuntu 24.04+ / Debian 12+ / Arch with native Wayland (Mutter /
  # KWin / wlroots-based compositors). GLFW 3.4 is required for the
  # GLFW_PLATFORM init hint and the GLFW_WAYLAND_APP_ID window hint string.
  # The libmpv 0.41.0 SDK from the Phase 8 wiki tarball is consumed via the
  # existing LIBMPV_SDK_DIR mechanism above; the matching runtime tarball
  # gets bundled into the .deb at /usr/lib/yauiclient/lib/, so we override
  # the default $ORIGIN rpath to reach it from /usr/bin/yauiclient.
  if(YAUI_WAYLAND)
    target_compile_definitions(yauiclient PRIVATE YAUI_WAYLAND)

    # wayland-client and wayland-protocols (data-only XML repository).
    pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)
    pkg_check_modules(WAYLAND_PROTOCOLS REQUIRED wayland-protocols>=1.41)
    target_link_libraries(yauiclient PRIVATE PkgConfig::WAYLAND_CLIENT)

    # Locate wayland-scanner and the protocol XML directory. The scanner
    # binary path is exposed under the 'wayland_scanner' variable in the
    # wayland-scanner.pc file; older layouts only expose 'bindir'.
    pkg_check_modules(WAYLAND_SCANNER_PC REQUIRED wayland-scanner)
    pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
    pkg_get_variable(WAYLAND_SCANNER_BIN wayland-scanner wayland_scanner)
    if(NOT WAYLAND_SCANNER_BIN)
      pkg_get_variable(WS_BINDIR wayland-scanner bindir)
      find_program(WAYLAND_SCANNER_BIN wayland-scanner HINTS "${WS_BINDIR}")
    endif()
    if(NOT WAYLAND_SCANNER_BIN)
      message(FATAL_ERROR
        "wayland-scanner not found — install libwayland-bin / wayland-scanner")
    endif()
    message(STATUS "YAUI_WAYLAND: wayland-scanner at ${WAYLAND_SCANNER_BIN}")
    message(STATUS "YAUI_WAYLAND: wayland-protocols at ${WAYLAND_PROTOCOLS_DIR}")

    # idle-inhibit-unstable-v1 protocol — generate client header + private
    # code into the build tree, then add them to the target sources.
    set(IDLE_INHIBIT_XML
      "${WAYLAND_PROTOCOLS_DIR}/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml")
    if(NOT EXISTS "${IDLE_INHIBIT_XML}")
      message(FATAL_ERROR
        "idle-inhibit-unstable-v1.xml not found at ${IDLE_INHIBIT_XML}")
    endif()
    set(WL_PROTO_DIR "${CMAKE_BINARY_DIR}/wayland-protocols")
    set(IDLE_INHIBIT_HEADER
      "${WL_PROTO_DIR}/idle-inhibit-unstable-v1-client-protocol.h")
    set(IDLE_INHIBIT_SOURCE
      "${WL_PROTO_DIR}/idle-inhibit-unstable-v1-protocol.c")

    add_custom_command(
      OUTPUT  "${IDLE_INHIBIT_HEADER}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${WL_PROTO_DIR}"
      COMMAND "${WAYLAND_SCANNER_BIN}" client-header
              "${IDLE_INHIBIT_XML}" "${IDLE_INHIBIT_HEADER}"
      DEPENDS "${IDLE_INHIBIT_XML}"
      VERBATIM)

    add_custom_command(
      OUTPUT  "${IDLE_INHIBIT_SOURCE}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${WL_PROTO_DIR}"
      COMMAND "${WAYLAND_SCANNER_BIN}" private-code
              "${IDLE_INHIBIT_XML}" "${IDLE_INHIBIT_SOURCE}"
      DEPENDS "${IDLE_INHIBIT_XML}"
      VERBATIM)

    target_sources(yauiclient PRIVATE
      "${IDLE_INHIBIT_HEADER}"
      "${IDLE_INHIBIT_SOURCE}")
    set_source_files_properties(
      "${IDLE_INHIBIT_HEADER}"
      "${IDLE_INHIBIT_SOURCE}"
      PROPERTIES GENERATED TRUE)
    target_include_directories(yauiclient PRIVATE "${WL_PROTO_DIR}")

    # rpath: where this binary should look for libmpv and its bundled deps.
    # Two layouts supported:
    #   default                bin/Release/yauiclient with libs alongside
    #                          -> $ORIGIN
    #   -DYAUI_DEB_LAYOUT=ON   /usr/bin/yauiclient with libs in
    #                          /usr/lib/yauiclient/lib
    #                          -> $ORIGIN/../lib/yauiclient/lib
    # BUILD_WITH_INSTALL_RPATH=TRUE makes the build-tree binary use
    # INSTALL_RPATH directly instead of CMake's separate build-tree rpath
    # logic, so we get a clean, relocatable $ORIGIN with no absolute paths
    # and no trailing-colon artefacts.
    if(YAUI_DEB_LAYOUT)
      set(_yc_rpath "\$ORIGIN/../lib/yauiclient/lib")
    else()
      set(_yc_rpath "\$ORIGIN")
    endif()
    set_target_properties(yauiclient PROPERTIES
      BUILD_WITH_INSTALL_RPATH TRUE
      BUILD_RPATH   "${_yc_rpath}"
      INSTALL_RPATH "${_yc_rpath}")
  endif()

  target_compile_options(yauiclient PRIVATE -Wall -Wextra -Wno-unused-parameter)
  if(NOT YAUI_WAYLAND)
    # Default rpath for LE / RPi / dev-tree builds where libmpv.so sits in
    # the same dir as the binary. The YAUI_WAYLAND branch above sets its
    # own rpath honoring -DYAUI_DEB_LAYOUT for the .deb layout; this branch
    # also honors YAUI_DEB_LAYOUT so the X11 .deb flavour (yauiclient-x11)
    # can bundle libmpv into /usr/lib/yauiclient/lib/.
    # BUILD_WITH_INSTALL_RPATH=TRUE makes the build-tree binary use
    # INSTALL_RPATH directly so $ORIGIN is the same in the build tree
    # and after install (no absolute paths, no trailing-colon artefacts).
    if(YAUI_DEB_LAYOUT)
      set(_yc_rpath_x11 "\$ORIGIN/../lib/yauiclient/lib")
    else()
      set(_yc_rpath_x11 "\$ORIGIN")
    endif()
    set_target_properties(yauiclient PROPERTIES
      BUILD_WITH_INSTALL_RPATH TRUE
      BUILD_RPATH   "${_yc_rpath_x11}"
      INSTALL_RPATH "${_yc_rpath_x11}")
  endif()

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