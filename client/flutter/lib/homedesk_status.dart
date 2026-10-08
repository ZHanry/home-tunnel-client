// HOMEDESK: 只读取现有网络、远控和账号状态，不更改许可或联网行为。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'models/platform_model.dart';
import 'common.dart' show start_service;
import 'models/state_model.dart';
import 'homedesk_account.dart';
import 'homedesk_theme.dart';
import 'homedesk_navigation.dart';

class HomeDeskStatusData {
  final String mode, server;
  final HomeDeskTone tone;
  final bool serviceStopped;
  const HomeDeskStatusData(
      {this.mode = '网络模式待确认',
      this.server = '远控服务器状态待确认',
      this.tone = HomeDeskTone.neutral,
      this.serviceStopped = false});
}

class HomeDeskStatus extends StatefulWidget {
  final HomeDeskAccount? account;
  final HomeDeskStatusData? data;
  final bool live, footer, exceptionOnly;
  final Future<void> Function()? onStartService;
  final VoidCallback? onNetwork;
  const HomeDeskStatus(
      {super.key,
      this.account,
      this.data,
      this.live = false,
      this.footer = false,
      this.exceptionOnly = false,
      this.onStartService,
      this.onNetwork});
  @override
  State<HomeDeskStatus> createState() => _HomeDeskStatusState();
}

class _HomeDeskStatusState extends State<HomeDeskStatus> {
  Timer? _timer;
  bool _starting = false;
  HomeDeskStatusData _data = const HomeDeskStatusData();
  @override
  void initState() {
    super.initState();
    if (widget.live) {
      _read();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read());
    }
  }

  void _read() {
    try {
      final mode = bind.mainGetOptionSync(key: 'homedesk-net-mode');
      final stopped = Get.isRegistered<RxBool>(tag: 'stop-service') &&
          Get.find<RxBool>(tag: 'stop-service').value;
      final status = stateGlobal.svcStatus.value;
      final next = HomeDeskStatusData(
          mode: mode == 'self_hosted'
              ? '自建公网模式'
              : mode == 'lan_only'
                  ? '纯内网模式'
                  : '网络模式待确认',
          server: stopped
              ? '远控后台服务已停止'
              : status == SvcStatus.ready
                  ? '远控服务器已连接'
                  : status == SvcStatus.connecting
                      ? '远控服务器连接中'
                      : '远控服务器未连接',
          serviceStopped: stopped,
          tone: stopped
              ? HomeDeskTone.neutral
              : status == SvcStatus.ready
                  ? HomeDeskTone.success
                  : status == SvcStatus.connecting
                      ? HomeDeskTone.warning
                      : HomeDeskTone.danger);
      if (mounted && (_data.mode != next.mode || _data.server != next.server)) {
        setState(() => _data = next);
      } else {
        _data = next;
      }
    } catch (_) {/* 测试环境不加载原生桥接，保持真实未知态。 */}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startService() async {
    if (_starting) {
      return;
    }
    setState(() => _starting = true);
    try {
      await (widget.onStartService?.call() ?? start_service(true));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('服务未能启动，请在设置中重试。')));
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        if (widget.live) {
          _read();
        }
      }
    }
  }

  Widget _body(BuildContext context) {
    final t = HomeDeskTokens.of(context), data = widget.data ?? _data;
    final accountLabel =
        widget.account?.signedIn == true ? '家庭账号已登录' : '家庭账号未登录';
    final attention = data.serviceStopped ||
        data.tone == HomeDeskTone.warning ||
        data.tone == HomeDeskTone.danger;
    if (widget.exceptionOnly && !attention) {
      return const SizedBox.shrink();
    }
    final surface = Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
            horizontal: widget.footer ? 12 : 16,
            vertical: widget.footer ? 6 : 10),
        decoration: BoxDecoration(
            color: widget.footer ? t.chrome : t.surface2,
            borderRadius: widget.footer
                ? null
                : BorderRadius.circular(HomeDeskTokens.blockRadius),
            border: widget.footer
                ? Border(top: BorderSide(color: t.border))
                : Border.all(color: t.border)),
        child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!widget.exceptionOnly)
                Text(data.mode, style: t.auxiliaryStyle),
              HomeDeskBadge(data.server, tone: data.tone),
              if (!widget.exceptionOnly)
                Text(accountLabel, style: t.auxiliaryStyle),
              if (data.serviceStopped)
                TextButton(
                    key: const ValueKey('status-start-service'),
                    onPressed: _starting ? null : _startService,
                    child: Text(_starting ? '正在启动…' : '启动服务')),
              if (widget.onNetwork != null)
                InkWell(
                    onTap: widget.onNetwork,
                    child: Text('网络设置',
                        style: TextStyle(
                            fontSize: HomeDeskTokens.auxiliary,
                            color: t.accentText))),
            ]));
    return widget.exceptionOnly
        ? Padding(
            padding: const EdgeInsets.only(bottom: HomeDeskTokens.moduleGap),
            child: surface)
        : surface;
  }

  @override
  Widget build(BuildContext context) => widget.account == null
      ? _body(context)
      : HomeDeskAccountView(account: widget.account!, builder: _body);
}
