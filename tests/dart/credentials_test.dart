// HOMEDESK: 只在注入的合成临时目录验证真实 Windows DPAPI，不读取用户凭据。
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../client/flutter/lib/homedesk_credentials.dart';
import '../../client/flutter/lib/homedesk_tunnel_session.dart';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

HomeDeskPortalCredential fixture({String suffix = 'first', int version = 1}) =>
    HomeDeskPortalCredential(
        origin: 'https://portal.example.invalid',
        userId: '11111111-1111-4111-8111-111111111111',
        username: 'fixture-account',
        displayName: '合成测试账号',
        refreshToken: 'fixture-refresh-token-$suffix',
        refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 2)),
        version: version);

HomeDeskCredentialStore store(Directory root, {List<int>? entropy}) =>
    HomeDeskCredentialStore(
        applicationSupportDirectory: () async => root, entropy: entropy);

Directory storageDirectory(Directory root) => Directory(
    '${root.path}${Platform.pathSeparator}homedesk${Platform.pathSeparator}portal');

File ciphertext(Directory root) => File(
    '${storageDirectory(root).path}${Platform.pathSeparator}account.dpapi');

Future<void> rejects(Future<void> Function() action, String code) async {
  try {
    await action();
  } on HomeDeskCredentialException catch (error) {
    expect(error.code == code, '错误类型应为 $code，实际为 ${error.code}');
    expect(!error.message.contains('fixture-refresh-token'), '错误不能泄露令牌');
    expect(!error.message.contains('account.dpapi'), '错误不能泄露凭据文件路径');
    return;
  }
  throw StateError('操作应该拒绝：$code');
}

bool isTestDirectory(Directory root) {
  final parent = Directory.systemTemp.absolute.path;
  final path = root.absolute.path;
  return path.startsWith(
      '$parent${Platform.pathSeparator}homedesk-credentials-fixture-');
}

Future<void> test(String name, Future<void> Function(Directory) action) async {
  final root =
      await Directory.systemTemp.createTemp('homedesk-credentials-fixture-');
  try {
    await action(root);
    stdout.writeln('通过：$name');
  } finally {
    expect(isTestDirectory(root), '清理范围必须是当前合成测试目录');
    await root.delete(recursive: true);
  }
}

