// تحقّقٌ بعد نشر الخادم 2edbcb5 (١٠ نوفمبر): نتيجة «فحص الآن» للأجهزة كما يولّدها كود الخادم المنشور نفسه (قرّاء prober/oltRead
// الحقيقيّة على أجهزةٍ وهميّة ⇒ sweeper.checkDevicesNow ⇒ agentRoutes.summarizeDevices) تُقرأ بمحلّل التطبيق 180 كما هو:
// reg_ok · radio · lw/lr · v_at_ms ⇒ «قُرئ» يُفصل عن «لم يُقرأ». والنتيجة نفسها بلا الحقول (خادمٌ أقدم) ⇒ الخطآن القديمان.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/merged_devices_check.dart';

NetworkDevice dev(int id, {required String type, String brand = 'mikrotik', String protocol = 'api'}) => NetworkDevice(
      id: id,
      adminId: '9',
      name: 'جهاز $id',
      type: type,
      brand: brand,
      ip: '10.10.1.$id',
      port: brand == 'mikrotik' ? 8728 : 161,
      protocol: protocol,
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

List<String> texts(DeviceCheckReport r) => [for (final f in r.findings) f.text];

void main() {
  final raw = jsonDecode(File('test/fixtures/server_devices_now_1110.json').readAsStringSync()) as Map<String, dynamic>;
  final devices = {
    61: dev(61, type: 'sector'),
    62: dev(62, type: 'router'),
    63: dev(63, type: 'router'),
    64: dev(64, type: 'sector'),
    70: dev(70, type: 'other', brand: 'hsgq', protocol: 'snmp'),
  };

  Map<int, DeviceCheckReport> judge(Map<String, dynamic> json, {Map<int, CheckMemo> prev = const {}}) {
    final res = VpnNowResult.fromJson(json);
    final by = {for (final d in res.devices) d.id: d};
    final now = DateTime.fromMillisecondsSinceEpoch(res.atMs!);
    return {
      for (final e in devices.entries)
        e.key: MergedDevicesCheckRunner.remoteReport(e.value, by[e.key], const CheckLimits(), prev[e.key], const {},
            serverAtMs: res.atMs, now: now),
    };
  }

  test('المحلّل يقرأ الحقول بأسمائها: v_at_ms ⇒ readAtMs، وv فيه reg_ok/radio/lw/lr', () {
    final res = VpnNowResult.fromJson(raw);
    expect(res.ok, isTrue);
    expect(res.atMs, isNotNull);
    final by = {for (final d in res.devices) d.id: d};
    for (final id in [61, 62, 63, 64, 70]) {
      expect(by[id]!.readAtMs, (raw['devices'] as List).firstWhere((x) => x['id'] == id)['v_at_ms'], reason: '$id');
      expect(by[id]!.readAtMs! <= res.atMs!, isTrue);
    }
    expect(by[13]!.vitals, isNull);
    expect(by[13]!.readAtMs, isNull);
    expect([by[61]!.vitals!['reg_ok'], by[62]!.vitals!['radio'], by[63]!.vitals!['radio'], by[64]!.vitals!['reg_ok']],
        [true, true, false, false]);
    expect([by[70]!.vitals!['lw'], by[70]!.vitals!['lr']], [4, 2]);
  });

  test('🚨 «كل الشركات»: سكتر مايكروتك بلا عملاء والخادم قرأ جدوله ⇒ «ما عليه أحد الآن» لا «لم يُقرأ»', () {
    final r = judge(raw, prev: {61: const CheckMemo(peers: 7)})[61]!;
    expect(r.state, isNot(CheckState.unread));
    expect(texts(r), contains('ما عليه أحد الآن — كانوا 7 بالفحص السابق'));
    expect(judge(raw)[61]!.state, CheckState.ok, reason: 'بلا فحصٍ سابق: «ما عليه أحد الآن» معلومة');
  });

  test('🚨 نقطة وصولٍ بحزمة wifi محفوظة «راوتر» بلا عملاء ⇒ لا «سليم» (radio: true بلا ap)؛ والراوتر بلا راديو «سليم»', () {
    final r = judge(raw);
    expect(r[62]!.state, isNot(CheckState.ok));
    expect(r[62]!.state, CheckState.unread);
    // ١٠ نوفمبر (قرار المالك): قائمته قُرئت (reg_ok) ووضعه وحده مجهول ⇒ بلا «ومشتركوه»، و«لم يُقرأ» ما لم يقل الخادم إنّ راديوه يعمل
    expect(texts(r[62]!), contains('وضعه اللاسلكيّ ما انقرأ'));
    expect(r[63]!.state, CheckState.ok);
  });

  test('سكتر جدوله لم يُجب (reg_ok: false) ⇒ «قائمة مشتركيه ما انقرت» و«لم يُقرأ»', () {
    final r = judge(raw)[64]!;
    expect(r.state, CheckState.unread);
    expect(texts(r), contains('قائمة مشتركيه ما انقرت'));
  });

  test('الأولت: lw/lr ⇒ «قُرئ 1 من 4 — الباقي لم يقرأه الخادم» و«بلا قراءة ضوء: 1»، وبعمره من v_at_ms لا «حتى 30 د»', () {
    final r = judge(raw)[70]!;
    expect(r.role, CheckRole.olt);
    expect(r.lightsWanted, 4);
    expect(texts(r), containsAll(['الضوء: قُرئ 1 من 4 — الباقي لم يقرأه الخادم', 'بلا قراءة ضوء: 1']));
    expect(r.bucket, isNot(CheckBucket.stale), reason: 'قراءةٌ بلحظتها من هذا الفحص');
  });

  test('المقارنة: النتيجة نفسها بلا الحقول (خادمٌ أقدم) ⇒ الخطآن القديمان — السكتر «لم يُقرأ» ونقطة الوصول «سليم»، والأولت «حتى 30 د»', () {
    final old = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    for (final d in (old['devices'] as List).cast<Map<String, dynamic>>()) {
      d.remove('v_at_ms');
      final v = d['v'];
      if (v is Map) {
        for (final k in ['reg_ok', 'radio', 'lw', 'lr']) {
          v.remove(k);
        }
      }
    }
    final r = judge(old, prev: {61: const CheckMemo(peers: 7)});
    expect(r[61]!.state, CheckState.unread);
    expect(texts(r[61]!), contains('قائمة مشتركيه ما انقرت'));
    expect(r[62]!.state, CheckState.ok);
    expect(r[70]!.bucket, CheckBucket.stale);
  });
}
