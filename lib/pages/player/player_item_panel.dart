import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/play_pause_icon.dart';
import 'package:kazumi/pages/player/player_adjustment_hud.dart';
import 'package:kazumi/pages/player/controller/player_aspect_ratio.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/pages/player/player_panel_hold.dart';
import 'package:kazumi/services/player/pip_utils.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/player/remote.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';
import 'package:kazumi/utils/format.dart';
import 'package:kazumi/pages/player/player_transport_bar.dart';
import 'package:kazumi/pages/player/player_screenshot_controls.dart';
import 'package:kazumi/pages/player/player_progress_bar.dart';

class PlayerItemPanel extends StatefulWidget {
  const PlayerItemPanel({
    super.key,
    required this.playerController,
    required this.videoPageController,
    required this.fillsWindow,
    required this.onBackPressed,
    required this.setPlaybackSpeed,
    required this.showDanmakuSwitch,
    required this.handleFullscreen,
    required this.enterAndroidPictureInPicture,
    required this.handleScreenShot,
    required this.showScreenshotCandidates,
    required this.onNextEpisode,
    required this.handleProgressBarDragStart,
    required this.handleProgressBarDragEnd,
    required this.handleSuperResolutionChange,
    required this.panelVisibilityController,
    this.onToggleSidePanel,
    required this.keyboardFocus,
    required this.acquirePlayerPanelHold,
    required this.onMenuVisibilityChanged,
    required this.handleDanmaku,
    required this.skipOP,
    required this.showVideoInfo,
    required this.showSyncPlayPanel,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
  });

  final PlayerController playerController;
  final VideoPageController videoPageController;
  final bool fillsWindow;
  final VoidCallback onBackPressed;
  final Future<void> Function(double) setPlaybackSpeed;
  final VoidCallback showDanmakuSwitch;
  final VoidCallback? onToggleSidePanel;
  final VoidCallback handleFullscreen;
  final Future<void> Function() enterAndroidPictureInPicture;
  final VoidCallback handleScreenShot;
  final VoidCallback showScreenshotCandidates;
  final VoidCallback handleProgressBarDragStart;
  final void Function(bool cancelled) handleProgressBarDragEnd;
  final Future<void> Function(SuperResolutionMode mode)
  handleSuperResolutionChange;
  final AnimationController panelVisibilityController;
  final FocusNode keyboardFocus;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final ValueChanged<bool> onMenuVisibilityChanged;
  final VoidCallback handleDanmaku;
  final VoidCallback onNextEpisode;
  final VoidCallback skipOP;
  final VoidCallback showVideoInfo;
  final VoidCallback showSyncPlayPanel;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;

  @override
  State<PlayerItemPanel> createState() => _PlayerItemPanelState();
}

