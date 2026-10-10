import 'package:flutter/material.dart';

import 'homedesk_theme.dart';
import 'nestlink_locale.dart';

/// A quiet form beside a purple illustration of devices joining one workspace.
class NestLinkLoginLayout extends StatelessWidget {
  final Widget form;
  const NestLinkLoginLayout({super.key, required this.form});

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 860 &&
          constraints.maxHeight >= 540 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20;
      final panel = ColoredBox(
          color: t.surface,
          child: LayoutBuilder(builder: (context, bounds) {
            return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: wide ? 48 : 24, vertical: 32),
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight:
                            (bounds.maxHeight - 64).clamp(0, double.infinity)),
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 380),
                            child: form))));
          }));
      if (!wide) return panel;
      return Row(children: [
        Expanded(flex: 44, child: _brandPanel(t)),
        Expanded(flex: 56, child: panel),
      ]);
    });
  }

  Widget _brandPanel(HomeDeskTokens t) => ColoredBox(
      key: const ValueKey('nestlink-login-brand'),
      color: t.chrome,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 40, 36, 32),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                              width: 300,
                              height: 196,
                              child: Stack(children: [
                                Positioned.fill(
                                    child: CustomPaint(
                                        painter: _ConnectedDevices(t))),
                                Positioned(
                                    left: 134,
                                    top: 86,
                                    child: Icon(Icons.link_rounded,
                                        color: t.accent, size: 28)),
                              ])),
                          const SizedBox(height: 32),
                          Text(nl('把设备连接起来', 'Bring your devices together'),
                              style: TextStyle(
                                  fontSize: 28,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  color: t.text)),
                          const SizedBox(height: 14),
                          Text(
                              nl('远程桌面、设备管理与内网穿透，\n从一个工作台开始。',
                                  'Remote desktops, devices and tunnels\nfrom one workspace.'),
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.8,
                                  color: t.secondary)),
                        ]))),
          ])));
}

class _ConnectedDevices extends CustomPainter {
  final HomeDeskTokens tokens;
  _ConnectedDevices(this.tokens);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300, size.height / 196);
    final line = Paint()
      ..color = tokens.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = tokens.surface;
    final screen = RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 14, 108, 75), const Radius.circular(8));
    canvas.drawRRect(screen, fill);
    canvas.drawRRect(screen, line);
    canvas.drawLine(const Offset(3, 75), const Offset(111, 75), line);
    canvas.drawLine(const Offset(57, 90), const Offset(57, 105), line);
    canvas.drawLine(const Offset(34, 105), const Offset(80, 105), line);
    final laptop = RRect.fromRectAndRadius(
        const Rect.fromLTWH(194, 118, 97, 60), const Radius.circular(7));
    canvas.drawRRect(laptop, fill);
    canvas.drawRRect(laptop, line);
    canvas.drawPath(
        Path()
          ..moveTo(188, 180)
          ..lineTo(298, 180)
          ..lineTo(291, 188)
          ..lineTo(195, 188)
          ..close(),
        line);
    canvas.drawPath(
        Path()
          ..moveTo(112, 51)
          ..lineTo(148, 51)
          ..lineTo(148, 76),
        line);
    canvas.drawPath(
        Path()
          ..moveTo(148, 124)
          ..lineTo(148, 148)
          ..lineTo(193, 148),
        line);
    final dot = Paint()..color = tokens.accent;
    canvas.drawCircle(const Offset(112, 51), 3.5, dot);
    canvas.drawCircle(const Offset(193, 148), 3.5, dot);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConnectedDevices oldDelegate) =>
      oldDelegate.tokens != tokens;
}
