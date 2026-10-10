import 'homedesk_credentials.dart';
import 'homedesk_tunnel_api.dart';
import 'nestlink_locale.dart';

// Presentation only: protocol exceptions and their wire codes stay unchanged.
String nestlinkErrorMessage(Object error, {String? fallback}) {
  String? code;
  String? message;
  if (error is HomeTunnelApiException) {
    code = error.code;
    message = error.message;
  } else if (error is HomeDeskCredentialException) {
    code = error.code;
    message = error.message;
  }
  final defaultMessage = fallback ??
      nl('服务暂时无法连接，请检查地址、证书和网络后重试。',
          'The server is unavailable. Check its address, certificate and your connection, then retry.');
  if (!nestlinkEnglish) return message ?? defaultMessage;
  final translated = _englishErrors[code];
  if (translated != null) return translated;
  // Never display an unrecognized response message in English. Restrict the
  // diagnostic identifier too, so arbitrary content cannot arrive via a code.
  final safeCode =
      code != null && RegExp(r'^[A-Z][A-Z0-9_]{0,63}$').hasMatch(code)
          ? code
          : null;
  return safeCode == null ? defaultMessage : '$defaultMessage ($safeCode)';
}

const _englishErrors = <String, String>{
  'AUTH_INVALID':
      'The username or password is incorrect. Check them and try again.',
  'INVALID_CREDENTIALS':
      'The username or password is incorrect. Check them and try again.',
  'AUTH_REQUIRED': 'Sign in to NestLink before continuing.',
  'LOGIN_REQUIRED': 'Sign in to NestLink before continuing.',
  'SESSION_REVOKED':
      'Your NestLink login expired or was revoked. Sign in again.',
  'SESSION_EXPIRED': 'Your NestLink login expired. Sign in again.',
  'SESSION_CHANGED':
      'The signed-in account changed. Refresh the directory before continuing.',
  'PASSWORD_CHANGE_REQUIRED':
      'Change your initial password in the NestLink management portal, then sign in again.',
  'TEMPORARY_PASSWORD_EXPIRED':
      'Your temporary password expired. Ask your administrator for a new one.',
  'USER_DISABLED':
      'Your NestLink account is disabled. Contact your administrator.',
  'RATE_LIMITED': 'Too many requests. Wait a moment before trying again.',
  'VALIDATION_ERROR':
      'The request is invalid. Check your input before trying again.',
  'INPUT_INVALID':
      'Check the service or device name, local address, port and tags before saving.',
  'FORBIDDEN':
      'Access was denied. Check your account permissions or contact your administrator.',
  'ACCESS_REVOKED':
      'This connection is closed or its local authorization was revoked. Confirm the authorized server address and sign in again.',
  'DEVICE_REVOKED': 'This device was revoked. Refresh the device directory.',
  'OWNERSHIP_MISMATCH':
      'The device or service no longer exists or belongs to another account. Refresh the directory.',
  'NOT_FOUND': 'The device or service no longer exists. Refresh the directory.',
  'ACCOUNT_SESSION_REQUIRED':
      'Sign in with an account management session to manage this device.',
  'DEVICE_CAPABILITY_SUBJECT_INVALID':
      'The device capability expired or belongs to another account. Refresh the directory.',
  'DEVICE_CAPABILITY_LINK_CONFLICT':
      'This capability is linked to another device. Refresh and review the directory.',
  'IDENTITY_MISMATCH':
      'The local device identity could not be confirmed. Refresh the directory and sign in again.',
  'VERSION_CONFLICT':
      'This resource changed. Keep your draft and refresh to review it before saving.',
  'METADATA_VERSION_CONFLICT':
      'The device information changed. Keep your draft and refresh to review it before saving.',
  'ACCESS_POLICY_VERSION_CONFLICT':
      'The access policy changed. Keep your draft and refresh to review it before saving.',
  'MUTATION_UNKNOWN':
      'The result of this operation is unknown. Keep your draft and refresh to review it before submitting again.',
  'CLIENT_RAW_TUNNELS_DISABLED':
      'Your administrator has not allowed this account to create TCP or UDP services. Contact your administrator.',
  'TCP_TUNNELS_DISABLED':
      'TCP services are disabled on this server. Contact your administrator.',
  'UDP_TUNNELS_DISABLED':
      'UDP services are disabled on this server. Contact your administrator.',
  'PORT_POOL_EXHAUSTED':
      'The server has no available ports. Contact your administrator.',
  'RESOURCE_LIMIT':
      'This account reached the device or service limit. Remove an unused item or contact your administrator.',
  'SUBDOMAIN_CONFLICT':
      'This subdomain is already in use. Choose another name and check availability.',
  'SUBDOMAIN_RESERVED':
      'This subdomain is reserved by the server. Choose another name.',
  'SUBDOMAIN_PREFIX_REQUIRED':
      'This subdomain does not meet the account naming policy. Check availability and use the required prefix.',
  'ORIGIN_INVALID':
      'Enter a valid HTTPS server address without a path or credentials.',
  'ORIGIN_NOT_APPROVED':
      'This device has not approved the server address. Review your network settings before signing in.',
  'PERMISSION_CHANGED':
      'Network authorization changed. Review your network settings and sign in again.',
  'DEVICE_NOT_FOUND':
      'The device directory changed. Refresh it before trying again.',
  'OPERATION_BUSY':
      'This operation is already in progress. Wait for it to finish before trying again.',
  'CAPABILITY_DISABLED':
      'The server does not allow this connection type. Refresh to see available capabilities or contact your administrator.',
  'SUBDOMAIN_UNAVAILABLE':
      'This public name is unavailable. Choose another name and check availability before saving.',
  'CONFIG_INVALID':
      'The connection configuration is invalid. Check the server address and restart NestLink.',
  'TLS_ERROR':
      'The HTTPS certificate could not be verified. Check the server hostname, certificate trust and device date; ask your administrator to fix the certificate.',
  'NETWORK_ERROR':
      'Could not connect to NestLink. Check the server address and your network, then retry.',
  'REQUEST_TIMEOUT':
      'The NestLink request timed out. Check your connection, then refresh or sign in again.',
  'REQUEST_CANCELLED':
      'The request was cancelled. Refresh the directory before continuing.',
  'REDIRECT_BLOCKED':
      'The server returned a redirect. Check the original HTTPS server address.',
  'REQUEST_TOO_LARGE':
      'The request is too large. Shorten your input before trying again.',
  'RESPONSE_TOO_LARGE':
      'The server response is too large. Contact your administrator before trying again.',
  'RESPONSE_INVALID':
      'The server returned invalid data. Refresh or sign in again; contact your administrator if it continues.',
  'HTTP_ERROR':
      'The NestLink request failed. Check the server status and your account permissions, then retry.',
  'STORAGE_UNAVAILABLE':
      'System secure storage is unavailable. Unlock or repair it, then sign in again; your login will not be saved as plain text.',
  'SECURE_STORE_ERROR':
      'Secure storage could not be updated. Check system secure storage before signing in again.',
  'STORAGE_INVALID': 'The saved login is invalid or damaged. Sign in again.',
  'DPAPI_FAILED':
      'Windows could not verify the saved login. Sign in again; your login will not be saved as plain text.',
  'CREDENTIAL_EXPIRED': 'The remembered login expired. Sign in again.',
  'CREDENTIAL_INVALID': 'The saved login is invalid. Sign in again.',
  'UNSUPPORTED_PLATFORM':
      'Secure remembered login is unavailable on this platform. Sign in for the current session.',
  'STALE_TRANSACTION':
      'This login save request is outdated. Sign in again to save the current account.',
};
