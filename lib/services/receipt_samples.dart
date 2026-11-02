import '../api/receipt_settings_api.dart';
import 'receipt_layout.dart';
import 'receipt_pdf.dart';

/// رابط QR العيّنة — رمزٌ حقيقيّ في المعاينة (لا يفتح بيانات مشترك).
const String receiptSampleQrUrl = 'https://pro.mysvcs.net/user-info/sample';

/// عيّنة «معاينة الوصل» لنوعٍ من الخمسة — من [receiptPreviewSamples] (`PREVIEW_SAMPLES` في ملفّ التثبيت المشترك، هي
/// عيّنات الموقع نفسها: باقة ٣٥٬٠٠٠، جزئيّ ٢٥٬٠٠٠، دين ١٠٬٠٠٠). لا بيانات مشترك. [issuedAt] null = الآن (`issuedText`
/// null في العيّنة)، و[qr] false = بلا رمز (شركةٌ بلا QR، أو أُطفئ).
ReceiptDoc receiptSampleDoc(
  ReceiptKind kind, {
  required ReceiptSettings look,
  required String shopName,
  String? issuer,
  bool qr = true,
  DateTime? issuedAt,
}) {
  final s = receiptPreviewSamples[kind.name]!;
  final sub = s['subscriber']! as Map;
  final sale = s['sale'] as Map?;
  num? n(Object? v) => v is num ? v : null;
  String? str(Object? v) => v is String ? v : null;
  return ReceiptDoc(
    kind: kind,
    issuedAt: issuedAt ?? DateTime.now(),
    look: look,
    receiptNo: n(s['receiptNo'])?.toInt(),
    shopName: shopName,
    subscriberName: str(sub['fullName']) ?? '',
    username: str(sub['username']) ?? '',
    phone: str(sub['phone']),
    packageName: sale == null ? str(sub['profileName']) : null,
    packagePrice: sale == null ? n(sub['packagePrice']) : null,
    expiration: str(sub['expiration']),
    remainingDays: n(sub['remainingDays'])?.toInt(),
    pay: switch (s['paymentType']) {
      'cash' => ReceiptPay.cash,
      'partial-cash' => ReceiptPay.partial,
      'non-cash' => ReceiptPay.credit,
      'wallet' => ReceiptPay.wallet,
      _ => null,
    },
    amount: n(s['amount']),
    partialAmount: n(s['partialAmount']),
    newBalance: n(s['newBalance']),
    qrUrl: qr && s['qr'] == true ? receiptSampleQrUrl : null,
    issuer: issuer,
    sale: sale == null
        ? null
        : SaleInvoiceDoc(
            id: n(sale['id'])!.toInt(),
            lines: [
              for (final l in (sale['lines'] as List).cast<Map>())
                (
                  name: str(l['name']) ?? '',
                  qty: str(l['qtyText']) ?? '',
                  unitPrice: n(l['unitPrice']) ?? 0,
                  total: n(l['total']) ?? 0,
                ),
            ],
            total: n(sale['total']) ?? 0,
            debt: sale['payment'] == 'debt',
          ),
  );
}
