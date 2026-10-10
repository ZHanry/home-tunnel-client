// HOMEDESK: 服务编辑草稿和冲突核对独立于远控协议。
import 'dart:io';

import 'package:flutter/material.dart';
import 'homedesk_theme.dart';
import 'nestlink_dialog.dart';

import 'homedesk_tunnel_api.dart';
import 'homedesk_device_label.dart';

class HomeDeskServiceDraft {
  final String? serviceId;
  final String deviceId;
  final String name;
  final String proxyType;
  final String localScheme;
  final String localHost;
  final int localPort;
  final String subdomain;
  final String? applicationProtocol;
  final bool enabled;
  final int? expectedVersion;

  const HomeDeskServiceDraft(
      {this.serviceId,
      required this.deviceId,
      this.name = '',
      this.proxyType = 'http',
      this.localScheme = 'http',
      this.localHost = '127.0.0.1',
      this.localPort = 80,
      this.subdomain = '',
      this.applicationProtocol,
      this.enabled = true,
      this.expectedVersion});

  Map<String, dynamic> toValues() => {
        'name': name,
        'local_scheme': localScheme,
        'local_host': localHost,
        'local_port': localPort,
        'enabled': enabled,
        if (serviceId == null) 'device_id': deviceId,
        if (serviceId == null) 'proxy_type': proxyType,
        if (proxyType == 'http') 'subdomain': subdomain,
        if (proxyType == 'tcp') 'application_protocol': applicationProtocol,
      };

  String get summary =>
      '$name · ${proxyType.toUpperCase()} · $localScheme://$localHost:$localPort'
      '${proxyType == 'http' ? ' · $subdomain' : ''} · ${enabled ? '启用' : '暂停'}';
}

class HomeDeskServiceReview {
  final String summary;
  final int? version;
  final bool exists;
  const HomeDeskServiceReview(
      {required this.summary, this.version, this.exists = true});
}

class HomeDeskServiceEditor extends StatefulWidget {
  final HomeDeskServiceDraft initial;
  final List<HomeTunnelDevice> devices;
  final Set<String> supportedTypes;
  final String? remoteEndpoint;
  final bool Function() isAllowed;
  final Future<void> Function(HomeDeskServiceDraft) onSave;
  final Future<HomeDeskServiceReview> Function() onReview;
  final ValueChanged<HomeDeskServiceDraft>? onDraftChanged;
  final VoidCallback? onReviewConfirmed;
  final bool needsReview;

  const HomeDeskServiceEditor(
      {super.key,
      required this.initial,
      required this.devices,
      required this.supportedTypes,
      required this.isAllowed,
      required this.onSave,
      required this.onReview,
      this.remoteEndpoint,
      this.onDraftChanged,
      this.onReviewConfirmed,
      this.needsReview = false});

  @override
  State<HomeDeskServiceEditor> createState() => _HomeDeskServiceEditorState();
}

