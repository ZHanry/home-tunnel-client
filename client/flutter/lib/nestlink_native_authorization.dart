import 'dart:async';
import 'homedesk_tunnel_api.dart';

/// Orders native authorization across account instances, including late IPC.
class NestLinkNativeAuthorization {
  static Future<void> _tail = Future<void>.value();
  final bool Function() _ready;
  final Future<String> Function(Map<String, String>) _install;
  final Future<String> Function() _clear;
  bool _closed = false;
  String _installedToken = '';
  Future<void>? _closing;

  NestLinkNativeAuthorization({
    required bool Function() ready,
    required Future<String> Function(Map<String, String>) install,
    required Future<String> Function() clear,
  })  : _ready = ready,
        _install = install,
        _clear = clear;

  static Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    // The caller receives the error. It cannot prevent a queued logout or the
    // next account from running after this operation has actually finished.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> synchronize(Map<String, String> auth) {
    final request = Map<String, String>.unmodifiable(auth);
    return _serialize(() async {
      if (_closed)
        throw const HomeTunnelApiException('账号授权已结束。', 'REQUEST_CANCELLED');
      if (_installedToken == request['access_token'] && _ready()) return;
      final error = await _install(request);
      if (error.isNotEmpty)
        throw HomeTunnelApiException(error, 'REMOTE_NOT_READY');
      // close() has already queued a clear before any replacement account.
      if (_closed)
        throw const HomeTunnelApiException('账号授权已结束。', 'REQUEST_CANCELLED');
      _installedToken = request['access_token']!;
    });
  }

  Future<void> close() {
    if (_closed) return _closing!;
    _closed = true;
    return _closing = _serialize(() async {
      _installedToken = '';
      final error = await _clear();
      if (error.isNotEmpty)
        throw HomeTunnelApiException(error, 'REMOTE_NOT_READY');
    });
  }
}
