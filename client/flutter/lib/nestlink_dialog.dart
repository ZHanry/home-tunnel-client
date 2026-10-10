import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'nestlink_locale.dart';

/// Shared desktop dialog frame. Only the body scrolls, keeping actions visible.
class NestLinkDialog extends StatefulWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final double width;
  final bool scrollContent;

  /// Whether a dismissible dialog with no explicit actions gets a footer close button.
  final bool showClose;
  final VoidCallback? onClose;
  final EdgeInsets contentPadding;
  final Key? scrollKey;

  const NestLinkDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.width = 520,
    this.scrollContent = true,
    this.showClose = true,
    this.onClose,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 8, 24, 20),
    this.scrollKey,
  });

  @override
  State<NestLinkDialog> createState() => _NestLinkDialogState();
}

class _NestLinkDialogState extends State<NestLinkDialog> {
  final _scroll = ScrollController();
  final _frame = GlobalKey();
  final _viewport = GlobalKey();
  Offset _offset = Offset.zero;
  bool _measurementQueued = false;

  void _queueClamp() {
    if (_measurementQueued) return;
    _measurementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementQueued = false;
      if (!mounted) return;
      final constrained = _constrain(_offset);
      if ((constrained - _offset).distance > .1) {
        setState(() => _offset = constrained);
      }
    });
  }

  Offset _constrain(Offset requested) {
    final frame = _frame.currentContext?.findRenderObject();
    final viewport = _viewport.currentContext?.findRenderObject();
    if (frame is! RenderBox ||
        viewport is! RenderBox ||
        !frame.hasSize ||
        !viewport.hasSize) {
      return requested;
    }
    final media = MediaQuery.of(context);
    final visibleWindow = Rect.fromLTRB(
      math.max(media.padding.left, media.viewInsets.left),
      math.max(media.padding.top, media.viewInsets.top),
      media.size.width - math.max(media.padding.right, media.viewInsets.right),
      media.size.height -
          math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
    final visible = viewportRect.intersect(visibleWindow).deflate(8);
    // Remove the current paint translation to recover the centered layout rect.
    final centered = (frame.localToGlobal(Offset.zero) - _offset) & frame.size;
    final left = visible.left - centered.left;
    final right = visible.right - centered.right;
    final top = visible.top - centered.top;
    final bottom = visible.bottom - centered.bottom;
    return Offset(
      left <= right ? requested.dx.clamp(left, right) : right,
      top <= bottom ? requested.dy.clamp(top, bottom) : top,
    );
  }

  void _drag(DragUpdateDetails details) {
    final constrained = _constrain(_offset + details.delta);
    if (constrained != _offset) {
      setState(() => _offset = constrained);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = widget.actions.isNotEmpty
        ? widget.actions
        : widget.showClose
            ? <Widget>[
                TextButton(
                  key: const ValueKey('nestlink-dialog-default-close'),
                  onPressed:
                      widget.onClose ?? () => Navigator.of(context).maybePop(),
                  child: Text(nl('关闭', 'Close')),
                ),
              ]
            : const <Widget>[];
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.vertical - 48;
    return LayoutBuilder(builder: (context, constraints) {
      _queueClamp();
      return Transform.translate(
        key: _viewport,
        offset: _offset,
        child: Dialog(
          insetAnimationDuration: Duration.zero,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _queueClamp();
              return false;
            },
            child: SizeChangedLayoutNotifier(
                child: ConstrainedBox(
              key: _frame,
              constraints: BoxConstraints(
                maxWidth: widget.width,
                maxHeight: availableHeight.clamp(0.0, double.infinity),
              ),
              child: SizedBox(
                key: const ValueKey('nestlink-dialog-frame'),
                width: widget.width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.basic,
                      child: GestureDetector(
                        key: const ValueKey('nestlink-dialog-title-drag'),
                        behavior: HitTestBehavior.opaque,
                        supportedDevices: const {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                        onPanUpdate: _drag,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 40),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              heightFactor: 1,
                              child: DefaultTextStyle.merge(
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                child: widget.title,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: widget.scrollContent
                          ? Scrollbar(
                              controller: _scroll,
                              child: SingleChildScrollView(
                                key: widget.scrollKey,
                                controller: _scroll,
                                padding: widget.contentPadding,
                                child: widget.content,
                              ),
                            )
                          : Padding(
                              padding: widget.contentPadding,
                              child: widget.content,
                            ),
                    ),
                    if (actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                        child: LayoutBuilder(builder: (context, constraints) {
                          return Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final action in actions)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  child: action,
                                ),
                            ],
                          );
                        }),
                      ),
                  ],
                ),
              ),
            )),
          ),
        ),
      );
    });
  }
}