class _HomeDeskServiceEditorState extends State<HomeDeskServiceEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _subdomain;
  late String _deviceId;
  late String _proxyType;
  late String _scheme;
  String? _applicationProtocol;
  late bool _enabled;
  int? _reviewVersion;
  bool _busy = false;
  bool _needsReview = false;
  bool _reviewLoaded = false;
  bool _reviewed = false;
  bool _exists = true;
  String _message = '';
  String _serverSummary = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial.name);
    _host = TextEditingController(text: initial.localHost);
    _port = TextEditingController(text: initial.localPort.toString());
    _subdomain = TextEditingController(text: initial.subdomain);
    _deviceId = initial.deviceId;
    _proxyType = initial.proxyType;
    _scheme = initial.localScheme;
    _applicationProtocol = initial.applicationProtocol;
    _enabled = initial.enabled;
    _needsReview = widget.needsReview;
    if (_needsReview) {
      _message = '上次操作结果未确认，请刷新核对。当前草稿已保留，不会自动重试。';
    }
    for (final controller in [_name, _host, _port, _subdomain]) {
      controller.addListener(_draftChanged);
    }
  }

  HomeDeskServiceDraft get _draft => HomeDeskServiceDraft(
      serviceId: widget.initial.serviceId,
      deviceId: _deviceId,
      name: _name.text.trim(),
      proxyType: _proxyType,
      localScheme: _scheme,
      localHost: _host.text.trim(),
      localPort: int.tryParse(_port.text) ?? 0,
      subdomain: _subdomain.text.trim(),
      applicationProtocol: _applicationProtocol,
      enabled: _enabled,
      expectedVersion: _reviewed && _reviewVersion != null
          ? _reviewVersion
          : widget.initial.expectedVersion);

  void _draftChanged() => widget.onDraftChanged?.call(_draft);

  void _change(VoidCallback change) {
    setState(change);
    _draftChanged();
  }

  bool _allowed() {
    if (widget.isAllowed()) return true;
    setState(() => _message = '网络许可已变化，请关闭编辑器并重新登录。草稿已保留。');
    return false;
  }

  Future<void> _save() async {
    if (_busy || !_allowed() || !_form.currentState!.validate()) return;
    if (_needsReview && (!_reviewLoaded || !_reviewed || !_exists)) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await widget.onSave(_draft);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final code = error is HomeTunnelApiException ? error.code : '';
      setState(() {
        if (code == 'MUTATION_UNKNOWN') {
          _message = '结果未确认，刷新核对后再决定是否保存。当前草稿已保留，不会自动重试。';
          _needsReview = true;
          _reviewLoaded = false;
          _reviewed = false;
        } else if (code.contains('VERSION_CONFLICT')) {
          _message = '服务器上的设置已经变化，请刷新核对后再保存。当前草稿已保留。';
          _needsReview = true;
          _reviewLoaded = false;
          _reviewed = false;
        } else {
          _message = error is HomeTunnelApiException
              ? error.message
              : '保存未完成，请检查网络。当前草稿已保留。';
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    if (_busy || !_allowed()) return;
    setState(() => _busy = true);
    try {
      final review = await widget.onReview();
      if (!mounted || !widget.isAllowed()) return;
      setState(() {
        _serverSummary = review.summary;
        _reviewVersion = review.version;
        _exists = review.exists;
        _reviewLoaded = true;
        _reviewed = false;
        _message = review.exists
            ? '已刷新服务器设置。核对后可以继续保存当前草稿。'
            : '这个服务已被删除，不能覆盖保存。当前草稿仍保留。';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            error is HomeTunnelApiException ? error.message : '刷新未完成，请稍后再核对。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _nameError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '请输入服务名称。';
    if (text.length > 120 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      return '名称最多 120 个字符，不能包含控制字符。';
    }
    return null;
  }

  String? _hostError(String? value) {
    final host = value?.trim() ?? '';
    if (InternetAddress.tryParse(host) != null) return null;
    if (host.length > 253 ||
        host.isEmpty ||
        !host.split('.').every((part) =>
            RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
                .hasMatch(part))) {
      return '请输入主机名或 IP，不包含协议、路径或端口。';
    }
    return null;
  }

  String? _portError(String? value) {
    final port = int.tryParse(value ?? '');
    return port == null || port < 1 || port > 65535 ? '端口应为 1 至 65535。' : null;
  }

  String? _subdomainError(String? value) =>
      RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
              .hasMatch(value?.trim() ?? '')
          ? null
          : '请输入小写字母、数字和连字符组成的访问名称。';

  @override
  void dispose() {
    for (final controller in [_name, _host, _port, _subdomain]) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration({String? hint, String? helper}) =>
      InputDecoration(
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
          errorMaxLines: 3,
          isDense: true,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: null);

  Widget _pair(Widget first, Widget second,
          {int firstFlex = 1, int secondFlex = 1}) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 480 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        if (!wide) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 12), second]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: firstFlex, child: first),
          const SizedBox(width: 16),
          Expanded(flex: secondFlex, child: second),
        ]);
      });

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial.serviceId == null;
    final colors = Theme.of(context).colorScheme;
    final types = <String>{...widget.supportedTypes, _proxyType};
    final saveAllowed =
        !_busy && (!_needsReview || (_reviewLoaded && _reviewed && _exists));
    final name = HomeDeskFieldLabel('服务名称',
        child: TextFormField(
            key: const ValueKey('service-name'),
            controller: _name,
            enabled: !_busy,
            validator: _nameError,
            textInputAction: TextInputAction.next,
            decoration: _decoration(hint: '例如家庭相册')));
    final type = HomeDeskFieldLabel('连接类型',
        child: DropdownButtonFormField<String>(
            key: const ValueKey('service-type'),
            value: _proxyType,
            isExpanded: true,
            decoration: _decoration(),
            items: [
              for (final type in types)
                DropdownMenuItem(
                    value: type,
                    child: Text(
                        type == 'http'
                            ? '网页服务（HTTP / HTTPS）'
                            : type.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis))
            ],
            onChanged: _busy || !isNew
                ? null
                : (value) => _change(() {
                      _proxyType = value ?? _proxyType;
                      if (_proxyType != 'tcp') _applicationProtocol = null;
                    })));
    final host = HomeDeskFieldLabel('本地主机 / IP',
        child: TextFormField(
            key: const ValueKey('service-local-host'),
            controller: _host,
            enabled: !_busy,
            autocorrect: false,
            validator: _hostError,
            textInputAction: TextInputAction.next,
            decoration: _decoration(hint: '127.0.0.1')));
    final port = HomeDeskFieldLabel('本地端口',
        child: TextFormField(
            key: const ValueKey('service-local-port'),
            controller: _port,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            validator: _portError,
            decoration: _decoration()));
    return PopScope(
      canPop: !_busy,
      child: NestLinkDialog(
        title: Text(isNew ? '添加家庭服务' : '编辑家庭服务'),
        width: 680,
        showClose: !_busy,
        onClose: () => Navigator.pop(context, false),
        scrollKey: const ValueKey('service-form-scroll'),
        contentPadding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isNew) ...[
                        HomeDeskFieldLabel('提供服务的设备',
                            child: DropdownButtonFormField<String>(
                                key: const ValueKey('service-device'),
                                value: _deviceId,
                                isExpanded: true,
                                decoration: _decoration(),
                                items: [
                                  for (final device in widget.devices)
                                    DropdownMenuItem(
                                        value: device.id,
                                        child: Text(
                                            homeDeskDeviceLabel(device.name),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis))
                                ],
                                onChanged: _busy
                                    ? null
                                    : (value) => _change(
                                        () => _deviceId = value ?? _deviceId))),
                        const SizedBox(height: 8),
                      ],
                      _pair(name, type),
                      if (!isNew)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('连接类型不能修改，需要换类型时请新建服务。',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant))),
                      const SizedBox(height: 12),
                      _pair(host, port, firstFlex: 3),
                      Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: Text(
                              '填写上方设备能访问的地址，例如本机 127.0.0.1 或 NAS 的内网 IP。',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant))),
                      if (_proxyType == 'http')
                        _pair(
                            HomeDeskFieldLabel('设备上的服务协议',
                                child: DropdownButtonFormField<String>(
                                    key: const ValueKey('service-local-scheme'),
                                    value: _scheme,
                                    isExpanded: true,
                                    decoration: _decoration(),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'http', child: Text('HTTP')),
                                      DropdownMenuItem(
                                          value: 'https', child: Text('HTTPS')),
                                    ],
                                    onChanged: _busy
                                        ? null
                                        : (value) => _change(
                                            () => _scheme = value ?? _scheme))),
                            HomeDeskFieldLabel('公网访问名称',
                                child: TextFormField(
                                    key: const ValueKey('service-subdomain'),
                                    controller: _subdomain,
                                    enabled: !_busy,
                                    autocorrect: false,
                                    validator: _subdomainError,
                                    decoration: _decoration(
                                        hint: '例如 album',
                                        helper: '保存前会检查名称是否可用。'))),
                            secondFlex: 2)
                      else ...[
                        if (_proxyType == 'tcp') ...[
                          HomeDeskFieldLabel('应用类型',
                              child: DropdownButtonFormField<String>(
                                  key: const ValueKey('service-application'),
                                  value: _applicationProtocol ?? '',
                                  isExpanded: true,
                                  decoration: _decoration(),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '', child: Text('未指定')),
                                    DropdownMenuItem(
                                        value: 'ssh', child: Text('SSH')),
                                    DropdownMenuItem(
                                        value: 'rdp', child: Text('RDP')),
                                    DropdownMenuItem(
                                        value: 'rtsp', child: Text('RTSP')),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (value) => _change(() =>
                                          _applicationProtocol =
                                              value == '' ? null : value))),
                          const SizedBox(height: 12),
                        ],
                        Text(
                            widget.remoteEndpoint == null
                                ? '公网端口由服务端自动分配，创建后会显示访问地址。'
                                : '公网访问地址：${widget.remoteEndpoint}。公网端口不能在这里修改。',
                            style: TextStyle(
                                fontSize: 12, color: colors.onSurfaceVariant)),
                      ],
                      CheckboxListTile(
                          key: const ValueKey('service-enabled'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          title: const Text('启用服务'),
                          value: _enabled,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                  _change(() => _enabled = value ?? false)),
                      if (_message.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_message,
                                style: TextStyle(color: colors.error))),
                      if (_needsReview) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                            key: const ValueKey('service-review'),
                            onPressed: _busy ? null : _review,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('刷新核对')),
                        if (_serverSummary.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('服务器当前设置：'),
                          SelectableText(_serverSummary),
                        ],
                        if (_reviewLoaded && _exists)
                          CheckboxListTile(
                              key: const ValueKey('service-reviewed'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text('已核对，允许保存当前草稿'),
                              value: _reviewed,
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      setState(
                                          () => _reviewed = value ?? false);
                                      _draftChanged();
                                      if (_reviewed) {
                                        widget.onReviewConfirmed?.call();
                                      }
                                    }),
                      ],
                    ])),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('service-save'),
            onPressed: saveAllowed ? _save : null,
            child: Text(_busy ? '正在保存…' : '保存'),
          ),
        ],
      ),
    );
  }
}

