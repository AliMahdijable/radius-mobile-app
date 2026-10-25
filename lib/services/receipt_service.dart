import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/company_route.dart';
import '../api/package_names_api.dart';
import '../api/printed_receipts_api.dart';
import '../api/receipt_facts.dart';
import '../api/receipt_settings_api.dart';
import '../api/subscribers_api.dart';
import '../models/merged_company.dart';
import '../models/subscriber.dart';
import 'active_company.dart';
import 'auth_storage.dart';
import 'merged_mode.dart';
import 'print_output.dart';
import 'print_prefs.dart';
import 'provider_service.dart';
import 'receipt_pdf.dart';

/// وصولات المشترك كما يطبعها الموقع — المالك ٢٤ أكتوبر: «التطبيق مابي طباعة وصل مباشر مثل
/// الويب للمشترك».
///
/// • التصميم من «قوالب الطباعة» في الموقع (`receipt_settings`) لكلّ المزوّدين: الترويسة والتذييل
///   والأقسام الظاهرة ورمز QR وعرض ورق الكاشير. (كانت ايرث لنك وحدها، والساس على قوالب
///   `print_templates` الكلاسيكيّة التي لا يقرؤها الموقع ولا يكتبها أحد منذ النقل.)
/// • «طباعة وصل» من صفحة المشترك = بطاقة معلوماته الآن، بلا أرشفة (كالموقع).
/// • وصل التفعيل/التمديد/التسديد بعد النجاح: مرقّمٌ في أرشيف الوصولات (رقم الموقع نفسه)، والانتهاء
///   والرصيد كما أعادهما الخادم ([ReceiptFacts]) لا تقديراً.
/// • «الكل الشركات»: باسم شركة المشترك وتصميمها وأرشيفها (كلّ طلبٍ موجَّه لها).
class ReceiptService {
  ReceiptService._();

  /// بطاقة معلومات المشترك الحاليّة.
  static Future<PrintResult> printSubscriberCard(Subscriber sub) => _emit(
        ReceiptKind.info,
        sub,
        packagePrice: sub.currentSalePrice ?? sub.price,
        expiration: sub.expiration,
        remainingDays: sub.remainingDays,
        newBalance: sub.balanceAmount,
      );

  /// وصل التفعيل بعد نجاحه. [price] سعر الباقة الفعليّ، و[partialAmount] المدفوع نقداً للجزئيّ.
  static Future<PrintResult> printActivation({
    required Subscriber sub,
    required num price,
    required ReceiptPay pay,
    num? partialAmount,
    String? packageName,
    int? packageId,
  }) {
    final f = ReceiptFacts.take(sub.idx, companyKey: sub.companyKey);
    return _emit(
      ReceiptKind.activation,
      sub,
      packageName: packageName,
      packageId: packageId,
      packagePrice: price,
      amount: price,
      pay: pay,
      partialAmount: pay == ReceiptPay.partial ? partialAmount : null,
      expiration: f?.expiration,
      remainingDays: f?.remainingDays,
      newBalance: f?.newBalance,
    );
  }

  /// وصل التمديد بعد نجاحه — [price] ما خُصم من رصيد المدير (صفر بالنقاط).
  static Future<PrintResult> printExtension({
    required Subscriber sub,
    required num price,
    String? packageName,
  }) {
    final f = ReceiptFacts.take(sub.idx, companyKey: sub.companyKey);
    return _emit(
      ReceiptKind.extension,
      sub,
      packageName: packageName,
      packagePrice: price,
      amount: price,
      expiration: f?.expiration,
      remainingDays: f?.remainingDays,
      newBalance: f?.newBalance,
    );
  }

  /// وصل تسديد الدين بعد نجاحه.
  static Future<PrintResult> printDebtPayment({
    required Subscriber sub,
    required num paid,
  }) {
    final f = ReceiptFacts.take(sub.idx, companyKey: sub.companyKey);
    return _emit(
      ReceiptKind.payment,
      sub,
      packagePrice: sub.currentSalePrice ?? sub.price,
      amount: f?.amountPaid ?? paid,
      expiration: sub.expiration,
      newBalance: f?.newBalance,
    );
  }

  /// معاينة «قوالب الطباعة»: وصلٌ تجريبيّ بتصميم الحساب، كما يخرج بعد التفعيل.
  static Future<PrintResult> printSample(ReceiptSettings? settings) async {
    final id = await _identity(null);
    final doc = ReceiptDoc(
      kind: ReceiptKind.activation,
      issuedAt: DateTime.now(),
      look: settings ?? const ReceiptSettings(),
      shopName: settings?.shopName ?? id.shop,
      subscriberName: 'أحمد محمد',
      username: 'ahmed01',
      phone: '07701234567',
      packageName: 'باقة 35 ميغا',
      packagePrice: 35000,
      expiration: '2026-11-24 18:30',
      remainingDays: 30,
      pay: ReceiptPay.cash,
      amount: 35000,
      newBalance: 0,
      issuer: id.issuer,
    );
    return _print(doc);
  }

  /// «الطباعة التلقائيّة» في مصمّم الموقع لشركة المشترك: خانة «طباعة وصل بعد التأكيد» تأتي
  /// معلَّمةً (الموقع: `printChecked || isAutoPrintEnabled()`).
  static Future<bool> autoPrintFor(String? companyKey) async {
    final s = await CompanyRoute.run(companyKey, ReceiptSettingsApi.fetch);
    return s?.autoPrint ?? false;
  }

  // ─── داخليّ ──────────────────────────────────

  static bool get _sessionIsEarthlink =>
      ProviderService.isEarthlink || ActiveCompany.current?.sasCode == 'earthlink';

