// Real Linux Secret Service regression. Every record belongs to a new temporary directory.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../client/flutter/lib/homedesk_credentials.dart';
import '../../client/flutter/lib/homedesk_tunnel_session.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

final _fixtureRandom = Random.secure();

HomeDeskCredentialStore store(Directory root) => HomeDeskCredentialStore(
    applicationSupportDirectory: () async => root,
    // Keep IDs unique while deterministically exercising secret-tool's
    // option parser: '-' is a valid first character of a Base64URL ID.
    secretServiceRecordId: () =>
        '-${base64Url.encode(List<int>.generate(32, (_) => _fixtureRandom.nextInt(256))).substring(1, 43)}');

Future<void> checkKeyringDeleted(String id) async {
  final result = await Process.run('/usr/bin/secret-tool',
      ['lookup', '--', 'application', 'HomeDesk', 'portal-record', id]);
  check(result.exitCode == 1 && result.stdout == '' && result.stderr == '',
      'Consumed or cleared credential remained in Secret Service');
}

HomeDeskPortalCredential fixture() => HomeDeskPortalCredential(
    origin: 'https://fixture.nestlink.invalid',
    userId: '11111111-1111-4111-8111-111111111111',
    username: 'fixture-account',
    displayName: 'Fixture account',
    refreshToken: 'SyntheticFixtureNeverAuthenticates_0001',
    refreshExpiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)));

Future<void> main(List<String> args) async {
  if (!Platform.isLinux) return;
  if (args.length == 2 && args.first == '--unavailable') {
    final root = Directory(args.last).absolute;
    check(
        root.path.startsWith(
            '${Directory.systemTemp.absolute.path}/nestlink-secret-service-'),
        'Unexpected unavailable-storage fixture directory');
    final storage = store(root);
    final transaction = await storage.begin();
    try {
      await storage.save(fixture(), transaction);
      throw StateError('Unavailable Secret Service accepted a credential');
    } on HomeDeskCredentialException catch (error) {
      check(error.code == 'STORAGE_UNAVAILABLE',
          'Unavailable Secret Service returned the wrong error');
      check(!await File('${root.path}/homedesk/portal/account.dpapi').exists(),
          'Unavailable Secret Service persisted a credential');
    }
    return;
  }
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
    check(ascii.decode(bytes.sublist(4)).startsWith('nlss:-'),
        'The regression must exercise a leading-dash Secret Service ID');
    check(
        !utf8
            .decode(bytes, allowMalformed: true)
            .contains(fixture().refreshToken),
        'Credential file contains plaintext');
    check(await storage.peekAccount() != null,
        'Account hint could not be restored');
    final packages = Platform.packageConfig ??
        File.fromUri(Platform.script
                .resolve('../../client/flutter/.dart_tool/package_config.json'))
            .path;
    final child = await Process.run(Platform.resolvedExecutable,
        ['--packages=$packages', Platform.script.toFilePath(), root.path]);
    check(child.exitCode == 0, 'Cross-process restore failed');
    await checkKeyringDeleted(ascii.decode(bytes.sublist(9)));
    check(await storage.consume() == null,
        'Child consumed record must stay invalidated');
    await storage.save(fixture(), await storage.begin());
    final logoutId = ascii.decode((await record.readAsBytes()).sublist(9));
    await storage.clear();
    await checkKeyringDeleted(logoutId);
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
    final unavailable = await Process.run(Platform.resolvedExecutable, [
      '--packages=$packages',
      Platform.script.toFilePath(),
      '--unavailable',
      '${root.path}/unavailable',
    ], environment: {
      'DBUS_SESSION_BUS_ADDRESS': 'unix:path=${root.path}/missing-bus',
    });
    check(unavailable.exitCode == 0,
        'Unavailable Secret Service must fail closed without file fallback');
    stdout.writeln(
        'Linux Secret Service: leading-dash record IDs, protected storage, cross-process single consumption, logout, corruption recovery and unavailable-backend rejection passed');
  } finally {
    await storage.clear();
    await root.delete(recursive: true);
  }
}
