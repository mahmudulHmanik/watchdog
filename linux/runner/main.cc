#include <unistd.h>

#include <cstdlib>
#include <string>

#include "my_application.h"

// Flutter's engine (libflutter_linux_gtk.so) exports its own, incompatible copy of the C++
// unwinder (_Unwind_RaiseException, _Unwind_Resume). The system libmpv is built with LuaJIT, and
// LuaJIT implements every Lua error with the system unwinder. Inside this process its calls bind
// to Flutter's copy instead, which does not know LuaJIT's registered frames, so the first Lua error
// in one of mpv's built-in scripts (stats.lua, ...) kills the app with SIGSEGV as soon as a video
// is opened. Preloading the system libgcc_s makes LuaJIT bind to the right unwinder.
//
// LD_PRELOAD only works at exec time, so the first run re-executes itself once with it set. The
// second run restores the caller's own LD_PRELOAD, so child processes do not inherit ours.
// Reproduced and verified with a small program that loads the engine and then libmpv: it crashed
// in 3 of 5 runs without the preload and in 0 of 26 with it.
static void use_system_unwinder(char** argv) {
  const char* kGuard = "WATCHDOG_UNWINDER_FIXED";
  const char* kOrig = "WATCHDOG_ORIG_LD_PRELOAD";

  if (getenv(kGuard) != nullptr) {
    // Second run: preload is already in effect. Put the caller's value back.
    const char* orig = getenv(kOrig);
    if (orig != nullptr && orig[0] != '\0') {
      setenv("LD_PRELOAD", orig, 1);
    } else {
      unsetenv("LD_PRELOAD");
    }
    unsetenv(kOrig);
    unsetenv(kGuard);
    return;
  }

  const char* current = getenv("LD_PRELOAD");
  std::string preload = "libgcc_s.so.1";
  if (current != nullptr && current[0] != '\0') {
    preload += ":";
    preload += current;
  }
  setenv(kOrig, current != nullptr ? current : "", 1);
  setenv(kGuard, "1", 1);
  setenv("LD_PRELOAD", preload.c_str(), 1);
  execv("/proc/self/exe", argv);

  // exec failed: carry on without the workaround rather than not starting at all.
  if (current != nullptr) {
    setenv("LD_PRELOAD", current, 1);
  } else {
    unsetenv("LD_PRELOAD");
  }
  unsetenv(kOrig);
  unsetenv(kGuard);
}

int main(int argc, char** argv) {
  use_system_unwinder(argv);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
