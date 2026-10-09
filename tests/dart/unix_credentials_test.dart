// Real Linux Secret Service regression. Every record belongs to a new temporary directory.
import 'dart:convert';
import 'dart:io';
import '../../client/flutter/lib/homedesk_credentials.dart';
import '../../client/flutter/lib/homedesk_tunnel_session.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

HomeDeskCredentialStore store(Directory root) =>
    HomeDeskCredentialStore(applicationSupportDirectory: () async => root);

HomeDeskPortalCredential fixture() => HomeDeskPortalCredential(
    origin: 'https://fixture.nestlink.invalid',
    userId: '11111111-1111-4111-8111-111111111111',
    username: 'fixture-account',
    displayName: 'Fixture account',
    refreshToken: 'SyntheticFixtureNeverAuthenticates_0001',
    refreshExpiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)));

Future<void> main(List<String> args) async {
  if (!Platform.isLinux) return;
  if (args.length == 1) {
    final root = Directory(args.single).absolute;
    check(
        root.path.startsWith(
            '${Directory.systemTemp.absolute.path}/nestlink-secret-service-'),
        'Unexpected fixture directory');
    final lease = await store(root).consume();
    check(lease?.record.username == 'fixture-account',
        'Cross-process Secret Service restore failed');
    check(await store(root).consume() == null,
        'A remembered credential must be consumed once');
    return;
  }
  final root =
      await Directory.systemTemp.createTemp('nestlink-secret-service-');
  final storage = store(root);
  try {
    check(storage.supported, 'Linux storage must be supported');
    await storage.save(fixture(), await storage.begin());
    final record = File('${root.path}/homedesk/portal/account.dpapi');
    final bytes = await record.readAsBytes();
    check(
        !utf8
            .decode(bytes, allowMalformed: true)
            .contains(fixture().refreshToken),
        'Credential file contains plaintext');
    check(await storage.peekAccount() != null,
        'Account hint could not be restored');
    final packages = File.fromUri(Platform.script
        .resolve('../../client/flutter/.dart_tool/package_config.json'));
    final child = await Process.run(Platform.resolvedExecutable, [
      '--packages=${packages.path}',
      Platform.script.toFilePath(),
      root.path
    ]);
    check(child.exitCode == 0, 'Cross-process restore failed');
    check(await storage.consume() == null,
        'Child consumed record must stay invalidated');
    await storage.save(fixture(), await storage.begin());
    await storage.clear();
    check(await storage.peekAccount() == null,
        'Logout did not erase the saved credential');
    await record.writeAsBytes([0, 1, 2, 3, 4]);
    try {
      await storage.peekAccount();
      throw StateError('Tampered record accepted');
    } on HomeDeskCredentialException {
      check(!await record.exists(), 'Tampered credential must be removed');
    }
    await storage.save(fixture(), await storage.begin());
    check(await storage.peekAccount() != null,
        'Storage did not recover after corruption');
    stdout.writeln(
        'Linux Secret Service: protected storage, cross-process single consumption, logout and corruption recovery passed');
  } finally {
    await storage.clear();
    await root.delete(recursive: true);
  }
}
