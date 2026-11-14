import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/net/zte_ont_service.dart';

/// كلمة سرّ الواي فاي على الراوتر الضوئيّ ZTE/ZXIC (المالك ١٤ نوفمبر: «راوترات الضوئي… نكدر نظهر الرمز مال وايرلس مالتهم وهم
/// نغيره؟» ثمّ «يجلب الرمز ويغيره ان امكن»).
///
/// الصفحة من جهاز فحص المالك H.T.M HS8546V2 (حساب user) منقّحةً: كلّ اسم شبكةٍ وكلمةٍ وماكٍ ورمز جلسةٍ مزيّف. فيها الكلمة
/// صريحة (`Transfer_meaning('KeyPassphrase','…')`) والنجوم من حقل المتصفّح وحده — والحفظ نموذجها `fSubmit` كما يبنيه سكربتها
/// `pageSubmit` حرفاً.
void main() {
  final page = File('test/fixtures/zte_wifi/hs8546v2_security_wlan1.html').readAsStringSync();

  Map<String, String> fields(String body) => {
        for (final kv in body.split('&'))
          Uri.decodeQueryComponent(kv.split('=').first): Uri.decodeQueryComponent(kv.substring(kv.indexOf('=') + 1)),
      };
  List<String> order(String body) => [for (final kv in body.split('&')) Uri.decodeQueryComponent(kv.split('=').first)];

  group('الصفحة في قائمة الحساب', () {
    test('اسمها بخطئها الإملائيّ عند ZTE، والصحيح احتياطاً، ولا شيء حين لا تكون', () {
      expect(ZteOntParse.wifiPage({'status_dev_info_t.gch', 'net_wlan_secrity_t.gch'}), 'net_wlan_secrity_t.gch');
      expect(ZteOntParse.wifiPage({'net_wlan_security_t.gch'}), 'net_wlan_security_t.gch');
      expect(ZteOntParse.wifiPage({'net_wlan_essid_t.gch', 'status_wlaninfo_t.gch'}), isNull);
    });
  });

  group('القراءة', () {
    test('الشبكة المعروضة بكلمتها الصريحة ونطاقها ونمط أمانها، والمنتقي بثماني شبكات', () {
      final f = ZteOntParse.wifiForm(page)!;
      expect(f.view, 'IGD.LD1.WLAN1');
      expect(f.refs, hasLength(8));
      expect(f.refs[4], 'IGD.LD1.WLAN5');
      expect(f.mode, ZteWifiMode.wpa2);
      expect(f.token, 'FAKETOKEN0123456');
      final n = f.network;
      expect(n.password, 'OldPass123');
      expect(n.band, '2.4G');
      expect(n.ssid, 'TestNet-24');
      expect(n.security, 'WPA2');
      expect(n.enabled, isTrue);
      expect(n.ref, 'IGD.LD1.WLAN1');
      expect(f.secondBandRef, 'IGD.LD1.WLAN5', reason: 'ثنائيّ النطاق: الخامسة أوّل النصف الثاني');
    });

    test('شبكةٌ مفتوحة أو WEP: لا كلمة شخصيّة تُعرض ولا تُغيَّر', () {
      final open = page.replaceAll("Transfer_meaning('BeaconType','11i')", "Transfer_meaning('BeaconType','None')");
      final f = ZteOntParse.wifiForm(open)!;
      expect(f.mode, isNull);
      expect(f.network.password, isNull);
      expect(f.network.security, 'مفتوحة');
      expect(ZteOntParse.wifiApplyBody(open, 'NewPass456'), isNull, reason: 'لا نرسل شيئاً');
    });

    test('صيغةٌ لا نعرفها ⇒ null: بلا نموذج، أو بلا مصفوفتي التصفير، أو رمز جلسةٍ مطلوبٍ لا نجده، أو صفحة «انتهت الجلسة»', () {
      expect(ZteOntParse.wifiForm(page.replaceAll('fSubmit', 'fOther')), isNull);
      expect(ZteOntParse.wifiForm(page.replaceAll('CONFIG_PARA', 'CFG_X')), isNull);
      expect(ZteOntParse.wifiForm(page.replaceAll(RegExp(r'var\s+session_token\s*=\s*"[^"]*";'), '')), isNull);
      expect(ZteOntParse.wifiForm('<html><script>logout_redirect();</script>Session timeout</html>'), isNull);
    });
  });

  group('الحفظ — ما يرسله pageSubmit حرفاً', () {
    test('كلّ إعدادٍ NULL (لا يُمسّ) إلّا نمط الأمان وتشفيره الحاليّان والكلمة الجديدة، بأمر apply والشبكة نفسها ورمز الجلسة', () {
      final body = ZteOntParse.wifiApplyBody(page, 'New Pass#456')!;
      final v = fields(body);
      expect(v['IF_ACTION'], 'apply');
      expect(v['IF_CONFIGTAG'], 'Y');
      expect(v['IF_PSKTAG'], 'Y');
      expect(v['IF_WEPKEYTAG'], 'N');
      expect(v['IF_VIEWID'], 'IGD.LD1.WLAN1');
      expect(v['KeyPassphrase'], 'New Pass#456');
      expect(v['BeaconType'], '11i');
      expect(v['11iAuthMode'], 'PSKAuthentication');
      expect(v['11iEncryptType'], 'AESEncryption', reason: 'التشفير الحاليّ كما هو');
      for (final n in ['Enable', 'RadioStatus', 'Channel', 'ESSID', 'TxPower', 'WPAAuthMode', 'WPAEncryptType', 'WPA3SAEAuthMode']) {
        expect(v[n], 'NULL', reason: '$n لا يُمسّ');
      }
      expect(v['PreSharedKey'], 'NULL');
      expect(v['AssociatedDeviceMACAddress'], 'NULL');
      expect(v['_SESSION_TOKEN'], 'FAKETOKEN0123456');
      expect(body.contains('OldPass123'), isFalse, reason: 'الكلمة القديمة لا تُرسل');
    });

    test('ترتيب الحقول ترتيب النموذج، ورمز الجلسة آخرها؛ ولا أمر ضبط مصنعٍ أو إقلاعٍ أبداً', () {
      final body = ZteOntParse.wifiApplyBody(page, 'NewPass456')!;
      final o = order(body);
      expect(o.first, 'IF_ACTION');
      expect(o.last, '_SESSION_TOKEN');
      expect(o.indexOf('KeyPassphrase'), greaterThan(o.indexOf('PreSharedKey')));
      expect(o.toSet().length, o.length, reason: 'لا حقل مكرّر');
      for (final bad in ['devrestore', 'devrestart', 'restore', 'factory', 'reboot']) {
        expect(body.toLowerCase().contains(bad), isFalse, reason: bad);
      }
    });

    test('مدّة تجديد المفتاح بلا أصفارٍ أولى (RmZero) — كما يفعل سكربت الصفحة', () {
      final p = page.replaceAll(RegExp(r"Transfer_meaning\('WPAGroupRekey','[^']*'\)"), "Transfer_meaning('WPAGroupRekey','03600')");
      expect(fields(ZteOntParse.wifiApplyBody(p, 'NewPass456')!)['WPAGroupRekey'], '3600');
      expect(ZteOntParse.rmZero('0000'), '0');
      expect(ZteOntParse.rmZero('600'), '600');
      expect(ZteOntParse.rmZero(''), '');
    });

    test('أنماط الأمان الأخرى: كلٌّ بحقوله كما في pageSetValue', () {
      String withMode(String bt) => page.replaceAll("Transfer_meaning('BeaconType','11i')", "Transfer_meaning('BeaconType','$bt')");
      final both = fields(ZteOntParse.wifiApplyBody(withMode('WPAand11i'), 'NewPass456')!);
      expect(both['BeaconType'], 'WPAand11i');
      expect(both['WPAAuthMode'], 'PSKAuthentication');
      expect(both['11iAuthMode'], 'PSKAuthentication');
      expect(both['11iEncryptType'], both['WPAEncryptType'], reason: 'الاثنان من منتقي التشفير نفسه');
      final w3 = fields(ZteOntParse.wifiApplyBody(withMode('WPA3SAE'), 'NewPass456')!);
      expect(w3['BeaconType'], 'WPA3SAE');
      expect(w3['WPA3SAEAuthMode'], 'PSKAuthentication');
      expect(w3['WPAGroupRekey'], 'NULL', reason: 'WPA3 بلا تجديد مفتاح في سكربت الصفحة');
      final w = fields(ZteOntParse.wifiApplyBody(withMode('WPA'), 'NewPass456')!);
      expect(w['BeaconType'], 'WPA');
      expect(w['WPAAuthMode'], 'PSKAuthentication');
      expect(w['11iAuthMode'], 'NULL');
    });
  });

  group('منتقي الشبكة (ESSID_Choose)', () {
    test('النموذج بقيمه كما هي بلا أمر وشبكةٌ أخرى ⇒ لا حفظ', () {
      final body = ZteOntParse.wifiViewBody(page, 'IGD.LD1.WLAN5')!;
      final v = fields(body);
      expect(v['IF_VIEWID'], 'IGD.LD1.WLAN5');
      expect(v['IF_ACTION'], '', reason: 'لا apply');
      expect(v['BeaconType'], '11i', reason: 'القيم كما هي — لا NULL');
      expect(v['_SESSION_TOKEN'], 'FAKETOKEN0123456');
    });

    test('شبكةٌ ليست في المنتقي أو صفحةٌ تحمل أمراً ⇒ لا شيء يُرسل', () {
      expect(ZteOntParse.wifiViewBody(page, 'IGD.LD1.WLAN9'), isNull);
      final acting = page.replaceAll("Transfer_meaning('IF_ACTION','')", "Transfer_meaning('IF_ACTION','apply')");
      expect(ZteOntParse.wifiViewBody(acting, 'IGD.LD1.WLAN5'), isNull);
    });
  });
}
