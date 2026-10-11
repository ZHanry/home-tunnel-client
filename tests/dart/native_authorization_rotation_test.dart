import 'dart:async';
import '../../client/flutter/lib/homedesk_tunnel_api.dart';
import '../../client/flutter/lib/nestlink_native_authorization.dart';
import 'tunnel_api_test.dart' as fixture;

Map<String, String> authorization(String token) => {
      'origin': fixture.origin,
      'device_id': fixture.uuid(17),
      'access_token': token,
    };

Future<HomeTunnelApi> signedInGui(fixture.Harness h) async {
  h.overrides['/api/v2/auth/devices'] = (request, _) => fixture.jsonResponse(
      request,
      {
        'device_id': fixture.uuid(17),
        'access_token': fixture.oldAccess,
        'refresh_token': fixture.oldRefresh,
        'access_expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 5))
            .toIso8601String(),
      },
      status: 201);
  h.overrides['/api/v2/auth/refresh'] =
      (request, _) => fixture.jsonResponse(request, {
            'access_token': fixture.nextAccess,
            'refresh_token': fixture.nextRefresh,
            'access_expires_at': '2030-01-01T00:00:00Z',
          });
  h.overrides['/api/v2/browser/hosts/poll'] = (request, _) =>
      fixture.jsonResponse(request, {'items': [], 'stun_urls': []});
  final api = h.api();
  await api.login(username: 'demo', password: 'fixture-password');
  await api.registerGuiDevice(
      installId: fixture.uuid(17), fingerprint: 'a' * 64, name: 'fixture');
  return api;
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(
      String name, Future<void> Function(fixture.Harness) run) async {
    final harness = await fixture.Harness.start();
    try {
      await run(harness);
      passed++;
      print('Passed: $name');
    } finally {
      await harness.close();
    }
  }

  await test('browser refresh awaits native synchronization for every consumer',
      (h) async {
    final api = await signedInGui(h);
    final started = Completer<void>(), installed = Completer<void>();
    var installs = 0;
    final native = NestLinkNativeAuthorization(
        ready: () => true,
        install: (auth) async {
          installs++;
          fixture.expect(auth['access_token'] == fixture.nextAccess,
              'only the returned replacement reaches native');
          started.complete();
          await installed.future;
          return '';
        },
        clear: () async => '');
    api.onGuiAuthorizationChanged = native.synchronize;
    final browser = api.browserHostInbox();
    await started.future;
    var delivered = false;
    final other = api.nativeAuthorization().then((auth) {
      delivered = true;
      return auth;
    });
    await Future<void>.delayed(Duration.zero);
    fixture.expect(
        !delivered &&
            installs == 1 &&
            !h.seen.any((row) => row['path'] == '/api/v2/browser/hosts/poll'),
        'neither browser nor another consumer can outrun native installation');
    installed.complete();
    await browser;
    fixture.expect(
        (await other)['access_token'] == fixture.nextAccess &&
            h.seen
                    .where((row) => row['path'] == '/api/v2/auth/refresh')
                    .length ==
                1 &&
            h.seen.last['token'] == 'Bearer ${fixture.nextAccess}',
        'one rotation completes before the browser uses its new token');
    await native.close();
  });

  for (final code in ['REMOTE_NOT_READY', 'REQUEST_TIMEOUT']) {
    await test(
        'failed native synchronization after refresh is fail closed: $code',
        (h) async {
      final api = await signedInGui(h);
      api.onGuiAuthorizationChanged = (_) async {
        throw HomeTunnelApiException('fixture failure', code);
      };
      await fixture.rejects(() async => api.browserHostInbox(), code);
      fixture.expect(
          !api.isSignedIn &&
              !h.seen.any((row) => row['path'] == '/api/v2/browser/hosts/poll'),
          'a failed rotated authorization never escapes to the browser');
    });
  }

  await test('late old callback failure cannot revoke a new management login',
      (h) async {
    final api = await signedInGui(h);
    final started = Completer<void>(), finish = Completer<void>();
    api.onGuiAuthorizationChanged = (_) async {
      started.complete();
      await finish.future;
      throw const HomeTunnelApiException(
          'late fixture failure', 'REMOTE_NOT_READY');
    };
    final old = api.nativeAuthorization();
    final rejected = fixture.rejects(() async => old, 'REMOTE_NOT_READY');
    await started.future;
    api.onGuiAuthorizationChanged = null;
    await api.login(username: 'demo', password: 'fixture-password');
    finish.complete();
    await rejected;
    fixture.expect(api.isSignedIn && api.guiDeviceId.isEmpty,
        'the old generation cannot close the replacement account');
  });

  await test(
      'inflight old native install, close, then replacement are serialized',
      (_) async {
    final events = <String>[];
    var active = '';
    final started = Completer<void>(), finish = Completer<void>();
    final old = NestLinkNativeAuthorization(
        ready: () => false,
        install: (_) async {
          events.add('old-start');
          started.complete();
          await finish.future;
          active = 'old';
          events.add('old-complete');
          return '';
        },
        clear: () async {
          active = '';
          events.add('old-clear');
          return '';
        });
    final next = NestLinkNativeAuthorization(
        ready: () => false,
        install: (_) async {
          active = 'new';
          events.add('new-install');
          return '';
        },
        clear: () async {
          active = '';
          return '';
        });
    final pending = old.synchronize(authorization('old'));
    final rejected = fixture.rejects(() => pending, 'REQUEST_CANCELLED');
    await started.future;
    final closing = old.close();
    final replacement = next.synchronize(authorization('new'));
    finish.complete();
    await rejected;
    await closing;
    await replacement;
    fixture.expect(
        active == 'new' &&
            events.join(',') == 'old-start,old-complete,old-clear,new-install',
        'the old late install is cleared before the new account is installed');
    await next.close();
  });

  await test('queued install checks closed before entering native', (_) async {
    final blocked = Completer<void>(), started = Completer<void>();
    final blocker = NestLinkNativeAuthorization(
        ready: () => false,
        install: (_) async {
          started.complete();
          await blocked.future;
          return '';
        },
        clear: () async => '');
    final first = blocker.synchronize(authorization('blocker'));
    await started.future;
    var oldInstalls = 0;
    final old = NestLinkNativeAuthorization(
        ready: () => false,
        install: (_) async {
          oldInstalls++;
          return '';
        },
        clear: () async => '');
    final queued = old.synchronize(authorization('old'));
    final rejected = fixture.rejects(() => queued, 'REQUEST_CANCELLED');
    final closing = old.close();
    blocked.complete();
    await first;
    await rejected;
    await closing;
    fixture.expect(
        oldInstalls == 0, 'a closed queued account never calls native install');
    await blocker.close();
  });

  await test(
      'native install failure cannot poison the queued clear or next account',
      (_) async {
    var clears = 0, newInstalls = 0;
    final old = NestLinkNativeAuthorization(
        ready: () => false,
        install: (_) async => 'fixture native rejected',
        clear: () async {
          clears++;
          return '';
        });
    final next = NestLinkNativeAuthorization(
        ready: () => false,
        install: (_) async {
          newInstalls++;
          return '';
        },
        clear: () async => '');
    await fixture.rejects(
        () => old.synchronize(authorization('old')), 'REMOTE_NOT_READY');
    await old.close();
    await next.synchronize(authorization('new'));
    fixture.expect(clears == 1 && newInstalls == 1,
        'failure is delivered to its caller while subsequent cleanup still runs');
    await next.close();
  });
  print('Native authorization rotation integration: $passed passed');
}
