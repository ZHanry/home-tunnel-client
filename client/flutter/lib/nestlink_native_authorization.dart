import 'dart:async';
import 'homedesk_tunnel_api.dart';
import 'nestlink_native_status.dart';

/// Orders native authorization across account instances, including late IPC.
class NestLinkNativeAuthorization {
  static Future<void> _tail = Future<void>.value();
  final bool Function() _ready;
  final Future<String> Function(Map<String, String>) _install;
  final Future<String> Function() _clear;
  final void Function(NestLinkNativeStatus)? _onStatus;
  NestLinkNativeStatus _status = NestLinkNativeStatus.idle;
  bool _closed = false;
  String _installedToken = '';
  Future<void>? _closing;

  NestLinkNativeAuthorization({
    required bool Function() ready,
    required Future<String> Function(Map<String, String>) install,
    required Future<String> Function() clear,
    void Function(NestLinkNativeStatus)? onStatus,
  })  : _ready = ready,
        _install = install,
        _clear = clear,
        _onStatus = onStatus;

  void _publish(NestLinkNativeStatus status) {
    if (_closed || status == _status) return;
    _status = status;
    try {
      _onStatus?.call(status);
    } catch (_) {/* Presentation observers cannot change authorization. */}
  }

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
      if (_closed) {
        throw const HomeTunnelApiException('账号授权已结束。', 'REQUEST_CANCELLED');
      }
      if (_installedToken == request['access_token'] && _ready()) {
        _publish(NestLinkNativeStatus.ready);
        return;
      }
      if (_status == NestLinkNativeStatus.idle ||
          _status == NestLinkNativeStatus.ready) {
        _publish(NestLinkNativeStatus.connecting);
      }
      final String error;
      try {
        error = await _install(request);
      } catch (failure) {
        final status = classifyNestLinkNativeFailure(failure);
        _publish(status);
        throw NestLinkNativeException(status);
      }
      if (error.isNotEmpty) {
        final status = classifyNestLinkNativeError(error);
        _publish(status);
        throw NestLinkNativeException(status);
      }
      // close() has already queued a clear before any replacement account.
      if (_closed) {
        throw const HomeTunnelApiException('账号授权已结束。', 'REQUEST_CANCELLED');
      }
      _installedToken = request['access_token']!;
      _publish(_ready()
          ? NestLinkNativeStatus.ready
          : NestLinkNativeStatus.connecting);
    });
  }

  Future<void> close() {
    if (_closed) return _closing!;
    _publish(NestLinkNativeStatus.idle);
    _closed = true;
    return _closing = _serialize(() async {
      _installedToken = '';
      final String error;
      try {
        error = await _clear();
      } catch (failure) {
        throw NestLinkNativeException(classifyNestLinkNativeFailure(failure));
      }
      if (error.isNotEmpty) {
        throw NestLinkNativeException(classifyNestLinkNativeError(error));
      }
    });
  }
}
