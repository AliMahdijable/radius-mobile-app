// «جهازك غير متوافق» في Google Play — حارس المانيفست.
//
// Play يحجب التطبيق عن أيّ جهازٍ ينقصه عتادٌ «مطلوب»، وبعض الأذونات تجعل
// العتاد مطلوباً ضمناً ما لم يُصرَّح له بـ android:required="false".
// حادثة ١٤ نوفمبر: RECORD_AUDIO ⇒ android.hardware.microphone ⇒ أجهزة الكاشير
// SUNMI V2 SE (بلا مايك) لا ترى التطبيق في المتجر. ومثلها قبلها الموقع والبلوتوث.
//
// يقرأ المانيفست المصدريّ وحده؛ المدمج (مع أذونات الإضافات) يفحصه
// check_artifact.py على ملفّ الـAPK عند الإصدار («Play device filter»).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الأذونات التي يشترط Play بسببها عتاداً — جدول «Permissions that imply
/// feature requirements» في توثيق Play (أوسع قليلاً من aapt2 احتياطاً).
const _implied = <String, List<String>>{
  'android.permission.RECORD_AUDIO': ['android.hardware.microphone'],
  'android.permission.CAMERA': ['android.hardware.camera', 'android.hardware.camera.autofocus'],
  'android.permission.BLUETOOTH': ['android.hardware.bluetooth'],
  'android.permission.BLUETOOTH_ADMIN': ['android.hardware.bluetooth'],
  'android.permission.ACCESS_FINE_LOCATION': ['android.hardware.location', 'android.hardware.location.gps'],
  'android.permission.ACCESS_COARSE_LOCATION': ['android.hardware.location', 'android.hardware.location.network'],
  'android.permission.ACCESS_MOCK_LOCATION': ['android.hardware.location'],
  'android.permission.ACCESS_LOCATION_EXTRA_COMMANDS': ['android.hardware.location'],
  'android.permission.ACCESS_WIFI_STATE': ['android.hardware.wifi'],
  'android.permission.CHANGE_WIFI_STATE': ['android.hardware.wifi'],
  'android.permission.CHANGE_WIFI_MULTICAST_STATE': ['android.hardware.wifi'],
  'android.permission.CALL_PHONE': ['android.hardware.telephony'],
  'android.permission.CALL_PRIVILEGED': ['android.hardware.telephony'],
  'android.permission.MODIFY_PHONE_STATE': ['android.hardware.telephony'],
  'android.permission.PROCESS_OUTGOING_CALLS': ['android.hardware.telephony'],
  'android.permission.READ_SMS': ['android.hardware.telephony'],
  'android.permission.RECEIVE_SMS': ['android.hardware.telephony'],
  'android.permission.RECEIVE_MMS': ['android.hardware.telephony'],
  'android.permission.RECEIVE_WAP_PUSH': ['android.hardware.telephony'],
  'android.permission.SEND_SMS': ['android.hardware.telephony'],
  'android.permission.WRITE_APN_SETTINGS': ['android.hardware.telephony'],
  'android.permission.WRITE_SMS': ['android.hardware.telephony'],
};

Iterable<String> _tags(String xml, String tag) =>
    RegExp('<$tag\\b[^>]*>', dotAll: true).allMatches(xml).map((m) => m[0]!);

String? _attr(String tag, String name) =>
    RegExp('android:$name\\s*=\\s*"([^"]*)"').firstMatch(tag)?.group(1);

void main() {
  // التعليقات تذكر «uses-feature … required=true» نصّاً — تُحذف قبل القراءة.
  final xml = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final perms = _tags(xml, 'uses-permission').map((t) => _attr(t, 'name')).whereType<String>().toSet();
  final features = <String, String?>{
    for (final t in _tags(xml, 'uses-feature'))
      if (_attr(t, 'name') != null) _attr(t, 'name')!: _attr(t, 'required'),
  };

  test('كلّ عتادٍ تشترطه الأذونات ضمناً مصرَّحٌ له required="false"', () {
    final missing = [
      for (final p in perms)
        for (final f in _implied[p] ?? const <String>[])
          if (features[f] != 'false') '$f ← $p',
    ];
    expect(missing, isEmpty,
        reason: 'أضف <uses-feature android:name="…" android:required="false"/> وإلّا حجب Play كلّ جهازٍ بلا هذا العتاد');
  });

  test('لا عتاد مطلوباً صراحةً', () {
    final required = [for (final e in features.entries) if (e.value != 'false') e.key];
    expect(required, isEmpty);
  });

  test('المايكروفون اختياريّ — أجهزة الكاشير SUNMI بلا مايك (١٤ نوفمبر)', () {
    expect(perms, contains('android.permission.RECORD_AUDIO'));
    expect(features['android.hardware.microphone'], 'false');
  });
}
