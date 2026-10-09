import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/homedesk_android_credentials.dart' as credentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  tearDown(() => messenger.setMockMessageHandler('homedesk/credentials', null));

  test(
      'decrypted platform reply can be cleared even when native bytes are read-only',
      () async {
    final payload = Uint8List.fromList([17, 42, 63]);
    ByteData? platformReply;
    messenger.setMockMessageHandler('homedesk/credentials', (message) async {
      final call = codec.decodeMethodCall(message!);
      expect(call.method, 'unprotect');
      final encoded = codec.encodeSuccessEnvelope(payload);
      platformReply = ByteData.sublistView(
          Uint8List.sublistView(encoded).asUnmodifiableView());
      return platformReply;
    });

    final result = await credentials.crypt(
        Uint8List.fromList([1, 2, 3]), Uint8List.fromList([4, 5]),
        encrypt: false);
    expect(result, payload);
    final nativeView = codec.decodeEnvelope(platformReply!) as Uint8List;
    expect(() => nativeView[0] = 0, throwsUnsupportedError);
    result!.fillRange(0, result.length, 0);
    expect(result, [0, 0, 0]);
    expect(nativeView, payload);
  });
}
