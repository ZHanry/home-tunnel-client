// HOMEDESK: 纯 Dart 安全会话存储协议；令牌只能交给显式注入的受保护存储。
class HomeDeskPortalCredential {
  final String origin;
  final String userId;
  final String username;
  final String displayName;
  final String refreshToken;
  final DateTime refreshExpiresAt;
  final int version;

  const HomeDeskPortalCredential(
      {required this.origin,
      required this.userId,
      required this.username,
      required this.displayName,
      required this.refreshToken,
      required this.refreshExpiresAt,
      this.version = 1});

  factory HomeDeskPortalCredential.fromJson(Map<String, dynamic> value) {
    String text(String name, int max) {
      final result = value[name];
      if (result is! String ||
          result.isEmpty ||
          result.length > max ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(result)) {
        throw const FormatException('保存的 NestLink 会话格式无效');
      }
      return result;
    }

    final origin = text('origin', 4096);
    final uri = Uri.tryParse(origin);
    final userId = text('user_id', 36);
    final refresh = text('refresh_token', 1024);
    final expires = DateTime.tryParse(text('refresh_expires_at', 64));
    if (value['version'] != 1 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535 ||
        expires == null ||
        !RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
            .hasMatch(userId) ||
        !RegExp(r'^[a-zA-Z0-9_-]{16,1024}$').hasMatch(refresh)) {
      throw const FormatException('保存的 NestLink 会话格式无效');
    }
    return HomeDeskPortalCredential(
        origin: origin,
        userId: userId,
        username: text('username', 128),
        displayName: text('display_name', 120),
        refreshToken: refresh,
        refreshExpiresAt: expires.toUtc());
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'origin': origin,
        'user_id': userId,
        'username': username,
        'display_name': displayName,
        'refresh_token': refreshToken,
        'refresh_expires_at': refreshExpiresAt.toUtc().toIso8601String(),
      };
}

class CredentialTransaction {
  final String generation;
  const CredentialTransaction(this.generation);
}

class CredentialLease {
  final HomeDeskPortalCredential record;
  final CredentialTransaction transaction;
  const CredentialLease({required this.record, required this.transaction});
}

class HomeDeskRememberedAccount {
  final String origin;
  final String userId;
  final String username;
  final String displayName;
  const HomeDeskRememberedAccount(
      {required this.origin,
      required this.userId,
      required this.username,
      required this.displayName});
}

abstract class HomeDeskCredentialStorage {
  bool get supported;

  /// 只读取用于展示和匹配的元数据；不能让保存的地址授予新的网络权限。
  Future<HomeDeskRememberedAccount?> peekAccount();

  /// 开始新登录：持久旋转代次并销毁旧记录，完成后旧事务不能再保存。
  Future<CredentialTransaction> begin();

  /// 原子消费：先持久旋转代次并销毁旧记录，再返回仅能消费一次的令牌。
  Future<CredentialLease?> consume();

  /// 仅在事务代次仍有效时原子保存新令牌，完成后才允许交付登录状态。
  Future<void> save(
      HomeDeskPortalCredential record, CredentialTransaction transaction);

  /// 只失效仍由该事务拥有的记录；旧实例失败不能删除别的实例的新登录。
  Future<void> discard(CredentialTransaction transaction);

  /// 显式退出或授权撤销：持久失效所有旧事务并销毁保存的记录。
  Future<void> clear();
}
