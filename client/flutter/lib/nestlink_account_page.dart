import 'dart:async';
import 'package:flutter/material.dart';
import 'homedesk_account.dart';
import 'homedesk_tunnel_api.dart';
import 'homedesk_theme.dart';
import 'nestlink_locale.dart';
import 'nestlink_workspace.dart' show NestLinkSettings;

class NestLinkAccountPage extends StatefulWidget {
  final HomeDeskAccount? account;

  /// Builds non-scrolling local settings inside the account page's ListView.
  final WidgetBuilder? settingsBuilder;
  final VoidCallback? onLogin;
  const NestLinkAccountPage(
      {super.key, this.account, this.settingsBuilder, this.onLogin});
  @override
  State<NestLinkAccountPage> createState() => _NestLinkAccountPageState();
}

class _NestLinkAccountPageState extends State<NestLinkAccountPage> {
  final _currentPassword = TextEditingController(),
      _newPassword = TextEditingController();
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _sessions = [];
  HomeTunnelApi? _owner;
  bool _busy = false;
  bool _accountUpdateQueued = false;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _owner = widget.account?.api;
    widget.account?.addListener(_accountChanged);
    _refresh();
  }

  @override
  void didUpdateWidget(NestLinkAccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.account, widget.account)) {
      oldWidget.account?.removeListener(_accountChanged);
      widget.account?.addListener(_accountChanged);
    }
    _syncOwner();
  }

  void _syncOwner() {
    if (!identical(_owner, widget.account?.api)) {
      _owner = widget.account?.api;
      _busy = false;
      _summary = null;
      _sessions = [];
      _message = '';
      _currentPassword.clear();
      _newPassword.clear();
      _refresh();
    }
  }

  void _accountChanged() {
    if (_accountUpdateQueued) return;
    _accountUpdateQueued = true;
    scheduleMicrotask(() {
      _accountUpdateQueued = false;
      if (!mounted) return;
      setState(_syncOwner);
    });
  }

  bool _current(HomeTunnelApi api) =>
      identical(api, _owner) &&
      identical(api, widget.account?.api) &&
      widget.account?.signedIn == true;

  Future<void> _refresh() async {
    final api = _owner;
    if (api == null || !_current(api)) return;
    try {
      final result =
          await Future.wait([api.accountSummary(), api.managementSessions()]);
      if (!mounted || !_current(api)) return;
      setState(() {
        _summary = result[0] as Map<String, dynamic>;
        _sessions = result[1] as List<Map<String, dynamic>>;
      });
    } on HomeTunnelApiException catch (error) {
      if (mounted && _current(api)) setState(() => _message = error.message);
    }
  }

  Future<void> _run(HomeTunnelApi? api,
      Future<void> Function(HomeTunnelApi) operation) async {
    if (_busy || api == null || !_current(api)) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await operation(api);
      if (!mounted ||
          !identical(api, _owner) ||
          !identical(api, widget.account?.api)) {
        return;
      }
      if (api.isSignedIn) {
        await _refresh();
      } else {
        await widget.account?.signOut();
      }
    } on HomeTunnelApiException catch (error) {
      if (mounted && _current(api)) setState(() => _message = error.message);
    } catch (_) {
      if (mounted && _current(api)) {
        setState(() => _message = nl('操作未完成，请检查网络后重试。',
            'The operation failed. Check your connection and retry.'));
      }
    } finally {
      if (mounted && identical(api, _owner)) setState(() => _busy = false);
    }
  }

  String _bytes(Object? value) {
    if (value is! num) return nl('不限', 'Unlimited');
    return value >= 1073741824
        ? '${(value / 1073741824).toStringAsFixed(1)} GB'
        : '${(value / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    widget.account?.removeListener(_accountChanged);
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final owner = _owner;
    final signedIn = owner != null && _current(owner);
    Widget section(String title, List<Widget> children) => Card(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: t.sectionStyle),
                  const SizedBox(height: 16),
                  ...children
                ])));
    return ListView(key: const ValueKey('account-settings-scroll'), children: [
      if (_message.isNotEmpty)
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_message, key: const ValueKey('account-message'))),
      if (!signedIn)
        section(nl('账号', 'Account'), [
          Text(nl('尚未登录', 'Signed out'), style: t.auxiliaryStyle),
          if (widget.onLogin != null) ...[
            const SizedBox(height: 16),
            Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                    key: const ValueKey('account-login'),
                    onPressed: widget.onLogin,
                    child: Text(nl('登录', 'Sign in')))),
          ],
        ]),
      if (signedIn)
        section(nl('账号与额度', 'Account and quota'), [
          Text(widget.account?.displayName ?? '', style: t.titleStyle),
          if (_owner != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(_owner!.base.origin)),
          const SizedBox(height: 20),
          Text(
              '${nl('本月用量', 'This month')}: ${_bytes(_summary?['month_to_date_bytes'] ?? 0)} / ${_bytes(_summary?['monthly_quota_bytes'])}'),
          const SizedBox(height: 16),
          Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                  key: const ValueKey('account-sign-out'),
                  onPressed: _busy
                      ? null
                      : () => _run(owner, (api) async {
                            await widget.account?.signOut();
                          }),
                  child: Text(nl('退出登录', 'Sign out')))),
        ]),
      const SizedBox(height: 20),
      KeyedSubtree(
          key: ObjectKey(widget.account?.api),
          child: widget.settingsBuilder?.call(context) ??
              NestLinkSettings(account: widget.account, embedded: true)),
      if (signedIn) ...[
        const SizedBox(height: 20),
        section(nl('账号密码', 'Account password'), [
          TextField(
              key: const ValueKey('account-current-password'),
              controller: _currentPassword,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration:
                  InputDecoration(labelText: nl('当前密码', 'Current password'))),
          const SizedBox(height: 16),
          TextField(
              key: const ValueKey('account-new-password'),
              controller: _newPassword,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                  labelText: nl('新密码', 'New password'),
                  helperText: nl('至少 12 个字符，不能包含用户名',
                      'At least 12 characters; must not contain your username'))),
          const SizedBox(height: 16),
          Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(owner, (api) async {
                            await api.changeAccountPassword(
                                _currentPassword.text, _newPassword.text);
                            if (identical(api, _owner)) {
                              _currentPassword.clear();
                              _newPassword.clear();
                            }
                          }),
                  child: Text(nl('保存密码', 'Save password')))),
        ]),
        const SizedBox(height: 20),
        section(nl('管理会话', 'Management sessions'), [
          if (_sessions.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: Text(nl('暂无管理会话', 'No management sessions')))),
          for (final session in _sessions)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '${session['client_type']}${session['current'] == true ? ' · ${nl('当前会话', 'Current session')}' : ''}'),
                subtitle: Text(session['created_at'] as String),
                trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(owner, (api) async {
                              await api.revokeManagementSession(
                                  session['id'] as String);
                              if (session['current'] == true &&
                                  identical(api, widget.account?.api)) {
                                await widget.account?.signOut();
                              }
                            }),
                    child: Text(nl('退出会话', 'Revoke')))),
        ]),
      ],
      const SizedBox(height: 24),
    ]);
  }
}