class HomeDeskDeviceDraft {
  final List<String> tags;
  final bool favorite;
  final int expectedMetadataVersion;
  const HomeDeskDeviceDraft(
      {required this.tags,
      required this.favorite,
      required this.expectedMetadataVersion});
}

class HomeDeskDeviceEditor extends StatefulWidget {
  final String deviceName;
  final HomeDeskDeviceDraft initial;
  final bool Function() isAllowed;
  final Future<void> Function(HomeDeskDeviceDraft) onSave;
  final Future<HomeDeskDeviceDraft> Function() onReview;
  final ValueChanged<HomeDeskDeviceDraft>? onDraftChanged;
  final VoidCallback? onReviewConfirmed;
  final bool needsReview;
  const HomeDeskDeviceEditor(
      {super.key,
      required this.deviceName,
      required this.initial,
      required this.isAllowed,
      required this.onSave,
      required this.onReview,
      this.onDraftChanged,
      this.onReviewConfirmed,
      this.needsReview = false});

  @override
  State<HomeDeskDeviceEditor> createState() => _HomeDeskDeviceEditorState();
}

class _HomeDeskDeviceEditorState extends State<HomeDeskDeviceEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _tags;
  late bool _favorite;
  int? _reviewVersion;
  bool _busy = false;
  bool _needsReview = false;
  bool _reviewed = false;
  bool _reviewLoaded = false;
  String _message = '';
  String _serverSummary = '';

  HomeDeskDeviceDraft get _draft => HomeDeskDeviceDraft(
      tags: _tags.text
          .split(RegExp(r'[,，]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(),
      favorite: _favorite,
      expectedMetadataVersion: _reviewed && _reviewVersion != null
          ? _reviewVersion!
          : widget.initial.expectedMetadataVersion);

  @override
  void initState() {
    super.initState();
    _tags = TextEditingController(text: widget.initial.tags.join(', '));
    _favorite = widget.initial.favorite;
    _needsReview = widget.needsReview;
    if (_needsReview) _message = '上次操作结果未确认，请刷新核对。当前草稿已保留。';
    _tags.addListener(() => widget.onDraftChanged?.call(_draft));
  }

  Future<void> _save() async {
    if (_busy || !widget.isAllowed() || !_form.currentState!.validate()) return;
    if (_needsReview && (!_reviewLoaded || !_reviewed)) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await widget.onSave(_draft);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final code = error is HomeTunnelApiException ? error.code : '';
      setState(() {
        _needsReview =
            code == 'MUTATION_UNKNOWN' || code.contains('VERSION_CONFLICT');
        _reviewLoaded = false;
        _reviewed = false;
        _message = code == 'MUTATION_UNKNOWN'
            ? '结果未确认，刷新核对后再决定是否保存。当前草稿已保留，不会自动重试。'
            : code.contains('VERSION_CONFLICT')
                ? '设备设置已经变化，请刷新核对。当前草稿已保留。'
                : error is HomeTunnelApiException
                    ? error.message
                    : '保存未完成，当前草稿已保留。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    if (_busy || !widget.isAllowed()) return;
    setState(() => _busy = true);
    try {
      final current = await widget.onReview();
      if (!mounted || !widget.isAllowed()) return;
      setState(() {
        _reviewVersion = current.expectedMetadataVersion;
        // The removed favorite control must not overwrite newer server metadata.
        _favorite = current.favorite;
        _serverSummary =
            '标签：${current.tags.isEmpty ? '无' : current.tags.join('、')}';
        _reviewLoaded = true;
        _reviewed = false;
        _message = '已刷新设备设置，请核对后再保存当前草稿。';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            error is HomeTunnelApiException ? error.message : '刷新未完成，请稍后再核对。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: NestLinkDialog(
          title: const Text('管理隧道设备'),
          width: 520,
          showClose: !_busy,
          onClose: () => Navigator.pop(context, false),
          content: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(homeDeskDeviceLabel(widget.deviceName),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('设备名称由该设备上的 NestLink 客户端修改。',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 12),
                    HomeDeskFieldLabel('标签',
                        child: TextFormField(
                            key: const ValueKey('device-tags'),
                            controller: _tags,
                            enabled: !_busy,
                            decoration:
                                const InputDecoration(helperText: '多个标签用逗号分隔。'),
                            validator: (_) {
                              final tags = _draft.tags;
                              if (tags.length > 12 ||
                                  tags.any((tag) =>
                                      tag.length > 32 ||
                                      RegExp(r'[\x00-\x1f\x7f]')
                                          .hasMatch(tag))) {
                                return '最多 12 个标签，每个最多 32 个字符。';
                              }
                              return null;
                            })),
                    if (_message.isNotEmpty)
                      Text(_message,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (_needsReview) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          key: const ValueKey('device-review'),
                          onPressed: _busy ? null : _review,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('刷新核对')),
                      if (_serverSummary.isNotEmpty) Text(_serverSummary),
                      if (_reviewLoaded)
                        CheckboxListTile(
                            key: const ValueKey('device-reviewed'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('已核对，允许保存当前草稿'),
                            value: _reviewed,
                            onChanged: _busy
                                ? null
                                : (value) {
                                    setState(() => _reviewed = value ?? false);
                                    widget.onDraftChanged?.call(_draft);
                                    if (_reviewed) {
                                      widget.onReviewConfirmed?.call();
                                    }
                                  }),
                    ],
                    if (_busy) const LinearProgressIndicator(),
                  ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                key: const ValueKey('device-save'),
                onPressed:
                    !_busy && (!_needsReview || (_reviewLoaded && _reviewed))
                        ? _save
                        : null,
                child: Text(_busy ? '正在保存…' : '保存')),
          ]));
}