Future<ProcessResult> child(String operation, Directory root) {
  final packages = File.fromUri(Platform.script
          .resolve('../../client/flutter/.dart_tool/package_config.json'))
      .path;
  return Process.run(Platform.resolvedExecutable, [
    '--packages=$packages',
    Platform.script.toFilePath(),
    operation,
    root.path,
  ]).timeout(const Duration(seconds: 30));
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    if (arguments.length != 2) throw StateError('合成子进程参数无效');
    final root = Directory(arguments[1]);
    expect(isTestDirectory(root), '子进程只能访问合成测试目录');
    if (arguments[0] == '--consume-child') {
      stdout
          .writeln(await store(root).consume() == null ? 'empty' : 'consumed');
    } else if (arguments[0] == '--clear-child') {
      await store(root).clear();
      stdout.writeln('cleared');
    } else {
      throw StateError('合成子进程操作无效');
    }
    return;
  }
  if (!Platform.isWindows) {
    var directoryRead = false;
    final unavailable =
        HomeDeskCredentialStore(applicationSupportDirectory: () async {
      directoryRead = true;
      throw StateError('不应访问任何目录');
    });
    expect(!unavailable.supported, '非 Windows 不能启用持久记住登录');
    final transaction = await unavailable.begin();
    expect(await unavailable.peekAccount() == null, '无安全存储时没有保存账号');
    expect(await unavailable.consume() == null, '无安全存储时不能返回令牌');
    await rejects(
        () => unavailable.save(fixture(), transaction), 'UNSUPPORTED_PLATFORM');
    await unavailable.clear();
    expect(!directoryRead, '不支持的平台不能降级为文件存储');
    stdout.writeln('通过：不支持平台保持纯内存且拒绝明文回退');
    return;
  }

  await test('真实 DPAPI 保护整份记录，元数据读取不消费，令牌仅消费一次', (root) async {
    final storage = store(root);
    final transaction = await storage.begin();
    final original = fixture();
    await storage.save(original, transaction);
    final encoded = latin1.decode(await ciphertext(root).readAsBytes());
    for (final secret in [
      original.refreshToken,
      original.origin,
      original.username,
      'refresh_token'
    ]) {
      expect(!encoded.contains(secret), '完整账号 JSON 必须加密');
    }
    final account = await storage.peekAccount();
    expect(
        account?.origin == original.origin &&
            account?.userId == original.userId &&
            account?.username == original.username &&
            account?.displayName == original.displayName,
        '元数据应与保存账号一致');
    expect(await ciphertext(root).exists(), '只读元数据不能消费刷新令牌');
    final lease = await storage.consume();
    expect(lease?.record.refreshToken == original.refreshToken,
        '当前 Windows 用户应该能够解密合成令牌');
    expect(!await ciphertext(root).exists(), '网络收到令牌前必须删除密文');
    expect(await storage.consume() == null, '同一刷新令牌不能消费两次');
    await storage.save(fixture(suffix: 'rotated'), lease!.transaction);
    expect(
        (await storage.consume())?.record.refreshToken ==
            fixture(suffix: 'rotated').refreshToken,
        '只能保存轮换后的新令牌');
  });

  await test('替换密文不留部分文件，替换失败仍保留旧密文', (root) async {
    final storage = store(root);
    final transaction = await storage.begin();
    await storage.save(fixture(), transaction);
    await storage.save(fixture(suffix: 'replacement'), transaction);
    final before = await ciphertext(root).readAsBytes();
    final path = ciphertext(root).path.toNativeUtf16();
    final handle = CreateFile(
        path,
        GENERIC_ACCESS_RIGHTS.GENERIC_READ,
        FILE_SHARE_MODE.FILE_SHARE_READ,
        nullptr,
        FILE_CREATION_DISPOSITION.OPEN_EXISTING,
        FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_NORMAL,
        0);
    calloc.free(path);
    expect(handle != INVALID_HANDLE_VALUE, '合成密文锁必须创建成功');
    try {
      await rejects(() => storage.save(fixture(suffix: 'blocked'), transaction),
          'STORAGE_UNAVAILABLE');
    } finally {
      CloseHandle(handle);
    }
    final after = await ciphertext(root).readAsBytes();
    expect(
        before.length == after.length &&
            List.generate(
                    before.length, (index) => before[index] == after[index])
                .every((same) => same),
        '原子替换失败不能破坏已有密文');
    expect(
        !await storageDirectory(root)
            .list()
            .any((entity) => entity.path.endsWith('.tmp')),
        '不能遗留临时文件');
    expect(
        (await storage.consume())?.record.refreshToken ==
            fixture(suffix: 'replacement').refreshToken,
        '替换失败后仍只能读取完整旧记录');
  });

  await test('损坏密文失败后也无法重放', (root) async {
    final storage = store(root);
    await storage.save(fixture(), await storage.begin());
    final bytes = await ciphertext(root).readAsBytes();
    bytes[bytes.length - 1] ^= 0x40;
    await ciphertext(root).writeAsBytes(bytes, flush: true);
    await rejects(() async {
      await storage.consume();
    }, 'DPAPI_FAILED');
    expect(!await ciphertext(root).exists(), '验证失败前也必须完成失效删除');
    expect(await storage.consume() == null, '损坏密文不能再消费');
  });

  await test('异产品 entropy 无法解密且没有明文回退', (root) async {
    final storage = store(root);
    await storage.save(fixture(), await storage.begin());
    final other = store(root, entropy: utf8.encode('foreign-fixture-product'));
    await rejects(() async {
      await other.consume();
    }, 'DPAPI_FAILED');
    expect(await storage.consume() == null, '异产品验证失败也必须销毁旧记录');
  });

  await test('并发实例只能有一个取得旧刷新令牌', (root) async {
    final first = store(root), second = store(root);
    await first.save(fixture(), await first.begin());
    final leases = await Future.wait([first.consume(), second.consume()]);
    expect(leases.where((lease) => lease != null).length == 1,
        '文件锁必须阻止同进程两个实例重复消费');
    expect(!await ciphertext(root).exists(), '并发消费之后不能保留旧密文');
  });

  await test('独立进程也只能消费一次，跨进程退出使旧事务失效', (root) async {
    final storage = store(root);
    await storage.save(fixture(), await storage.begin());
    final results = await Future.wait(
        [child('--consume-child', root), child('--consume-child', root)]);
    expect(results.every((result) => result.exitCode == 0), '合成子进程应正常退出');
    expect(
        results
                .where(
                    (result) => result.stdout.toString().trim() == 'consumed')
                .length ==
            1,
        '跨进程锁必须只交付一次刷新令牌');
    final old = await storage.begin();
    await storage.save(fixture(), old);
    final cleared = await child('--clear-child', root);
    expect(
        cleared.exitCode == 0 && cleared.stdout.toString().trim() == 'cleared',
        '另一个进程应能明确清理合成记录');
    await rejects(
        () => storage.save(fixture(suffix: 'late'), old), 'STALE_TRANSACTION');
    expect(await storage.peekAccount() == null, '迟到保存不能恢复已退出账号');
  });

  await test('clear 与新登录代次都拒绝迟到保存', (root) async {
    final first = store(root), second = store(root);
    final old = await first.begin();
    await first.save(fixture(), old);
    await second.clear();
    await rejects(
        () => first.save(fixture(suffix: 'late'), old), 'STALE_TRANSACTION');
    final next = await second.begin();
    await second.save(fixture(suffix: 'current'), next);
    await rejects(
        () => first.save(fixture(suffix: 'late'), old), 'STALE_TRANSACTION');
    expect(
        (await second.consume())?.record.refreshToken ==
            fixture(suffix: 'current').refreshToken,
        '旧回调不能覆盖新账号记录');
  });

  await test('删除后放回旧密文也不能恢复旧代次，未开启事务不能直接保存', (root) async {
    final storage = store(root);
    await rejects(
        () => storage.save(fixture(), const CredentialTransaction('')),
        'STALE_TRANSACTION');
    await storage.save(fixture(), await storage.begin());
    final oldBlob = await ciphertext(root).readAsBytes();
    await storage.clear();
    await ciphertext(root).writeAsBytes(oldBlob, flush: true);
    await rejects(() async {
      await storage.consume();
    }, 'CREDENTIAL_INVALID');
    expect(!await ciphertext(root).exists(), '旧密文的持久代次必须保持失效');
    expect(await storage.consume() == null, '旧密文验证失败不能再次消费');
  });

  await test('旧事务失败清理不影响新事务记录，只清理当前事务', (root) async {
    final first = store(root), second = store(root);
    final old = await first.begin();
    await first.save(fixture(), old);
    final current = await second.begin();
    await second.save(fixture(suffix: 'new-owner'), current);
    await first.discard(old);
    expect((await second.peekAccount())?.username == fixture().username,
        '旧事务失败清理不能删除另一实例的新账号');
    final lease = await second.consume();
    expect(
        lease?.record.refreshToken == fixture(suffix: 'new-owner').refreshToken,
        '新事务记录应保持可消费');
    await second.save(fixture(suffix: 'new-token'), lease!.transaction);
    await first.discard(lease.transaction);
    expect(await second.peekAccount() == null, '当前事务失败应删除自身记录');
    await rejects(() => second.save(fixture(suffix: 'late'), lease.transaction),
        'STALE_TRANSACTION');
  });

  await test('记录版本与有效期无效时拒绝保存', (root) async {
    final storage = store(root);
    final transaction = await storage.begin();
    await rejects(() => storage.save(fixture(version: 2), transaction),
        'CREDENTIAL_INVALID');
    final expired = HomeDeskPortalCredential(
        origin: fixture().origin,
        userId: fixture().userId,
        username: fixture().username,
        displayName: fixture().displayName,
        refreshToken: fixture().refreshToken,
        refreshExpiresAt: DateTime.utc(2000));
    await rejects(
        () => storage.save(expired, transaction), 'CREDENTIAL_EXPIRED');
    expect(!await ciphertext(root).exists(), '校验失败不能写出任何凭据记录');
  });
}
