# Third-party software

watchdog is Apache-2.0 (see `LICENSE`, `NOTICE`). This file lists what it depends on at runtime. Generated from `dart pub deps --no-dev` and each package's own LICENSE file (detected by text match; confirm before release). Dev-only tooling (build_runner, drift_dev, lints, test) is not shipped and not listed. Versions are those in `pubspec.lock`.

## Native libraries in the Android APK

| Component | Version | License | Source |
|---|---|---|---|
| libmpv (mpv, built `-Dgpl=false`) | commit 78d43740 | LGPL-2.1-or-later | https://github.com/mpv-player/mpv |
| FFmpeg (libavcodec, libavformat, libavutil, libavfilter, libswscale, libswresample), static in libmpv | 6.0 | LGPL-3.0-or-later (`--disable-gpl --enable-version3`, verified in binary) | https://ffmpeg.org |
| libass, freetype, harfbuzz, fribidi, mbedtls, dav1d, libxml2, static in libmpv | see `docs/LICENSE-ANALYSIS.md` | permissive / LGPL, unverified at build level | via https://github.com/media-kit/libmpv-android-video-build/tree/v1.1.7 |
| SQLite (`libsqlite3.so`, via package:sqlite3) | bundled by hook | Public domain | https://www.sqlite.org |
| Flutter engine (`libflutter.so`) | 3.50.1 | BSD-3-Clause plus bundled notices | https://github.com/flutter/flutter |

**LGPL compliance (Android APK).** libmpv and FFmpeg are LGPL and shipped as separate shared libraries, not statically merged into the app code, so they can be replaced by the user. The source offer and links are in `NOTICE`. Before each release, confirm the libmpv build version still matches the source link above.

## Native library on Linux

| Component | License | Note |
|---|---|---|
| libmpv (system, user-installed) | GPL-2+ or LGPL-2.1+ depending on distro build | Not distributed by this project |
| mimalloc 2.1.2 (downloaded by media_kit_libs_linux at build) | MIT | https://github.com/microsoft/mimalloc |

## Dart/Flutter packages

### Direct runtime dependencies

| Package | Version | License |
|---|---|---|
| android_intent_plus | 6.1.0 | BSD-3-Clause |
| background_downloader | 9.6.6 | MIT |
| cupertino_icons | 1.0.9 | MIT |
| drift | 2.35.4 | MIT |
| file_picker | 13.4.1 | MIT |
| flutter | 0.0.0 | BSD-3-Clause |
| flutter_riverpod | 3.5.0 | MIT |
| html | 0.15.7 | MIT |
| http | 1.6.0 | BSD-3-Clause |
| material_ui | 1.11.1 | BSD-3-Clause |
| media_kit | 1.2.6 | MIT |
| media_kit_libs_video | 1.0.7 | MIT |
| media_kit_video | 2.0.1 | MIT |
| path | 1.9.1 | BSD-3-Clause |
| path_provider | 2.1.6 | BSD-3-Clause |
| sqlite3 | 3.9.1 | MIT |

### Transitive runtime dependencies

