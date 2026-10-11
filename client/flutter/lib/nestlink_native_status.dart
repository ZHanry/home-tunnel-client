import 'dart:async';
import 'dart:io';
import 'homedesk_tunnel_api.dart';

/// Only fixed categories cross from native authorization into presentation.
/// Native messages, URLs and credentials are never retained in this state.
enum NestLinkNativeStatus {
  idle,
  connecting,
  ready,
  http401,
  http403,
  httpOther,
  authorizationRequired,
  platformVerifier,
  tlsConfiguration,
  certificateRejected,
  timeout,
  network,
  invalidResponse,
  runnerNotReady,
  runnerBusy,
  unknown;

  bool get isFailure => index > ready.index;

  String title(bool english) => switch (this) {
        idle => '',
        connecting => english ? 'Verifying remote access' : '正在验证远控授权',
        ready => english ? 'Remote access is ready' : '远控授权已就绪',
        http401 => english ? 'Remote authorization expired' : '远控授权已失效',
        http403 => english ? 'Remote access was denied' : '远控访问被拒绝',
        httpOther =>
          english ? 'The server rejected remote authorization' : '服务未接受远控授权请求',
        authorizationRequired =>
          english ? 'Remote authorization is unavailable' : '尚未取得远控授权',
        platformVerifier => english
            ? 'System certificate verification is unavailable'
            : '系统证书验证尚未就绪',
        tlsConfiguration => english
            ? 'Remote HTTPS configuration is incompatible'
            : '远控 HTTPS 配置不兼容',
        certificateRejected => english
            ? 'The remote HTTPS certificate could not be verified'
            : '无法验证远控 HTTPS 证书',
        timeout => english ? 'Remote authorization timed out' : '远控授权确认超时',
        network => english
            ? 'Could not send the remote authorization request'
            : '远控授权请求未能发送',
        invalidResponse => english
            ? 'The server returned invalid remote authorization'
            : '服务返回的远控授权无效',
        runnerNotReady =>
          english ? 'The remote service is not ready' : '远控服务尚未就绪',
        runnerBusy => english ? 'The remote service is busy' : '远控服务正忙',
        unknown => english
            ? 'Remote authorization could not be confirmed'
            : '暂时无法确认远控授权',
      };

  String advice(bool english) => switch (this) {
        idle || ready => '',
        connecting => english
            ? 'Keep NestLink open while it registers this device.'
            : '请保持 NestLink 打开，等待设备完成登记。',
        http401 => english
            ? 'Sign out and sign in again to renew remote authorization.'
            : '请退出账号后重新登录，以更新远控授权。',
        http403 => english
            ? 'Ask your administrator to check this account and device permission.'
            : '请联系管理员核对账号与设备的远控权限。',
        httpOther => english
            ? 'Check the server status or ask your administrator. NestLink will retry automatically.'
            : '请检查服务状态或联系管理员，NestLink 会自动重试。',
        authorizationRequired => english
            ? 'Sign in to your server and wait for this device to register.'
            : '请登录自建服务，等待本设备完成登记。',
        platformVerifier => english
            ? 'Restart NestLink. If it continues, update the app or contact your administrator.'
            : '请重启 NestLink；若仍未恢复，请更新客户端或联系管理员。',
        tlsConfiguration => english
            ? 'Update NestLink or contact your administrator to check the remote HTTPS setup.'
            : '请更新 NestLink，或联系管理员核对远控 HTTPS 配置。',
        certificateRejected => english
            ? 'Check the device date, server hostname and certificate trust. Ask your administrator to fix the certificate.'
            : '请检查设备时间、服务域名与证书信任，并联系管理员修复证书。',
        timeout || network => english
            ? 'Check the server address and your connection. NestLink will retry automatically.'
            : '请核对服务地址和网络连接，NestLink 会自动重试。',
        invalidResponse => english
            ? 'Ask your administrator to check the server version and device authorization.'
            : '请联系管理员核对服务端版本与设备授权。',
        runnerNotReady || runnerBusy => english
            ? 'Wait for NestLink to retry. If it continues, restart the app.'
            : '请等待 NestLink 重试；若持续未恢复，请重启客户端。',
        unknown => english
            ? 'Check the server and network. If it continues, restart NestLink or contact your administrator.'
            : '请检查服务与网络；若仍未恢复，请重启 NestLink 或联系管理员。',
      };
}

