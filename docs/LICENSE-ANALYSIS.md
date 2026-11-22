# License analysis: distributing an Apache-2.0 APK that bundles libmpv/FFmpeg

Status: research that led to the owner's decision (Apache-2.0 with the LGPL libmpv flavor, option 1 below; implemented in `LICENSE` and `NOTICE`). This is engineering analysis, not legal advice.

## Summary

- The Android APK bundles `libmpv.so` from the **"default" flavor** of `media-kit/libmpv-android-video-build` v1.1.7. It is built **without GPL**: mpv with `-Dgpl=false` (LGPL-2.1-or-later) and FFmpeg 6.0 with `--disable-gpl --disable-nonfree --enable-version3` (LGPL-3.0-or-later). FFmpeg is statically linked into `libmpv.so`.
- LGPL does not force the app to change license. Apache-2.0 for the app code stays possible, provided the LGPL obligations below are met. Relicensing to GPL-3.0 is not required.
- Recommendation: keep Apache-2.0, keep the default (LGPL) flavor, never switch to the `encoders-gpl` flavor, and add LGPL attribution plus a source offer to the release (see "Obligations").
- Linux: the app links the user's system `libmpv` at runtime and ships none. Nothing is distributed, so no obligation arises from libmpv. Distro libmpv builds are usually GPL-2+, which is the user's own installation.

## Verified evidence

1. The APK pulls the native libs from `default-arm64-v8a.jar` of release v1.1.7:
   `~/.pub-cache/hosted/pub.dev/media_kit_libs_android_video-1.3.8/android/build.gradle` (downloads `https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.7/default-*.jar`, MD5 pinned).
2. Build scripts for that flavor, upstream repo `https://github.com/media-kit/libmpv-android-video-build`:
   - `buildscripts/flavors/default.sh`: `--disable-gpl --disable-nonfree --enable-version3 --enable-static --disable-shared`, explicit decoder/demuxer allow-list.
   - `buildscripts/scripts/mpv.sh`: `-Dgpl=false -Dlibmpv=true -Dlua=disabled -Dcplayer=false`.
   - `buildscripts/include/depinfo.sh`: ffmpeg 6.0, mpv commit `78d43740f52db817d98bcf24fb30a76ab6fa13ff`, libass 0.17.1, harfbuzz 7.2.0, fribidi 1.0.12, freetype 2-13-0, mbedtls 3.4.0, dav1d 1.2.0, libxml2 2.10.3.
3. Upstream `LICENSE` of that repo: the "default" and "full" flavors are MIT (build scripts, by Ilya Zhuravlev and sfan5); the `encoders-gpl` flavor (libx264, libvpx, libvorbis encoders; adds fftools) is GPL-3.0-or-later. This license covers the build scripts, not the resulting binaries; the binaries carry the licenses of the libraries inside.
4. Directly inspected the built `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`: `lib/arm64-v8a/libmpv.so` contains the strings `libavcodec/libavformat/libavutil/libavfilter/libswscale/libswresample license: LGPL version 3 or later` and mpv's `Configuration: -Dgpl=false ...` and the FFmpeg configure line with `--disable-gpl --enable-version3`. So the shipped binary matches the scripts.
5. mpv's own statement (`https://github.com/mpv-player/mpv/blob/master/Copyright`): GPLv2+ by default, LGPLv2.1+ if built without GPL-only files; `-Dgpl=false` is provided for that purpose "but does not in itself create a LGPLv2.1+ license grant".
6. Other APK native libs: `libsqlite3.so` (SQLite, public domain, from `package:sqlite3` build hook), `libmediakitandroidhelper.so` (media_kit, MIT), `libdartjni.so`, `libflutter.so` (Flutter engine, BSD-3-Clause plus bundled third-party notices), `libapp.so` (this project).
7. Linux: `media_kit_libs_linux-1.2.1/linux/CMakeLists.txt` downloads only mimalloc v2.1.2 (MIT) and bundles no libmpv. `media_kit` README tells Linux users to install `libmpv-dev mpv` from the distro.
8. Dart dependencies: see `docs/THIRD_PARTY.md`. Detected licenses are all permissive (MIT, BSD-2/3, Apache-2.0) except `dbus` and `nm` (MPL-2.0, Linux-only transitive via `connectivity_plus`; file-level copyleft, no conflict with Apache-2.0 when unmodified and used as packages).

## What it means for Apache-2.0

- Apache-2.0 app code calling an LGPL library is fine; LGPL section 4 / LGPL-3.0 section 4 lets the combined work be licensed under terms of your choice provided the user can replace the library. The user-replaceable condition is met because `libmpv.so` is a separate shared object in the APK and the whole app is open source and buildable (swap the jar, rebuild).
- GPL-3.0 relicensing would be needed only if a GPL-built libmpv/FFmpeg (e.g. `encoders-gpl`, or a distro libmpv bundled into a Linux package) were shipped. Apache-2.0 is one-way compatible with GPL-3.0, so the option exists later without difficulty if it ever becomes necessary.

## Options

