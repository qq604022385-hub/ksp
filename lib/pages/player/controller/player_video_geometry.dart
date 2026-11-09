import 'package:media_kit/media_kit.dart';

/// Decoded pixels are separate from the display aspect and rotation.
class PlayerVideoGeometry {
  const PlayerVideoGeometry([this.params = const VideoParams()]);

  final VideoParams params;

  bool get hasResolution => (params.w ?? 0) > 0 && (params.h ?? 0) > 0;

  String get resolutionLabel =>
      hasResolution ? '${params.w} × ${params.h}' : '读取中';

  bool? get isPortrait {
    double? aspect = params.aspect;
    if (aspect == null || !aspect.isFinite || aspect <= 0) {
      final width = (params.dw ?? 0) > 0 ? params.dw : params.w;
      final height = (params.dh ?? 0) > 0 ? params.dh : params.h;
      if (width == null || height == null || width <= 0 || height <= 0) {
        return null;
      }
      aspect = width / height;
    }
    final rotation = (params.rotate ?? 0) % 360;
    if (rotation == 90 || rotation == 270) aspect = 1 / aspect;
    return aspect < 1;
  }
}
