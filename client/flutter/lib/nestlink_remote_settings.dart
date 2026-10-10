import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart'
    show callMainCheckSuperUserPermission, canBeBlocked, option2bool;
import 'consts.dart';
import 'homedesk_account.dart';
import 'homedesk_theme.dart';
import 'models/platform_model.dart';
import 'models/state_model.dart';
import 'models/server_model.dart'
    show kUseTemporaryPassword, kUsePermanentPassword, kUseBothPasswords;
import 'nestlink_dialog.dart';
import 'nestlink_locale.dart';

class NestLinkRemoteSettings extends StatefulWidget {
  final HomeDeskAccount? account;
  final String Function(String)? readOption;
  final bool Function()? remoteReady;
  final bool Function(String)? isOptionFixed;
  final bool Function()? passwordEditable;
  final Future<void> Function(String, String)? saveOption;
  final Future<bool> Function(String)? saveRemotePassword;
  final Future<bool> Function()? hasRemotePassword;
  final bool? initiallyLocked, privacyModeSupported;
  final bool? mobilePlatform;
  final Future<bool> Function()? unlockSettings;
  final Future<bool> Function()? remoteConfigBlocked;

  const NestLinkRemoteSettings({
    super.key,
    this.account,
    this.readOption,
    this.remoteReady,
    this.isOptionFixed,
    this.passwordEditable,
    this.saveOption,
    this.saveRemotePassword,
    this.hasRemotePassword,
    this.initiallyLocked,
    this.privacyModeSupported,
    this.mobilePlatform,
    this.unlockSettings,
    this.remoteConfigBlocked,
  });

  @override
  State<NestLinkRemoteSettings> createState() => _NestLinkRemoteSettingsState();
}

class _NestLinkRemoteSettingsState extends State<NestLinkRemoteSettings> {
  bool get _mobile =>
      widget.mobilePlatform ?? (Platform.isAndroid || Platform.isIOS);
  static const _desktopPermissions = {
    kOptionEnableCamera,
    kOptionEnableTerminal,
    kOptionEnableTunnel,
    kOptionEnableRemoteRestart,
    kOptionEnableRecordSession,
    kOptionEnableRemotePrinter,
    kOptionEnableBlockInput,
    kOptionEnablePrivacyMode,
  };
  static const _permissionLabels = <String, List<String>>{
    kOptionEnableKeyboard: ['键盘与鼠标', 'Keyboard and mouse'],
    kOptionEnableClipboard: ['剪贴板', 'Clipboard'],
    kOptionEnableFileTransfer: ['文件传输', 'File transfer'],
    kOptionEnableAudio: ['声音', 'Audio'],
    kOptionEnableCamera: ['摄像头', 'Camera'],
    kOptionEnableTerminal: ['终端', 'Terminal'],
    kOptionEnableTunnel: ['TCP 隧道', 'TCP tunneling'],
    kOptionEnableRemoteRestart: ['远程重启', 'Remote restart'],
    kOptionEnableRecordSession: ['会话录制', 'Session recording'],
    kOptionEnableRemotePrinter: ['远程打印', 'Remote printing'],
    kOptionEnableBlockInput: ['锁定本机键鼠', 'Block local input'],
    kOptionEnablePrivacyMode: ['隐私模式', 'Privacy mode'],
    kOptionAllowRemoteConfigModification: ['远程修改配置', 'Remote configuration'],
  };
  static const _otherKeys = [
    kOptionApproveMode,
    kOptionVerificationMethod,
    'temporary-password-length',
    kOptionAllowNumericOneTimePassword,
    kOptionAccessMode,
    kOptionEnableLanDiscovery,
    kOptionDirectServer,
    kOptionDirectAccessPort,
    kOptionWhitelist,
    kOptionAllowAutoDisconnect,
    kOptionAutoDisconnectTimeout,
    kOptionKeepAwakeDuringIncomingSessions,
    'allow-only-conn-window-open',
  ];

  final _options = <String, String>{};
  final _dropdownForms = <String, GlobalKey<FormState>>{};
  final _resettingDropdowns = <String>{};
  Object? _owner;
  int _tab = 0;
  bool _busy = false, _locked = false, _installed = false;
  bool _pinSet = false, _privacySupported = false, _optionsLoaded = false;
  bool? _passwordSet;
  int _passwordRevision = 0;
  String _message = '';
  DialogRoute<bool>? _dialogRoute;
  NavigatorState? _dialogNavigator;

  @override
  void initState() {
    super.initState();
    _owner = widget.account?.api;
    try {
      _installed = !_mobile && bind.mainIsInstalled();
      _pinSet = !_mobile && bind.mainGetUnlockPin().isNotEmpty;
      _privacySupported =
          !_mobile && bind.mainSupportedPrivacyModeImpls() != '[]';
    } catch (_) {
      // Native state is unavailable in a preview or before initialization.
    }
    _privacySupported = widget.privacyModeSupported ?? _privacySupported;
    _locked = widget.initiallyLocked ?? (_installed || _pinSet);
    _loadOptions();
    _loadPasswordState();
  }

