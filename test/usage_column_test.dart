import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';

/// يردّ على /api/v2/subscribers-usage بأرقامٍ ثابتة ويحفظ ما طُلب.
class _UsageServer implements HttpClientAdapter {
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    asked.add(o.uri.toString());
    final ids = (o.queryParameters['ids'] ?? '').toString().split(',');
    final data = {for (final id in ids) id: {'today': 1048576 * 5, 'month': 1073741824 * 3}};
    return ResponseBody.fromString(jsonEncode({'success': true, 'data': data}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// المالك ٢٤ أكتوبر: «الاستهلاك ما يظهر» — عمود الاستهلاك ظهر في جدول الحاسبة افتراضيّاً، والجلب كان معلّقاً على
/// تفضيل «عرض الاستهلاك» المطفأ افتراضاً، فبقي العمود فارغاً.
void main() {
  late _UsageServer server;
  setUp(() {
    server = _UsageServer();
    ApiClient.dio.httpClientAdapter = server;
    SubscriberUsageStore.reset();
    UsagePrefs.enabled.value = false;
  });
  tearDown(() {
    SubscriberUsageStore.columnShown = false;
    SubscriberUsageStore.reset();
  });

  test('عمود الاستهلاك ظاهرٌ في الجدول ⇒ يُجلب ولو كان «عرض الاستهلاك» مطفأ', () async {
    SubscriberUsageStore.columnShown = true;
    SubscriberUsageStore.want('11');
    SubscriberUsageStore.want('12');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.asked, hasLength(1));
    expect(server.asked.single, contains('subscribers-usage'));
    final e = SubscriberUsageStore.get('11');
    expect(e?.v?.today, 1048576 * 5);
    expect(e?.v?.month, 1073741824 * 3);
  });

  test('بلا العمود والتفضيل مطفأ (الهاتف): لا جلب — كما كان', () async {
    SubscriberUsageStore.columnShown = false;
    SubscriberUsageStore.want('21');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.asked, isEmpty);
    expect(SubscriberUsageStore.get('21'), isNull);
  });
}
