import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_video_geometry.dart';
import 'package:kazumi/pages/player/player_resolution_label.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('9:16 short dramas select portrait; normal movies select landscape', () {
    expect(
      const PlayerVideoGeometry(VideoParams(w: 1080, h: 1920)).isPortrait,
      isTrue,
    );
    expect(
      const PlayerVideoGeometry(VideoParams(w: 1920, h: 1080)).isPortrait,
      isFalse,
    );
    expect(const PlayerVideoGeometry().isPortrait, isNull);
    expect(const PlayerVideoGeometry().resolutionLabel, '读取中');
  });

  test('orientation includes rotation and non-square pixel display aspect', () {
    for (final rotation in [90, 270, -90]) {
      final geometry = PlayerVideoGeometry(
        VideoParams(w: 1920, h: 1080, rotate: rotation),
      );
      expect(geometry.isPortrait, isTrue);
      expect(geometry.resolutionLabel, '1920 × 1080');
    }
    expect(
      const PlayerVideoGeometry(
        VideoParams(w: 1080, h: 1920, rotate: 180),
      ).isPortrait,
      isTrue,
    );
    expect(
      const PlayerVideoGeometry(
        VideoParams(w: 720, h: 576, dw: 500, dh: 720),
      ).isPortrait,
      isTrue,
    );
  });

  testWidgets('resolution uses decoded pixels and updates on source changes', (
    tester,
  ) async {
    final debug = PlayerDebugController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 110,
            child: PlayerResolutionLabel(debug: debug),
          ),
        ),
      ),
    );
    expect(find.text('分辨率 读取中'), findsOneWidget);
    debug.updateVideoGeometry(
      const VideoParams(w: 1080, h: 1920, dw: 2160, dh: 3840),
    );
    await tester.pump();
    expect(find.text('分辨率 1080 × 1920'), findsOneWidget);
    expect(find.textContaining('2160'), findsNothing);
    expect(tester.takeException(), isNull);
    debug.updateVideoGeometry(const VideoParams(w: 1280, h: 720));
    await tester.pump();
    expect(find.text('分辨率 1280 × 720'), findsOneWidget);
    await debug.cancel();
    await tester.pump();
    expect(find.text('分辨率 读取中'), findsOneWidget);
    expect(debug.videoGeometry.isPortrait, isNull);
  });

  testWidgets('fullscreen preserves portrait and back restores system mode', (
    tester,
  ) async {
    final requests = <({bool fullscreen, bool? portrait})>[];
    final controller = VideoFullscreenController(
      applyFullscreen: (fullscreen, {portrait}) async {
        requests.add((fullscreen: fullscreen, portrait: portrait));
      },
    );
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            controller.attach(ModalRoute.of(context)!);
            return const Scaffold();
          },
        ),
      ),
    );
    await controller.updateVideoOrientation(true);
    await controller.toggle();
    await tester.pump();
    expect(controller.isFullscreen, isTrue);
    expect(requests.single, (fullscreen: true, portrait: true));
    await Navigator.of(pageContext).maybePop();
    await tester.pump();
    expect(controller.isFullscreen, isFalse);
    expect(requests.last.fullscreen, isFalse);
    await controller.close();
  });

  testWidgets('late metadata and episode changes update active fullscreen', (
    tester,
  ) async {
    final requests = <({bool fullscreen, bool? portrait})>[];
    final controller = VideoFullscreenController(
      applyFullscreen: (fullscreen, {portrait}) async {
        requests.add((fullscreen: fullscreen, portrait: portrait));
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            controller.attach(ModalRoute.of(context)!);
            return const Scaffold();
          },
        ),
      ),
    );
    await controller.setFullscreen(true);
    expect(requests.last, (fullscreen: true, portrait: null));
    await controller.updateVideoOrientation(true);
    expect(requests.last, (fullscreen: true, portrait: true));
    final count = requests.length;
    await controller.updateVideoOrientation(null);
    expect(requests.length, count);
    await controller.updateVideoOrientation(false);
    expect(requests.last, (fullscreen: true, portrait: false));
    await controller.close();
    await controller.updateVideoOrientation(true);
    expect(requests.last.fullscreen, isFalse);
  });
}
