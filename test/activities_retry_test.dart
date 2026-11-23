import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/reports_api.dart';

import 'visual_perm/visual_perm_harness.dart';

// المالك (٢٣ نوفمبر): «سجل النشاط رجع لحالته القديمة يعرض هلخطا» — بأوّل فتحٍ للسجلّ خرج طلب الصرفيّات ولم يصل طلب الحركات
// الخادم أصلاً (لا سطر له في nginx)، فظهر «تعذّر التحميل»؛ والفتح التالي نجح. عطل نقلٍ قبل أيّ ردّ يُعاد الآن بصمت (الصفحة نفسها،
// مرّتين بعد مهلة، فوق إعادة المعترض الفوريّة)، وردٌّ وصل — أيّاً كانت حالته — لا يُعاد.

class _Flaky implements HttpClientAdapter {
  _Flaky(this.inner, {required this.failFirst, this.status = 200});
  final VisualServer inner;
  final int failFirst;
  final int status;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    if (o.uri.path != '/api/activities') return inner.fetch(o, body, cancel);
    calls++;
    if (calls <= failFirst) throw const SocketException('Connection reset by peer');
    final ok = status == 200;
    return ResponseBody.fromString(
      jsonEncode(ok
          ? {
              'success': true,
              'data': [
                {'id': 7, 'action_type': 'SUBSCRIBER_ACTIVATE', 'action_description': 'تفعيل نقدي', 'created_at': '2026-11-23 10:00:00'},
              ],
              'pagination': {'total': 1, 'page': 1, 'limit': 2000},
            }
          : {'success': false, 'message': 'لا تملك صلاحية'}),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(visualSetUpAll);
  setUp(() => ReportsApi.activitiesRetryDelay = (_) => Duration.zero);
  tearDown(() => ReportsApi.activitiesRetryDelay = (a) => Duration(milliseconds: a == 0 ? 400 : 1000));

  Future<({bool ok, int rows, String? error, int calls})> run(int failFirst, {int status = 200}) async {
    final flaky = _Flaky(await visualSetUp(s1bSasOwner), failFirst: failFirst, status: status);
    ApiClient.dio.httpClientAdapter = flaky;
    try {
      final r = await ReportsApi.activitiesAll(from: DateTime(2026, 11, 21), to: DateTime(2026, 11, 23), userIds: const ['2']);
      return (ok: r.ok, rows: r.rows.length, error: r.error, calls: flaky.calls);
    } finally {
      await visualTearDown();
    }
  }

  test('عطل نقلٍ عابر (4 محاولات ميتة = المعترض مرّتين × محاولتان) ⇒ السطور بلا «تعذّر التحميل»', () async {
    final r = await run(4);
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(r.rows, 1);
    expect(r.calls, 5);
  });

  test('عطلٌ دائم ⇒ «تعذّر التحميل» بعد ثلاث محاولاتٍ لا أكثر (لا حلقة)', () async {
    final r = await run(1000);
    expect(r.ok, isFalse);
    expect(r.error, 'تعذّر التحميل');
    expect(r.calls, 6, reason: 'ثلاث محاولات للصفحة، وكلٌّ منها يعيدها المعترض مرّةً واحدة');
  });

  test('ردٌّ وصل (403) لا يُعاد — رسالته كما هي', () async {
    final r = await run(0, status: 403);
    expect(r.ok, isFalse);
    expect(r.calls, 1);
  });

  test('ردٌّ وصل بخطأ خادم (500) لا يُعاد — عطلٌ حقيقيّ لا نقل', () async {
    final r = await run(0, status: 500);
    expect(r.ok, isFalse);
    expect(r.calls, 1);
  });

  test('بلا عطل ⇒ طلبٌ واحد', () async {
    final r = await run(0);
    expect(r.ok, isTrue);
    expect(r.calls, 1);
  });
}