| Package | Version | License |
|---|---|---|
| android_file_picker | 2.2.1 | MIT |
| archive | 4.7.1 | MIT |
| args | 2.7.0 | BSD-3-Clause |
| async | 2.13.1 | BSD-3-Clause |
| boolean_selector | 2.1.2 | BSD-3-Clause |
| characters | 1.4.1 | BSD-3-Clause |
| clock | 1.1.3 | Apache-2.0 |
| code_assets | 2.2.0 | BSD-3-Clause |
| collection | 1.19.1 | BSD-3-Clause |
| connectivity_plus | 7.3.2 | BSD-3-Clause |
| connectivity_plus_platform_interface | 2.1.0 | BSD-3-Clause |
| convert | 3.1.2 | BSD-3-Clause |
| cross_file | 0.3.5+5 | BSD-3-Clause |
| crypto | 3.0.8 | BSD-3-Clause |
| csslib | 1.0.2 | BSD-3-Clause |
| cupertino_ui | 1.1.7 | BSD-3-Clause |
| dbus | 0.8.1 | MPL-2.0 |
| fake_async | 1.3.3 | Apache-2.0 |
| ffi | 2.2.0 | BSD-3-Clause |
| ffi_leak_tracker | 0.1.2 | BSD-3-Clause |
| file | 7.0.1 | BSD-3-Clause |
| file_picker_darwin | 2.5.2 | MIT |
| file_picker_linux | 2.0.5 | MIT |
| file_picker_platform_interface | 4.3.0 | MIT |
| file_picker_web | 4.2.2 | MIT |
| fixnum | 1.1.1 | BSD-3-Clause |
| flutter_localizations | 0.0.0 | Flutter SDK (BSD-3-Clause) |
| flutter_test | 0.0.0 | Flutter SDK (BSD-3-Clause) |
| flutter_web_plugins | 0.0.0 | Flutter SDK (BSD-3-Clause) |
| glob | 2.2.0 | BSD-3-Clause |
| hooks | 2.2.0 | BSD-3-Clause |
| http_parser | 4.1.2 | BSD-3-Clause |
| image | 4.13.1 | MIT |
| intl | 0.20.3 | BSD-3-Clause |
| jni | 1.2.1 | BSD-3-Clause |
| jni_flutter | 1.1.0 | BSD-3-Clause |
| jni_util | 1.0.0 | BSD-3-Clause |
| leak_tracker | 11.0.2 | BSD-3-Clause |
| leak_tracker_flutter_testing | 3.0.10 | BSD-3-Clause |
| leak_tracker_testing | 3.0.2 | BSD-3-Clause |
| listen | 1.0.1 | BSD-3-Clause |
| logging | 1.3.0 | BSD-3-Clause |
| matcher | 0.12.20 | BSD-3-Clause |
| material_color_utilities | 0.13.0 | Apache-2.0 |
| media_kit_libs_android_video | 1.3.8 | MIT |
| media_kit_libs_ios_video | 1.1.4 | MIT |
| media_kit_libs_linux | 1.2.1 | MIT |
| media_kit_libs_macos_video | 1.1.4 | MIT |
| media_kit_libs_windows_video | 1.0.11 | MIT |
| meta | 1.19.0 | BSD-3-Clause |
| mime | 2.1.0 | BSD-3-Clause |
| native_toolchain_c | 0.19.6 | BSD-3-Clause |
| nm | 0.6.0 | MPL-2.0 |
| objective_c | 9.6.4 | BSD-3-Clause |
| package_config | 3.0.0 | BSD-3-Clause |
| package_info_plus | 10.2.2 | BSD-3-Clause |
| package_info_plus_platform_interface | 4.1.0 | BSD-3-Clause |
| path_provider_android | 2.3.1 | BSD-3-Clause |
| path_provider_foundation | 2.6.0 | BSD-3-Clause |
| path_provider_linux | 2.2.2 | BSD-3-Clause |
| path_provider_platform_interface | 2.1.3 | BSD-3-Clause |
| path_provider_windows | 2.3.0 | BSD-3-Clause |
| petitparser | 7.1.0 | MIT |
| platform | 3.2.0 | BSD-3-Clause |
| plugin_platform_interface | 2.1.8 | BSD-3-Clause |
| posix | 6.5.4 | MIT |
| process | 5.0.6 | BSD-3-Clause |
| pub_semver | 2.2.1 | BSD-3-Clause |
| record_use | 1.1.1 | BSD-3-Clause |
| riverpod | 3.5.0 | MIT |
| safe_local_storage | 2.0.7 | MIT |
| sky_engine | 0.0.0 | Flutter SDK (BSD-3-Clause) |
| source_span | 1.10.2 | BSD-3-Clause |
| stack_trace | 1.12.2 | BSD-3-Clause |
| state_notifier | 1.0.0 | MIT |
| stream_channel | 2.1.4 | BSD-3-Clause |
| string_scanner | 1.4.1 | BSD-3-Clause |
| synchronized | 3.6.1+1 | MIT |
| term_glyph | 1.2.2 | BSD-3-Clause |
| test_api | 0.7.14 | BSD-3-Clause |
| typed_data | 1.4.0 | BSD-3-Clause |
| universal_platform | 1.1.0 | MIT |
| uri_parser | 3.0.2 | MIT |
| uuid | 4.6.0 | MIT |
| vector_math | 2.4.3 | BSD-3-Clause |
| vm_service | 15.4.0 | BSD-3-Clause |
| wakelock_plus | 1.8.2 | BSD-3-Clause |
| wakelock_plus_platform_interface | 1.7.0 | BSD-3-Clause |
| web | 1.1.2 | BSD-3-Clause |
| win32 | 6.4.0 | BSD-3-Clause |
| windows_file_picker | 2.0.2 | MIT |
| xdg_directories | 1.1.0 | BSD-3-Clause |
| xml | 7.1.0 | MIT |
| yaml | 3.1.4 | MIT |

Notes: `flutter`, `flutter_localizations`, `flutter_web_plugins`, `flutter_test` and `sky_engine` are part of the Flutter SDK (BSD-3-Clause). `dbus` and `nm` (MPL-2.0) are Linux-only, pulled in by `connectivity_plus` via `background_downloader`.

## Bundled fonts

| Font | Source | License |
|---|---|---|
| JetBrains Mono (variable) | https://github.com/JetBrains/JetBrainsMono | SIL OFL 1.1 (`assets/fonts/OFL-JetBrainsMono.txt`) |
| Inter (variable) | https://github.com/rsms/inter | SIL OFL 1.1 (`assets/fonts/OFL-Inter.txt`) |

Both were taken unmodified from the google/fonts repository (`ofl/jetbrainsmono`, `ofl/inter`) and renamed only to drop brackets from the file names. They are bundled because desktop Flutter does not resolve system fonts by family name.
