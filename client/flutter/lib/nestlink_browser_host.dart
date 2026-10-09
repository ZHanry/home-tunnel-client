import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'homedesk_dashboard.dart';
import 'homedesk_tunnel_api.dart';
import 'models/platform_model.dart';
import 'nestlink_locale.dart';

final nestlinkBrowserStatus = ValueNotifier<String>('');

/// The GUI owns account authorization and consent. The helper carries only P2P transport.
class NestLinkBrowserHost {
  final HomeTunnelApi api;
  static NestLinkBrowserHost? active;
  Timer? _pollTimer, _frameTimer, _leaseTimer;
  Process? _process;
  DialogRoute<bool>? _approval;
  NavigatorState? _navigator;
  bool _closed = false,
      _polling = false,
      _drawing = false,
      _renewing = false,
      _ready = false,
      _authorized = false;
  String _id = '', _executable = '';
  String _offerDigest = '', _answerDigest = '';
  int _generation = 0;
  final Set<String> _seen = {};
  NestLinkBrowserHost(this.api);

  Future<void> start() async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    final directory =
        path.join(path.dirname(Platform.resolvedExecutable), 'tunnel-runtime');
    final manifestFile = File(path.join(directory, 'runtime.json'));
    if (await manifestFile.length() > 65536)
      throw const FormatException('Invalid runtime metadata');
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final expected = manifest['browser_helper_sha256'];
    final executable = File(path.join(directory,
        'nestlink-browser-helper${Platform.isWindows ? '.exe' : ''}'));
    if (expected is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected) ||
        (await sha256.bind(executable.openRead()).first).toString() != expected)
      throw const FormatException('Browser helper integrity check failed');
    _executable = executable.path;
    if (_closed) return;
    active = this;
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_poll()));
    await _poll();
  }

  Future<void> _poll() async {
    if (_closed || _polling || !api.isSignedIn) return;
    _polling = true;
    try {
      if (!bind.mainNestlinkAccountReady() ||
          bind.mainGetOptionSync(key: 'stop-service') == 'Y' ||
          bind.isOutgoingOnly()) {
        await disconnect();
        await api.browserHostStop();
        return;
      }
      final inbox = await api.browserHostInbox();
      final items = inbox['items'] as List<Map<String, dynamic>>;
      if (_closed) return;
      for (final request in items) {
        final id = request['session_id'];
        if (id is! String ||
            !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id) ||
            request['offer'] is! String ||
            (request['offer'] as String).length > 32768 ||
            request['controller_name'] is! String) {
          throw const FormatException('Invalid browser request');
        }
        if (_id.isNotEmpty || _seen.contains(id)) continue;
        _seen.add(id);
        if (_seen.length > 64) _seen.remove(_seen.first);
        final password = request['password'] as String? ?? '';
        final mode = bind.mainGetOptionSync(key: 'approve-mode');
        var approve = false;
        if (password.isNotEmpty && mode != 'click') {
          approve = bind.mainNestlinkBrowserCheckPassword(password: password);
        } else if (mode != 'password') {
          final context = HomeDeskDashboard.active?.context;
          if (context != null && context.mounted) {
            _navigator = Navigator.of(context);
            _approval = DialogRoute<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                      title: Text(nl('浏览器请求远控', 'Browser remote request')),
                      content: Text(
                          '${request['controller_name']}\n${nl('请求查看并操作这台设备。', 'wants to view and control this device.')}'),
                      actions: [
                        TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: Text(nl('拒绝', 'Decline'))),
                        FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: Text(nl('允许连接', 'Allow connection'))),
                      ],
                    ));
            final route = _approval!;
            approve = await _navigator!
                    .push(route)
                    .timeout(const Duration(seconds: 25), onTimeout: () {
                  if (route.isActive && _navigator?.mounted == true)
                    _navigator!.removeRoute(route);
                  return false;
                }) ??
                false;
            _approval = null;
          }
        }
        if (_closed || !api.isSignedIn) return;
        if (!approve) {
          await api.browserDecision(id, approve: false);
          continue;
        }
        _id = id;
        _offerDigest =
            sha256.convert(utf8.encode(request['offer'] as String)).toString();
        nestlinkBrowserStatus.value = nl('浏览器正在连接', 'Browser connecting');
        await _launch();
        if (_closed || _id != id) return;
        _send({
          'kind': 'start',
          'id': id,
          'offer': request['offer'],
          'stun_urls': inbox['stun_urls']
        });
      }
    } catch (_) {
      if (_id.isNotEmpty) await disconnect();
      if (!_closed)
        nestlinkBrowserStatus.value =
            nl('浏览器共享暂不可用，正在重试', 'Browser sharing unavailable. Retrying');
    } finally {
      _polling = false;
    }
  }

  Future<void> _launch() async {
    if (_process != null) return;
    final process = await Process.start(_executable, const [],
        runInShell: false,
        workingDirectory: path.dirname(Platform.resolvedExecutable));
    if (_closed) {
      process.kill();
      return;
    }
    _process = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (_closed || line.length > 65536) return;
      try {
        unawaited(_event(jsonDecode(line) as Map<String, dynamic>)
            .catchError((Object _) => disconnect()));
      } catch (_) {
        unawaited(disconnect());
      }
    }, onError: (Object _) => unawaited(disconnect()));
    process.stderr.drain<void>();
    unawaited(process.exitCode.then((_) {
      if (identical(_process, process)) {
        _process = null;
        unawaited(disconnect());
      }
    }));
  }

  void _send(Map<String, Object?> message) {
    final process = _process;
    if (process != null && !_closed) process.stdin.writeln(jsonEncode(message));
  }

  Future<void> _event(Map<String, dynamic> event) async {
    if (_closed || _id.isEmpty || event['id'] != _id) return;
    final id = _id, generation = _generation;
    switch (event['kind']) {
      case 'answer':
        _answerDigest =
            sha256.convert(utf8.encode(event['answer'] as String)).toString();
        final session = await api.browserDecision(id,
            approve: true, answer: event['answer'] as String);
        if (_closed || _id != id || generation != _generation) return;
        final error = await bind.mainNestlinkBrowserAllow(
            id: id,
            grant: session['grant'] as String,
            offerSha256: _offerDigest,
            answerSha256: _answerDigest);
        if (error.isNotEmpty) {
          await disconnect();
          return;
        }
        _authorized = true;
        _leaseTimer?.cancel();
        _leaseTimer = Timer.periodic(
            const Duration(seconds: 3), (_) => unawaited(_renew()));
        _frameTimer?.cancel();
        _frameTimer = Timer.periodic(
            const Duration(milliseconds: 150), (_) => unawaited(_frame()));
      case 'ready':
        _ready = true;
        nestlinkBrowserStatus.value = nl('浏览器已连接', 'Browser connected');
      case 'input':
        if (_ready && _authorized) {
          final error = await bind.mainNestlinkBrowserInput(
              payload: jsonEncode(event['input']));
          if (error.isNotEmpty) await disconnect();
        }
      case 'closed':
      case 'failed':
        await disconnect();
    }
  }

  Future<void> _renew() async {
    if (_closed || _renewing || _id.isEmpty) return;
    _renewing = true;
    final id = _id;
    try {
      final session = await api.browserHeartbeat(id);
      if (_closed || _id != id) return;
      if (session['state'] != 'active') {
        await disconnect();
        return;
      }
      final error = await bind.mainNestlinkBrowserAllow(
          id: id,
          grant: session['grant'] as String,
          offerSha256: _offerDigest,
          answerSha256: _answerDigest);
      if (error.isNotEmpty) await disconnect();
    } catch (_) {
      await disconnect();
    } finally {
      _renewing = false;
    }
  }

  Future<void> _frame() async {
    if (_closed || _drawing || !_ready || !_authorized || _id.isEmpty) return;
    _drawing = true;
    final id = _id;
    try {
      final image = await bind.mainNestlinkBrowserFrame();
      if (_closed || _id != id) return;
      if (image.startsWith('{')) {
        await disconnect();
        return;
      }
      if (image.isNotEmpty) _send({'kind': 'frame', 'id': id, 'image': image});
    } catch (_) {
      await disconnect();
    } finally {
      _drawing = false;
    }
  }

  Future<void> disconnect() async {
    final id = _id;
    _id = '';
    _generation++;
    _ready = false;
    _authorized = false;
    _frameTimer?.cancel();
    _leaseTimer?.cancel();
    nestlinkBrowserStatus.value = '';
    if (id.isNotEmpty) {
      _send({'kind': 'close', 'id': id});
      await bind.mainNestlinkBrowserStop();
      if (api.isSignedIn) await api.browserClose(id).catchError((Object _) {});
    }
  }

  void close() {
    if (_closed) return;
    unawaited(disconnect());
    _closed = true;
    _pollTimer?.cancel();
    if (identical(active, this)) active = null;
    final route = _approval;
    if (route?.isActive == true && _navigator?.mounted == true)
      _navigator!.removeRoute(route!);
    final process = _process;
    _process = null;
    if (process != null) {
      unawaited(process.stdin.close().then((_) async {
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          process.kill();
        }
      }));
    }
  }
}
