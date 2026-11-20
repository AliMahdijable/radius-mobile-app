import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/core/util/phone.dart';
import 'package:rad_mysvcs/services/manual_wa_sender.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// رقم الواتساب بصيغته الدوليّة في كلّ رابط (٢١ نوفمبر — المالك بصورة وكيل: «Couldn't look up phone number 07812180744 …
/// missing a country code»، ثمّ: «٠٧x / 0096 … الدالة العدنا تسوي هيج نوع تصحيح، تأكّد من تعميمها بالعمليات اليدوي والجداول
/// والتلقائي»، و«هذا الزر لاتنساها» — أيقونة المحادثة بجانب الرقم في صفحة المشترك).
class _FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final launched = <String>[];
  bool appInstalled = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => url.startsWith('whatsapp:') ? appInstalled : true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

const _want = '9647812180744';
const _iraqForms = <String>[
  '07812180744',
  '٠٧٨١٢١٨٠٧٤٤', // أرقامٌ عربيّة
  '۰۷۸۱۲۱۸۰۷۴۴', // فارسيّة
  '٠٧٨١٢١8٠٧٤٤', // مخلوطة
  '7812180744',
  '9647812180744',
  '+9647812180744',
  '+964 781 218 0744',
  '009647812180744',
  '00964 781-218-0744',
  '96407812180744', // مفتاحٌ ثمّ صفرٌ زائد
  '+964 0781 218 0744',
  '(0781) 218-0744',
  '‎0781 218 0744‏', // علامات اتّجاه
];

void main() {
  group('waPhone — القواعد (نفسها في الخادم phoneNorm.js والموقع wa-phone.ts)', () {
    for (final f in _iraqForms) {
      test('«$f» ⇒ $_want', () => expect(waPhone(f), _want));
    }
    test('الأجنبيّ كما هو بلا + ولا 00', () {
      expect(waPhone('+44 7911 123456'), '447911123456');
      expect(waPhone('00447911123456'), '447911123456');
    });
    test('الناقص لا يُخترع له رقم، والفارغ فارغ', () {
      expect(waPhone('0781218074'), '0781218074');
      expect(waPhone(''), '');
      expect(waPhone('—'), '');
    });
    test('latinDigits: العربيّة والفارسيّة لاتينيّة والباقي كما هو', () {
      expect(latinDigits('٠١٢٣٤٥٦٧٨٩ ۰۱۲۳۴۵۶۷۸۹ abc+'), '0123456789 0123456789 abc+');
    });
    test('localPhone (الاتّصال والنسخ) كما كان', () {
      expect(localPhone('9647812180744'), '07812180744');
      expect(localPhone('07812180744'), '07812180744');
    });
  });

  group('openManualWa — الإرسال اليدويّ (القوالب، بعد العمليّات، المدراء، تنبيه الاتّصال، الألياف)', () {
    late _FakeLauncher fake;
    late UrlLauncherPlatform saved;
    setUp(() {
      saved = UrlLauncherPlatform.instance;
      fake = _FakeLauncher();
      UrlLauncherPlatform.instance = fake;
    });
    tearDown(() => UrlLauncherPlatform.instance = saved);

    for (final f in ['07812180744', '٠٧٨١٢١٨٠٧٤٤', '009647812180744', '7812180744', '+964 781 218 0744']) {
      test('«$f» ⇒ whatsapp://send?phone=$_want', () async {
        expect(await openManualWa(phone: f, message: 'تذكير: دينك 60,000'), isTrue);
        expect(fake.launched, hasLength(1));
        final u = Uri.parse(fake.launched.single);
        expect([u.scheme, u.queryParameters['phone'], u.queryParameters['text']], ['whatsapp', _want, 'تذكير: دينك 60,000']);
      });
    }

    test('واتساب غير مثبَّت ⇒ wa.me بالرقم الدوليّ نفسه', () async {
      fake.appInstalled = false;
      expect(await openManualWa(phone: '07812180744', message: 'x'), isTrue);
      expect(Uri.parse(fake.launched.single).toString(), 'https://wa.me/$_want?text=x');
    });

    test('بلا رقم ⇒ لا يفتح شيئاً', () async {
      expect(await openManualWa(phone: '—', message: 'x'), isFalse);
      expect(fake.launched, isEmpty);
    });
  });

  test('رابط واتساب الدعم في جواب المساعد: «٠٧…» و«7…» دوليّان، والرابط الغريب يُرفض', () {
    String? wa(Object? v) => AiSupport.fromJson({'whatsapp': v})?.whatsapp?.toString();
    expect(wa('٠٧٨١٢١٨٠٧٤٤'), 'https://wa.me/$_want');
    expect(wa('7812180744'), 'https://wa.me/$_want');
    expect(wa('009647812180744'), 'https://wa.me/$_want');
    expect(wa('https://wa.me/$_want'), 'https://wa.me/$_want');
    expect(wa('https://wa.me.evil.example/1'), isNull);
  });

  /// كلّ رابط واتساب في التطبيق يُبنى من [waPhone] — رابطٌ جديد برقمٍ خامٍ يُسقط هذا الاختبار قبل أن يصل وكيلاً
  /// («هذا الزر لاتنساها»: أيقونة المحادثة بجانب الرقم في صفحة المشترك كانت تحذف ما ليس رقماً وحده).
  test('🚨 حارس: لا رابط واتساب في lib/ برقمٍ غير مطبَّع', () {
    final link = RegExp(r'''(?:wa\.me/|whatsapp://send\?phone=)\$(\{([^}]*)\}|([A-Za-z_]\w*))''');
    final found = <String>[];
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in link.allMatches(src)) {
        final expr = (m.group(2) ?? m.group(3) ?? '').trim();
        final where = '${f.path}: $expr';
        found.add(where);
        final ok = expr.startsWith('waPhone(') ||
            RegExp(r'^_(?:digits|intlDigits)\(').hasMatch(expr) ||
            // متغيّرٌ محلّيّ: مُسنَدٌ من waPhone في الملفّ نفسه
            (RegExp(r'^[a-z]\w*$').hasMatch(expr) && RegExp('\\b$expr\\s*=\\s*(?:[^;]*\\?\\s*)?waPhone\\(').hasMatch(src));
        if (!ok) bad.add(where);
      }
    }
    expect(found.length, greaterThanOrEqualTo(8), reason: 'الحارس لم يجد الروابط (تغيّر شكلها؟): $found');
    expect(bad, isEmpty, reason: 'روابط واتساب برقمٍ غير مطبَّع:\n${bad.join('\n')}');
    final detail = File('lib/screens/subscribers/subscriber_detail_screen.dart').readAsStringSync();
    expect(detail, contains('static String _digits(String phone) => waPhone(phone);'));
    expect(detail, contains('static String _intlDigits(String raw) => waPhone(raw);'));
  });
}