1. **Keep Apache-2.0 + LGPL libmpv (recommended).** Add: LGPL notice in an in-app licenses page, a copy of LGPL-2.1 and LGPL-3.0 texts in release assets, a written source offer (pointing at the exact upstream tags/commits in "Obligations"), and a note on how to rebuild the APK with a replaced `libmpv.so`.
2. **Relicense the app to GPL-3.0.** Not required for the current binary; only worthwhile if the owner prefers it or wants to bundle GPL builds. Loses Apache's patent grant clarity for downstream users.
3. **Switch libmpv variant.** The default flavor is already the LGPL build; there is no smaller/"lite" LGPL variant in `media_kit_libs_android_video` 1.3.8 (the Gradle file lists only `default-*.jar`). The `full` flavor is also LGPL but larger. `encoders-gpl` is GPL and would force option 2. Not recommended.
4. **Source-only distribution.** Removes binary-distribution obligations from the project but users still receive the same LGPL APK once they build it; no benefit for a personal-use app. Only worthwhile if no binaries are ever published.

## Obligations to satisfy for each APK release (option 1)

- Include license texts: LGPL-2.1, LGPL-3.0, Apache-2.0, plus MIT/BSD/ISC notices of statically linked libs (below).
- State that the APK contains FFmpeg and mpv, modified-or-not, and where the corresponding source is:
  - FFmpeg 6.0: `https://ffmpeg.org/releases/` (tag n6.0).
  - mpv at commit `78d43740f52db817d98bcf24fb30a76ab6fa13ff`: `https://github.com/mpv-player/mpv`.
  - Build scripts and patches (`buildscripts/patches`): `https://github.com/media-kit/libmpv-android-video-build/tree/v1.1.7`.
- Do not use patent or trademark claims about FFmpeg/mpv; do not imply endorsement by their projects.
- Document that users can rebuild with a different `libmpv.so` (swap the jar URL/checksum in a fork of `media_kit_libs_android_video`, or place a replacement `libmpv.so` under `android/app/src/main/jniLibs/arm64-v8a/`).

## What I could not verify

- Exact licenses of the statically linked sub-libraries, as built (libass ISC, freetype FTL or GPL-2 dual, harfbuzz MIT, fribidi LGPL-2.1+, mbedtls 3.4.0 Apache-2.0 OR GPL-2.0+, dav1d BSD-2, libxml2 MIT) are from my knowledge of those projects at those versions, not from their source trees. A one-time check of each version's license file is needed before a public release. Same for the symbols actually linked in.
- Whether the v1.1.7 jar includes any patches affecting license (the repo has `buildscripts/patches`; I did not read them).
- I did not decompile the jar download itself, only the built APK I had on disk, and I did not confirm it was produced from the pinned MD5 jar.
- Whether any GPL-only mpv source file ended up compiled in despite `-Dgpl=false` (mpv itself warns the switch is not a grant). The FFmpeg strings say LGPL; mpv's own license string was not located in the binary.
- Android Gradle-side native/JVM dependencies of plugins such as `background_downloader` (WorkManager, OkHttp, Kotlin) and their licenses; Maven POMs were not inspected (all are typically Apache-2.0).
- Linux distro libmpv license for a specific user (Arch builds are typically GPL-2+); matters only if the project ever distributes a Linux bundle (AppImage/Flatpak/deb) that includes libmpv.
- Legal interpretation: LGPL-3.0 "Installation Information" duties for Android "User Products" and codec patent exposure (H.264/HEVC/AAC patent pools) are legal questions outside this analysis.

## Addendum 2026-11-22 (v0.3.1)

Re-checked against the v0.3.1 dependency set. The libmpv/FFmpeg analysis is unchanged (same `media_kit_libs_android_video` 1.3.8, same v1.1.7 jar).

- New Dart packages since v0.1.0 (`flutter_secure_storage`, `flutter_svg`, `screen_brightness`, `crypto` now direct, plus their transitive packages): all BSD-3-Clause or MIT, read from each package's `LICENSE` in the pub cache. No copyleft added. Listed in `docs/THIRD_PARTY.md`.
- `flutter_secure_storage` pulls the JVM library Tink (`tink-android` 1.23.0, Apache-2.0 per its POM) into the Android APK. This closes one part of the "Gradle-side dependencies" gap above, only for Tink; WorkManager/OkHttp/Kotlin remain unchecked.
- Linux: the `flutter_secure_storage_linux` plugin is compiled in and needs system `libsecret` (LGPL-2.1+) at build/run time as a dynamic system dependency. The project does not distribute it. If a Linux bundle that includes libsecret or libmpv is ever shipped, redo the Linux analysis.
- TMDB: API use and the bundled logo are under TMDB's own attribution terms (free for non-commercial use; required notice in `NOTICE` and Settings > About; logo only as provided, not modified except its CSS fill was inlined). These terms are not an open-source license and apply to the logo asset and TMDB data, not to the Apache-2.0 app code. If the project ever turns commercial, TMDB's terms need a fresh read.
- Still unverified: build-level licenses of the libraries inside `libmpv.so` (see above).