class _PlayerItemPanelState extends State<PlayerItemPanel> {
  late final Animation<Offset> _topOffsetAnimation;
  late final Animation<Offset> _bottomOffsetAnimation;
  late final Animation<Offset> _rightOffsetAnimation;
  late final VideoPageController videoPageController =
      widget.videoPageController;
  late final PlayerController playerController;
  void _showForwardChange() {
    KazumiDialog.show(
      builder: (context) {
        var input = '';
        return AlertDialog(
          title: const Text('跳过秒数'),
          content: TextField(
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              floatingLabelBehavior: FloatingLabelBehavior.never,
              labelText: playerController.playback.buttonSkipTime.toString(),
            ),
            onChanged: (value) {
              input = value;
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => KazumiDialog.dismiss(),
              child: Text(
                '取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                if (input.isNotEmpty) {
                  playerController.setButtonForwardTime(int.parse(input));
                }
                KazumiDialog.dismiss();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    final visibility = widget.panelVisibilityController.drive(
      CurveTween(curve: Curves.easeInOut),
    );
    _topOffsetAnimation = visibility.drive(
      Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero),
    );
    _bottomOffsetAnimation = visibility.drive(
      Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero),
    );
    _rightOffsetAnimation = visibility.drive(
      Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero),
    );
  }

  Widget _forwardButton() {
    return Tooltip(
      message: '快进${playerController.playback.buttonSkipTime}秒，长按修改时间',
      child: GestureDetector(
        onLongPress: _showForwardChange,
        child: IconButton(
          icon: Image.asset(
            'assets/images/forward_80.png',
            color: Colors.white,
            height: 24,
          ),
          onPressed: widget.skipOP,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _buildPanel(
      constraints.maxWidth < MediaQuery.textScalerOf(context).scale(600),
    ),
  );

  Widget _buildPanel(bool compact) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildScrim(
            height: 50,
            colors: const [Colors.black45, Colors.transparent],
            offset: _topOffsetAnimation,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildScrim(
            height: 100,
            colors: const [Colors.transparent, Colors.black45],
            offset: _bottomOffsetAnimation,
          ),
        ),
        Positioned(
          top: 25,
          child: Observer(
            builder: (context) {
              // Hidden HUDs must not observe playback ticks.
              final visible = playerController.panel.showSeekTime;
              return PlayerSeekHud(
                visible: visible,
                currentPosition: visible
                    ? playerController.playback.currentPosition
                    : Duration.zero,
                playerPosition: visible
                    ? playerController.playback.playerPosition
                    : Duration.zero,
                duration: visible
                    ? playerController.playback.duration
                    : Duration.zero,
                direction: playerController.panel.seekDirection,
                cancelPending: playerController.panel.seekCancelPending,
                disableAnimations: widget.disableAnimations,
              );
            },
          ),
        ),
        Positioned(
          top: 25,
          child: Observer(
            builder: (context) {
              return PlayerSpeedHud(
                visible: playerController.panel.showPlaySpeed,
                speed: playerController.playback.playerSpeed,
                disableAnimations: widget.disableAnimations,
              );
            },
          ),
        ),
        Positioned(
          top: 25,
          child: Observer(
            builder: (context) {
              final showVolume = playerController.panel.showVolume;
              final showBrightness = playerController.panel.showBrightness;
              return PlayerAdjustmentHud(
                visible: showVolume || showBrightness,
                type: showVolume
                    ? PlayerAdjustmentHudType.volume
                    : PlayerAdjustmentHudType.brightness,
                value: showVolume
                    ? playerController.playback.volume
                    : playerController.panel.brightness,
                disableAnimations: widget.disableAnimations,
              );
            },
          ),
        ),
        if (!isDesktop())
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Observer(
              builder: (context) {
                if ((compact || !widget.fillsWindow) &&
                    !playerController.panel.lockPanel) {
                  return const SizedBox.shrink();
                }
                return Visibility(
                  visible: widget.disableAnimations
                      ? playerController.panel.showVideoController
                      : true,
                  child: widget.disableAnimations
                      ? _rightControls
                      : SlideTransition(
                          position: _rightOffsetAnimation,
                          child: _rightControls,
                        ),
                );
              },
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Observer(
            builder: (context) {
              return Visibility(
                visible:
                    !playerController.panel.lockPanel &&
                    (widget.disableAnimations
                        ? playerController.panel.showVideoController
                        : true),
                child: widget.disableAnimations
                    ? _buildTopControls(compact)
                    : SlideTransition(
                        position: _topOffsetAnimation,
                        child: _buildTopControls(compact),
                      ),
              );
            },
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Observer(
            builder: (context) {
              return Visibility(
                visible:
                    !playerController.panel.lockPanel &&
                    (widget.disableAnimations
                        ? playerController.panel.showVideoController
                        : true),
                child: widget.disableAnimations
                    ? _buildBottomControls(compact)
                    : SlideTransition(
                        position: _bottomOffsetAnimation,
                        child: _buildBottomControls(compact),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScrim({
    required double height,
    required List<Color> colors,
    required Animation<Offset> offset,
  }) => Observer(
    builder: (context) {
      final scrim = Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
      );
      return Visibility(
        visible:
            !playerController.panel.lockPanel &&
            (!widget.disableAnimations ||
                playerController.panel.showVideoController),
        child: widget.disableAnimations
            ? scrim
            : SlideTransition(position: offset, child: scrim),
      );
    },
  );

  List<Widget> _choiceItems<T>(
    Iterable<T> values, {
    required String Function(T) label,
    required bool Function(T) selected,
    required void Function(T) onSelected,
  }) => [
    for (final value in values)
      KazumiMenuItem(
        onPressed: () => onSelected(value),
        label: label(value),
        selected: selected(value),
      ),
  ];

  List<Widget> get _aspectRatioItems => _choiceItems(
    PlayerAspectRatio.values,
    label: (value) => value.label,
    selected: (value) => value == playerController.panel.aspectRatioMode,
    onSelected: (value) => playerController.panel.aspectRatioMode = value,
  );

  List<Widget> get _speedItems => _choiceItems(
    defaultPlaySpeedList,
    label: (value) => '${value}x',
    selected: (value) => value == playerController.playback.playerSpeed,
    onSelected: widget.setPlaybackSpeed,
  );

  List<Widget> get _superResolutionItems => _choiceItems(
    SuperResolutionMode.values,
    label: (value) => value.label,
    selected: (value) => value == playerController.playback.superResolutionMode,
    onSelected: widget.handleSuperResolutionChange,
  );

  Widget _menuButton({
    required Widget child,
    required List<Widget> items,
    String? tooltip,
  }) => PlayerPanelHoldMenuAnchor(
    acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
    onVisibilityChanged: widget.onMenuVisibilityChanged,
    builder: (context, toggle) => tooltip == null
        ? TextButton(onPressed: toggle, child: child)
        : IconButton(onPressed: toggle, icon: child, tooltip: tooltip),
    menuChildren: items,
  );

  Widget get _wideControls => Row(
    children: [
      const Spacer(),
      _menuButton(
        child: const Text('超分辨率', style: TextStyle(color: Colors.white)),
        items: _superResolutionItems,
      ),
      _menuButton(
        child: Text(
          playerController.playback.playerSpeed == 1
              ? '倍速'
              : '${playerController.playback.playerSpeed}x',
          style: const TextStyle(color: Colors.white),
        ),
        items: _speedItems,
      ),
      _menuButton(
        child: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
        tooltip: '视频比例',
        items: _aspectRatioItems,
      ),
      if (widget.onToggleSidePanel != null)
        IconButton(
          color: Colors.white,
          icon: const Icon(Icons.menu_open_rounded),
          tooltip: '选集面板',
          onPressed: widget.onToggleSidePanel,
        ),
    ],
  );

  Widget _buildBottomControls(bool compact) => SafeArea(
    top: false,
    bottom: !compact && widget.fillsWindow,
    left: !compact && widget.fillsWindow,
    right: !compact && widget.fillsWindow,
    child: PlayerPanelHoldMouseRegion(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      cursor:
          (videoPageController.isFullscreen &&
              !playerController.panel.showVideoController)
          ? SystemMouseCursors.none
          : SystemMouseCursors.basic,
      child: PlayerTransportBar(
        compact: compact,
        timePlacement: PlayerTimeLabelPlacement.forViewport(
          MediaQuery.sizeOf(context),
          desktop: isDesktop(),
        ),
        playPause: IconButton(
          tooltip: playerController.playback.playing ? '暂停' : '播放',
          onPressed: () => playerController.playOrPause(),
          icon: PlayPauseIcon(
            iconColor: Colors.white,
            playing: playerController.playback.playing,
          ),
        ),
        nextEpisode: IconButton(
          color: Colors.white,
          icon: const Icon(Icons.skip_next_rounded),
          tooltip: '下一集',
          onPressed: widget.onNextEpisode,
        ),
        // Playback ticks only rebuild the progress bar and its time labels.
        progressBuilder: ({required sideLabels}) => Observer(
          builder: (context) => PlayerProgressBar(
            sideLabels: sideLabels,
            progress: playerController.playback.currentPosition,
            buffered: playerController.playback.buffer,
            total: playerController.playback.duration,
            onDragStart: widget.handleProgressBarDragStart,
            onDragUpdate: (position) =>
                playerController.seeking.updateInteractiveSeek(position),
            onDragEnd: widget.handleProgressBarDragEnd,
            onSeek: playerController.seek,
          ),
        ),
        timeLabel: Observer(
          builder: (context) => Text(
            '${compact ? '    ' : ''}${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
            style: TextStyle(
              color: Colors.white,
              fontSize: !compact && isDesktop() ? 16 : 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        controls: compact ? const SizedBox.shrink() : _wideControls,
        fullscreen: _buildFullscreenButton(compact),
      ),
    ),
  );

  Widget _buildFullscreenButton(bool compact) {
    if (videoPageController.isPip) {
      return compact ? const Text('    ') : const SizedBox.shrink();
    }
    if (!isDesktop() &&
        widget.fillsWindow &&
        !videoPageController.isFullscreen) {
      return const SizedBox.shrink();
    }
    return IconButton(
      color: Colors.white,
      icon: Icon(
        videoPageController.isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
      ),
      tooltip: videoPageController.isFullscreen ? '退出全屏' : '全屏',
      onPressed: widget.handleFullscreen,
    );
  }

  Widget _buildTopControls(bool compact) {
    return EmbeddedNativeControlArea(
      requireOffset: compact || !videoPageController.isFullscreen,
      child: SafeArea(
        top: false,
        bottom: false,
        left: !compact && widget.fillsWindow,
        right: !compact && widget.fillsWindow,
        child: PlayerPanelHoldMouseRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          cursor:
              (videoPageController.isFullscreen &&
                  !playerController.panel.showVideoController)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回',
                onPressed: widget.onBackPressed,
              ),
              Expanded(
                child: dtb.DragToMoveArea(
                  child: compact
                      ? const SizedBox(height: 40)
                      : Text(
                          ' ${videoPageController.title} [${videoPageController.roadList[videoPageController.selectedEpisode.road].identifier[videoPageController.selectedEpisode.episode - 1]}]',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Theme.of(
                              context,
                            ).textTheme.titleMedium!.fontSize,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
              ),
              _forwardButton(),
              if (isDesktop())
                PlayerScreenshotControls(
                  controller: playerController.screenshots,
                  onCapture: widget.handleScreenShot,
                  onReview: widget.showScreenshotCandidates,
                ),
              if ((isDesktop() &&
                      (compact || !videoPageController.isFullscreen)) ||
                  Platform.isAndroid)
                IconButton(
                  onPressed: () async {
                    if (isDesktop()) {
                      if (videoPageController.isPip) {
                        await PipUtils.exitDesktopPIPWindow();
                      } else {
                        await PipUtils.enterDesktopPIPWindow(
                          width: playerController.debug.playerWidth,
                          height: playerController.debug.playerHeight,
                        );
                      }
                      videoPageController.isPip = !videoPageController.isPip;
                      return;
                    }
                    await widget.enterAndroidPictureInPicture();
                  },
                  tooltip: '画中画',
                  icon: const Icon(
                    Icons.picture_in_picture,
                    color: Colors.white,
                  ),
                ),
              PlayerPanelHoldCollectButton(
                acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                bangumiItem: videoPageController.bangumiItem,
              ),
              PlayerPanelHoldMenuAnchor(
                acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                onVisibilityChanged: widget.onMenuVisibilityChanged,
                builder: (context, toggle) {
                  return IconButton(
                    onPressed: toggle,
                    tooltip: '更多选项',
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                  );
                },
                menuChildren: [
                  if (compact) ...[
                    SubmenuButton(
                      menuChildren: _aspectRatioItems,
                      child: const Text('视频比例'),
                    ),
                    SubmenuButton(
                      menuChildren: _speedItems,
                      child: const Text('倍速'),
                    ),
                    SubmenuButton(
                      menuChildren: _superResolutionItems,
                      child: const Text('超分辨率'),
                    ),
                  ],
                  KazumiMenuItem(
                    onPressed: widget.showVideoInfo,
                    label: '视频详情',
                  ),
                  KazumiMenuItem(
                    onPressed: () {
                      // Renderers fetch the URL themselves: they cannot reach
                      // a file on this device or send the rule's Referer.
                      if (playerController.isLocalPlayback) {
                        KazumiDialog.showToast(message: '暂不支持离线视频');
                        return;
                      }
                      if (playerController.referer.isNotEmpty) {
                        KazumiDialog.showToast(message: '暂不支持该规则');
                        return;
                      }
                      final needRestart = playerController.playback.playing;
                      playerController.pause();
                      RemotePlay()
                          .castVideo(
                            playerController.videoUrl,
                            title: playerController.mediaTitle,
                          )
                          .whenComplete(() {
                            if (mounted && needRestart) {
                              playerController.play();
                            }
                          });
                    },
                    label: '远程投屏',
                  ),
                  KazumiMenuItem(
                    onPressed: playerController.launchExternalPlayer,
                    label: '外部播放',
                  ),
                  SubmenuButton(
                    menuChildren: [
                      KazumiMenuItem(
                        onPressed: TimedShutdownService().cancel,
                        label: '不开启',
                        selected: !TimedShutdownService().isActive,
                      ),
                      for (final int minutes in [15, 30, 60])
                        KazumiMenuItem(
                          onPressed: () {
                            TimedShutdownService().start(
                              minutes,
                              onExpired: widget.pauseForTimedShutdown,
                            );
                            KazumiDialog.showToast(
                              message:
                                  '已设置 ${TimedShutdownService().formatMinutesToDisplay(minutes)} 后定时关闭',
                            );
                          },
                          label: '$minutes 分钟',
                          selected:
                              TimedShutdownService().setMinutes == minutes,
                        ),
                      KazumiMenuItem(
                        onPressed: () {
                          TimedShutdownService.showCustomTimerDialog(
                            onExpired: widget.pauseForTimedShutdown,
                          );
                        },
                        label: '自定义',
                      ),
                    ],
                    child: ValueListenableBuilder<int>(
                      valueListenable:
                          TimedShutdownService().remainingSecondsNotifier,
                      builder: (context, remainingSeconds, _) => Text(
                        remainingSeconds > 0
                            ? "定时关闭 (${TimedShutdownService().formatRemainingTime()})"
                            : "定时关闭",
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get _rightControls {
    return SafeArea(
      top: false,
      bottom: false,
      left: widget.fillsWindow,
      right: widget.fillsWindow,
      child: PlayerPanelHoldMouseRegion(
        acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
        cursor: SystemMouseCursors.basic,
        child: Column(
          children: [
            const Spacer(),
            if (!playerController.panel.lockPanel)
              IconButton(
                icon: const Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.white,
                ),
                tooltip: '截图',
                onPressed: widget.handleScreenShot,
              ),
            IconButton(
              icon: Icon(
                playerController.panel.lockPanel
                    ? Icons.lock_outline
                    : Icons.lock_open,
                color: Colors.white,
              ),
              tooltip: playerController.panel.lockPanel ? '解锁面板' : '锁定面板',
              onPressed: () {
                playerController.panel.lockPanel =
                    !playerController.panel.lockPanel;
              },
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