  /// اسم المحلّ الاحتياطيّ (بلا اسمٍ في المصمّم) و«أصدره».
  ///
  /// جلسة الموظّف: اسم العرض اسمه هو لا اسم الشركة — فالترويسة يوزر المدير، و«أصدره» الموظّف.
  static Future<({String shop, String? issuer})> _identity(MergedCompany? merged) async {
    if (merged != null) return (shop: merged.name, issuer: merged.username);
    final employee = await AuthStorage.isEmployee();
    final display = (await AuthStorage.readDisplayName())?.trim() ?? '';
    final user = (await AuthStorage.readAdminUsername())?.trim() ?? '';
    final shop = employee ? user : (display.isNotEmpty ? display : user);
    return (
      shop: shop.isEmpty ? 'MyServices' : shop,
      issuer: employee ? (display.isEmpty ? null : display) : (user.isEmpty ? null : user),
    );
  }

  /// اسم الباقة على الوصل كما يراه المشترك (المالك ٢٦ أكتوبر): اسمها في «بوابة المشترك» لرقمها إن كتبه الحساب،
  /// وإلّا كما وصل. الرقم من الكائن نفسه الذي جاء منه الاسم: [packageName] برقمه [packageId] — وبلا رقمٍ كما هو
  /// (باقة التمديد ليست باقة مشترك) — وإلّا باقة المشترك ورقمها.
  @visibleForTesting
  static String packageLabel(
      PackageNames names, Subscriber sub, String? packageName, int? packageId) {
    final sas = (packageName ?? sub.profileName ?? '').trim();
    final id = packageName == null ? sub.profileId : packageId;
    return (names.display(id, sas) ?? sas).trim();
  }

  static Future<PrintResult> _emit(
    ReceiptKind kind,
    Subscriber sub, {
    String? packageName,
    int? packageId,
    num? packagePrice,
    num? amount,
    ReceiptPay? pay,
    num? partialAmount,
    String? expiration,
    int? remainingDays,
    num? newBalance,
  }) async {
    try {
      final key = sub.companyKey;
      final merged = MergedMode.companyOf(key);
      final earthlink = merged != null ? merged.provider == MergedProvider.earthlink : _sessionIsEarthlink;
      final idx = sub.idx;
      final namesF = CompanyRoute.run(key, PackageNamesApi.fetch);
      final settings = await CompanyRoute.run(key, ReceiptSettingsApi.fetch);
      final look = settings ?? const ReceiptSettings();
      final id = await _identity(merged);
      final name = sub.fullName.trim().isEmpty ? sub.username : sub.fullName.trim();
      final phone = sub.displayPhone.trim();
      final pkg = packageLabel(await namesF, sub, packageName, packageId);

      // رابط QR ورقم الأرشيف معاً لا تباعاً: الوصل لا ينتظر رحلتين. فشل أيٍّ منهما لا يمنع الطباعة.
      // QR: الساس وحده (ايرث لنك بلا مسار generate-link — كالموقع).
      final qrF = look.showQr && !earthlink && idx != null && idx.isNotEmpty
          ? CompanyRoute.run(key, () => SubscribersApi.receiptLink(idx))
          : Future<String?>.value(null);
      final op = kind.archiveOp;
      final noF = op == null
          ? Future<int?>.value(null)
          : CompanyRoute.run(
              key,
              () => PrintedReceiptsApi.archive({
                    if (idx != null) 'subscriber_id': idx,
                    'subscriber_username': sub.username,
                    'subscriber_name': name,
                    'subscriber_phone': phone.isEmpty ? null : phone,
                    'operation_type': op,
                    'amount': amount ?? 0,
                    'payment_method': (pay ?? ReceiptPay.cash).archiveMethod,
                    'partial_amount': partialAmount ?? 0,
                    'package_name': pkg.isEmpty ? null : pkg,
                    'package_price': packagePrice ?? 0,
                    'expiry_date': expiration,
                    'remaining_time': remainingDays == null ? null : '$remainingDays يوم',
                    'payload': {
                      'receiptType': kind.name,
                      'source': 'app',
                      'subscriber': {
                        'username': sub.username,
                        'fullName': name,
                        if (phone.isNotEmpty) 'phone': phone,
                        if (pkg.isNotEmpty) 'profileName': pkg,
                        if (packagePrice != null) 'packagePrice': packagePrice,
                        if (expiration != null) 'expiration': expiration,
                        if (remainingDays != null) 'remainingDays': remainingDays,
                      },
                      if (amount != null) 'amount': amount,
                      if (pay != null) 'paymentType': pay.name,
                      if (partialAmount != null) 'partialAmount': partialAmount,
                      if (newBalance != null) 'newBalance': newBalance,
                      if (id.issuer != null) 'issuer': id.issuer,
                    },
                  }));
      final qr = await qrF;
      final no = await noF;

      final doc = ReceiptDoc(
        kind: kind,
        issuedAt: DateTime.now(),
        look: look,
        receiptNo: no,
        shopName: look.shopName ?? id.shop,
        subscriberName: name,
        username: sub.username,
        phone: phone.isEmpty ? null : phone,
        packageName: pkg.isEmpty ? null : pkg,
        packagePrice: packagePrice,
        expiration: expiration,
        remainingDays: remainingDays,
        pay: pay,
        amount: amount,
        partialAmount: partialAmount,
        newBalance: newBalance,
        qrUrl: qr,
        issuer: id.issuer,
      );
      return _print(doc);
    } catch (e) {
      if (kDebugMode) debugPrint('[ReceiptService] error: $e');
      return PrintResult.failed('$e');
    }
  }

  static Future<PrintResult> _print(ReceiptDoc doc) async {
    final pdf = await ReceiptPdf.build(doc, a4: PrintPrefs.currentTemplateType == 'a4');
    return PrintOutput.send(pdf);
  }
}
