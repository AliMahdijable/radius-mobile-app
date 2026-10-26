// الاستطلاع الصامت لشاشة المشتركين (٢٦ أكتوبر، المالك: «تخفيف الطلبات المتكرّرة»): كلّ ٥ ثوانٍ كان يطلب «آخر الدفعات»
// و«روابط تلغرام» مع المتصلين (~٤٥ ألف طلبٍ يوميّاً منهما وحدهما)، وهما لا تتغيّران إلّا بعمليّة — والعمليّة تمرّ بالتحديث
// الكامل. الآن المتصلون كلّ ٥ ثوانٍ كما كانوا، وهاتان كلّ دقيقة. خادم الصلاحيّات الوهميّ يعدّ الطلبات.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/subscriber_events.dart';

import 'visual_perm/visual_perm_harness.dart';

class _Counting implements HttpClientAdapter {
  _Counting(this.inner);

  final HttpClientAdapter inner;
  final List<String> paths = [];

  int count(String prefix) => paths.where((p) => p.startsWith(prefix)).length;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) {
    paths.add(o.uri.path);
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

const _online = '/api/v2/online-users';
const _payments = '/api/subscribers/last-financial-movements/';
const _telegram = '/api/telegram/bindings/';

Future<void> _tick(WidgetTester t, int ticks) async {
  for (var i = 0; i < ticks; i++) {
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('المتصلون كلّ ٥ ثوانٍ كما كانوا، و«آخر الدفعات» و«روابط تلغرام» كلّ دقيقة لا كلّ ٥ ثوانٍ', (t) async {
    final srv = _Counting(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = srv;
    SubscribersApi.clearAllCaches();
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 2);

    final online0 = srv.count(_online);
    final pay0 = srv.count(_payments);
    final tg0 = srv.count(_telegram);
    expect(pay0, greaterThanOrEqualTo(1), reason: 'التحميل الأوّل يأخذهما');
    expect(tg0, greaterThanOrEqualTo(1));

    await _tick(t, 6); // ٣٠ ثانية
    expect(srv.count(_online) - online0, greaterThanOrEqualTo(5), reason: 'المتصلون كلّ ٥ ثوانٍ');
    expect(srv.count(_payments) - pay0, 0, reason: 'لا «آخر دفعات» داخل الدقيقة');
    expect(srv.count(_telegram) - tg0, 0, reason: 'ولا «روابط تلغرام»');

    await _tick(t, 7); // تجاوزت الدقيقة
    expect(srv.count(_payments) - pay0, 1, reason: 'مرّةً بعد الدقيقة');
    expect(srv.count(_telegram) - tg0, 1);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('بعد عمليّة (تغيّر البيانات) ⇒ تحديثٌ كامل يأخذهما فوراً — لا انتظار الدقيقة', (t) async {
    final srv = _Counting(await visualSetUp(s1bSasOwner));
    ApiClient.dio.httpClientAdapter = srv;
    SubscribersApi.clearAllCaches();
    final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
    await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
    await settle(t, seconds: 2);
    final pay0 = srv.count(_payments);
    final tg0 = srv.count(_telegram);

    SubscriberEvents.notifyChange(); // تفعيل/تسديد/… من أيّ شاشة
    await _tick(t, 2);
    expect(srv.count(_payments) - pay0, greaterThanOrEqualTo(1), reason: 'آخر دفعةٍ بعد العمليّة مباشرةً');
    expect(srv.count(_telegram) - tg0, greaterThanOrEqualTo(1));

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
