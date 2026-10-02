// HOMEDESK: 独立门户凭据只使用 Windows 当前用户 DPAPI，不提供明文回退。
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'homedesk_tunnel_session.dart';

typedef HomeDeskCredentialStoreFactory = HomeDeskCredentialStorage Function();

class HomeDeskCredentialException implements Exception {
  final String message;
  final String code;
  const HomeDeskCredentialException(this.message, this.code);
  @override
  String toString() => message;
}

const _uiForbidden = 0x1;
const _replaceExisting = 0x1;
const _writeThrough = 0x8;
const _maxBlobBytes = 64 * 1024;
const _credentialFile = 'account.dpapi';
const _stateFile = 'transaction.state';
const _lockFile = 'transaction.lock';
const _magic = [0x48, 0x44, 0x50, 0x31];
final _random = Random.secure();

// 此符号在实际 Windows 写入时才加载，Linux 内存会话不会调用系统库。
final _moveFile = DynamicLibrary.open('kernel32.dll').lookupFunction<
    Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
    int Function(Pointer<Utf16>, Pointer<Utf16>, int)>('MoveFileExW');

String _newGeneration() => base64Url
    .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
    .replaceAll('=', '');

HomeDeskCredentialException _storageFailure() =>
    const HomeDeskCredentialException(
        '系统安全存储暂时不可用，请重新登录；不会改用明文保存。', 'STORAGE_UNAVAILABLE');

/// 生产目录由 path_provider 的 getApplicationSupportDirectory 注入；测试只传临时目录。
class HomeDeskCredentialStore implements HomeDeskCredentialStorage {
  final Future<Directory> Function() _applicationSupportDirectory;
  final Uint8List _entropy;
  final DateTime Function() _clock;
  Future<Directory>? _directoryFuture;

  HomeDeskCredentialStore(
      {required Future<Directory> Function() applicationSupportDirectory,
      List<int>? entropy,
      DateTime Function()? clock})
      : _applicationSupportDirectory = applicationSupportDirectory,
        _entropy = Uint8List.fromList(entropy ??
            utf8.encode('HomeDesk.HomeTunnel.Portal.Credentials.v1')),
        _clock = clock ?? (() => DateTime.now().toUtc()) {
    if (_entropy.isEmpty || _entropy.length > 1024) {
      throw const HomeDeskCredentialException('系统安全存储参数无效。', 'STORAGE_INVALID');
    }
  }

  @override
  bool get supported => Platform.isWindows;

  Future<Directory> _directory() => _directoryFuture ??= () async {
        final root = (await _applicationSupportDirectory()).absolute;
        final directory = Directory(
            '${root.path}${Platform.pathSeparator}homedesk${Platform.pathSeparator}portal');
        await directory.create(recursive: true);
        return directory;
      }();

