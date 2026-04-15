import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import '../constants/api_constants.dart';

/// CryptoJS-compatible AES encryption service.
/// Matches the OpenSSL format: "Salted__" + salt(8) + ciphertext -> base64
class EncryptionService {
  static const String _key = ApiConstants.sas4EncryptionKey;

  static dynamic decrypt(String encrypted) {
    try {
      final bytes = base64.decode(encrypted);
      if (bytes.length < 16) return null;

      final prefix = utf8.decode(bytes.sublist(0, 8), allowMalformed: true);
      if (prefix != 'Salted__') return null;

      final salt = bytes.sublist(8, 16);
      final cipherText = bytes.sublist(16);

      final derived = _evpBytesToKey(_key, salt, 32, 16);
      final key = derived.sublist(0, 32);
      final iv = derived.sublist(32, 48);

      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      );

      cipher.init(
        false,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );

      final decrypted = cipher.process(Uint8List.fromList(cipherText));
      final jsonString = utf8.decode(decrypted);
      return jsonDecode(jsonString);
    } catch (_) {
      return null;
    }
  }

  static String encrypt(dynamic data) {
    final jsonString = jsonEncode(data);
    final salt = _generateRandomBytes(8);
    final derived = _evpBytesToKey(_key, salt, 32, 16);
    final key = derived.sublist(0, 32);
    final iv = derived.sublist(32, 48);

    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );

    cipher.init(
      true,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );

    final inputBytes = Uint8List.fromList(utf8.encode(jsonString));
    final encrypted = cipher.process(inputBytes);

    // OpenSSL format: "Salted__" + salt + ciphertext
    final output = Uint8List(8 + 8 + encrypted.length);
    output.setAll(0, utf8.encode('Salted__'));
    output.setAll(8, salt);
    output.setAll(16, encrypted);

    return base64.encode(output);
  }

  /// EVP_BytesToKey key derivation (MD5-based, OpenSSL compatible)
  static Uint8List _evpBytesToKey(
    String password,
    Uint8List salt,
    int keyLen,
    int ivLen,
  ) {
    final passBytes = Uint8List.fromList(utf8.encode(password));
    final totalLen = keyLen + ivLen;
    final result = Uint8List(totalLen);
    var offset = 0;
    Uint8List? prev;

    while (offset < totalLen) {
      final md5 = MD5Digest();
      if (prev != null) {
        md5.update(prev, 0, prev.length);
      }
      md5.update(passBytes, 0, passBytes.length);
      md5.update(salt, 0, salt.length);

      prev = Uint8List(md5.digestSize);
      md5.doFinal(prev, 0);

      final copyLen =
          (totalLen - offset) < prev.length ? (totalLen - offset) : prev.length;
      result.setRange(offset, offset + copyLen, prev);
      offset += copyLen;
    }
    return result;
  }

  static Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
