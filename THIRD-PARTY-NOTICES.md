# Third-party source and native dependencies

## KSPlayer 2.3.4

- Upstream: https://github.com/kingslay/KSPlayer/tree/2.3.4
- Commit: `bdfa2da39bb18865b317c4ffd08cdef5f8efc043`
- License: GNU GPL version 3; full upstream license: `Vendor/KSPlayer/LICENSE`.
- Included: upstream `Sources/` and `Tests/`, including original copyright notices.
- Integration changes (2026-10-25): `Package.swift` uses the sibling local FFmpegKit
  package instead of a floating network version; `KSPlayerLayer.swift` retains
  `KSOptions.firstPlayerType` during wireless route changes instead of forcing
  KSAVPlayer. App-owned controls/adapter are in `Kanke/PlayerController.swift`.
- This is the public source release, not the upstream paid LGPL edition.

## kingslay/FFmpegKit 6.1.3

- Upstream: https://github.com/kingslay/FFmpegKit/tree/6.1.3
- Commit: `85b77c589de0360c111de16752db86b60496d70b`
- Fetched by `Scripts/prepare_player.py` into ignored `Vendor/FFmpegKit/`.
- Upstream `LICENSE` (GPLv3), `LICENSE.LGPLv3`, README, C glue and package
  manifest are retained. XCFrameworks are the upstream prebuilt native libraries.
- The sparse checkout retains iPhone arm64 and arm64/x86_64 simulator slices,
  plus the small macOS-only libbluray artifact declared by the upstream manifest.
- Upstream build recipes and dependency configuration are available in the same
  repository's `Plugins/BuildFFmpeg/`. No build plugin is run by this app workflow.
- This is kingslay's repository; it is not the unrelated arthenica FFmpegKit.

The integrated player includes GPL-licensed code. Preserve these notices,
licenses and corresponding source when redistributing a combined build under
the applicable license terms. The project is not presented as MIT-only or as
a proprietary-licensed player. Individual native libraries retain their own
copyright and license terms.
