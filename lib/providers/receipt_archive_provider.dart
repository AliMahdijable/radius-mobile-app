import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../core/utils/receipt_printer.dart';

/// نوع العملية المرافق للوصل. يطابق enum بالـbackend.
enum ReceiptOperation { activate, extend, payDebt, addDebt }

extension ReceiptOperationApi on ReceiptOperation {
  String get apiKey {
    switch (this) {
      case ReceiptOperation.activate: return 'activate';
      case ReceiptOperation.extend:   return 'extend';
      case ReceiptOperation.payDebt:  return 'pay_debt';
      case ReceiptOperation.addDebt:  return 'add_debt';
    }
  }

  /// عربي للعرض. يطابق نفس النصوص المعتمدة في الواجهة.
  String get arabicLabel {
    switch (this) {
      case ReceiptOperation.activate: return 'تفعيل';
      case ReceiptOperation.extend:   return 'تمديد';
      case ReceiptOperation.payDebt:  return 'تسديد دين';
      case ReceiptOperation.addDebt:  return 'إضافة دين';
    }
  }
}

/// طريقة الدفع المرافقة للوصل (نقدي/جزئي/آجل). تنعكس على لون الزر بالـUI.
enum ReceiptPaymentMethod { cash, partial, credit }

extension ReceiptPaymentMethodApi on ReceiptPaymentMethod {
  String get apiKey {
    switch (this) {
      case ReceiptPaymentMethod.cash:    return 'cash';
      case ReceiptPaymentMethod.partial: return 'partial';
      case ReceiptPaymentMethod.credit:  return 'credit';
    }
  }
}

/// صف من الأرشيف. يطابق ما يرجعه GET /api/printed-receipts.
class ArchivedReceipt {
  final int id;
  final String? subscriberId;
  final String? subscriberUsername;
  final String? subscriberName;
  final String? subscriberPhone;
  final String operationType;
  final double amount;
  final String paymentMethod;
  final double partialAmount;
  final String? packageName;
  final double packagePrice;
  final String? expiryDate;
  final String? remainingTime;
  final DateTime printedAt;
  final int? printedByEmployeeId;
  final String? printedByEmployeeUsername;
  final int? templateId;
  final Map<String, dynamic>? payload;

  const ArchivedReceipt({
    required this.id,
    this.subscriberId,
    this.subscriberUsername,
    this.subscriberName,
    this.subscriberPhone,
    required this.operationType,
    this.amount = 0,
    this.paymentMethod = 'cash',
    this.partialAmount = 0,
    this.packageName,
    this.packagePrice = 0,
    this.expiryDate,
    this.remainingTime,
    required this.printedAt,
    this.printedByEmployeeId,
    this.printedByEmployeeUsername,
    this.templateId,
    this.payload,
  });

  factory ArchivedReceipt.fromJson(Map<String, dynamic> j) {
    double _num(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    final printedAtRaw = j['printed_at']?.toString();
    final printedAt =
        DateTime.tryParse(printedAtRaw ?? '') ?? DateTime.now().toUtc();
    Map<String, dynamic>? payload;
    final p = j['payload_json'];
    if (p is Map) payload = Map<String, dynamic>.from(p);
    return ArchivedReceipt(
      id: int.tryParse(j['id']?.toString() ?? '') ?? 0,
      subscriberId: j['subscriber_id']?.toString(),
      subscriberUsername: j['subscriber_username']?.toString(),
      subscriberName: j['subscriber_name']?.toString(),
      subscriberPhone: j['subscriber_phone']?.toString(),
      operationType: j['operation_type']?.toString() ?? 'activate',
      amount: _num(j['amount']),
      paymentMethod: j['payment_method']?.toString() ?? 'cash',
      partialAmount: _num(j['partial_amount']),
      packageName: j['package_name']?.toString(),
      packagePrice: _num(j['package_price']),
      expiryDate: j['expiry_date']?.toString(),
      remainingTime: j['remaining_time']?.toString(),
      printedAt: printedAt,
      printedByEmployeeId: int.tryParse(j['printed_by_employee_id']?.toString() ?? ''),
      printedByEmployeeUsername: j['printed_by_employee_username']?.toString(),
      templateId: int.tryParse(j['template_id']?.toString() ?? ''),
      payload: payload,
    );
  }
}

class ArchiveListArgs {
  final DateTime? from;
  final DateTime? to;
  final String? type;
  final String? query;
  final int limit;
  const ArchiveListArgs({
    this.from,
    this.to,
    this.type,
    this.query,
    this.limit = 100,
  });

