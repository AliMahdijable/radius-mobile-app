import 'route_checks.dart';
import 'route_scan.dart';

// ═══════════════════════════════════════════════════════════════════════
// «كل الشركات» — ما رُوجع من مواضع التوجيه، وأحكام الفحوص به (مراجعة 179، للإصدار 180 — route3_verify.json البنود ٥–١١).
// test/merged_route_invariant_test.dart يحكم بها على lib كما هو (كلّ حكمٍ فارغ)، وtest/merged_route_proof_test.dart يزرع النمط
// السيّئ في نسخةٍ منه بالذاكرة ويثبت أنّ الحكم نفسه — بقوائمه المراجَعة نفسها — يفشل عليه.
// ═══════════════════════════════════════════════════════════════════════

/// القراءات بـPOST المراجَعة، كلٌّ بمصدره: مدخل R بـPOST في جدول توجيه الخادم (server/companyRoutingAllow.js) يقابله، أو قراءةٌ لا
/// يوجّهها الخادم. الفحوص الثابتة و`writes()` في الاختبارات تأخذ هذه لا الثابت المنتَج (`CompanyRoute.readsByPost`) — كتابةٌ تُضاف
/// إليه لتُسكت رفضاً تفشل حتى تُراجَع، ومدخلٌ يزول منه كذلك.
const reviewedReadsByPost = <String, String>{
  '/api/v2/subscribers/device-batch': "الخادم: R('device-batch', 'POST', '/api/v2/subscribers/device-batch')",
  '/api/v2/subscribers/last-macs': "الخادم: R('last-macs', 'POST', '/api/v2/subscribers/last-macs')",
  '/api/v2/sales/debt-status': "الخادم: R('sales-debt-status', 'POST', '/api/v2/sales/debt-status')",
  '/api/v2/subscribers/lookup': 'أسماء مشتركي الحساب الكبير بأعيانهم (≤١٠٠ يوزر/رقم) — قراءة؛ ليست في جدول الخادم',
  '/api/v2/whatsapp/contact-risk': 'خطر رقم واتساب من قاعدتنا — قراءةٌ لا يوجّهها الخادم (يرفضها موجَّهةً)',
  '/api/v2/whatsapp/bulk-risk': 'خطر أرقام دفعة من قاعدتنا — قراءةٌ لا يوجّهها الخادم (يرفضها موجَّهةً)',
};

/// مسارات [reviewedReadsByPost] وحدها.
final reviewedReadPaths = reviewedReadsByPost.keys.toSet();

String _diff<T>(String what, Set<T> want, Set<T> got) {
  final extra = got.difference(want);
  final missing = want.difference(got);
  return '$what — جديدٌ غير مراجَع: $extra · مراجَعٌ زال: $missing';
}

// ─────────────────────────── ٩. واجهات الأقسام من خارجها ───────────────────────────

const sectionApis = {
  'BroadcastApi': 'broadcast_api', 'CardsApi': 'cards_api', 'DiscountsApi': 'discounts_api', 'EmployeesApi': 'employees_api',
  'ExpensesApi': 'expenses_api', 'ManagerDebtsApi': 'manager_debts_api', 'ManagerMovementsApi': 'manager_movements_api',
  'ManagersApi': 'managers_api', 'PortalSettingsApi': 'portal_settings_api', 'RecurringExpensesApi': 'recurring_expenses_api',
  'RenewRequestsApi': 'renew_requests_api', 'SendScopeApi': 'send_scope_api', 'SettlementsApi': 'settlements_api',
  'TelegramApi': 'telegram_api', 'TicketsApi': 'tickets_api', 'WaContactRiskApi': 'wa_contact_risk', 'SalesApi': 'sales_api',
};

const sectionDirs = [
  'lib/screens/expenses/', 'lib/screens/settlements/', 'lib/screens/managers/', 'lib/screens/message_logs/',
  'lib/screens/portal_settings/', 'lib/screens/renew/', 'lib/screens/tickets/', 'lib/screens/cards/', 'lib/screens/telegram/',
  'lib/screens/broadcast/', 'lib/screens/discounts/', 'lib/screens/employees/', 'lib/screens/sales/',
];

