import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';

class CollectButton extends StatefulWidget {
  const CollectButton({
    super.key,
    required this.bangumiItem,
    this.color = Colors.white,
    this.onOpen,
    this.onClose,
  }) : _isExtended = false;
  const CollectButton.extend({
    super.key,
    required this.bangumiItem,
    this.color = Colors.white,
    this.onOpen,
    this.onClose,
  }) : _isExtended = true;
  final BangumiItem bangumiItem;
  final Color color;
  final bool _isExtended;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  @override
  State<CollectButton> createState() => _CollectButtonState();
}

class _CollectButtonState extends State<CollectButton> {
  bool _busy = false;
  Future<void> _toggle(CollectController controller) async {
    if (_busy) return;
    setState(() => _busy = true);
    widget.onOpen?.call();
    try {
      if (controller.getCollectType(widget.bangumiItem) == 0) {
        await controller.addCollect(widget.bangumiItem);
      } else {
        await controller.deleteCollect(widget.bangumiItem);
      }
    } catch (_) {
      KazumiDialog.showToast(message: '�ղر���ʧ�ܣ�������');
    } finally {
      widget.onClose?.call();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      final controller = inject<CollectController>();
      final saved = controller.collectibles.any(
        (entry) => entry.bangumiItem.id == widget.bangumiItem.id,
      );
      final label = saved ? 'ȡ���ղ�' : '�ղ�';
      final icon = Icon(
        saved ? Icons.favorite : Icons.favorite_border,
        color: widget.color,
      );
      return widget._isExtended
          ? FilledButton.icon(
              onPressed: _busy ? null : () => _toggle(controller),
              icon: icon,
              label: Text(label),
            )
          : IconButton(
              onPressed: _busy ? null : () => _toggle(controller),
              tooltip: label,
              icon: icon,
            );
    },
  );
}
