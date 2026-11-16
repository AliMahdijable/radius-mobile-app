import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// خادمٌ وهميّ يجيب بردود **عقد الخادم الحقيقيّ** (server_contract*.json — ولّدها كود الخادم الحيّ) كما هي: «من أنا»، اللوحة، وتفاصيل كلّ فترة (كلّ حركاتها في صفحةٍ واحدة؛ وفلتر «المدراء» = ما نوعه manager).
class BalanceContractServer implements HttpClientAdapter {
  BalanceContractServer(this.contract);
  final Map<String, dynamic> contract;
  final filters = <String>[];

  static final _period = RegExp(r'^/api/v2/balance-reports/periods/(\d+)$');

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object? body;
    var status = 200;
    final m = _period.firstMatch(o.path);
    if (o.path == '/api/v2/admin-widgets') {
      body = {'success': true, 'points': 0, 'balance': 120000};
    } else if (o.path == '/api/v2/balance-reports/me') {
      body = contract['me_manager'];
    } else if (o.path == '/api/v2/balance-reports' && o.method == 'GET') {
      body = contract['overview'];
    } else if (m != null && o.method == 'GET') {
      final d = (contract['details'] as Map)[m.group(1)];
      final filter = '${o.queryParameters['filter'] ?? 'all'}';
      filters.add(filter);
      if (d is Map && filter == 'managers') {
        final data = Map<String, dynamic>.from(d['data'] as Map);
        final items = ((data['movements'] as Map)['items'] as List).where((x) => (x as Map)['kind'] == 'manager').toList();
        data['filter'] = 'managers';
        data['movements'] = {'items': items, 'total': items.length, 'offset': 0};
        body = {'success': true, 'data': data};
      } else {
        body = d;
      }
    }
    if (body == null) {
      status = 404;
      body = {'success': false, 'message': 'غير موجود'};
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
