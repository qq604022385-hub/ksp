# KSPlayer integration verification — 2026-10-25

## Implemented in source

- Replace the AVPlayerViewController wrapper with a persistent KSPlayer UIKit
  view hosted in SwiftUI. Explicitly select KSMEPlayer (FFmpeg), disable the
  fallback engine, and preserve that engine across wireless route changes.
- Reuse upstream controls and gestures. Add source, episode and next-episode
  menus to the full-screen toolbar. Keep playback headers, resume position,
  favorites/history and automatic next episode connected to KankeCore.
- Keep the view and engine alive when entering full screen. Invalidate the
  previous delegate before replacing streams. Stop and release callbacks when
  leaving the detail page.
- Pin KSPlayer public source 2.3.4 and kingslay/FFmpegKit 6.1.3 by commit. Retain
  GPL licenses and document local modifications in THIRD-PARTY-NOTICES.md.
- CI downloads the native dependency before its simulator and iPhone builds.
  Core protocol tests remain independent of the video dependencies.

## Executed on this Windows host

- Source/project consistency validator: 26 checks passed.
- Tree-sitter Swift syntax parse: 75 files, no syntax-error/missing nodes. This
  includes app, core, vendored player and package/test Swift sources.
- Workflow YAML parsed successfully, dependency preparation precedes Xcode.
- Dependency preparation downloaded the exact pinned commit and verified all
  50 expected iPhone/simulator artifact entries. A second run succeeded without
  replacing unrelated content. Downloaded native dependency data: about 287 MiB.
- Upstream source comparison: the only changed upstream implementation file
  is KSPlayerLayer.swift; the second upstream change is the package manifest.
  GPL license content is unchanged.
- Native iPhone framework binaries inspected as static archives inside fat
  containers; their presence is dependency evidence, not execution evidence.

## Still requires the user's GitHub/iPhone environment

No Swift typecheck, Xcode build, IPA installation or iPhone playback was executed
in this environment for this integration. A successful dependency fetch and
syntax parser do not establish these outcomes. The Actions workflow builds both
simulator and iPhone targets and reports the actual compiler result.

Device acceptance: HLS/MP4 playback with service headers; seek/resume; switching
sources/episodes while in full screen; rotation and return; double tap, pan,
long press, lock; interruptions/background return; automatic next episode;
history persistence. PiP/AirPlay features are not claimed as accepted here.

The incremental ZIP is applied to the latest previously supplied source. It
contains only changed/new files for this integration, including the upstream
player source. FFmpeg binaries are downloaded by Actions rather than included.
