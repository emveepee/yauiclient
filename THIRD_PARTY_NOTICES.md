# Third-party notices

yauiclient is licensed under the MIT License (see [LICENSE](LICENSE)). This repository
also contains the third-party code listed below, each under its own licence. The
licence text or notice in each component's files is the authoritative version.

## Bundled in this repository

| Component | Location | Author | Licence |
|---|---|---|---|
| nlohmann/json | `third_party/nlohmann/` | Niels Lohmann | MIT, see `third_party/nlohmann/LICENSE.MIT` |
| Hedley (used by nlohmann/json) | `third_party/nlohmann/thirdparty/hedley/` | Evan Nemerson | CC0 1.0 |
| fpng | `fpng.cpp`, `fpng.h` | Rich Geldreich | Public domain (Unlicense), see file header |
| stb_image | `stb_image.h` | Sean Barrett | Public domain or MIT, at your choice, see end of file |
| mpv client API headers | `deps/include/mpv/` | The mpv developers | ISC, see file headers |

## Used at build or run time, not included in this repository

These are obtained separately (vcpkg, system packages, Homebrew, CMake FetchContent,
or the libmpv SDK) and are covered by their own licences:

- libmpv, FFmpeg, libplacebo: LGPL or GPL, depending on how the SDK was configured.
  Binary releases that ship these libraries must meet the obligations of those
  licences, including making the corresponding source available.
- cpr (MIT), libcurl (curl licence), fmt (MIT), GLFW (zlib), GLEW (Modified BSD / MIT),
  zlib (zlib).