  @override
  bool operator ==(Object o) =>
      identical(this, o) ||
      (o is ArchiveListArgs &&
          o.from == from &&
          o.to == to &&
          o.type == type &&
          o.query == query &&
          o.limit == limit);

  @override
  int get hashCode => Object.hash(from, to, type, query, limit);
}

/// يحفظ صف أرشيف بعد طباعة وصل. fire-and-forget عشان فشل الأرشفة ما يبطّل
/// تجربة الطباعة. الـcaller يبني الـpayload من ReceiptData المُستعملة + أي
/// حقول إضافية (template_id، subscriber_id، إلخ).
Future<void> archivePrintedReceipt(
  WidgetRef ref, {
  required ReceiptData data,
  required ReceiptOperation operation,
  ReceiptPaymentMethod paymentMethod = ReceiptPaymentMethod.cash,
  String? subscriberId,
  String? subscriberUsername,
  int? templateId,
  Map<String, dynamic>? extraPayload,
}) async {
  try {
    final dio = ref.read(backendDioProvider);
    // الـpayload snapshot كامل عشان إعادة الطباعة لاحقاً تشتغل حتى لو
    // المشترك انحذف أو القالب تغيّر.
    final payload = <String, dynamic>{
      'subscriber_name': data.subscriberName,
      'phone_number': data.phoneNumber,
      'package_name': data.packageName,
      'package_price': data.packagePrice,
      'paid_amount': data.paidAmount,
      'remaining_amount': data.remainingAmount,
      'debt_amount': data.debtAmount,
      'expiry_date': data.expiryDate,
      'operation_type': data.operationType,
      ...?extraPayload,
    };

    await dio.post('/api/printed-receipts', data: {
      'subscriber_id': subscriberId,
      'subscriber_username': subscriberUsername,
      'subscriber_name': data.subscriberName,
      'subscriber_phone': data.phoneNumber,
      'operation_type': operation.apiKey,
      'amount': data.paidAmount,
      'payment_method': paymentMethod.apiKey,
      'partial_amount':
          paymentMethod == ReceiptPaymentMethod.partial ? data.paidAmount : 0,
      'package_name': data.packageName,
      'package_price': data.packagePrice,
      'expiry_date': data.expiryDate,
      'remaining_time': null,
      'template_id': templateId,
      'payload': payload,
    });
  } on DioException catch (e) {
    dev.log('archivePrintedReceipt failed: ${e.response?.statusCode} ${e.message}',
        name: 'RECEIPTS');
  } catch (e) {
    dev.log('archivePrintedReceipt error: $e', name: 'RECEIPTS');
  }
}

final receiptsArchiveProvider = FutureProvider.family
    .autoDispose<List<ArchivedReceipt>, ArchiveListArgs>((ref, args) async {
  final dio = ref.read(backendDioProvider);
  final qp = <String, dynamic>{'limit': args.limit};
  if (args.from != null) qp['from'] = args.from!.toIso8601String();
  if (args.to != null) qp['to'] = args.to!.toIso8601String();
  if (args.type != null && args.type!.isNotEmpty) qp['type'] = args.type;
  if (args.query != null && args.query!.trim().isNotEmpty) {
    qp['q'] = args.query!.trim();
  }
  try {
    final res = await dio.get('/api/printed-receipts', queryParameters: qp);
    final data = res.data;
    if (data is! Map || data['success'] != true) return const [];
    final list = (data['data'] as List? ?? const [])
        .map((e) => ArchivedReceipt.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return list;
  } catch (e) {
    dev.log('receiptsArchiveProvider error: $e', name: 'RECEIPTS');
    return const [];
  }
});

/// يجلب صف أرشيف واحد مع الـpayload الكامل. يُستعمل لإعادة الطباعة.
Future<ArchivedReceipt?> fetchArchivedReceipt(WidgetRef ref, int id) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/printed-receipts/$id');
    final data = res.data;
    if (data is Map && data['success'] == true && data['data'] is Map) {
      return ArchivedReceipt.fromJson(Map<String, dynamic>.from(data['data']));
    }
  } catch (e) {
    dev.log('fetchArchivedReceipt error: $e', name: 'RECEIPTS');
  }
  return null;
}
