// Physical-device identity must not collapse credential scopes or service routes.
import 'dart:async';
import '../../client/flutter/lib/homedesk_tunnel_api.dart';
import 'tunnel_api_test.dart' as f;

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function(f.Harness) run) async {
    final h = await f.Harness.start();
    try {
      await run(h);
      passed++;
      print('PASS: $name');
    } finally {
      await h.close();
    }
  }

  Map<String, Object?> link({String? remote, String? tunnel}) => {
        'physical_device_id': f.uuid(1),
        'remote_device_id': remote,
        'tunnel_device_id': tunnel,
      };
  void directory(f.Harness h, {Set<int>? members}) {
    h.overrides['/api/v1/client/devices'] = (request, _) => f.jsonResponse(
        request,
        f.page([
          for (final n in members ?? {1, 2, 3})
            {
              ...f.device(n),
              'name': 'Same hostname',
              'platform': n == 1 ? 'windows' : '',
              'online': n != 1
            }
        ]));
    h.overrides['/api/v1/client/connections'] =
        (request, _) => f.jsonResponse(request, {
              ...f.page([
                {...f.service(1, 'http'), 'device_id': f.uuid(2)},
              ]),
              'capabilities': f.rawCapabilities
            });
  }

  Future<HomeTunnelApi> login(f.Harness h, {bool register = true}) async {
    h.overrides['/api/v2/auth/devices'] = (request, body) {
      f.expect(body['credential_purpose'] == 'gui', 'GUI keeps its own scope');
      return f.jsonResponse(
          request, {...f.loginReply(), 'device_id': f.uuid(1)},
          status: 201);
    };
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    if (register)
      await api.registerGuiDevice(
          installId: f.uuid(11), fingerprint: 'a' * 64, name: 'Same hostname');
    return api;
  }

  await test(
      'verified local pair counts once, retains services and same-name peer',
      (h) async {
    directory(h);
    h.overrides['/api/v2/auth/device-capabilities'] = (request, _) async {
      request.response.statusCode = 404;
      request.response.write('<html>old server</html>');
      await request.response.close();
    };
    final api = await login(h);
    final catalog = await api.associateLocalDevice(f.uuid(2));
    f.expect(
        catalog.devices.length == 2, 'One physical machine and a real peer');
    final physical = catalog.devices.firstWhere((d) => d.id == f.uuid(1));
    f.expect(
        physical.remoteDeviceId == f.uuid(1) &&
            physical.tunnelDeviceId == f.uuid(2),
        'Keep both capability credential routes');
    f.expect(physical.platform == 'windows' && physical.tunnelOnline,
        'Platform and independent tunnel heartbeat retained');
    f.expect(catalog.services.single.deviceId == physical.id,
        'Service belongs to the physical machine');
    final refreshed = await api.catalog();
    f.expect(refreshed.devices.length == 2,
        'Refreshing cannot resurrect a duplicate');
    f.expect(
        h.seen
                .where((r) => r['path'] == '/api/v2/auth/device-capabilities')
                .length ==
            1,
        'Probe an old server only once per account session');
  });
  await test(
      'new service uses background subject; binding and metadata use remote subject',
      (h) async {
    directory(h);
    final api = await login(h);
    await api.associateLocalDevice(f.uuid(2));
    h.overrides['/api/v1/client/connections'] = (request, body) {
      f.expect(request.method == 'POST' && body['device_id'] == f.uuid(2),
          'Never create the tunnel on the GUI credential');
      f.expect(
          request.headers.value('authorization') == 'Bearer ${f.oldAccess}',
          'Creation still requires account authorization');
      return f.jsonResponse(
          request, {...f.service(2, 'http'), 'device_id': f.uuid(2)},
          status: 201);
    };
    final created = await api.createService(f.httpDraft());
    f.expect(created.deviceId == f.uuid(1),
        'Response resolves back to physical device');
    h.overrides['/api/v1/client/devices/${f.uuid(1)}/metadata'] =
        (request, _) =>
            f.jsonResponse(request, {'id': f.uuid(1), 'metadata_version': 2});
    await api.updateDevice(f.uuid(1),
        tags: ['home'], favorite: false, expectedMetadataVersion: 1);
    h.overrides['/api/v2/homedesk/devices'] =
        (request, _) => f.jsonResponse(request, {
              'items': [
                {
                  'device_id': f.uuid(1),
                  'remote_id': '123456789',
                  'server': 'remote.example.invalid:21116',
                  'key_sha256': 'a' * 64,
                  'platform': 'windows',
                  'online': false
                }
              ]
            });
    final binding = (await api.remoteBindings()).single;
    f.expect(binding.deviceId == f.uuid(1) && !binding.online,
        'Tunnel heartbeat must not make remote control online');
  });
  await test(
      'old-server delete revokes both capabilities and never replays partial outcome',
      (h) async {
    directory(h);
    final api = await login(h);
    await api.associateLocalDevice(f.uuid(2));
    h.overrides['/api/v2/auth/devices/${f.uuid(2)}'] = (request, _) async {
      request.response.statusCode = 204;
      await request.response.close();
    };
    h.overrides['/api/v2/auth/devices/${f.uuid(1)}'] = (request, _) =>
        f.jsonResponse(request, {'error_code': 'FORBIDDEN'}, status: 403);
    await f.rejects(() => api.deleteDevice(f.uuid(1)), 'MUTATION_UNKNOWN');
    f.expect(h.seen.where((r) => r['method'] == 'DELETE').length == 2,
        'No hidden retry after partial revocation');
    directory(h, members: {1, 3});
    final remaining = await api.catalog();
    f.expect(
        remaining.devices
            .firstWhere((d) => d.id == f.uuid(1))
            .tunnelDeviceId
            .isEmpty,
        'Missing capability remains missing during outcome review');
  });
  await test(
      'server association unifies other computers and uses atomic device deletion',
      (h) async {
    directory(h);
    h.overrides['/api/v2/auth/device-capabilities'] =
        (request, _) => f.jsonResponse(request, {
              'version': 1,
              'items': [link(remote: f.uuid(1), tunnel: f.uuid(2))]
            });
    final api = await login(h, register: false);
    final catalog = await api.catalog();
    f.expect(
        catalog.devices.length == 2 &&
            catalog.services.single.deviceId == f.uuid(1),
        'Server association works without local native identity');
    h.overrides['/api/v2/auth/device-capabilities/${f.uuid(1)}'] =
        (request, _) async {
      f.expect(
          request.headers.value('authorization') == 'Bearer ${f.oldAccess}',
          'Physical deletion uses management session');
      request.response.statusCode = 204;
      await request.response.close();
    };
    await api.deleteDevice(f.uuid(1));
    f.expect(h.seen.where((r) => r['method'] == 'DELETE').length == 1,
        'One atomic server revocation');
  });
  await test(
      'revoked remote capability keeps physical identity and surviving tunnel',
      (h) async {
    directory(h, members: {2, 3});
    h.overrides['/api/v2/auth/device-capabilities'] =
        (request, _) => f.jsonResponse(request, {
              'version': 1,
              'items': [link(tunnel: f.uuid(2))]
            });
    final api = await login(h, register: false);
    final physical = (await api.catalog()).devices.first;
    f.expect(
        physical.id == f.uuid(1) &&
            physical.remoteDeviceId.isEmpty &&
            physical.tunnelDeviceId == f.uuid(2),
        'Retain physical identity without claiming a revoked capability');
    h.overrides['/api/v1/client/devices/${f.uuid(2)}/metadata'] =
        (request, _) =>
            f.jsonResponse(request, {'id': f.uuid(2), 'metadata_version': 2});
    await api.updateDevice(physical.id,
        tags: [], favorite: false, expectedMetadataVersion: 1);
  });
  await test('absent native subject and duplicate server links are rejected',
      (h) async {
    directory(h);
    final api = await login(h);
    await f.rejects(
        () => api.associateLocalDevice(f.uuid(50)), 'OWNERSHIP_MISMATCH');
    f.expect((await api.catalog()).devices.length == 3,
        'Same hostname cannot establish identity');
    final other = h.api();
    await other.login(username: 'demo', password: 'fixture-password');
    h.overrides['/api/v2/auth/device-capabilities'] =
        (request, _) => f.jsonResponse(request, {
              'version': 1,
              'items': [
                link(remote: f.uuid(1), tunnel: f.uuid(2)),
                link(remote: f.uuid(1), tunnel: f.uuid(3))
              ]
            });
    await f.rejects(() async {
      await other.catalog();
    }, 'RESPONSE_INVALID');
  });
  await test(
      'unknown association response is checked by GET rather than replayed',
      (h) async {
    directory(h);
    var linked = false;
    h.overrides['/api/v2/auth/device-capabilities'] = (request, _) =>
        f.jsonResponse(request, {
          'version': 1,
          'items': linked ? [link(remote: f.uuid(1), tunnel: f.uuid(2))] : []
        });
    h.overrides['/api/v2/auth/device-capabilities/link'] = (request, _) =>
        f.jsonResponse(request, {'error_code': 'UNAVAILABLE'}, status: 503);
    final api = await login(h);
    await f.rejects(
        () => api.associateLocalDevice(f.uuid(2)), 'MUTATION_UNKNOWN');
    await f.rejects(
        () => api.associateLocalDevice(f.uuid(2)), 'MUTATION_UNKNOWN');
    f.expect(
        h.seen
                .where(
                    (r) => r['path'] == '/api/v2/auth/device-capabilities/link')
                .length ==
            1,
        'Never replay an uncertain link');
    linked = true;
    f.expect((await api.associateLocalDevice(f.uuid(2))).devices.length == 2,
        'Confirmed server result completes association');
  });
  await test(
      'changing account session drops local association and capability routes',
      (h) async {
    directory(h);
    final api = await login(h);
    await api.associateLocalDevice(f.uuid(2));
    await api.login(username: 'next-account', password: 'fixture-password');
    f.expect((await api.catalog()).devices.length == 3,
        'Local pairing must not survive account change');
  });
  await test(
      'unregistered and removed tunnel capabilities cannot receive new services',
      (h) async {
    directory(h);
    final api = await login(h);
    await api.catalog();
    await f.rejects(() => api.createService(f.httpDraft()), 'TUNNEL_NOT_READY');
    await api.associateLocalDevice(f.uuid(2));
    directory(h, members: {1, 3});
    await api.catalog();
    await f.rejects(() => api.createService(f.httpDraft()), 'TUNNEL_NOT_READY');
    f.expect(
        !h.seen.any((r) =>
            r['path'] == '/api/v1/client/connections' && r['method'] == 'POST'),
        'Do not send a service to a GUI or revoked tunnel subject');
  });
  await test('surviving tunnel uses its active metadata subject on old servers',
      (h) async {
    directory(h);
    final api = await login(h);
    await api.associateLocalDevice(f.uuid(2));
    directory(h, members: {2, 3});
    final physical = (await api.catalog()).devices.first;
    f.expect(physical.remoteDeviceId.isEmpty,
        'Do not retain a missing remote capability');
    h.overrides['/api/v1/client/devices/${f.uuid(2)}/metadata'] =
        (request, _) =>
            f.jsonResponse(request, {'id': f.uuid(2), 'metadata_version': 2});
    await api.updateDevice(physical.id,
        tags: [], favorite: false, expectedMetadataVersion: 1);
  });
  await test('a delayed pre-link directory cannot undo a completed association',
      (h) async {
    directory(h);
    var linked = false, blockRead = false;
    final postStarted = Completer<void>(), finishPost = Completer<void>();
    final readStarted = Completer<void>(), finishRead = Completer<void>();
    h.overrides['/api/v2/auth/device-capabilities'] = (request, _) async {
      final items = linked ? [link(remote: f.uuid(1), tunnel: f.uuid(2))] : [];
      if (blockRead) {
        blockRead = false;
        readStarted.complete();
        await finishRead.future;
      }
      await f.jsonResponse(request, {'version': 1, 'items': items});
    };
    h.overrides['/api/v2/auth/device-capabilities/link'] = (request, _) async {
      postStarted.complete();
      await finishPost.future;
      linked = true;
      await f.jsonResponse(request, link(remote: f.uuid(1), tunnel: f.uuid(2)),
          status: 201);
    };
    final api = await login(h);
    final associating = api.associateLocalDevice(f.uuid(2));
    await postStarted.future;
    blockRead = true;
    final stale = api.catalog();
    await readStarted.future;
    finishPost.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    finishRead.complete();
    final results = await Future.wait([associating, stale]);
    f.expect(
        results.every((c) =>
            c.devices.length == 2 && c.services.single.deviceId == f.uuid(1)),
        'Concurrent callers receive the confirmed physical directory');
    f.expect((await api.catalog()).devices.length == 2,
        'The committed route snapshot remains unified');
  });
  await test(
      'successful service mutation invalidates an older shared directory',
      (h) async {
    directory(h);
    final api = await login(h);
    await api.associateLocalDevice(f.uuid(2));
    var created = false, holdRead = true;
    final started = Completer<void>(), release = Completer<void>();
    h.overrides['/api/v1/client/connections'] = (request, body) async {
      if (request.method == 'POST') {
        f.expect(
            body['device_id'] == f.uuid(2), 'Mutation retains tunnel scope');
        created = true;
        await f.jsonResponse(
            request, {...f.service(2, 'http'), 'device_id': f.uuid(2)},
            status: 201);
        return;
      }
      final items = [
        {...f.service(1, 'http'), 'device_id': f.uuid(2)},
        if (created) {...f.service(2, 'http'), 'device_id': f.uuid(2)},
      ];
      if (holdRead) {
        holdRead = false;
        started.complete();
        await release.future;
      }
      await f.jsonResponse(
          request, {...f.page(items), 'capabilities': f.rawCapabilities});
    };
    final stale = api.catalog();
    await started.future;
    await api.createService(f.httpDraft());
    final refreshAfterMutation = api.catalog();
    release.complete();
    final results = await Future.wait([stale, refreshAfterMutation]);
    f.expect(results.every((catalog) => catalog.services.length == 2),
        'An old read cannot discard the confirmed new service');
    f.expect(
        results.every((catalog) =>
            catalog.services.every((service) => service.deviceId == f.uuid(1))),
        'Refreshing preserves physical ownership');
  });
  print('All $passed device capability contract checks passed.');
}