  bool get _current =>
      mounted &&
      (widget.account == null || identical(_owner, widget.account!.api));

  String _read(String key) =>
      widget.readOption?.call(key) ?? bind.mainGetOptionSync(key: key);

  void _loadOptions() {
    try {
      final next = <String, String>{
        for (final key in [..._otherKeys, ..._permissionLabels.keys])
          key: _read(key)
      };
      _options.addAll(next);
      _optionsLoaded = true;
    } catch (_) {
      _optionsLoaded = false;
    }
  }

  Future<void> _loadPasswordState() async {
    final revision = ++_passwordRevision;
    try {
      final set = widget.hasRemotePassword != null
          ? await widget.hasRemotePassword!()
          : await bind.mainGetCommon(key: 'permanent-password-set') == 'true';
      if (_current && revision == _passwordRevision) {
        setState(() => _passwordSet = set);
      }
    } catch (_) {
      if (_current && revision == _passwordRevision) {
        setState(() => _passwordSet = null);
      }
    }
  }

  @override
  void didUpdateWidget(covariant NestLinkRemoteSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_optionsLoaded && _ready()) _loadOptions();
  }

  bool _fixed(String key) {
    try {
      return widget.isOptionFixed?.call(key) ??
          bind.mainIsOptionFixed(key: key);
    } catch (_) {
      return false;
    }
  }

  bool _ready() {
    if (!_current || (widget.account != null && !widget.account!.signedIn)) {
      return false;
    }
    try {
      return widget.remoteReady?.call() ?? bind.mainNestlinkAccountReady();
    } catch (_) {
      return false;
    }
  }

  bool _passwordEditable() {
    try {
      return widget.passwordEditable?.call() ??
          (bind.mainGetBuildinOption(
                  key: 'disable-change-permanent-password') !=
              'Y');
    } catch (_) {
      return true;
    }
  }

  bool _pinEditable() {
    try {
      return bind.mainGetBuildinOption(key: kOptionDisableUnlockPin) != 'Y';
    } catch (_) {
      return true;
    }
  }

  bool get _editable => !_busy && !_locked && _optionsLoaded;
  bool _bool(String key) => option2bool(key, _options[key] ?? '');
  String get _approval {
    final value = _options[kOptionApproveMode];
    return value == 'click' || value == 'password' ? value! : 'both';
  }

  String get _verification {
    final value = _options[kOptionVerificationMethod];
    return value == kUseTemporaryPassword || value == kUsePermanentPassword
        ? value!
        : kUseBothPasswords;
  }

  String get _access {
    final value = _options[kOptionAccessMode];
    return value == 'full' || value == 'view' ? value! : 'custom';
  }

  String get _length {
    final value = _options['temporary-password-length'];
    return value == '8' || value == '10' ? value! : '6';
  }

  String? _changeError() {
    if (!_current) {
      return nl('账号已切换，请重新打开设置。', 'Account changed. Reopen settings.');
    }
    if (_locked) return nl('请先解锁安全设置', 'Unlock security settings first');
    if (!_ready()) {
      return nl('请等待远控服务就绪', 'Wait for remote authorization to be ready');
    }
    return null;
  }

  Future<String?> _writeError() async {
    final error = _changeError();
    if (error != null) return error;
    try {
      if (widget.readOption == null &&
          (bind.isOutgoingOnly() ||
              bind.isDisableSettings() ||
              bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) ==
                  'Y')) {
        return nl(
            '此设备的安全设置由策略管理', 'Security settings are managed by device policy');
      }
      final blocked = widget.remoteConfigBlocked != null
          ? await widget.remoteConfigBlocked!()
          : stateGlobal.videoConnCount.value > 0 && await canBeBlocked();
      if (!_current) {
        return nl('账号已切换，请重新打开设置。', 'Account changed. Reopen settings.');
      }
      if (blocked) {
        return nl('当前远控会话不允许修改本机安全设置',
            'The current remote session cannot modify security settings');
      }
      // An account or authorization can change while the permission check awaits.
      return _changeError();
    } catch (_) {
      return nl('无法核对设置修改权限，请重试。',
          'Could not verify permission to change settings. Retry.');
    }
  }

  Future<bool> _saveSetting(String key, String? value) async {
    if (!_current || value == null || _busy || _fixed(key)) return false;
    final error = _changeError();
    if (error != null) {
      setState(() => _message = error);
      return false;
    }
    setState(() => _busy = true);
    try {
      final permissionError = await _writeError();
      if (permissionError != null || _fixed(key)) {
        if (_current) {
          setState(() => _message =
              permissionError ?? nl('由设备策略管理', 'Managed by device policy'));
        }
        return false;
      }
      if (widget.saveOption != null) {
        await widget.saveOption!(key, value);
      } else {
        await bind.mainSetOption(key: key, value: value);
        if (!_current) return false;
        // A build policy may reject a value. Do not report a rejected change as saved.
        if (await bind.mainGetOption(key: key) != value) {
          throw StateError('Option did not change');
        }
      }
      if (!_current) return false;
      setState(() {
        _options[key] = value;
        _message = '';
      });
      return true;
    } catch (_) {
      if (_current) {
        setState(() => _message = nl('设置未保存，请重试或检查此设备的设置策略。',
            'Setting was not saved. Retry or check this device’s policy.'));
      }
      return false;
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<bool?> _showEditor(WidgetBuilder builder) async {
    if (!_current || _dialogRoute != null) return null;
    final navigator = Navigator.of(context);
    final route = DialogRoute<bool>(
        context: context, barrierDismissible: false, builder: builder);
    _dialogRoute = route;
    _dialogNavigator = navigator;
    try {
      return await navigator.push(route);
    } finally {
      if (_current && identical(_dialogRoute, route)) {
        setState(() => _dialogRoute = null);
      }
    }
  }

  Future<void> _editPassword(
      {String? enableVerification, String? enableApproval}) async {
    if (!_editable || !_passwordEditable() || _dialogRoute != null) return;
    final result = await _showEditor((_) => _RemoteSettingEditor(
          title: _passwordSet == true
              ? nl('修改固定远控密码', 'Change permanent remote password')
              : nl('设置固定远控密码', 'Set permanent remote password'),
          label: nl('新密码', 'New password'),
          description: enableApproval != null
              ? nl('保存后将使用密码连接本设备。',
                  'Saving will enable password connections to this device.')
              : enableVerification == null
                  ? nl('用于连接本设备，与账号登录密码无关。',
                      'Used to connect to this device, separate from your account password.')
                  : enableVerification == kUsePermanentPassword
                      ? nl('保存后将仅使用固定密码连接本设备。',
                          'Saving will enable permanent passwords only.')
                      : nl('保存后可使用一次性或固定密码连接本设备。',
                          'Saving will enable one-time or permanent passwords.'),
          secret: true,
          confirmation: true,
          fieldKey: const ValueKey('settings-remote-password'),
          confirmKey: const ValueKey('settings-confirm-remote-password'),
          saveKey: const ValueKey('settings-save-remote-password'),
          saveLabel: nl('保存密码', 'Save password'),
          isCurrent: () => _current,
          validate: (value) =>
              value.length < 6 || value.length > 128 || value.trim().isEmpty
                  ? nl('远控密码需要 6 到 128 个字符', 'Use 6 to 128 characters')
                  : null,
          save: (value) async {
            final error = await _writeError();
            if (error != null) return error;
            if (!_passwordEditable()) {
              return nl('此设备不允许修改固定密码', 'Password changes are restricted');
            }
            try {
              final ok = widget.saveRemotePassword != null
                  ? await widget.saveRemotePassword!(value)
                  : await bind.mainSetPermanentPasswordWithResult(
                      password: value);
              if (!_current) return nl('账号已切换', 'Account changed');
              if (!ok) {
                return nl('远控密码保存失败，请稍后重试',
                    'Failed to save remote password. Try again.');
              }
              _passwordRevision++;
              setState(() => _passwordSet = true);
              return null;
            } catch (_) {
              return nl('远控密码保存失败，请稍后重试',
                  'Failed to save remote password. Try again.');
            }
          },
        ));
    if (result != true || !_current) return;
    if (enableVerification != null) {
      if (!await _saveSetting(kOptionVerificationMethod, enableVerification)) {
        return;
      }
    }
    if (enableApproval != null &&
        !await _saveSetting(kOptionApproveMode, enableApproval)) return;
    if (_current) {
      setState(() => _message = nl('远控密码已保存', 'Remote password saved'));
    }
  }

  Future<void> _setVerification(String? value) async {
    if (!_editable ||
        value == null ||
        value == _verification ||
        _fixed(kOptionVerificationMethod)) return;
    if (value != kUseTemporaryPassword) {
      if (_passwordSet == null) await _loadPasswordState();
      if (!_current) return;
      if (_passwordSet != true) {
        if (!_passwordEditable()) {
          setState(() => _message =
              nl('请先设置固定远控密码', 'Set a permanent remote password first'));
        } else {
          await _editPassword(enableVerification: value);
        }
        return;
      }
    }
    await _saveSetting(kOptionVerificationMethod, value);
  }

  Future<void> _setApproval(String? value) async {
    if (!_editable || value == null || _fixed(kOptionApproveMode)) return;
    if (value == 'password' && _verification == kUsePermanentPassword) {
      if (_passwordSet == null) await _loadPasswordState();
      if (!_current) return;
      if (_passwordSet != true) {
        if (_passwordEditable()) {
          await _editPassword(enableApproval: value);
        } else {
          setState(() => _message =
              nl('请先设置固定远控密码', 'Set a permanent remote password first'));
        }
        return;
      }
    }
    await _saveSetting(
        kOptionApproveMode, value == 'both' ? 'password-click' : value);
  }

  Future<void> _unlock() async {
    if (!_current || _busy || !_locked) return;
    if (widget.unlockSettings != null) {
      setState(() => _busy = true);
      try {
        final unlocked = await widget.unlockSettings!();
        if (_current && unlocked) setState(() => _locked = false);
      } finally {
        if (_current) setState(() => _busy = false);
      }
      return;
    }
    try {
      final pin = bind.mainGetUnlockPin();
      bool unlocked;
      if (pin.isEmpty) {
        setState(() => _busy = true);
        unlocked = await callMainCheckSuperUserPermission();
      } else {
        unlocked = await _showEditor((_) => _RemoteSettingEditor(
                  title: nl('解锁安全设置', 'Unlock security settings'),
                  label: nl('设置锁定 PIN', 'Settings PIN'),
                  secret: true,
                  saveLabel: nl('解锁', 'Unlock'),
                  isCurrent: () => _current,
                  save: (value) async => value.trim() == pin
                      ? null
                      : nl('PIN 不正确', 'Incorrect PIN'),
                )) ==
            true;
      }
      if (_current && unlocked) setState(() => _locked = false);
    } catch (_) {
      if (_current) {
        setState(() => _message =
            nl('安全设置未解锁，请重试。', 'Settings were not unlocked. Retry.'));
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _editPin() async {
    if (!_editable || !_pinEditable()) return;
    final result = await _showEditor((_) => _RemoteSettingEditor(
          title: nl('设置锁定 PIN', 'Set settings PIN'),
          label: 'PIN',
          description: nl('重新打开安全设置时需要输入此 PIN。',
              'Enter this PIN when reopening security settings.'),
          secret: true,
          confirmation: true,
          saveLabel: nl('保存 PIN', 'Save PIN'),
          isCurrent: () => _current,
          validate: (value) {
            final length = value.trim().runes.length;
            return length < 4 || length > bind.mainMaxEncryptLen()
                ? nl('PIN 长度不符合要求', 'PIN length is invalid')
                : null;
          },
          save: (value) async {
            final error = await _writeError();
            if (error != null) return error;
            if (!_pinEditable()) {
              return nl('PIN 由设备策略管理', 'PIN is managed by device policy');
            }
            final result = bind.mainSetUnlockPin(pin: value.trim());
            return result.isEmpty ? null : result;
          },
        ));
    if (result == true && _current) setState(() => _pinSet = true);
  }

  Future<void> _removePin() async {
    if (!_editable || !_pinEditable()) return;
    final result = await _showEditor((_) => _RemoteSettingEditor(
          title: nl('移除设置锁定 PIN', 'Remove settings PIN'),
          label: nl('当前 PIN', 'Current PIN'),
          secret: true,
          description: nl('输入当前 PIN 后移除设置锁定。',
              'Enter the current PIN to remove the settings lock.'),
          saveLabel: nl('移除 PIN', 'Remove PIN'),
          isCurrent: () => _current,
          save: (value) async {
            final error = await _writeError();
            if (error != null) return error;
            if (!_pinEditable()) {
              return nl('PIN 由设备策略管理', 'PIN is managed by device policy');
            }
            if (value.trim() != bind.mainGetUnlockPin()) {
              return nl('PIN 不正确', 'Incorrect PIN');
            }
            final result = bind.mainSetUnlockPin(pin: '');
            return result.isEmpty ? null : result;
          },
        ));
    if (result == true && _current) setState(() => _pinSet = false);
  }

  Future<void> _editValue(String key, String title, String value,
      {String? description,
      bool multiline = false,
      String? Function(String)? validate}) async {
    if (!_editable || _fixed(key)) return;
    await _showEditor((_) => _RemoteSettingEditor(
          title: title,
          label: title,
          value: value,
          description: description,
          multiline: multiline,
          numeric: !multiline,
          saveLabel: nl('保存', 'Save'),
          fieldKey: ValueKey('settings-edit-$key'),
          saveKey: ValueKey('settings-save-$key'),
          isCurrent: () => _current,
          validate: validate,
          save: (draft) async {
            final next = multiline
                ? draft
                    .trim()
                    .split(RegExp(r'[\s,;]+'))
                    .where((s) => s.isNotEmpty)
                    .join(',')
                : draft.trim();
            return await _saveSetting(key, next)
                ? null
                : _message.isNotEmpty
                    ? _message
                    : nl('设置未保存，请重试。', 'Setting was not saved. Retry.');
          },
        ));
  }

  String? _validateWhitelist(String value) {
    for (final entry
        in value.trim().split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty)) {
      final parts = entry.split('/');
      final ip = InternetAddress.tryParse(parts.first);
      final prefix = parts.length == 2 ? int.tryParse(parts.last) : null;
      if (ip == null ||
          parts.length > 2 ||
          (parts.length == 2 &&
              (prefix == null ||
                  prefix < 1 ||
                  prefix > (ip.type == InternetAddressType.IPv4 ? 32 : 128)))) {
        return nl(
            '请输入有效的 IP 地址或 CIDR 网段', 'Enter valid IP addresses or CIDR ranges');
      }
    }
    return null;
  }

  @override
  void dispose() {
    final route = _dialogRoute, navigator = _dialogNavigator;
    if (route != null && navigator != null) {
      // Remove only this account's dialog, including its password draft.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
    super.dispose();
  }

  Widget _row(String title, Widget control, {String? description}) {
    final t = HomeDeskTokens.of(context);
    final label =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w500)),
      if (description != null) ...[
        const SizedBox(height: 5),
        Text(description, style: t.auxiliaryStyle),
      ],
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 580 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.35) {
          return Row(children: [
            Expanded(child: label),
            const SizedBox(width: 24),
            SizedBox(width: 250, child: control)
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 10),
              control,
            ]);
      }),
    );
  }

  Widget _dropdown(String key, String value, Map<String, String> choices,
      {Future<dynamic> Function(String?)? onChanged}) {
    final height = homeDeskControlHeight(context);
    final textHeight =
        MediaQuery.textScalerOf(context).scale(16).clamp(24.0, height);
    final formKey =
        _dropdownForms.putIfAbsent(key, () => GlobalKey<FormState>());
    return Form(
        key: formKey,
        child: DropdownButtonFormField<String>(
          key: ValueKey(key),
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            constraints: BoxConstraints.tightFor(height: height),
            contentPadding: EdgeInsets.symmetric(
                horizontal: 12, vertical: (height - textHeight) / 2),
          ),
          items: choices.entries
              .map((entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value,
                      maxLines: 1, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onChanged == null
              ? null
              : (next) async {
                  if (_resettingDropdowns.contains(key)) return;
                  await onChanged(next);
                  // Form fields optimistically select an item. Restore the actual saved
                  // value after a cancelled password prompt or a rejected native write.
                  if (_current) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_current) {
                        _resettingDropdowns.add(key);
                        try {
                          formKey.currentState?.reset();
                        } finally {
                          _resettingDropdowns.remove(key);
                        }
                      }
                    });
                    setState(() {});
                  }
                },
        ));
  }

  Widget _toggle(String key, String title,
      {String? description, bool permission = false}) {
    final preset = permission && _access != 'custom';
    final value = preset ? _access == 'full' : _bool(key);
    final enabled = _editable && !_fixed(key) && !preset;
    final control = Switch(
        key: ValueKey('settings-$key'),
        value: value,
        onChanged:
            enabled ? (value) => _saveSetting(key, value ? 'Y' : 'N') : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: HomeDeskTokens.of(context).text)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description, style: HomeDeskTokens.of(context).auxiliaryStyle)
          ],
          if (_fixed(key))
            Text(nl('由设备策略管理', 'Managed by device policy'),
                style: HomeDeskTokens.of(context).auxiliaryStyle),
        ])),
        const SizedBox(width: 16),
        control,
      ]),
    );
  }

  Widget _button(String key, String label, VoidCallback? action) => SizedBox(
      height: homeDeskControlHeight(context),
      child: OutlinedButton(
          key: ValueKey(key), onPressed: action, child: Text(label)));

  List<Widget> _connection() => [
        _row(
            nl('连接本设备的方式', 'How to connect to this device'),
            _dropdown(
                'settings-host-authorization',
                _approval,
                {
                  'password': nl('密码连接', 'Password connection'),
                  'click': nl('本机确认', 'Approve on this device'),
                  'both': nl('密码或本机确认', 'Password or local approval'),
                },
                onChanged: _editable && !_fixed(kOptionApproveMode)
                    ? _setApproval
                    : null),
            description: _approval == 'click'
                ? nl('每次连接都由本机点击允许。', 'Approve each request on this device.')
                : _approval == 'password'
                    ? nl('对方验证远控密码后连接。',
                        'Connect after verifying the remote password.')
                    : nl('验证密码或由本机点击允许，任一方式均可连接。',
                        'Connect with a password or by approving on this device.')),
        _row(
            nl('可用的远控密码', 'Remote passwords'),
            _dropdown(
                'settings-password-verification',
                _verification,
                {
                  kUseTemporaryPassword: nl('仅一次性密码', 'One-time password only'),
                  kUsePermanentPassword: nl('仅固定密码', 'Permanent password only'),
                  kUseBothPasswords:
                      nl('一次性或固定密码', 'One-time or permanent password'),
                },
                onChanged: _editable && !_fixed(kOptionVerificationMethod)
                    ? _setVerification
                    : null),
            description: _approval == 'click'
                ? nl('当前由本机确认；切换到密码连接后生效。',
                    'Used when password connections are enabled.')
                : null),
        if (_verification != kUsePermanentPassword) ...[
          _row(
              nl('一次性密码长度', 'One-time password length'),
              _dropdown(
                  'settings-temporary-password-length',
                  _length,
                  {
                    for (final length in ['6', '8', '10'])
                      length: '$length ${nl('位', 'characters')}',
                  },
                  onChanged: _editable && !_fixed('temporary-password-length')
                      ? (value) =>
                          _saveSetting('temporary-password-length', value)
                      : null)),
          _toggle(kOptionAllowNumericOneTimePassword,
              nl('一次性密码仅用数字', 'Digits for one-time passwords')),
        ],
        Divider(color: HomeDeskTokens.of(context).border),
        _row(
            nl('固定远控密码', 'Permanent remote password'),
            _button(
                'settings-edit-remote-password',
                _passwordSet == true
                    ? nl('修改密码', 'Change password')
                    : nl('设置密码', 'Set password'),
                _editable && _passwordEditable()
                    ? () => _editPassword()
                    : null),
            description: !_passwordEditable()
                ? nl('由设备策略管理', 'Managed by device policy')
                : _passwordSet == null
                    ? nl('密码状态暂不可用，可重新设置。',
                        'Password status unavailable. You can set a new password.')
                    : _passwordSet == true
                        ? nl('已设置', 'Set')
                        : nl('未设置', 'Not set')),
      ];

  List<Widget> _permissions() => [
        _row(
            nl('远控权限模式', 'Remote permissions'),
            _dropdown(
                'settings-access-mode',
                _access,
                {
                  'custom': nl('自定义权限', 'Custom permissions'),
                  'full': nl('完整控制', 'Full access'),
                  'view': nl('仅查看屏幕', 'View screen only'),
                },
                onChanged: _editable && !_fixed(kOptionAccessMode)
                    ? (value) => _saveSetting(kOptionAccessMode, value)
                    : null),
            description: _access == 'custom'
                ? nl('选择对方连接本设备后可使用的功能。',
                    'Choose the functions available to the remote device.')
                : _access == 'full'
                    ? nl('完整控制会启用下列全部权限；单项修改请选自定义。',
                        'Full access enables all permissions below. Choose Custom to edit them.')
                    : nl('仅允许查看屏幕，下列操作权限全部关闭。',
                        'Only screen viewing is allowed. All permissions below are disabled.')),
        Divider(color: HomeDeskTokens.of(context).border),
        for (final entry in _permissionLabels.entries)
          if ((!_mobile || !_desktopPermissions.contains(entry.key)) &&
              (entry.key != kOptionEnableRemotePrinter &&
                      entry.key != kOptionEnableBlockInput ||
                  Platform.isWindows) &&
              (entry.key != kOptionEnablePrivacyMode || _privacySupported))
            _toggle(entry.key, nl(entry.value[0], entry.value[1]),
                permission: true),
      ];

  List<Widget> _security() => [
        _toggle(kOptionAllowAutoDisconnect,
            nl('空闲时自动断开', 'Disconnect idle sessions')),
        if (_bool(kOptionAllowAutoDisconnect))
          _row(
              nl('空闲超时', 'Idle timeout'),
              _button(
                  'settings-idle-timeout',
                  '${_options[kOptionAutoDisconnectTimeout]?.isNotEmpty == true ? _options[kOptionAutoDisconnectTimeout] : '10'} ${nl('分钟', 'minutes')}',
                  _editable && !_fixed(kOptionAutoDisconnectTimeout)
                      ? () => _editValue(
                          kOptionAutoDisconnectTimeout,
                          nl('空闲超时（分钟）', 'Idle timeout (minutes)'),
                          _options[kOptionAutoDisconnectTimeout]?.isNotEmpty ==
                                  true
                              ? _options[kOptionAutoDisconnectTimeout]!
                              : '10',
                          validate: _validateNumber)
                      : null)),
        _toggle(kOptionKeepAwakeDuringIncomingSessions,
            nl('被控期间保持唤醒', 'Keep awake during incoming sessions')),
        if (_installed)
          _toggle(
              'allow-only-conn-window-open',
              nl('仅在主窗口打开时允许连接',
                  'Only accept connections while the main window is open')),
        if (!_mobile && Platform.isWindows) ...[
          _row(
              nl('设置锁定 PIN', 'Settings PIN'),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _button(
                        'settings-edit-pin',
                        _pinSet
                            ? nl('修改 PIN', 'Change PIN')
                            : nl('设置 PIN', 'Set PIN'),
                        _editable && _pinEditable() ? _editPin : null),
                    if (_pinSet)
                      _button('settings-remove-pin', nl('移除 PIN', 'Remove PIN'),
                          _editable && _pinEditable() ? _removePin : null),
                  ]),
              description: nl('保护本设备的远控安全设置。',
                  'Protect this device’s remote security settings.')),
        ],
        Divider(color: HomeDeskTokens.of(context).border),
        _toggle(
            kOptionEnableLanDiscovery, nl('允许局域网发现', 'Allow LAN discovery')),
        _toggle(kOptionDirectServer,
            nl('允许通过 IP 直连', 'Allow direct IP connections'),
            description: nl('直连仍需通过账号与远控授权检查。',
                'Direct connections still require account and remote authorization.')),
        if (_bool(kOptionDirectServer))
          _row(
              nl('直连端口', 'Direct access port'),
              _button(
                  'settings-direct-port',
                  _options[kOptionDirectAccessPort]?.isNotEmpty == true
                      ? _options[kOptionDirectAccessPort]!
                      : '21118',
                  _editable && !_fixed(kOptionDirectAccessPort)
                      ? () => _editValue(
                          kOptionDirectAccessPort,
                          nl('直连端口', 'Direct access port'),
                          _options[kOptionDirectAccessPort]?.isNotEmpty == true
                              ? _options[kOptionDirectAccessPort]!
                              : '21118',
                          validate: _validateNumber)
                      : null)),
        _row(
            nl('来源 IP 白名单', 'Source IP whitelist'),
            _button(
                'settings-whitelist',
                nl('设置', 'Configure'),
                _editable && !_fixed(kOptionWhitelist)
                    ? () => _editValue(
                        kOptionWhitelist,
                        nl('来源 IP 白名单', 'Source IP whitelist'),
                        (_options[kOptionWhitelist] ?? '')
                            .split(',')
                            .join('\n'),
                        multiline: true,
                        description: nl(
                            '每行一个 IP 地址或 CIDR 网段。留空表示清除限制，设备策略仍会生效。',
                            'One IP address or CIDR range per line. Leave empty to clear; device policy still applies.'),
                        validate: _validateWhitelist)
                    : null),
            description: (_options[kOptionWhitelist] ?? '').isEmpty
                ? nl('未设置额外来源限制', 'No additional source restriction')
                : nl(
                    '仅允许名单中的来源地址', 'Only listed source addresses are allowed')),
        if (!_mobile && Platform.isWindows && _installed) _rdpSetting(),
      ];

  String? _validateNumber(String value) {
    final number = int.tryParse(value.trim());
    return number == null || number < 1 || number > 65535
        ? nl('请输入 1 到 65535 的整数', 'Enter a whole number from 1 to 65535')
        : null;
  }

  Widget _rdpSetting() {
    bool? value;
    try {
      value = bind.mainIsShareRdp();
    } catch (_) {
      // Keep an unavailable native setting read-only.
    }
    return _row(
        nl('RDP 会话共享', 'RDP session sharing'),
        Align(
            alignment: Alignment.centerRight,
            child: Switch(
                value: value ?? false,
                onChanged: _editable && value != null
                    ? (value) async {
                        final error = await _writeError();
                        if (error != null) {
                          setState(() => _message = error);
                          return;
                        }
                        setState(() => _busy = true);
                        try {
                          await bind.mainSetShareRdp(enable: value);
                          if (bind.mainIsShareRdp() != value) {
                            throw StateError('RDP sharing did not change');
                          }
                        } catch (_) {
                          if (_current) {
                            setState(() => _message = nl(
                                '设置未保存，请重试。', 'Setting was not saved. Retry.'));
                          }
                        } finally {
                          if (_current) setState(() => _busy = false);
                        }
                      }
                    : null)));
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeDeskTokens.of(context);
    final tabs = [
      nl('连接与密码', 'Connection and passwords'),
      nl('远控权限', 'Remote permissions'),
      nl('安全保护', 'Security')
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Divider(height: 1, color: t.border),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child: Text(nl('远控设置', 'Remote settings'), style: t.sectionStyle)),
        if (!_locked && (_installed || _pinSet))
          TextButton(
              onPressed: _busy ? null : () => setState(() => _locked = true),
              child: Text(nl('锁定设置', 'Lock settings'))),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var index = 0; index < tabs.length; index++)
          TextButton(
            key: ValueKey('settings-tab-$index'),
            style: TextButton.styleFrom(
                backgroundColor:
                    _tab == index ? t.accentSoft : Colors.transparent,
                foregroundColor: _tab == index ? t.accentText : t.secondary,
                minimumSize: Size(0, homeDeskControlHeight(context))),
            onPressed: () => setState(() {
              _tab = index;
              _message = '';
            }),
            child: Text(tabs[index]),
          ),
      ]),
      const SizedBox(height: 8),
      if (_locked)
        _row(
            nl('安全设置已锁定', 'Security settings are locked'),
            _button('settings-unlock', nl('解锁安全设置', 'Unlock security settings'),
                _busy ? null : _unlock)),
      if (!_ready())
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
                nl('远控尚未就绪，设置将在本机接入完成后保存。',
                    'Remote control is not ready. Wait for device registration before saving.'),
                style: t.auxiliaryStyle)),
      if (!_optionsLoaded)
        _row(
            nl('安全参数读取失败', 'Security settings could not be read'),
            _button('settings-reload', nl('重新读取', 'Reload'), () {
              setState(_loadOptions);
              _loadPasswordState();
            }))
      else
        ...(_tab == 0
            ? _connection()
            : _tab == 1
                ? _permissions()
                : _security()),
      if (_message.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message,
                key: const ValueKey('settings-feedback'),
                style: t.auxiliaryStyle)),
    ]);
  }
}

