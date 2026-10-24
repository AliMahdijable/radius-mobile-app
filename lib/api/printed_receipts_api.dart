import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// `POST /api/printed-receipts` — أرشيف الوصولات وترقيمها لكلّ مدير (`receipt_counters`)، كما يفعل
/// الموقع قبل كلّ طباعة: الوصل يحمل «No. 00012» نفسه أينما طُبع، ويبقى نسخةً في الأرشيف. بطاقة
/// المعلومات لا تُؤرشف (كالموقع).
class PrintedReceiptsApi {
  PrintedReceiptsApi._();

  /// رقم الوصل من الخادم، أو null على أيّ فشل — والوصل يُطبع بلا رقمٍ مؤرشف.
  static Future<int?> archive(Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/printed-receipts',
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final data = r.data ?? const {};
      if (data['success'] != true) return null;
      final no = data['receipt_no'];
      return no is int ? no : int.tryParse('${no ?? ''}');
    } catch (e) {
      if (kDebugMode) debugPrint('[PrintedReceiptsApi] archive: $e');
      return null;
    }
  }
}