/// open: داخل CompanyRoute.runOpen أو pin(null · row: بشركة صفّه (MergedOps.run/write(<صفّ>، writeAt/pinned(<…>.companyKey،
/// CompanyRoute.pin/run(<…>.companyKey) · value: قيمةٌ بلا نداء · implicit: ضمنيٌّ عن قصد (يتبع قاعدة المعترض) — سببه مكتوب.
const reviewedSectionSites = <String, (String, String)>{
  'lib/screens/accounts/accounts_screen.dart ManagersApi.fetchPassword': ('open', '«الصفحات» (OpenCompanyScope)'),
  'lib/screens/accounts/accounts_screen.dart ManagersApi.listFull': ('open', '«الصفحات» (OpenCompanyScope)'),
  'lib/screens/app_modules.dart TicketsApi.servedByProvider': ('value', 'قيمةٌ ثابتة، لا طلب'),
  'lib/screens/network_devices/fiber/fiber_outage_screen.dart BroadcastApi.broadcast': ('open', 'مشتركو أجهزة المفتوحة'),
  'lib/services/fiber/fiber_monitor.dart BroadcastApi.broadcast': ('open', '«رجع النت» بالخلفيّة'),
  'lib/screens/packages/packages_screen.dart ManagersApi.lite': ('open', 'قسم «للمفتوحة وحدها»'),
  'lib/screens/reports/activity_log_report_screen.dart ExpensesApi.list': ('open', 'تقرير المفتوحة'),
  'lib/screens/reports/all_managers_debts_screen.dart ManagerDebtsApi.list': ('open', 'تقرير المفتوحة'),
  'lib/screens/reports/all_managers_debts_screen.dart ManagerDebtsApi.summary': ('open', 'تقرير المفتوحة'),
  'lib/screens/reports/all_managers_debts_screen.dart ManagerMovementsApi.list': ('open', 'تقرير المفتوحة'),
  'lib/screens/reports/all_managers_debts_screen.dart ManagersApi.listFull': ('open', 'تقرير المفتوحة'),
  'lib/screens/reports/widgets/report_filters.dart EmployeesApi.list': ('open', 'فلاتر تقارير المفتوحة'),
  'lib/screens/reports/widgets/report_filters.dart ManagersApi.lite': ('open', 'فلاتر تقارير المفتوحة'),
  'lib/screens/subscribers/connection_alert_flow.dart PortalSettingsApi.fillAgentCode': ('row', 'MergedOps.run(sub (بلا مفتاح ⇒ المفتوحة)'),
  'lib/screens/subscribers/sheets/activate_sheet.dart CardsApi.codeCardNotAllowed': ('value', 'ثابت رمز رفض، لا طلب'),
  'lib/screens/subscribers/sheets/activate_sheet.dart CardsApi.codeNoCards': ('value', 'ثابت رمز رفض، لا طلب'),
  'lib/screens/subscribers/subscribers_screen.dart ManagersApi.lite':
      ('implicit', 'الوضع العاديّ/الكبير وحده (لا أقسام موجَّهة خارج «كل الشركات»)؛ «كل الشركات» بمفتاح كلّ شركة'),
  'lib/screens/subscribers/subscribers_screen.dart TelegramApi.listBindings':
      ('implicit', 'الوضع العاديّ/الكبير وحده؛ «كل الشركات»: CompanyRoute.run(مفتاح الشركة)'),
  'lib/screens/whatsapp/widgets/send_scope_panel.dart SendScopeApi.fetch':
      ('implicit', 'إعدادات الصفحة التي تعرضه (adminIdFor يتبع النطاق) — قسم التبليغات لشركته'),
  'lib/screens/whatsapp/widgets/send_scope_panel.dart SendScopeApi.update': ('implicit', 'كتابةٌ ضمنيّة ⇒ المفتوحة، أو تُرفض تحت قسمٍ موجَّهٍ لغيرها'),
  'lib/services/manager_notice.dart ManagersApi.sendBalanceUpdatePush': ('implicit', 'من أفعال المدراء — كتابةٌ ضمنيّة'),
  'lib/services/manager_notice.dart ManagersApi.sendTelegram': ('implicit', 'من أفعال المدراء — كتابةٌ ضمنيّة'),
  'lib/services/permissions_service.dart EmployeesApi.me': ('open', 'صلاحيّات الجلسة'),
  'lib/widgets/manual_wa_chip.dart WaContactRiskApi.one': ('open', 'واتساب المفتوحة'),
  'lib/api/whatsapp_api.dart PortalSettingsApi.fillAgentCode': ('row', 'CompanyRoute.pin(sub.companyKey (بلا مفتاح ⇒ المفتوحة)'),
};