  File _file(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  // 永久锁文件不能删除；所有实例与进程通过同一个文件锁串行消费和变更代次。
  Future<T> _locked<T>(Future<T> Function(Directory) action) async {
    RandomAccessFile? handle;
    var locked = false;
    try {
      final directory = await _directory();
      handle = await _file(directory, _lockFile).open(mode: FileMode.append);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!locked) {
        try {
          await handle.lock(FileLock.exclusive, 0, 1);
          locked = true;
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 33 ||
              DateTime.now().isAfter(deadline)) {
            throw _storageFailure();
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      return await action(directory);
    } on HomeDeskCredentialException {
      rethrow;
    } catch (_) {
      throw _storageFailure();
    } finally {
      if (handle != null) {
        try {
          if (locked) await handle.unlock(0, 1);
        } catch (_) {
          throw _storageFailure();
        } finally {
          try {
            await handle.close();
          } catch (_) {
            throw _storageFailure();
          }
        }
      }
    }
  }

  // 临时文件也只含密文或非秘密代次；同卷 MoveFileEx 原子替换且要求落盘。
  Future<void> _atomicWrite(File destination, List<int> bytes) async {
    final temporary = File('${destination.path}.${_newGeneration()}.tmp');
    RandomAccessFile? handle;
    try {
      handle = await temporary.open(mode: FileMode.writeOnly);
      await handle.writeFrom(bytes);
      await handle.flush();
      await handle.close();
      handle = null;
      final sourcePath = temporary.path.toNativeUtf16();
      final destinationPath = destination.path.toNativeUtf16();
      try {
        if (_moveFile(sourcePath, destinationPath,
                _replaceExisting | _writeThrough) ==
            0) {
          throw _storageFailure();
        }
      } finally {
        calloc.free(sourcePath);
        calloc.free(destinationPath);
      }
    } finally {
      await handle?.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<String> _state(Directory directory) async {
    final file = _file(directory, _stateFile);
    if (!await file.exists()) return '';
    if (await file.length() != 43) {
      throw const HomeDeskCredentialException(
          '保存的登录状态无效，请重新登录。', 'STORAGE_INVALID');
    }
    final value = await file.readAsString(encoding: ascii);
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
      throw const HomeDeskCredentialException(
          '保存的登录状态无效，请重新登录。', 'STORAGE_INVALID');
    }
    return value;
  }

  Future<CredentialTransaction> _rotate(Directory directory) async {
    final generation = _newGeneration();
    await _atomicWrite(_file(directory, _stateFile), ascii.encode(generation));
    return CredentialTransaction(generation);
  }

  Future<void> _deleteRecord(Directory directory) async {
    final record = _file(directory, _credentialFile);
    if (await record.exists()) await record.delete();
  }

  Future<Uint8List> _readBlob(Directory directory) async {
    final file = _file(directory, _credentialFile);
    final handle = await file.open(mode: FileMode.read);
    try {
      final size = await handle.length();
      if (size <= _magic.length || size > _maxBlobBytes) {
        throw const HomeDeskCredentialException(
            '保存的登录密文已损坏，请重新登录。', 'STORAGE_INVALID');
      }
      // 即使文件被外部程序替换或扩展，也不能进行无界读取。
      final bytes = await handle.read(_maxBlobBytes + 1);
      if (bytes.length != size) {
        throw const HomeDeskCredentialException(
            '保存的登录密文已损坏，请重新登录。', 'STORAGE_INVALID');
      }
      // 逐字节校验头部，避免接受其他产品或格式的密文。
      for (var i = 0; i < _magic.length; i++) {
        if (bytes[i] != _magic[i]) {
          throw const HomeDeskCredentialException(
              '保存的登录密文已损坏，请重新登录。', 'STORAGE_INVALID');
        }
      }
      return Uint8List.sublistView(bytes, _magic.length);
    } finally {
      await handle.close();
    }
  }

  Uint8List _crypt(Uint8List bytes, {required bool encrypt}) {
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final entropy = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    input.ref.cbData = bytes.length;
    input.ref.pbData = calloc<Uint8>(bytes.length);
    input.ref.pbData.asTypedList(bytes.length).setAll(0, bytes);
    entropy.ref.cbData = _entropy.length;
    entropy.ref.pbData = calloc<Uint8>(_entropy.length);
    entropy.ref.pbData.asTypedList(_entropy.length).setAll(0, _entropy);
    try {
      // 只使用 UI_FORBIDDEN，不设置 LOCAL_MACHINE，必须绑定当前 Windows 用户。
      final result = encrypt
          ? CryptProtectData(
              input, nullptr, entropy, nullptr, nullptr, _uiForbidden, output)
          : CryptUnprotectData(
              input, nullptr, entropy, nullptr, nullptr, _uiForbidden, output);
      if (result == 0 ||
          output.ref.pbData == nullptr ||
          output.ref.cbData < 1 ||
          output.ref.cbData > _maxBlobBytes - _magic.length) {
        throw const HomeDeskCredentialException(
            'Windows 无法验证保存的登录，请重新登录；不会改用明文保存。', 'DPAPI_FAILED');
      }
      return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData));
    } finally {
      input.ref.pbData
          .asTypedList(input.ref.cbData)
          .fillRange(0, input.ref.cbData, 0);
      calloc.free(input.ref.pbData);
      calloc.free(entropy.ref.pbData);
      if (output.ref.pbData != nullptr) {
        output.ref.pbData
            .asTypedList(output.ref.cbData)
            .fillRange(0, output.ref.cbData, 0);
        LocalFree(output.ref.pbData);
      }
      calloc.free(input);
      calloc.free(entropy);
      calloc.free(output);
    }
  }

  HomeDeskPortalCredential _validated(HomeDeskPortalCredential record) {
    try {
      final value = HomeDeskPortalCredential.fromJson(
          Map<String, dynamic>.from(record.toJson()));
      final uri = Uri.parse(value.origin);
      final unsafe = RegExp(r'[\x00-\x20\x7f\\]|%(?:0[0-9a-f]|1[0-9a-f]|7f)',
          caseSensitive: false);
      final host = uri.host;
      if (unsafe.hasMatch(value.origin) ||
          host.isEmpty ||
          host.length > 253 ||
          (InternetAddress.tryParse(host) == null &&
              !host.split('.').every((part) =>
                  RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
                      .hasMatch(part)))) {
        throw const FormatException();
      }
      if (!value.refreshExpiresAt.isAfter(_clock().toUtc())) {
        throw const HomeDeskCredentialException(
            '记住的登录已过期，请重新登录。', 'CREDENTIAL_EXPIRED');
      }
      return value;
    } on HomeDeskCredentialException {
      rethrow;
    } catch (_) {
      throw const HomeDeskCredentialException(
          '保存的登录信息无效，请重新登录。', 'CREDENTIAL_INVALID');
    }
  }

  HomeDeskPortalCredential _decode(Uint8List blob, String generation) {
    final plaintext = _crypt(blob, encrypt: false);
    try {
      final envelope = jsonDecode(utf8.decode(plaintext));
      if (envelope is! Map<String, dynamic> ||
          envelope.keys
              .toSet()
              .difference({'generation', 'credential'}).isNotEmpty ||
          envelope.length != 2 ||
          envelope['generation'] != generation ||
          envelope['credential'] is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final credential = envelope['credential'] as Map<String, dynamic>;
      const keys = {
        'version',
        'origin',
        'user_id',
        'username',
        'display_name',
        'refresh_token',
        'refresh_expires_at'
      };
      if (credential.length != keys.length ||
          credential.keys.toSet().difference(keys).isNotEmpty) {
        throw const FormatException();
      }
      return _validated(HomeDeskPortalCredential.fromJson(credential));
    } on HomeDeskCredentialException {
      rethrow;
    } catch (_) {
      throw const HomeDeskCredentialException(
          '保存的登录信息无效，请重新登录。', 'CREDENTIAL_INVALID');
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  @override
  Future<HomeDeskRememberedAccount?> peekAccount() async {
    if (!supported) return null;
    return _locked((directory) async {
      if (!await _file(directory, _credentialFile).exists()) return null;
      try {
        final generation = await _state(directory);
        final record = _decode(await _readBlob(directory), generation);
        return HomeDeskRememberedAccount(
            origin: record.origin,
            userId: record.userId,
            username: record.username,
            displayName: record.displayName);
      } catch (_) {
        await _rotate(directory);
        await _deleteRecord(directory);
        rethrow;
      }
    });
  }

  @override
  Future<CredentialTransaction> begin() async {
    if (!supported) return CredentialTransaction(_newGeneration());
    return _locked((directory) async {
      final transaction = await _rotate(directory);
      await _deleteRecord(directory);
      return transaction;
    });
  }

  @override
  Future<CredentialLease?> consume() async {
    if (!supported) return null;
    return _locked((directory) async {
      if (!await _file(directory, _credentialFile).exists()) return null;
      // 先保存无效化代次并删除文件，任何后续失败都不能让旧令牌再次消费。
      final generation = await _state(directory);
      Uint8List? blob;
      HomeDeskCredentialException? readFailure;
      try {
        blob = await _readBlob(directory);
      } on HomeDeskCredentialException catch (error) {
        readFailure = error;
      }
      final transaction = await _rotate(directory);
      await _deleteRecord(directory);
      if (readFailure != null) throw readFailure;
      final record = _decode(blob!, generation);
      return CredentialLease(record: record, transaction: transaction);
    });
  }

  @override
  Future<void> save(HomeDeskPortalCredential record,
      CredentialTransaction transaction) async {
    if (!supported) {
      throw const HomeDeskCredentialException(
          '此平台暂不支持安全记住登录，本次登录仅在内存中保留。', 'UNSUPPORTED_PLATFORM');
    }
    final valid = _validated(record);
    await _locked((directory) async {
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(transaction.generation) ||
          await _state(directory) != transaction.generation) {
        throw const HomeDeskCredentialException(
            '旧登录保存请求已失效。', 'STALE_TRANSACTION');
      }
      final plaintext = Uint8List.fromList(utf8.encode(jsonEncode({
        'generation': transaction.generation,
        'credential': valid.toJson(),
      })));
      try {
        final ciphertext = _crypt(plaintext, encrypt: true);
        await _atomicWrite(_file(directory, _credentialFile),
            Uint8List.fromList([..._magic, ...ciphertext]));
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    });
  }

  @override
  Future<void> discard(CredentialTransaction transaction) async {
    if (!supported) return;
    await _locked((directory) async {
      // 旧请求的失败清理不能删除另一实例随后成功保存的新登录。
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(transaction.generation) ||
          await _state(directory) != transaction.generation) {
        return;
      }
      await _rotate(directory);
      await _deleteRecord(directory);
    });
  }

  @override
  Future<void> clear() async {
    if (!supported) return;
    await _locked((directory) async {
      // 删除失败也已先使密文内的旧代次失效；不得因此恢复任何旧令牌。
      await _rotate(directory);
      await _deleteRecord(directory);
    });
  }
}
