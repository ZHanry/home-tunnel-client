// HOMEDESK: 连接质量面板只展示会话观测数据，不根据网络模式推测连接路径。
import 'package:flutter/material.dart';
import 'homedesk_theme.dart';

String homeDeskConnectionPath(String? path) => switch (path) {
      'lan' => '局域网直连',
      'p2p' => '公网 P2P',
      'relay' => '中继转发',
      'direct_unknown' => '直连（路径未确认）',
      _ => '正在连接',
    };

class HomeDeskQuality extends StatelessWidget {
  final String? path, transport, speed, fps, delay, bitrate, codec, chroma;
  final bool? secure;
  const HomeDeskQuality(
      {super.key,
      this.path,
      this.transport,
      this.speed,
      this.fps,
      this.delay,
      this.bitrate,
      this.codec,
      this.chroma,
      this.secure});
  String get _delay {
    if (delay == null || delay!.isEmpty) return '—';
    final zero = fps != null &&
        fps!.trim().isNotEmpty &&
        fps!.replaceAll(' ', '').replaceAll('0', '').isEmpty;
    return '${zero ? '0' : delay} 毫秒';
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(
                    color: HomeDeskTokens.of(context).secondary,
                    fontSize: HomeDeskTokens.caption))),
        const SizedBox(width: 12),
        Expanded(
            flex: 7,
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: HomeDeskTokens.of(context).text,
                    fontSize: 12,
                    fontWeight: FontWeight.w500))),
      ]));
  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: HomeDeskTokens.of(context).surface,
          borderRadius: BorderRadius.circular(HomeDeskTokens.controlRadius),
          border: Border.all(color: HomeDeskTokens.of(context).border)),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('连接质量',
                style: TextStyle(
                    color: HomeDeskTokens.of(context).text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _row(context, '连接路径', homeDeskConnectionPath(path)),
            _row(
                context,
                '传输协议',
                transport == 'Relay'
                    ? '未提供'
                    : transport?.isNotEmpty == true
                        ? transport!
                        : '—'),
            _row(
                context,
                '会话安全',
                secure == null
                    ? '确认中'
                    : secure!
                        ? '已加密'
                        : '未加密'),
            Divider(color: HomeDeskTokens.of(context).border, height: 16),
            _row(context, '接收速度', speed ?? '—'),
            _row(context, '帧率', fps == null ? '—' : '$fps 帧/秒'),
            _row(context, '延迟', _delay),
            _row(context, '目标码率', bitrate == null ? '—' : '$bitrate kbps'),
            _row(context, '视频编码', codec ?? '—'),
            _row(context, '色彩采样', chroma ?? '—'),
          ]));
}
