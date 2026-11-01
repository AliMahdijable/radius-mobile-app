import '../api/receipt_settings_api.dart';
import 'receipt_pdf.dart';

/// رابط QR العيّنة — رمزٌ حقيقيّ في المعاينة (لا يفتح بيانات مشترك).
const String receiptSampleQrUrl = 'https://pro.mysvcs.net/user-info/sample';

/// عيّنات «معاينة الوصل» بأنواعه الخمسة — أرقام عيّنة الموقع نفسها (`PREVIEW_SAMPLES` / `preview-samples.ts`): باقة
/// ٣٥٬٠٠٠، جزئيّ ٢٥٬٠٠٠، دين ١٠٬٠٠٠. لا بيانات مشترك. [issuedAt] null = الآن.
ReceiptDoc receiptSampleDoc(
  ReceiptKind kind, {
  required ReceiptSettings look,
  required String shopName,
  String? issuer,
  bool qr = true,
  DateTime? issuedAt,
}) {
  final at = issuedAt ?? DateTime.now();
  final qrUrl = qr ? receiptSampleQrUrl : null;
  ReceiptDoc sub({
    required int? no,
    required String expiration,
    int? days,
    ReceiptPay? pay,
    num? amount,
    num? partial,
    num? balance,
  }) =>
      ReceiptDoc(
        kind: kind,
        issuedAt: at,
        look: look,
        receiptNo: no,
        shopName: shopName,
        subscriberName: 'محمد علي',
        username: 'sample.user',
        phone: '07700000000',
        packageName: 'Economy',
        packagePrice: 35000,
        expiration: expiration,
        remainingDays: days,
        pay: pay,
        amount: amount,
        partialAmount: partial,
        newBalance: balance,
        qrUrl: qrUrl,
        issuer: issuer,
      );
  return switch (kind) {
    ReceiptKind.extension =>
      sub(no: 13, expiration: '2026-12-31 10:00', days: 60, pay: ReceiptPay.cash, amount: 35000, balance: 0),
    ReceiptKind.payment => sub(no: 14, expiration: '2026-12-01 10:00', amount: 25000, balance: -10000),
    ReceiptKind.info => sub(no: null, expiration: '2026-12-01 10:00', days: 30, balance: -10000),
    ReceiptKind.sale => ReceiptDoc(
        kind: ReceiptKind.sale,
        issuedAt: at,
        look: look,
        shopName: shopName,
        subscriberName: 'محمد علي',
        username: 'sample.user',
        phone: '07700000000',
        issuer: issuer,
        sale: const SaleInvoiceDoc(
          id: 128,
          lines: [
            (name: 'راوتر TP-Link', qty: '1 قطعة', unitPrice: 35000, total: 35000),
            (name: 'كيبل شبكة', qty: '15 متر', unitPrice: 500, total: 7500),
          ],
          total: 42500,
          debt: false,
        ),
      ),
    ReceiptKind.activation => sub(
        no: 12,
        expiration: '2026-12-01 10:00',
        days: 30,
        pay: ReceiptPay.partial,
        amount: 35000,
        partial: 25000,
        balance: -10000,
      ),
  };
}