/// ودجات الشريط نفسها تقرأ اختياره؛ غيرها لا يمرّر الشريط شركةً لغلاف.
const stripFiles = {'lib/widgets/merged_company_strip.dart', 'lib/widgets/merged_section.dart'};

/// واجهات الأقسام من خارجها: الجرد مساوٍ للمراجَع، وكلّ موضعٍ بطريقته، ولا غلاف يأخذ الشريط وسيطاً.
List<String> sectionVerdict(Lib lib) {
  final r = sectionApiSites(lib, apis: sectionApis, sectionDirs: sectionDirs, reviewed: reviewedSectionSites);
  return [
    if (!_same(r.found.keys.toSet(), reviewedSectionSites.keys.toSet()))
      _diff('نداء واجهة قسمٍ من خارجه — ثبّته للمفتوحة (CompanyRoute.runOpen) أو بشركة صفّه (MergedOps/pin)، ثمّ أضفه بطريقته',
          reviewedSectionSites.keys.toSet(), r.found.keys.toSet()),
    ...r.bad,
    for (final f in focusInWrappers(lib, stripFiles: stripFiles)) '$f: غلافٌ يأخذ الشريط وسيطاً — شركته تتبدّل تحت ما فُتح لها',
  ];
}

bool _same<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

// ─────────────────────────── ١١. dio ───────────────────────────

/// مسارٌ لا يُحلّ لا يُعرف أهو مال أو مشترك — مراجَعٌ بسببه.
const reviewedUnresolved = {
  'lib/api/ai_api.dart _send': 'المساعد الذكيّ (/api/v2/ai/…): مساره من ثابت الملفّ يمرّ بمتغيّر — لا مشترك ولا مال',
  'lib/api/national_device_api.dart _send':
      'جهاز مشترك الوطنيّ (/api/v2/ftth/subscriptions/…): من KitFiberCard للصفوف بلا مفتاح وحدها — لا مال ولا /api/v2/subscribers',
};

/// كتابات المال في كلّ lib (أيّ مستقبِل) بشركتها الصريحة، وكلّ كتابةٍ على خادمنا بمسارٍ محلولٍ أو مراجَع.
List<String> dioVerdict(Lib lib) {
  final r = moneyDioWrites(lib, readsByPost: reviewedReadPaths);
  final unresolved = unresolvedServerWrites(lib);
  return [
    for (final b in r.bad) '$b: كتابة مالٍ بلا شركةٍ صريحة — تأخذ الشركة المفتوحة أو تُرفض بدل شركتها',
    for (final f in moneyApiFiles.keys)
      if ((r.perFile[f] ?? 0) == 0) '$f: الفحص لم يجد كتابات (تغيّرت الصيغة؟)',
    if (!_same(unresolved, reviewedUnresolved.keys.toSet()))
      _diff('كتابةٌ على خادمنا بمسارٍ لا يُحلّ — اجعله حرفيّاً/ثابتاً، أو راجعه وأضفه بسببه', reviewedUnresolved.keys.toSet(), unresolved),
  ];
}

// ─────────────────────────── ٦/٨. كتّاب المشترك ───────────────────────────

