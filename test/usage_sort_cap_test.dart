import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';

/// الترتيب بالاستهلاك فوق ٥٠٠٠ صفّ (مراجعة 3.0.18+179): «كل الشركات» بثلاث شركات × ٢٠٠٠ = ٦٠٠٠ صفّ — حدّ الكاش كان يطرد أوّل
/// نتائج الترتيب نفسه (فتغوص «بلا قراءة» ولا تُجلب ثانيةً). الآن صفوف الترتيب القائم لا تُطرد، والصفوف الظاهرة تأخذ مكانها فوقها،
/// وبعد إلغاء الترتيب يعود الكاش لحدّه المعتاد.
class _UsageServer implements HttpClientAdapter {
  var requests = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests++;
    final company = o.headers['x-company-key'] as String?;
    final ids = (o.queryParameters['ids'] ?? '').toString().split(',');
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {for (final id in ids) id: {'today': 1024, 'month': 1048576 * (int.tryParse(id) ?? 1)}},
        'errors': 0,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (company != null) 'x-company-key': [company],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _companies = ['c0000000000aa', 'c0000000000bb', 'c0000000000cc'];

void main() {
  late _UsageServer server;
  final originalTokenSource = AccountApi.tokenSource;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AccountApi.tokenSource = ({bool force = false}) async => 'test-account';
    server = _UsageServer();
    ApiClient.dio.httpClientAdapter = server;
    SubscriberUsageStore.reset();
    UsagePrefs.enabled.value = true;
    SubscriberUsageStore.columnShown = false;
    ProviderService.debugSet(null);
  });
  tearDown(() {
    AccountApi.tokenSource = originalTokenSource;
    SubscriberUsageStore.cancelSortFetch();
    SubscriberUsageStore.reset();
    UsagePrefs.enabled.value = false;
    ProviderService.debugSet(null);
  });

  final rows = <({String idx, String? company})>[
    for (final c in _companies)
      for (var i = 1; i <= 2000; i++) (idx: '$i', company: c),
  ];
  int read(Iterable<({String idx, String? company})> rs) =>
      rs.where((r) => SubscriberUsageStore.get(r.idx, company: r.company)?.v?.month != null).length;

  test('٦٠٠٠ صفّ: كلّها مقروءةٌ بعد الترتيب — لا يطرد الترتيب نتائجه', () async {
    var last = (done: 0, total: 0);
    await SubscriberUsageStore.ensureFor(rows, onProgress: (d, t) => last = (done: d, total: t));
    expect(last, (done: 6000, total: 6000));
    expect(server.requests, 150, reason: 'دفعات ٤٠، كلّ شركةٍ وحدها');
    expect(read(rows), 6000, reason: 'كان ٥٠٠٠ — أوّل ١٠٠٠ تُطرد فتغوص «بلا قراءة»');
    expect(SubscriberUsageStore.get('1', company: _companies.first)?.v?.month, 1048576);
    // ترتيبٌ ثانٍ للصفوف نفسها: لا شيء ينقص فلا طلب
    await SubscriberUsageStore.ensureFor(rows);
    expect(server.requests, 150);
  });

  test('الصفوف الظاهرة أثناء الترتيب تأخذ مكانها فوقه ولا تطرد منه شيئاً؛ وبعد إلغائه يعود الكاش لحدّه', () async {
    await SubscriberUsageStore.ensureFor(rows);
    final visible = [for (var i = 1; i <= 120; i++) (idx: 'v$i', company: null)];
    for (final r in visible) {
      SubscriberUsageStore.want(r.idx);
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(read(visible), 120, reason: 'الظاهرة تُقرأ ولا تُطرد هي (لا حلقة إعادة طلب)');
    expect(read(rows), 6000, reason: 'ولا تطرد صفوف الترتيب القائم');
    // الترتيب أُلغي ⇒ الدفعة التالية تُعيد الكاش لحدّه (الأقدم يُطرد أوّلاً، والأحدث يبقى)
    SubscriberUsageStore.cancelSortFetch();
    final more = [for (var i = 1; i <= 40; i++) (idx: 'm$i', company: null)];
    for (final r in more) {
      SubscriberUsageStore.want(r.idx);
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(read(more), 40);
    expect(read(visible), 120);
    expect(read(rows) + read(visible) + read(more), 5000);
  });
}
