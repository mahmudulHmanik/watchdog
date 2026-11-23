// Regression check for the Linux crash fixed in linux/runner/main.cc (v0.3.3 hotfix).
//
// Flutter's engine exports its own _Unwind_RaiseException/_Unwind_Resume. The system libmpv uses
// LuaJIT, whose Lua errors then run through the engine's copy and kill the process (SIGSEGV in
// thread "lua/stats") once mpv's built-in Lua scripts run. This loads the engine first, then libmpv,
// and plays a generated test video (no network, no display).
//
//   clang tool/linux/mpv_unwinder_repro.c -o /tmp/repro -ldl
//   ENGINE=build/linux/x64/release/bundle/lib/libflutter_linux_gtk.so
//   /tmp/repro "$ENGINE"                              # crashes about 3 runs in 5 (exit 139)
//   LD_PRELOAD=libgcc_s.so.1 /tmp/repro "$ENGINE"     # always survives; this is what the runner does
//   /tmp/repro none                                   # libmpv alone: survives
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mpv/client.h>

typedef mpv_handle *(*create_t)(void);
typedef int (*init_t)(mpv_handle *);
typedef int (*setopt_t)(mpv_handle *, const char *, const char *);
typedef int (*cmd_t)(mpv_handle *, const char **);
typedef mpv_event *(*wait_t)(mpv_handle *, double);
typedef void (*term_t)(mpv_handle *);

int main(int argc, char **argv) {
  const char *flutter = argc > 1 ? argv[1] : NULL;
  if (flutter && strcmp(flutter, "none") != 0) {
    void *f = dlopen(flutter, RTLD_NOW | RTLD_GLOBAL);   // engine first, like the app
    if (!f) { fprintf(stderr, "dlopen flutter: %s\n", dlerror()); return 2; }
    fprintf(stderr, "flutter engine loaded\n");
  }
  void *m = dlopen("libmpv.so.2", RTLD_NOW);
  if (!m) { fprintf(stderr, "dlopen mpv: %s\n", dlerror()); return 2; }
  create_t create = dlsym(m, "mpv_create");
  init_t init = dlsym(m, "mpv_initialize");
  setopt_t setopt = dlsym(m, "mpv_set_option_string");
  cmd_t cmd = dlsym(m, "mpv_command");
  wait_t wait = dlsym(m, "mpv_wait_event");
  term_t term = dlsym(m, "mpv_terminate_destroy");
  mpv_handle *h = create();
  setopt(h, "vo", "null"); setopt(h, "ao", "null"); setopt(h, "config", "no");
  setopt(h, "terminal", "no");
  if (init(h) < 0) { fprintf(stderr, "init failed\n"); return 3; }
  fprintf(stderr, "mpv initialised (built-in Lua scripts are loading)\n");
  const char *play[] = {"loadfile", "av://lavfi:testsrc=size=320x240:rate=10", NULL};
  cmd(h, play);
  for (int i = 0; i < 40; i++) {            // ~4 s of event loop
    mpv_event *e = wait(h, 0.1);
    if (e->event_id == MPV_EVENT_SHUTDOWN) break;
  }
  fprintf(stderr, "SURVIVED: no crash\n");
  term(h);
  return 0;
}
