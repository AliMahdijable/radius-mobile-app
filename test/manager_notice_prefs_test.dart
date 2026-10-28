import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/manager_notice_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «الاسهم الافتراضيه… يحفظهن مره وحده ويبقن ثابتات» (المالك ٢٨ أكتوبر): اختيارات واتساب/التطبيق/تلغرام بنوافذ المدير الفرعيّ
/// تُحفظ لكلّ حسابٍ على الجهاز، وغيابها = الافتراضيّ القديم.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth.admin_id': '2251'});
  });

  test('بلا حفظٍ سابق ⇒ الافتراضيّ القديم (واتساب ✓، التطبيق ✓، تلغرام ✗)', () async {
    final p = await ManagerNoticePrefs.load();
    expect(p, ManagerNoticePrefs.defaults);
    expect(p.whatsApp && p.push && !p.telegram, isTrue);
  });

  test('يُحفظ مرّةً ويبقى — والحساب الآخر على الجهاز نفسه بافتراضيّه', () async {
    await ManagerNoticePrefs.save(whatsApp: false, push: true, telegram: true);
    expect(await ManagerNoticePrefs.load(), (whatsApp: false, push: true, telegram: true));
    await ManagerNoticePrefs.save(whatsApp: false, push: false, telegram: false);
    expect(await ManagerNoticePrefs.load(), (whatsApp: false, push: false, telegram: false));
    FlutterSecureStorage.setMockInitialValues({'auth.admin_id': 'speednet-iq:77'});
    expect(await ManagerNoticePrefs.load(), ManagerNoticePrefs.defaults);
  });

  test('قيمةٌ تالفة ⇒ الافتراضيّ', () async {
    SharedPreferences.setMockInitialValues({'mgr.notice.v1.2251': '1x0'});
    expect(await ManagerNoticePrefs.load(), ManagerNoticePrefs.defaults);
    SharedPreferences.setMockInitialValues({'mgr.notice.v1.2251': '10'});
    expect(await ManagerNoticePrefs.load(), ManagerNoticePrefs.defaults);
  });
}
