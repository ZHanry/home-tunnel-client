import 'dart:async';
import '../../client/flutter/lib/homedesk_tunnel_api.dart';
import '../../client/flutter/lib/nestlink_native_authorization.dart';
import '../../client/flutter/lib/nestlink_native_status.dart';

void check(bool value, String name) {
  if (!value) throw StateError(name);
}

Map<String, String> authorization(String token) => {
      'origin': 'https://fixture.invalid',
      'device_id': 'fixture-device',
      'access_token': token,
    };

Future<Object> failure(Future<void> operation) => operation.then<Object>(
    (_) => throw StateError('Expected fail-closed error'),
    onError: (Object error) => error);

Future<void> main() async {
  final codes = <String, NestLinkNativeStatus>{
    'HTTP_401': NestLinkNativeStatus.http401,
    'HTTP_403': NestLinkNativeStatus.http403,
    'HTTP_OTHER': NestLinkNativeStatus.httpOther,
    'AUTH_REQUIRED': NestLinkNativeStatus.authorizationRequired,
    'PLATFORM_VERIFIER': NestLinkNativeStatus.platformVerifier,
    'TLS_CONFIGURATION': NestLinkNativeStatus.tlsConfiguration,
    'CERTIFICATE_REJECTED': NestLinkNativeStatus.certificateRejected,
    'TIMEOUT': NestLinkNativeStatus.timeout,
    'NETWORK': NestLinkNativeStatus.network,
    'INVALID_RESPONSE': NestLinkNativeStatus.invalidResponse,
    'UNKNOWN': NestLinkNativeStatus.unknown,
  };
  for (final entry in codes.entries) {
    final wire = 'NESTLINK_NATIVE_AUTH_V1:${entry.key}';
    check(classifyNestLinkNativeError(wire) == entry.value, 'fixed code');
    check(
        classifyNestLinkNativeError(
                '$wire https://fixture.invalid?token=fake') ==
            NestLinkNativeStatus.unknown,
        'appended private text refused');
    check(
        entry.value.title(false).isNotEmpty &&
            entry.value.title(true).isNotEmpty &&
            entry.value.advice(false).isNotEmpty &&
            entry.value.advice(true).isNotEmpty,
        'fixed bilingual guidance');
  }
  check(
      classifyNestLinkNativeError(
              'error sending request for url https://fixture.invalid?token=fake') ==
          NestLinkNativeStatus.unknown,
      'raw transport string is not a code');
  check(
      classifyNestLinkNativeError('账号或远控许可已失效（HTTP 503）') ==
          NestLinkNativeStatus.unknown,
      'other HTTP is not revocation');
  check(
      classifyNestLinkNativeFailure(
              const HomeTunnelApiException('fake-private', 'NETWORK_ERROR')) ==
          NestLinkNativeStatus.network,
      'known API code');
  print('Passed: strict fixed categories and bilingual safe guidance');

  var ready = false, installs = 0;
  Completer<String>? held;
  final states = <NestLinkNativeStatus>[];
  final native = NestLinkNativeAuthorization(
      ready: () => ready,
      install: (_) async {
        installs++;
        return held == null ? '' : await held.future;
      },
      clear: () async => '',
      onStatus: states.add);
  await native.synchronize(authorization('first'));
  check(
      states.last == NestLinkNativeStatus.connecting &&
          !states.contains(NestLinkNativeStatus.ready),
      'empty result does not imply readiness');
  ready = true;
  await native.synchronize(authorization('first'));
  check(installs == 1 && states.last == NestLinkNativeStatus.ready,
      'same confirmed token uses ready fast path');
  ready = false;
  held = Completer<String>();
  final reinstallation = native.synchronize(authorization('first'));
  await Future<void>.delayed(Duration.zero);
  check(states.last == NestLinkNativeStatus.connecting && installs == 2,
      'pending reinstallation clears stale ready');
  held.complete('');
  await reinstallation;
  check(installs == 2 && states.last == NestLinkNativeStatus.connecting,
      'monitor-cleared native state loses previous ready');
  ready = true;
  await native.synchronize(authorization('first'));
  held = Completer<String>();
  final rotation = native.synchronize(authorization('second'));
  await Future<void>.delayed(Duration.zero);
  check(states.last == NestLinkNativeStatus.connecting && installs == 3,
      'new token cannot display ready while confirmation is pending');
  held.complete('');
  await rotation;
  check(states.last == NestLinkNativeStatus.ready,
      'new token confirms readiness');
  await native.close();
  check(states.last == NestLinkNativeStatus.idle, 'close clears status');
  print('Passed: native readiness and monitor-cleared state');

  final repeatedStates = <NestLinkNativeStatus>[];
  final repeated = NestLinkNativeAuthorization(
      ready: () => false,
      install: (_) async => 'NESTLINK_NATIVE_AUTH_V1:NETWORK',
      clear: () async => '',
      onStatus: repeatedStates.add);
  await failure(repeated.synchronize(authorization('repeated')));
  await failure(repeated.synchronize(authorization('repeated')));
  check(
      repeatedStates.length == 2 &&
          repeatedStates.last == NestLinkNativeStatus.network,
      'automatic retry retains one stable failure status');
  await repeated.close();
  print('Passed: unchanged failures remain stable across retries');

  for (final outcome in ['success', 'error', 'throw']) {
    final entered = Completer<void>(), complete = Completer<String>();
    final oldStates = <NestLinkNativeStatus>[],
        newStates = <NestLinkNativeStatus>[];
    final old = NestLinkNativeAuthorization(
        ready: () => true,
        install: (_) {
          entered.complete();
          return complete.future;
        },
        clear: () async => '',
        onStatus: oldStates.add);
    final pending = failure(old.synchronize(authorization('old')));
    await entered.future;
    final closing = old.close();
    final replacement = NestLinkNativeAuthorization(
        ready: () => true,
        install: (_) async => '',
        clear: () async => '',
        onStatus: newStates.add);
    final newPending = replacement.synchronize(authorization('new'));
    if (outcome == 'throw') {
      complete.completeError(StateError('fake-token https://fixture.invalid'));
    } else {
      complete.complete(
          outcome == 'error' ? 'NESTLINK_NATIVE_AUTH_V1:NETWORK' : '');
    }
    await pending;
    await closing;
    await newPending;
    check(
        oldStates.length == 2 &&
            oldStates.first == NestLinkNativeStatus.connecting &&
            oldStates.last == NestLinkNativeStatus.idle,
        'late old completion suppressed');
    check(newStates.last == NestLinkNativeStatus.ready,
        'replacement owns current state');
    await replacement.close();
  }
  print('Passed: late success error and throw after close/account replacement');

  const private = 'fake-token https://fixture.invalid/private';
  final safe = NestLinkNativeAuthorization(
      ready: () => false,
      install: (_) async => private,
      clear: () async => private,
      onStatus: (_) => throw StateError('observer'));
  final installError = await failure(safe.synchronize(authorization('safe')));
  final clearError = await failure(safe.close());
  for (final error in [installError, clearError]) {
    check(
        error is NestLinkNativeException &&
            error.code == 'REMOTE_NOT_READY' &&
            error.status == NestLinkNativeStatus.unknown,
        'safe fail-closed type');
    check(
        !error.toString().contains(private) &&
            !(error as HomeTunnelApiException)
                .message
                .contains('fixture.invalid'),
        'native raw cannot escape exception presentation');
  }
  final observer = NestLinkNativeAuthorization(
      ready: () => true,
      install: (_) async => '',
      clear: () async => '',
      onStatus: (_) => throw StateError('observer'));
  await observer.synchronize(authorization('observer'));
  await observer.close();
  print('Passed: raw errors and throwing presentation observers stay isolated');
}
