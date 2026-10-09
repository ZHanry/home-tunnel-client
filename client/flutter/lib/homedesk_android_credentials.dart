// HOMEDESK: Keep the platform bridge separate so Windows DPAPI can be tested across real Dart processes.
import 'dart:typed_data';
import 'package:flutter/services.dart';

Future<Uint8List?> crypt(Uint8List bytes, Uint8List entropy,
    {required bool encrypt}) async {
  final result = await const MethodChannel('homedesk/credentials')
      .invokeMethod<Uint8List>(encrypt ? 'protect' : 'unprotect',
          {'bytes': bytes, 'entropy': entropy});
  // Platform replies may expose read-only views. The store owns this copy so
  // it can clear decrypted credentials after parsing without failing restore.
  return result == null ? null : Uint8List.fromList(result);
}