/// Preserve fail-closed API behavior while preventing other UI from exposing
/// the original native string through HomeTunnelApiException.message.
class NestLinkNativeException extends HomeTunnelApiException {
  final NestLinkNativeStatus status;
  NestLinkNativeException(this.status)
      : super('${status.title(false)}。${status.advice(false)}',
            'REMOTE_NOT_READY');
}

NestLinkNativeStatus classifyNestLinkNativeError(String message) {
  switch (message) {
    case 'NESTLINK_NATIVE_AUTH_V1:HTTP_401':
      return NestLinkNativeStatus.http401;
    case 'NESTLINK_NATIVE_AUTH_V1:HTTP_403':
      return NestLinkNativeStatus.http403;
    case 'NESTLINK_NATIVE_AUTH_V1:HTTP_OTHER':
      return NestLinkNativeStatus.httpOther;
    case 'NESTLINK_NATIVE_AUTH_V1:AUTH_REQUIRED':
      return NestLinkNativeStatus.authorizationRequired;
    case 'NESTLINK_NATIVE_AUTH_V1:PLATFORM_VERIFIER':
      return NestLinkNativeStatus.platformVerifier;
    case 'NESTLINK_NATIVE_AUTH_V1:TLS_CONFIGURATION':
      return NestLinkNativeStatus.tlsConfiguration;
    case 'NESTLINK_NATIVE_AUTH_V1:CERTIFICATE_REJECTED':
      return NestLinkNativeStatus.certificateRejected;
    case 'NESTLINK_NATIVE_AUTH_V1:TIMEOUT':
      return NestLinkNativeStatus.timeout;
    case 'NESTLINK_NATIVE_AUTH_V1:NETWORK':
      return NestLinkNativeStatus.network;
    case 'NESTLINK_NATIVE_AUTH_V1:INVALID_RESPONSE':
      return NestLinkNativeStatus.invalidResponse;
    case '原生服务尚未就绪':
      return NestLinkNativeStatus.runnerNotReady;
    case '原生服务正忙，请稍后重试':
      return NestLinkNativeStatus.runnerBusy;
    case '原生账号授权确认超时':
      return NestLinkNativeStatus.timeout;
  }
  return NestLinkNativeStatus.unknown;
}

NestLinkNativeStatus classifyNestLinkNativeFailure(Object error) {
  if (error is NestLinkNativeException) return error.status;
  if (error is HomeTunnelApiException) {
    return switch (error.code) {
      'AUTH_REQUIRED' ||
      'LOGIN_REQUIRED' ||
      'SESSION_REVOKED' ||
      'SESSION_EXPIRED' =>
        NestLinkNativeStatus.http401,
      'FORBIDDEN' ||
      'ACCESS_REVOKED' ||
      'DEVICE_REVOKED' =>
        NestLinkNativeStatus.http403,
      'TLS_ERROR' => NestLinkNativeStatus.certificateRejected,
      'REQUEST_TIMEOUT' => NestLinkNativeStatus.timeout,
      'NETWORK_ERROR' => NestLinkNativeStatus.network,
      'RESPONSE_INVALID' ||
      'RESPONSE_TOO_LARGE' =>
        NestLinkNativeStatus.invalidResponse,
      'REMOTE_NOT_READY' => classifyNestLinkNativeError(error.message),
      _ => NestLinkNativeStatus.unknown,
    };
  }
  if (error is TimeoutException) return NestLinkNativeStatus.timeout;
  if (error is HandshakeException) {
    return NestLinkNativeStatus.certificateRejected;
  }
  if (error is SocketException) return NestLinkNativeStatus.network;
  if (error is FormatException) return NestLinkNativeStatus.invalidResponse;
  return NestLinkNativeStatus.unknown;
}
