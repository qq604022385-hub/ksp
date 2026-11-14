import 'dart:async';

import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/services/builtin_sources/source_protocols.dart';

/// WebView 视频源解析服务
///
/// 使用 WebView 解析视频页面，提取视频源 URL。
/// WebView 实例在服务生命周期内复用，切换集数时调用 unloadPage 释放页面资源，
/// 仅在 [dispose] 时才真正销毁 WebView。
class WebViewVideoSourceService implements IVideoSourceService {
  WebViewVideoSourceService({
    Future<ResolvedMedia> Function(String)? builtinResolver,
  }) : _builtinResolver = builtinResolver ?? ServiceSources.instance.resolve;
  final Future<ResolvedMedia> Function(String) _builtinResolver;

  // 单个服务实例持有一个 WebView，因此解析任务按实例串行执行。
  // 下载并行通过多个服务实例实现。
  Future<void>? _resolveTail = Future<void>.value();
  _ResolveRequest? _activeRequest;

  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get onLog => _logController.stream;

  @override
  Future<VideoSource> resolve(
    String episodeUrl, {
    required bool useLegacyParser,
    int offset = 0,
    Duration timeout = const Duration(seconds: 50),
  }) async {
    final resolveTail = _resolveTail;
    if (resolveTail == null) {
      throw const VideoSourceCancelledException();
    }

    _activeRequest?.cancel();
    final request = _ResolveRequest();
    _activeRequest = request;

    final resolveFuture = resolveTail.then(
      (_) => _runResolve(
        request,
        episodeUrl,
        useLegacyParser: useLegacyParser,
        offset: offset,
        timeout: timeout,
      ),
    );

    _resolveTail = resolveFuture.then<void>((_) {}, onError: (_) {});
    return resolveFuture;
  }

  Future<VideoSource> _runResolve(
    _ResolveRequest request,
    String episodeUrl, {
    required bool useLegacyParser,
    required int offset,
    required Duration timeout,
  }) async {
    request.throwIfNotCurrent(_activeRequest);

    if (ServiceSources.isServiceUrl(episodeUrl)) {
      try {
        final media =
            await Future.any([
              _builtinResolver(episodeUrl),
              request.cancelled.then<ResolvedMedia>(
                (_) => throw const VideoSourceCancelledException(),
              ),
            ]).timeout(
              timeout,
              onTimeout: () => throw VideoSourceTimeoutException(timeout),
            );
        request.throwIfNotCurrent(_activeRequest);
        return VideoSource(
          url: media.url,
          offset: offset,
          type: VideoSourceType.online,
          httpHeaders: media.headers,
        );
      } finally {
        if (identical(_activeRequest, request)) _activeRequest = null;
      }
    }

    if (identical(_activeRequest, request)) _activeRequest = null;
    throw const VideoSourceNotFoundException('本地解析已停用，请返回片库重新获取剧集');
  }

  @override
  void cancel() {
    _activeRequest?.cancel();
  }

  @override
  Future<void> dispose() async {
    final resolveTail = _resolveTail;
    _resolveTail = null;
    cancel();
    await resolveTail;
    _activeRequest = null;

    if (!_logController.isClosed) {
      await _logController.close();
    }
  }
}

class _ResolveRequest {
  final Completer<void> _cancelled = Completer<void>();

  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  void throwIfNotCurrent(_ResolveRequest? current) {
    if (_cancelled.isCompleted || !identical(current, this)) {
      throw const VideoSourceCancelledException();
    }
  }
}