const expectedSubscriberWriters = {
  'EarthlinkApi.createSubscriber', 'EarthlinkApi.setAccountPassword', 'KitCardApi.start', 'PrivateNotesApi.save',
  'SubscriberPricesApi.remove', 'SubscriberPricesApi.set', 'SubscribersApi.activate', 'SubscribersApi.activateDetailed',
  'SubscribersApi.addCredit', 'SubscribersApi.addDebt', 'SubscribersApi.cancelProfileChange', 'SubscribersApi.createSubscriber',
  'SubscribersApi.delete', 'SubscribersApi.disconnect', 'SubscribersApi.extend', 'SubscribersApi.generatePortalQrToken',
  'SubscribersApi.payDebt', 'SubscribersApi.receiptLink', 'SubscribersApi.setDiscount', 'SubscribersApi.setLocation',
  'SubscribersApi.toggle', 'SubscribersApi.toggleResult', 'SubscribersApi.transferSubscriber', 'SubscribersApi.updateSubscriber',
};

/// الجماعيّة: صفوف «كل الشركات» تُرفض قبلها في دالّتها نفسها (أو في دالّة العرض التي وحدها تبني الشيت).
const reviewedBulk = {
  'lib/screens/subscribers/subscribers_screen.dart#_openBulkDisconnect SubscribersApi.disconnect': 'rows',
  'lib/screens/subscribers/subscribers_screen.dart#_bulk SubscribersApi.toggle': 'rows',
  'lib/screens/subscribers/subscribers_screen.dart#_bulk SubscribersApi.delete': 'rows',
  'lib/screens/subscribers/sheets/bulk_pay_debt_sheet.dart#_submit SubscribersApi.payDebt': 'show:showBulkPayDebtSheet:_BulkPayDebtSheet',
  'lib/screens/subscribers/sheets/bulk_activate_sheet.dart#_submit SubscribersApi.activateDetailed':
      'show:showBulkActivateSheet:_BulkActivateSheet',
};