/// Account-owned editor with confirmation, visible save feedback and a fixed footer.
class _RemoteSettingEditor extends StatefulWidget {
  final String title, label, saveLabel, value;
  final String? description;
  final bool secret, confirmation, multiline, numeric;
  final Key? fieldKey, confirmKey, saveKey;
  final bool Function() isCurrent;
  final String? Function(String)? validate;
  final Future<String?> Function(String) save;
  const _RemoteSettingEditor(
      {required this.title,
      required this.label,
      required this.saveLabel,
      required this.isCurrent,
      required this.save,
      this.value = '',
      this.description,
      this.secret = false,
      this.confirmation = false,
      this.multiline = false,
      this.numeric = false,
      this.fieldKey,
      this.confirmKey,
      this.saveKey,
      this.validate});
  @override
  State<_RemoteSettingEditor> createState() => _RemoteSettingEditorState();
}

class _RemoteSettingEditorState extends State<_RemoteSettingEditor> {
  late final _value = TextEditingController(text: widget.value);
  final _confirm = TextEditingController();
  bool _busy = false, _revealed = false;
  String? _error;

  Future<void> _save() async {
    if (_busy || !widget.isCurrent()) return;
    final error = widget.validate?.call(_value.text) ??
        (widget.confirmation && _value.text != _confirm.text
            ? nl('两次输入不一致', 'The entries do not match')
            : null);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final error = await widget.save(_value.text);
      if (!mounted || !widget.isCurrent()) return;
      if (error == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = error);
      }
    } catch (_) {
      if (mounted && widget.isCurrent()) {
        setState(() => _error = nl('保存失败，请重试。', 'Save failed. Retry.'));
      }
    } finally {
      if (mounted && widget.isCurrent()) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController controller, Key? key,
      {bool autofocus = false, bool submit = false}) {
    final height = homeDeskControlHeight(context, minimum: 48);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label),
      const SizedBox(height: 8),
      TextField(
          key: key,
          controller: controller,
          autofocus: autofocus,
          readOnly: _busy,
          obscureText: widget.secret && !_revealed,
          autocorrect: false,
          enableSuggestions: false,
          minLines: widget.multiline ? 4 : 1,
          maxLines: widget.multiline ? 6 : 1,
          keyboardType: widget.numeric ? TextInputType.number : null,
          inputFormatters:
              widget.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
          textInputAction: submit ? TextInputAction.done : TextInputAction.next,
          onSubmitted: submit
              ? (_) => _save()
              : (_) => FocusScope.of(context).nextFocus(),
          style: const TextStyle(fontSize: 16, height: 1.5),
          decoration: InputDecoration(
            constraints: widget.multiline
                ? null
                : BoxConstraints.tightFor(height: height),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: height / 4),
            suffixIcon: widget.secret && autofocus
                ? IconButton(
                    tooltip: _revealed
                        ? nl('隐藏密码', 'Hide password')
                        : nl('显示密码', 'Show password'),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _revealed = !_revealed),
                    icon: Icon(_revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined))
                : null,
          )),
    ]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: NestLinkDialog(
          title: Text(widget.title),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.description != null) ...[
                  Text(widget.description!,
                      style: HomeDeskTokens.of(context).auxiliaryStyle),
                  const SizedBox(height: 20),
                ],
                _field(widget.label, _value, widget.fieldKey,
                    autofocus: true, submit: !widget.confirmation),
                if (widget.confirmation) ...[
                  const SizedBox(height: 16),
                  _field(nl('确认密码', 'Confirm password'), _confirm,
                      widget.confirmKey,
                      submit: true),
                ],
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]),
          actions: [
            SizedBox(
                height: homeDeskControlHeight(context),
                child: TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: Text(nl('取消', 'Cancel')))),
            SizedBox(
                height: homeDeskControlHeight(context),
                child: FilledButton(
                    key: widget.saveKey,
                    onPressed: _busy ? null : _save,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_busy) ...[
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8)
                      ],
                      Text(widget.saveLabel),
                    ]))),
          ],
        ),
      );
}
