# flutter-engine-linux-120hz

A patched build of Flutter's Linux GTK embedder (`libflutter_linux_gtk.so`) that adds a
display-rate vsync timer, so Flutter apps on Linux run at the monitor's actual refresh rate
(90/120/144 Hz) instead of being hard-capped at 60 fps.

This exists because of an upstream engine limitation, tracked in
[flutter/flutter#192342](https://github.com/flutter/flutter/issues/192342) ("Use vsync in Linux
embedder"), which is open and unmerged. Until it ships in a stable Flutter release, this repo
builds and publishes a drop-in replacement `.so` that
[QueryaHub/Querya-Desktop](https://github.com/QueryaHub/Querya-Desktop) splices into its Linux
release bundles in CI. See
[Querya-Desktop#980](https://github.com/QueryaHub/Querya-Desktop/issues/980) for the original
investigation and before/after numbers (60 fps stock → 110–120 fps patched, on scroll/hover/tree
scenarios; the sidebar-toggle animation stays at 60 fps for an unrelated reason — semantics tree
churn, tracked separately).

## What's patched

Only `shell/platform/linux/fl_engine.cc` and `fl_display_monitor.cc`/`.h` — the vsync-callback
part of flutter/flutter#192342. The Wayland-subsurface part of that PR does not apply to engine
revisions before the subsurface renderer landed; this patch is engine-revision-specific (see
below), not a straight cherry-pick of the whole upstream PR.

The patch is a **display-rate timer**, not real hardware vsync: GTK does not expose a vsync
callback for a window, so the engine paces itself against `GdkMonitor`'s reported refresh rate
instead of `VsyncWaiterFallback`'s hard-coded 60 Hz. See `patches/vsync-fl_engine-fl_display_monitor.patch`.

## Why an engine ABI pin matters

A `libflutter_linux_gtk.so` only works with the exact Dart/Skia/embedder ABI it was built against.
Flutter's tooling keys this by the engine's **content hash** (shown by `flutter --version` as
`Engine • hash <content_hash> (revision <engine.version>)`, and matches the `content_hash` GN arg
baked into the build). Every release published here is tagged `engine-<content_hash>` for exactly
that reason — grabbing the wrong one will crash or silently misbehave at startup.

## Consuming this from Querya-Desktop

Querya-Desktop's Linux CI (`ci.yml`'s `build-linux-release` job and `release.yml`'s `build-linux`
job) runs `scripts/linux/apply_patched_engine.sh` right after `flutter build linux --release`:
it resolves the pinned Flutter SDK's engine content hash, downloads the matching
`engine-<content_hash>` release asset from this repo via `gh release download`, and overwrites
`build/linux/x64/release/bundle/lib/libflutter_linux_gtk.so`. If no matching release exists yet
(e.g. Flutter was just bumped and nobody rebuilt this repo for the new engine yet), that script
**warns and falls back to the stock engine** rather than failing the build — Linux release builds
should never be blocked on this repo being up to date.

## Rebuilding for a new Flutter version

When Querya-Desktop bumps its pinned Flutter version, the engine content hash almost always
changes too, and this repo needs a new release to match it:

1. Find the new content hash: `flutter --version` (the `Engine • hash ...` line) on the exact
   Flutter version/channel Querya-Desktop's CI pins.
2. Run the `Build Linux engine` workflow (`workflow_dispatch`) in this repo, passing the Flutter
   **framework** git commit (`flutter --version`'s `Framework • revision` line) to check out —
   the engine sources live in the same monorepo commit.
3. It applies `patches/vsync-fl_engine-fl_display_monitor.patch`, builds
   `flutter/shell/platform/linux:flutter_linux_gtk` in release config, and — if the patch still
   applies cleanly and the resulting content hash matches what you expect — publishes it as a
   release tagged `engine-<content_hash>`.
4. If the patch fails to apply (upstream engine code the patch touches has changed), it needs a
   manual rebase against the new commit; see `scripts/build.sh` for the exact recipe used, which
   mirrors a manually-validated local build (see Querya-Desktop#980's benchmark comment).

`scripts/build.sh` can also be run locally the same way it was originally validated (this avoids
depending on the CI workflow actually having enough disk/time on a hosted runner, which is
untested for this repo so far — see caveats below).

## Caveats

- **Only tested manually so far.** The numbers in Querya-Desktop#980 come from a local build
  (`gclient sync` + `gn` + `ninja`, ~4000 build steps), not from the `Build Linux engine` workflow
  in this repo. That workflow is a straightforward translation of the same steps, but hasn't
  itself been run to completion in CI yet — GitHub-hosted runners may not have enough disk
  (`gclient sync` of the engine monorepo is on the order of 10 GB, before build outputs) or may
  need a longer timeout than the default. If it fails on disk/time, either switch it to a
  larger/self-hosted runner or keep building locally and upload with `scripts/publish_release.sh`.
- Only `release` runtime mode is built by default (what Querya-Desktop's release bundles need).
  Add `profile`/`debug` if Querya-Desktop's own benchmark tooling (`benchmark/app_perf_bench.dart`,
  run via `flutter run --profile`) needs a matching patched profile engine too.
- This whole repo goes away once flutter/flutter#192342 (or an equivalent fix) ships in a Flutter
  stable release Querya-Desktop adopts — at that point, delete the `apply_patched_engine.sh` step
  from Querya-Desktop's CI and archive this repo.
