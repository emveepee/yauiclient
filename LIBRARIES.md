# Libraries

Versions of the third-party libraries used by yauiclient, where each comes from,
and how updates are handled. The README's dependency table gives the short form.

## Current versions (Windows build, 2026-10-25)

| Library | Version | Source | Licence |
|---|---|---|---|
| libmpv | 0.41.0 | libmpv SDK (`src/deps/` for the Visual Studio solution, `sdk/` for CMake) | LGPL-2.1+ / GPL, depending on build configuration |
| mpv client headers | 0.41.0 | `src/deps/include/mpv` | ISC |
| FFmpeg | Set by the libmpv build | Bundled in the libmpv SDK runtime; the libmpv builder picks the FFmpeg version each mpv tag needs | LGPL / GPL, depending on build configuration |
| libplacebo | Set by the libmpv build | Bundled in the libmpv SDK runtime | LGPL-2.1+ |
| cpr | 1.14.2 | vcpkg (Visual Studio solution); FetchContent `GIT_TAG 1.14.2` (CMake) | MIT |
| libcurl | 8.18.0 | vcpkg | curl licence (MIT-style) |
| fmt | 12.1.0 | vcpkg | MIT |
| GLFW | 3.4 (Windows); 3.5.1 (Debian 12 workflow) | vcpkg (Windows); built from source in the Debian 12 workflow | zlib |
| GLEW | — | vcpkg (Windows only) | Modified BSD / MIT |
| zlib | 1.3.1 | vcpkg | zlib |
| nlohmann/json | 3.12.0 | `src/third_party/nlohmann` (all builds), refreshed from vcpkg | MIT |
| fpng | — | `src/third_party/fpng/` | Public domain (Unlicense) |
| stb_image | — | `src/third_party/stb/` | Public domain or MIT |

Exact vcpkg versions and port revisions are recorded in `src/deps/vcpkg-list.txt`.

## Pending updates

From `vcpkg upgrade` (dry run), not yet applied.

| Library | Current | Available | Kind | Watch for |
|---|---|---|---|---|
| GLFW | 3.4 | 3.5.1 | Minor | Callback and event-loop behaviour changes have happened within 3.x. Read the release notes. The Debian 12 workflow is already on 3.5.1. |
| cpr | 1.14.2 | 1.15.1 | Minor | cpr has changed APIs in minor releases. Check `VerifySsl`, timeouts and session options. If updated, change the CMake `GIT_TAG` to match. |
| libcurl | 8.18.0 | 8.23.0 | Minor | Stable ABI, but defaults (TLS, redirects) change. Used only through cpr. |
| fmt | 12.1.0 | 12.2.0 | Minor | Low risk. Breaking changes are kept to major versions. |
| zlib | 1.3.1 | 1.3.2 | Patch | Negligible. |
| opengl-registry | 2026-01-26 | 2026-08-03 | Headers | Negligible. |
| vcpkg-cmake, vcpkg-cmake-config | — | — | Build tooling | Does not affect the binary. |

## Update procedure (Windows)

1. Snapshot the current packages with `vcpkg export ... --zip` (outside the repo) and
   record `vcpkg list` and the vcpkg commit in `src/deps/vcpkg-list.txt`.
2. Run `vcpkg upgrade` and classify each change as major, minor or patch in the
   table above before applying anything.
3. Run `vcpkg upgrade --no-dry-run`, then Rebuild Solution for Debug and Release.
4. Refresh `src/third_party/nlohmann` from `C:\vcpkg\installed\x64-windows\include\nlohmann`,
   and `LICENSE.MIT` from `C:\vcpkg\installed\x64-windows\share\nlohmann-json\copyright`.
5. Smoke test: login, live TV start, pause, stop, a recording, thumbnails.
6. Update the version table and `src/deps/vcpkg-list.txt`, then commit.

To revert to the snapshot, set `VcpkgInstalledDir` in `yauiclient.vcxproj` to the
snapshot's `installed\` folder (trailing backslash required) and rebuild.

## Checking versions

Run these from `src\`.

- nlohmann/json: `findstr /C:"#define NLOHMANN_JSON_VERSION_" third_party\nlohmann\detail\abi_macros.hpp`
- mpv client API: `findstr MPV_CLIENT_API_VERSION deps\include\mpv\client.h`
- vcpkg packages: `C:\vcpkg\vcpkg list`
