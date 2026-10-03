// HOMEDESK: 连接质量面板只展示会话观测数据，不根据网络模式推测连接路径。
import 'package:flutter/material.dart';

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
    final zero = fps != null && fps!.trim().isNotEmpty &&
        fps!.replaceAll(' ', '').replaceAll('0', '').isEmpty;
    return '${zero ? '0' : delay} 毫秒';
  }

  Widget _row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 4,
            child: Text(label,
                style:
                    const TextStyle(color: Color(0xFFD3DBE8), fontSize: 12))),
        const SizedBox(width: 12),
        Expanded(
            flex: 7,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500))),
      ]));
  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xDD131A25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF3A465C))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('连接质量',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _row('连接路径', homeDeskConnectionPath(path)),
            _row(
                '传输协议',
                transport == 'Relay'
                    ? '未提供'
                    : transport?.isNotEmpty == true
                        ? transport!
                        : '—'),
            _row(
                '会话安全',
                secure == null
                    ? '确认中'
                    : secure!
                        ? '已加密'
                        : '未加密'),
            const Divider(color: Color(0xFF3A465C), height: 16),
            _row('接收速度', speed ?? '—'),
            _row('帧率', fps == null ? '—' : '$fps 帧/秒'),
            _row('延迟', _delay),
            _row('目标码率', bitrate == null ? '—' : '$bitrate kbps'),
            _row('视频编码', codec ?? '—'),
            _row('色彩采样', chroma ?? '—'),
          ]));
}
