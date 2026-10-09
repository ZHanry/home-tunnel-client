import 'package:flutter/material.dart';
import 'homedesk_account.dart';
import 'homedesk_tunnel_api.dart';
import 'homedesk_theme.dart';
import 'nestlink_locale.dart';

class NestLinkAccountPage extends StatefulWidget {
  final HomeDeskAccount? account;
  const NestLinkAccountPage({super.key, this.account});
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
  String _message = '';
  @override
  void initState() {
    super.initState();
    _owner = widget.account?.api;
    _refresh();
  }

  @override
  void didUpdateWidget(NestLinkAccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_owner, widget.account?.api)) {
      _owner = widget.account?.api;
      _summary = null;
      _sessions = [];
      _message = '';
      _currentPassword.clear();
      _newPassword.clear();
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final api = _owner;
    if (api == null || !api.isSignedIn) return;
    try {
      final result =
          await Future.wait([api.accountSummary(), api.managementSessions()]);
      if (!mounted || !identical(api, _owner) || !api.isSignedIn) return;
      setState(() {
        _summary = result[0] as Map<String, dynamic>;
        _sessions = result[1] as List<Map<String, dynamic>>;
      });
    } on HomeTunnelApiException catch (error) {
      if (mounted && identical(api, _owner))
        setState(() => _message = error.message);
    }
  }

  Future<void> _run(Future<void> Function(HomeTunnelApi) operation) async {
    final api = _owner;
    if (_busy || api == null || !api.isSignedIn) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await operation(api);
      if (api.isSignedIn) {
        await _refresh();
      } else {
        widget.account?.clear(api);
      }
    } on HomeTunnelApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted)
        setState(() => _message = nl('操作未完成，请检查网络后重试。',
            'The operation failed. Check your connection and retry.'));
    } finally {
      if (mounted) setState(() => _busy = false);
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
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
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
    return ListView(children: [
      if (_message.isNotEmpty)
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_message, key: const ValueKey('account-message'))),
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
                onPressed: _busy ? null : () => _run((api) => api.logout()),
                child: Text(nl('退出登录', 'Sign out')))),
      ]),
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
                    : () => _run((api) async {
                          await api.changeAccountPassword(
                              _currentPassword.text, _newPassword.text);
                          _currentPassword.clear();
                          _newPassword.clear();
                        }),
                child: Text(nl('保存密码', 'Save password')))),
      ]),
      const SizedBox(height: 20),
      section(nl('管理会话', 'Management sessions'), [
        if (_sessions.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child:
                  Center(child: Text(nl('暂无管理会话', 'No management sessions')))),
        for (final session in _sessions)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                  '${session['client_type']}${session['current'] == true ? ' · ${nl('当前会话', 'Current session')}' : ''}'),
              subtitle: Text(session['created_at'] as String),
              trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run((api) async {
                            await api.revokeManagementSession(
                                session['id'] as String);
                            if (session['current'] == true) await api.revoke();
                          }),
                  child: Text(nl('退出会话', 'Revoke')))),
      ]),
      const SizedBox(height: 24),
    ]);
  }
}
