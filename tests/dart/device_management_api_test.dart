// Production API contract checks use only a synthetic loopback transport.
import 'dart:async';
import '../../client/flutter/lib/homedesk_tunnel_api.dart';
import 'tunnel_api_test.dart' as fixture;

Future<void> main() async {
  var passed = 0;
  Future<void> test(
      String name, Future<void> Function(fixture.Harness) check) async {
    final harness = await fixture.Harness.start();
    try {
      await check(harness);
      passed++;
      print('PASS: $name');
    } finally {
      await harness.close();
    }
  }

  await test('owner deletion uses v2 management authorization and requires 204',
      (h) async {
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    final id = fixture.uuid(2);
    h.overrides['/api/v2/auth/devices/$id'] = (request, body) async {
      fixture.expect(
          request.method == 'DELETE', 'Device removal must issue DELETE');
      fixture.expect(
          request.headers.value('authorization') ==
              'Bearer ${fixture.oldAccess}',
          'Device deletion needs the current management token');
      fixture.expect(body.isEmpty,
          'The owner deletion contract has no optimistic version body');
      request.response.statusCode = 204;
      await request.response.close();
    };
    await api.deleteDevice(id);
    fixture.expect(api.isSignedIn,
        'Revoking a device must not manufacture a management logout');
    fixture.expect(
        !h.seen
            .any((request) => (request['path'] as String).contains('/admin/')),
        'Never invoke administrator deletion');
  });

  await test('unexpected 200 cannot become a successful deletion', (h) async {
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    final id = fixture.uuid(2);
    h.overrides['/api/v2/auth/devices/$id'] =
        (request, _) => fixture.jsonResponse(request, {'deleted': true});
    await fixture.rejects(() => api.deleteDevice(id), 'MUTATION_UNKNOWN');
    fixture.expect(
        h.seen.where((request) => request['method'] == 'DELETE').length == 1,
        'Unknown deletion outcomes are not retried');
  });

  await test(
      'ownership and missing-device failures do not retry or expose server messages',
      (h) async {
    final api = h.api();
    await api.login(username: 'demo', password: 'fixture-password');
    final id = fixture.uuid(2);
    var missing = false;
    h.overrides['/api/v2/auth/devices/$id'] =
        (request, _) => fixture.jsonResponse(
            request,
            {
              'error_code': missing ? 'NOT_FOUND' : 'ACCOUNT_SESSION_REQUIRED',
              'message': 'server-secret'
            },
            status: missing ? 404 : 403);
    await fixture.rejects(
        () => api.deleteDevice(id), 'ACCOUNT_SESSION_REQUIRED');
    missing = true;
    await fixture.rejects(() => api.deleteDevice(id), 'NOT_FOUND');
    fixture.expect(
        h.seen.where((request) => request['method'] == 'DELETE').length == 2,
        'Known permission failures are never replayed');
  });

  await test(
      'a device mutation is serialized and permission revocation stops requests',
      (h) async {
    var allowed = true;
    final api = h.api(isAllowed: () => allowed);
    await api.login(username: 'demo', password: 'fixture-password');
    final id = fixture.uuid(2);
    final sent = Completer<void>(), finish = Completer<void>();
    h.overrides['/api/v2/auth/devices/$id'] = (request, _) async {
      sent.complete();
      await finish.future;
      request.response.statusCode = 204;
      await request.response.close();
    };
    final deleting = api.deleteDevice(id);
    await sent.future;
    await fixture.rejects(
        () => api.updateDevice(id,
            tags: ['synthetic'], favorite: false, expectedMetadataVersion: 1),
        'OPERATION_BUSY');
    finish.complete();
    await deleting;
    final before = h.seen.length;
    allowed = false;
    await fixture.rejects(() => api.deleteDevice(id), 'ACCESS_REVOKED');
    fixture.expect(h.seen.length == before,
        'Revoked local permission cannot send a deletion');
  });
  print('全部通过：$passed 组设备管理 API 合同检查。');
}
