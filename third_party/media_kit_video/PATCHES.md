# Local patches to media_kit_video 2.0.1

Vendored from pub.dev (MIT, see LICENSE). Used through `dependency_overrides` in the app's
`pubspec.yaml`. Only `linux/video_output.cc` differs from upstream 2.0.1.

## Linux: GPU rendering when no EGL context is current (watchdog, 2026-11-23)

Problem: with Flutter's Impeller (OpenGL ES) backend the engine's EGL context lives on the raster
thread. `video_output_new()` runs on the platform thread, where `eglGetCurrentDisplay()` and
`eglGetCurrentContext()` are `EGL_NO_*`. Upstream then logs
`media_kit: VideoOutput: EGL display or context is invalid.` and falls back to CPU ("S/W")
rendering, so every 1080p frame is converted and copied by the CPU: dropped frames (choppy video, audio
fine) on weak CPUs such as an i3-4130.

Fix: when nothing is current, derive the `EGLDisplay` from GDK (`eglGetPlatformDisplay` on the
Wayland/X11 display GDK already created Flutter's context on, which returns the same display) and
choose a generic surfaceless GLES config. Frames still reach Flutter through the existing EGLImage
sharing. If GPU setup fails the original CPU fallback still runs.

Remove this override when upstream handles a missing current context.