/// كلّ موضعٍ ببادئة غلافه حرفاً — تغييرُ غلافٍ (runOpen مكان الصفّ، pin بشركةٍ أخرى…) يفشل حتى يُراجَع.
const reviewedWriterPrefixes = <String, List<String>>{
  'lib/screens/subscribers/sheets/activate_sheet.dart KitCardApi.start': ['MergedOps.run(widget.sub,'],
  'lib/screens/subscribers/sheets/activate_sheet.dart SubscribersApi.activate':
      ['MergedOps.run(widget.sub,', 'MergedOps.run(widget.sub,', 'MergedOps.run(widget.sub,'],
  'lib/screens/subscribers/sheets/add_credit_sheet.dart SubscribersApi.addCredit': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/add_debt_sheet.dart SubscribersApi.addDebt': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/add_subscriber_sheet.dart SubscribersApi.createSubscriber': ['_co('],
  'lib/screens/subscribers/sheets/edit_subscriber_sheet.dart EarthlinkApi.setAccountPassword': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/edit_subscriber_sheet.dart SubscribersApi.cancelProfileChange': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/edit_subscriber_sheet.dart SubscribersApi.transferSubscriber': ['MergedOps.run(widget.sub,'],
  'lib/screens/subscribers/sheets/edit_subscriber_sheet.dart SubscribersApi.updateSubscriber': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/el_add_subscriber_sheet.dart EarthlinkApi.createSubscriber': ['_co('],
  'lib/screens/subscribers/sheets/extend_sheet.dart SubscribersApi.extend': ['MergedOps.run(widget.sub,'],
  'lib/screens/subscribers/sheets/location_sheets.dart SubscribersApi.setLocation': ['MergedOps.write(widget.sub,', 'MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/pay_debt_sheet.dart SubscribersApi.payDebt': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/qr_login_sheet.dart SubscribersApi.generatePortalQrToken': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/quick_discount_sheet.dart SubscribersApi.setDiscount': ['MergedOps.write(widget.sub,'],
  'lib/screens/subscribers/sheets/subscriber_price_sheet.dart SubscriberPricesApi.remove': ['MergedOps.writeAt(widget.companyKey,'],
  'lib/screens/subscribers/sheets/subscriber_price_sheet.dart SubscriberPricesApi.set': ['MergedOps.writeAt(widget.companyKey,'],
  'lib/screens/subscribers/subscriber_detail_screen.dart SubscribersApi.delete': ['MergedOps.write(sub,'],
  'lib/screens/subscribers/subscriber_detail_screen.dart SubscribersApi.disconnect': ['MergedOps.write(sub,'],
  'lib/screens/subscribers/subscriber_detail_screen.dart SubscribersApi.toggleResult': ['MergedOps.write(sub,'],
  'lib/screens/subscribers/widgets/private_note_card.dart PrivateNotesApi.save': ['MergedOps.write(widget.sub,'],
  'lib/services/receipt_service.dart SubscribersApi.receiptLink': ['CompanyRoute.pin(key=sub.companyKey,'],
};

/// `_co(...)` في شيتَي «مشترك جديد»: شركة الشيت (run بمفتاحها)، وبلاها في «كل الشركات» ⇒ المفتوحة صراحةً.
final _coDef = RegExp(r'Future<T>\s+_co<T>\(Future<T> Function\(\) f\)\s*\{\s*final c = widget\.company;\s*'
    r'if \(c != null\) return CompanyRoute\.run\(c\.key, f\);\s*'
    r'return MergedMode\.active\.value \? CompanyRoute\.runOpen\(f\) : f\(\);\s*\}');

/// كتّاب المشترك مشتقّون كما رُوجعوا، وكلّ نداءٍ لهم من خارج lib/api بغلافه المراجَع حرفاً وخارج كلّ إغلاقٍ مؤجَّل، والجماعيّة بحارسها
/// في دالّتها.
List<String> writerVerdict(Lib lib) {
  final writers = subscriberWriters(lib, readsByPost: reviewedReadPaths);
  final r = writerSites(lib, writers, bulk: reviewedBulk.keys.toSet());
  final out = <String>[
    if (!_same(writers, expectedSubscriberWriters))
      _diff('واجهة كتابةٍ على مشترك — راجع نداءاتها ثمّ حدّث القائمة', expectedSubscriberWriters, writers),
    for (final b in r.bad) '$b — مرّرها بـMergedOps بالصفّ نفسه',
    if (!_same(r.bulkSeen, reviewedBulk.keys.toSet())) _diff('نداءٌ جماعيّ', reviewedBulk.keys.toSet(), r.bulkSeen),
    ...bulkGuardViolations(lib, reviewedBulk),
  ];
  final sites = {...r.prefixes.keys, ...reviewedWriterPrefixes.keys};
  for (final s in sites) {
    final got = r.prefixes[s] ?? const <String>[];
    final want = reviewedWriterPrefixes[s] ?? const <String>[];
    if (got.join('|') != want.join('|')) {
      out.add('$s: غلافه $got والمراجَع $want — runOpen أو pin بغير شركة الصفّ يكتب لمشتركٍ آخر بالرقم نفسه؛ راجعه ثمّ حدّث القائمة');
    }
  }
  for (final s in r.prefixes.entries.where((e) => e.value.contains('_co('))) {
    final f = s.key.split(' ').first;
    if (!_coDef.hasMatch(lib[f]!.raw)) out.add('$f: _co بتعريفٍ غير المراجَع');
  }
  return out;
}

// ─────────────────────────── ٥. شركة كتابات المال في الشاشات ───────────────────────────

const expectedMoneyWriters = {
  'SalesApi.createItem', 'SalesApi.updateItem', 'SalesApi.stock', 'SalesApi.voidMove', 'SalesApi.sell', 'SalesApi.voidSale',
  'SalesApi.resolve', 'SalesApi.resolveVoid', 'SettlementsApi.open', 'SettlementsApi.settle', 'SettlementsApi.voidSettlement',
  'ExpensesApi.create', 'ExpensesApi.update', 'ExpensesApi.delete', 'RecurringExpensesApi.create', 'RecurringExpensesApi.update',
  'RecurringExpensesApi.pause', 'RecurringExpensesApi.resume', 'RecurringExpensesApi.delete', 'RecurringExpensesApi.payNow',
  'RecurringExpensesApi.confirm', 'RecurringExpensesApi.skip',
};

const expectedMoneySheets = {
  '_VoidSheet', '_ResolveSheet', '_ItemSheet', '_StockSheet', '_DefectSheet', '_MovesSheet', '_NewSaleSheet', '_TemplateSheet',
  '_PayNowSheet', '_ConfirmRunSheet', '_SettleSheet', '_DetailSheet', '_AddExpenseSheet', '_EditExpenseSheet',
  'showAddExpenseSheet', 'showEditExpenseSheet', 'showSettleSheet', 'showSettlementDetailSheet', 'showSellToSubscriber',
};

/// مصدرٌ غير المعتاد في موضعٍ مراجَعٍ وحده.
const reviewedMoneyLiteral = {
  // «+ إضافة صرفية» بعد «في أيّ شركة؟» اختار المفتوحة (pickOpenCompanyFor) ⇒ لها صراحةً
  'lib/screens/main_shell.dart showAddExpenseSheet': 'null',
  // «بيع مادّة» من صفحة المشترك: شركة صفّه
  'lib/screens/subscribers/subscriber_detail_screen.dart showSellToSubscriber': 'sub.companyKey',
};

/// كلّ نداء كتابة مالٍ/شيت مالٍ خارج lib/api بمصدر شركته.
const reviewedMoneyKeys = <String, int>{
  'lib/screens/expenses/expenses_screen.dart ExpensesApi.delete companyKey: companyKey': 1,
  'lib/screens/expenses/expenses_screen.dart showAddExpenseSheet companyKey: _companyKey': 1,
  'lib/screens/expenses/expenses_screen.dart showEditExpenseSheet companyKey: _companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.confirm companyKey: widget.companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.create companyKey: widget.companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.delete companyKey: key': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.pause companyKey: _companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.payNow companyKey: widget.companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.resume companyKey: _companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.skip companyKey: key': 1,
  'lib/screens/expenses/recurring_expenses_section.dart RecurringExpensesApi.update companyKey: widget.companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart _ConfirmRunSheet companyKey: _companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart _PayNowSheet companyKey: _companyKey': 1,
  'lib/screens/expenses/recurring_expenses_section.dart _TemplateSheet companyKey: _companyKey': 1,
  'lib/screens/expenses/sheets/add_expense_sheet.dart ExpensesApi.create companyKey: widget.companyKey': 1,
  'lib/screens/expenses/sheets/add_expense_sheet.dart _AddExpenseSheet companyKey: companyKey': 1,
  'lib/screens/expenses/sheets/edit_expense_sheet.dart ExpensesApi.update companyKey: widget.companyKey': 1,
  'lib/screens/expenses/sheets/edit_expense_sheet.dart _EditExpenseSheet companyKey: companyKey': 1,
  'lib/screens/main_shell.dart showAddExpenseSheet companyKey: null': 1,
  'lib/screens/sales/sales_screen.dart SalesApi.createItem companyKey: widget.companyKey': 1,
  'lib/screens/sales/sales_screen.dart SalesApi.resolve companyKey: widget.companyKey': 1,
  'lib/screens/sales/sales_screen.dart SalesApi.resolveVoid companyKey: widget.companyKey': 1,
  'lib/screens/sales/sales_screen.dart SalesApi.sell companyKey: widget.companyKey': 1,
  'lib/screens/sales/sales_screen.dart SalesApi.stock companyKey: widget.companyKey': 2,
  'lib/screens/sales/sales_screen.dart SalesApi.updateItem companyKey: widget.companyKey': 1,
  'lib/screens/sales/sales_screen.dart SalesApi.voidMove companyKey: widget.companyKey': 1,
  'lib/screens/sales/sales_screen.dart SalesApi.voidSale companyKey: widget.companyKey': 1,
  'lib/screens/sales/sales_screen.dart _DefectSheet companyKey: _co': 1,
  'lib/screens/sales/sales_screen.dart _ItemSheet companyKey: _co': 3,
  'lib/screens/sales/sales_screen.dart _MovesSheet companyKey: _co': 1,
  'lib/screens/sales/sales_screen.dart _NewSaleSheet companyKey: _co': 2,
  'lib/screens/sales/sales_screen.dart _NewSaleSheet companyKey: companyKey': 1,
  'lib/screens/sales/sales_screen.dart _ResolveSheet companyKey: _co': 1,
  'lib/screens/sales/sales_screen.dart _StockSheet companyKey: _co': 1,
  'lib/screens/sales/sales_screen.dart _VoidSheet companyKey: _co': 1,
  'lib/screens/settlements/settlements_screen.dart SettlementsApi.open companyKey: _companyKey': 1,
  'lib/screens/settlements/settlements_screen.dart showSettleSheet companyKey: _companyKey': 1,
  'lib/screens/settlements/settlements_screen.dart showSettlementDetailSheet companyKey: _companyKey': 1,
  'lib/screens/settlements/sheets/settle_sheet.dart SettlementsApi.settle companyKey: widget.companyKey': 1,
  'lib/screens/settlements/sheets/settle_sheet.dart _SettleSheet companyKey: companyKey': 1,
  'lib/screens/settlements/sheets/settlement_detail_sheet.dart SettlementsApi.voidSettlement companyKey: widget.companyKey': 1,
  'lib/screens/settlements/sheets/settlement_detail_sheet.dart _DetailSheet companyKey: companyKey': 1,
  // زرّ «بيع مادّة» + «بيع لفلان» بالأمر الصوتيّ (١٠ نوفمبر، _runAutoAction) — كلاهما شركة صفّ الصفحة نفسه
  'lib/screens/subscribers/subscriber_detail_screen.dart showSellToSubscriber companyKey: sub.companyKey': 2,
};

/// كاتبات المال وشيتاته كما رُوجعت، وكلّ نداءٍ لها في الشاشات (المجلّدات كلّها) بمصدر شركةٍ مراجَع — لا من الشريط، وnull في موضعٍ
/// مراجَعٍ وحده — والجرد مساوٍ للمراجَع.
List<String> moneyKeyVerdict(Lib lib) {
  final writers = moneyWriters(lib, readsByPost: reviewedReadPaths);
  final sheets = moneySheets(lib);
  final r = moneyKeySites(lib, writers: writers, sheets: sheets, reviewedLiteral: reviewedMoneyLiteral);
  final out = <String>[
    if (!_same(writers, expectedMoneyWriters))
      _diff('كاتبة مال — أضفها لاختبار المعترض (٢٢ كتابة بمفتاحها) وراجع نداءاتها', expectedMoneyWriters, writers),
    if (!_same(sheets, expectedMoneySheets)) _diff('شيت مال — راجع من يفتحه وبأيّ شركة', expectedMoneySheets, sheets),
    for (final b in r.bad) '$b — كتابة مالٍ تذهب لشركةٍ غير المعروضة',
  ];
  for (final k in {...r.inventory.keys, ...reviewedMoneyKeys.keys}) {
    if (r.inventory[k] != reviewedMoneyKeys[k]) {
      out.add('$k: ${r.inventory[k] ?? 0} نداء والمراجَع ${reviewedMoneyKeys[k] ?? 0} — مصدر شركةٍ جديد أو تغيّر: راجعه ثمّ حدّث الجرد');
    }
  }
  return out;
}

// ─────────────────────────── ٧. كتّابٌ لكلّ مشتركٍ خارج /api/v2/subscribers ───────────────────────────

const reviewedSideWriters = <String, (String, String, String)>{
  'lib/screens/managers/sheets/send_info_sheet.dart#_send WhatsAppApi.sendMessage':
      ('manager', '', 'بيانات دخولٍ لمدير (هاتفه) لا لمشترك — والمدراء «للعرض» بلا أفعال في غير المفتوحة'),
  'lib/screens/managers/sheets/telegram_link_sheet.dart#_sendViaWhatsApp WhatsAppApi.sendMessage':
      ('manager', '', 'رابط تلغرام لمدير — كسابقه'),
  'lib/services/manager_notice.dart#notify WhatsAppApi.sendMessage': ('manager', '', 'إشعار مديرٍ بعد عمليّة رصيدٍ له'),
  'lib/screens/subscribers/connection_alert_flow.dart#showConnectionAlertFlow WhatsAppApi.sendMessage':
      ('guard', '', '«تنبيه المشترك» للشركة وحدها (MergedOps.unsupported) — قوالبها وواتسابها'),
  'lib/screens/subscribers/sheets/qr_login_sheet.dart#_sendWhatsApp WhatsAppApi.sendMessage':
      ('guard', '', 'إرسال رمز الدخول من واتسابٍ للشركة وحدها'),
  'lib/screens/subscribers/subscriber_detail_screen.dart#_sendTemplate WhatsAppApi.sendTemplateWithPreview':
      ('guard', '', 'قوالب واتساب (المعاينة ثمّ الإرسال) للشركة وحدها'),
  'lib/screens/subscribers/subscribers_screen.dart#_sendDebtReminderFromList WhatsAppApi.sendTemplateWithPreview':
      ('gate', r'!_mergedOn\b', 'تذكير الدين من القائمة لا يُعرض في «كل الشركات»'),
  'lib/services/manual_wa_sender.dart#handleWaPreviewAfterOp WhatsAppApi.sendMessage':
      ('open-guard', '', 'التلقائيّ من واتساب المفتوحة صراحةً، وصفّ غيرها يُرفض قبله (autoWaBlockedFor)'),
  'lib/screens/subscribers/sheets/device_config_sheet.dart#_save DeviceConfigApi.saveConfig': (
    'entry',
    'lib/screens/subscribers/widgets/device_probe_card.dart#_openConfig DeviceConfigSheet',
    'إعداد الجهاز يُفتح من كارت الجهاز وحده بعد MergedOps.unsupportedAt',
  ),
  'lib/screens/subscribers/sheets/device_config_sheet.dart#_reset DeviceConfigApi.resetConfig':
      ('entry', 'lib/screens/subscribers/widgets/device_probe_card.dart#_openConfig DeviceConfigSheet', 'كسابقه'),
  'lib/services/receipt_service.dart#_emit PrintedReceiptsApi.archive': ('row', '', 'أرشيف الوصل لشركة المشترك'),
  'lib/screens/subscribers/sheets/fiberx_extend_flow.dart#showFiberxExtendFlow SubscribersApi.fiberxExtendNotice':
      ('gate', r'\bsub\.companyKey\s*==\s*null\b', 'إشعار فايبر اكس لصفٍّ بلا مفتاح وحده (مشترك الجلسة)'),
  'lib/screens/telegram/sheets/telegram_bindings_sheet.dart#_unbind TelegramApi.unbind':
      ('gate', r'!widget\.readOnly\b', 'فكّ الربط مخفيٌّ في «للعرض» (قسم تلغرام لشركةٍ أخرى)'),
  'lib/screens/telegram/sheets/telegram_link_generator_sheet.dart#_sendViaWa TelegramApi.sendLinkViaWa':
      ('section', 'lib/screens/telegram/', 'قسم تلغرام (/api/telegram): المعترض يرفض كتابته الضمنيّة تحت شركةٍ أخرى'),
};

/// كلّ نداءٍ لكتّاب المشترك خارج /api/v2/subscribers مراجَعٌ بطريقته، والجرد مساوٍ للمراجَع.
List<String> sideVerdict(Lib lib) {
  final r = sideWriterSites(lib, reviewedSideWriters);
  return [
    for (final b in r.bad) '$b — رسالة/إعداد/أرشيف لمشترك قد يخرج باسم شركةٍ غير شركته',
    if (!_same(r.seen, reviewedSideWriters.keys.toSet())) _diff('موضع كاتبٍ لمشترك', reviewedSideWriters.keys.toSet(), r.seen),
  ];
}
