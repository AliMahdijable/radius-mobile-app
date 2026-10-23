import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// تشفير ويندوز للمستخدم (DPAPI): ما يُشفَّر هنا لا يفكّه إلّا حساب ويندوز نفسه على الجهاز نفسه — وهو
/// ما كانت إضافة flutter_secure_storage تفعله بملفّها، بلا مكتبةٍ إضافيّة (crypt32 من النظام).
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);
typedef _UnprotectNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _UnprotectDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> mem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> mem);

/// بلا واجهة: لا نافذة تسأل المستخدم شيئاً.
const int _cryptprotectUiForbidden = 0x1;

class WindowsDpapi {
  WindowsDpapi._();

  static final DynamicLibrary _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _protect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData');
  static final _unprotect = _crypt32.lookupFunction<_UnprotectNative, _UnprotectDart>('CryptUnprotectData');
  static final _localFree = _kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');

  static Uint8List protect(List<int> plain) => _run(plain, encrypt: true);

  /// يرمي إن لم تكن البيانات مشفّرةً لهذا المستخدم على هذا الجهاز.
  static Uint8List unprotect(List<int> cipher) => _run(cipher, encrypt: false);

  static Uint8List _run(List<int> data, {required bool encrypt}) {
    final input = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buf.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buf;
      final ok = encrypt
          ? _protect(input, nullptr, nullptr, nullptr, nullptr, _cryptprotectUiForbidden, output)
          : _unprotect(input, nullptr, nullptr, nullptr, nullptr, _cryptprotectUiForbidden, output);
      if (ok == 0) throw StateError(encrypt ? 'CryptProtectData failed' : 'CryptUnprotectData failed');
      final out = Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      _localFree(output.ref.pbData.cast());
      return out;
    } finally {
      calloc.free(buf);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
