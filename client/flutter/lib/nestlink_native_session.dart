import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'homedesk_tunnel_api.dart';
import 'models/platform_model.dart';

/// One foreground account owns native remote authorization. Tunnel Agents have their own credentials.
class NestLinkNativeSession {
  final HomeTunnelApi api;
  Timer? _timer;
  WebSocket? _socket;
  bool _closed = false, _busy = false;
  String _installedToken = '';
  DateTime _lastBinding = DateTime.fromMillisecondsSinceEpoch(0);
  String message = '';
  NestLinkNativeSession(this.api);

  Future<void> start() async {
    _timer =
        Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_sync()));
    await _sync();
  }

  Future<void> _sync() async {
    if (_closed || _busy || !api.isSignedIn) return;
    _busy = true;
    try {
      if (api.guiDeviceId.isEmpty) {
        final identity = jsonDecode(await bind.mainNestlinkInstallation())
            as Map<String, dynamic>;
        if (_closed) return;
        await api.registerGuiDevice(
            installId: identity['install_id'] as String,
            fingerprint: identity['fingerprint_hash'] as String,
            name: Platform.isAndroid ? 'Android' : Platform.localHostname);
      }
      final auth = await api.nativeAuthorization();
      if (_closed) return;
      if (_installedToken != auth['access_token'] ||
          !bind.mainNestlinkAccountReady()) {
        final error = await bind.mainNestlinkAccountInstall(
            origin: auth['origin']!,
            deviceId: auth['device_id']!,
            accessToken: auth['access_token']!);
        if (error.isNotEmpty)
          throw HomeTunnelApiException(error, 'REMOTE_NOT_READY');
        if (_closed) {
          await bind.mainNestlinkAccountClear();
          return;
        }
        _installedToken = auth['access_token']!;
      }
      if (DateTime.now().difference(_lastBinding) >=
          const Duration(seconds: 30)) {
        final binding = jsonDecode(await bind.mainNestlinkBindingProof())
            as Map<String, dynamic>;
        if (binding['error'] != null)
          throw HomeTunnelApiException(
              binding['error'] as String, 'REMOTE_NOT_READY');
        if (_closed) return;
        await api.publishNativeBinding(binding);
        _lastBinding = DateTime.now();
      }
      if (_socket == null) {
        final socket = await api.realtime();
        if (_closed) {
          await socket.close();
          return;
        }
        _socket = socket;
        socket.listen((data) {
          if (_closed || data is! String || data.length > 65536) return;
          try {
            final event = jsonDecode(data) as Map;
            final payload = event['payload'];
            final ownDeviceRevoked = event['event'] == 'subject.revoked' &&
                payload is Map &&
                payload['subject_type'] == 'device' &&
                payload['subject_id'] == api.guiDeviceId;
            // Unrelated device events may also be delivered to an administrator.
            if (event['event'] == 'account.session.revoked' ||
                ownDeviceRevoked) {
              close();
              unawaited(api.revoke());
            }
          } catch (_) {/* Malformed events do not grant authorization. */}
        }, onError: (Object _) {
          if (identical(_socket, socket)) _socket = null;
        }, onDone: () {
          if (identical(_socket, socket)) _socket = null;
          if (socket.closeCode == 4001 && !_closed) {
            close();
            unawaited(api.revoke());
          }
        });
      }
      message = '';
    } on HomeTunnelApiException catch (error) {
      message = error.message;
    } catch (_) {
      message = '远控服务暂时未就绪，请检查服务配置和网络。';
    } finally {
      _busy = false;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    unawaited(_socket?.close());
    _socket = null;
    unawaited(bind
        .mainNestlinkAccountClear()
        .then<void>((_) {})
        .catchError((Object _) {}));
  }
}
