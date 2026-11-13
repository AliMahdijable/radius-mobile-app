// ساسٌ بطيء (١٣ نوفمبر ٢٠٢٦ — بلاغ «فايبر لنك كربلاء»): القائمة لم تصل ⇒ السبب لا «لا يوجد مشترك»،
// والنبضة لا تبدأ فوق نبضةٍ جارية، وطلب «المتّصلين» الجاري يُنتظَر ولا يُكرَّر.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';

void main() {
  group('نصّ فشل القائمة', () {
    test('رسالة الخادم العربيّة (503 SAS_UNREACHABLE) تُعرض كما هي', () {
      const msg = 'ساس الشركة لا يستجيب الآن — أعد المحاولة بعد قليل';
      expect(
        SubscribersApi.listErrorText({'success': false, 'code': 'SAS_UNREACHABLE', 'message': msg}),
        msg,
      );
    });

    test('مهلة التطبيق (٣٠ث) ⇒ «سيرفر الشركة بطيء» لا رسالة الخادم', () {
      final t = SubscribersApi.listErrorText({'message': 'x'}, timedOut: true);
      expect(t, contains('بطيء'));
      expect(t, contains('٣٠'));
    });

    test('بلا رسالة أو بجسمٍ غريب ⇒ نصٌّ عامّ عربيّ، لا فراغ', () {
      for (final body in <Object?>[null, 'x', 42, <String, dynamic>{}, {'message': '   '}]) {
        final t = SubscribersApi.listErrorText(body);
        expect(t, contains('تعذّر'), reason: '$body');
      }
    });

    test('قبل أيّ جلب: لا خطأ محفوظ', () {
      expect(SubscribersApi.lastListError, isNull);
    });
  });

  // حرّاس المصدر: السلوك حيّ داخل الشاشة (حالة خاصّة) فيُثبَّت بنصّه.
  group('حرّاس المصدر', () {
    final screen = File('lib/screens/subscribers/subscribers_screen.dart').readAsStringSync();
    final api = File('lib/api/subscribers_api.dart').readAsStringSync();

    test('النبضة الصامتة: لا تبدأ فوق جارية، والعلم يُرفع في finally', () {
      final start = screen.indexOf('Future<void> _silentRefresh() async {');
      expect(start, greaterThan(0));
      final end = screen.indexOf('void didChangeAppLifecycleState', start);
      final body = screen.substring(start, end);
      final guard = body.indexOf('if (_silentBusy) return;');
      final set = body.indexOf('_silentBusy = true;');
      final fetch = body.indexOf('await _fetchAndMerge(quiet: true);');
      expect(guard, greaterThan(0));
      expect(set, greaterThan(guard));
      expect(fetch, greaterThan(set));
      expect(body.indexOf('} finally {\n      _silentBusy = false;'), greaterThan(fetch));
    });

    test('«المتّصلون»: الطلب الجاري لنفس التوكن يُعاد ولا يُكرَّر، ويُنظَّف بعد انتهائه', () {
      final start = api.indexOf('static Future<Map<String, OnlineSessionInfo>?> loadOnline() async {');
      expect(start, greaterThan(0));
      final body = api.substring(start, api.indexOf('static Future<Map<String, OnlineSessionInfo>?> _loadOnline(', start));
      expect(body, contains('if (running != null && _onlineInFlightToken == token) return running;'));
      expect(body, contains('if (identical(_onlineInFlight, f)) {'));
    });

    test('القائمة الفارغة لسبب فشلٍ تعرض السبب وزرّ الإعادة (ليس للكبير ولا «كل الشركات»)', () {
      expect(screen, contains('error: !_big && !_mergedOn && _all.isEmpty'));
      expect(screen, contains('? SubscribersApi.lastListError'));
      expect(screen, contains("if (error != null && query.isEmpty) return _failed(error!);"));
      expect(screen, contains('تعذّر جلب المشتركين من سيرفر الشركة'));
    });
  });
}
