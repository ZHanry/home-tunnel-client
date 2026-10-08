// HOMEDESK: Android Keystore is available only through the native Flutter bridge.
import 'dart:typed_data';

Future<Uint8List?> crypt(Uint8List bytes, Uint8List entropy,
        {required bool encrypt}) =>
    Future.error(UnsupportedError('Android Keystore requires Flutter'));
