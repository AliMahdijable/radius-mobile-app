import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/earthlink_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/contact_picker.dart';
import '../../../models/package_change.dart';
import '../../../models/subscriber.dart';
import '../../../services/merged_mode.dart';
import '../../../services/active_company.dart';
import '../../../services/auth_storage.dart';
import '../../../services/permissions_service.dart';
import '../../../services/provider_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/package_picker_field.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';

/// متى تتغيّر باقة مشتركٍ **فعّال** في SAS4 — خيار الساس نفسه (`user/changeProfile`
/// بـ`change_type`)، بقرار المالك ١٨ أكتوبر. غير الفعّال «حالاً» وحدها كالساس.
enum PackageChangeTiming {
  /// «حالاً»: الساس يلغي الاشتراك الحاليّ — يصفّر تاريخ الانتهاء إلى لحظة التغيير
  /// (مُثبَتٌ حيّاً على سوبرنت) فيُعتبر المشترك منتهياً. إلّا سوبرنت: الخادم يعيد التاريخ
  /// الأصليّ لمن يملك تعديله (`immediate_keeps_date` في activation-data) كما كان الكلاسيك.
  immediate,

  /// «عند انتهاء الاشتراك»: يكمل الاشتراك الحاليّ، والباقة تتغيّر في موعد انتهائه
  /// (تُلغى من الشيت نفسه قبل موعدها).
  schedule;

  /// القيمة كما يقرؤها الخادم (`change_type`).
  String get wire => this == immediate ? 'immediate' : 'schedule';
}

/// هل يُمنع تغيير الباقة الآن؟ — القاعدة **السابقة**، وتبقى لحالتين:
///
/// • ايرث لنك على قاعدتها (canChangeAccount): تتغيّر للمنتهي ولمن بقي له يومٌ فأقلّ، و«More»
///   لا. الحَكَم [earthlinkAllows] (`can_change_package` بصفّ المشترك — حكم الخادم)، وبلاه
///   (خادمٌ أقدم) نافذة اليوم الأخير ٢٤ ساعة — كورقتي التفعيل والتمديد. والتاريخ لا يُرسَل لها.
/// • SAS4 أمام خادمٍ **لا يعرف** «حالاً / عند انتهاء الاشتراك» (activation-data بلا حقوله):
///   يُمنع أثناء التفعيل ما لم يُرسَل التاريخ الأصليّ مع الطلب ليعيده الخادم ([keepsDate])،
///   فالساس يصفّر تاريخ الانتهاء عند تغيير باقة الفعّال — وبلاه يُقطع اشتراكه.
///
/// والخادم الذي يعرفهما يسلك [offersPackageChangeTiming] بدلها.
bool packageChangeBlocked({
  required bool changesPackage,
  required DateTime? activeUntil,
  required bool keepsDate,
  required bool isEarthlink,
  bool? earthlinkAllows,
  DateTime? now,
}) {
  if (!changesPackage) return false;
  final at = now ?? DateTime.now();
  if (isEarthlink) {
    if (earthlinkAllows != null) return !earthlinkAllows;
    return activeUntil != null &&
        activeUntil.difference(at) > const Duration(hours: 24);
  }
  if (activeUntil == null || !activeUntil.isAfter(at)) return false;
  return !keepsDate;
}

/// يُعرض اختيار «حالاً / عند انتهاء الاشتراك»؟ SAS4 (لا ايرث لنك) لمشتركٍ فعّال تتغيّر
/// باقته، والخادم يعرف `change_type` ([timingSupported]): خادمٌ أقدم يتجاهله فتصير «عند
/// انتهاء الاشتراك» تغييراً فوريّاً يقطع الاشتراك — فلا يُعرض له.
bool offersPackageChangeTiming({
  required bool changesPackage,
  required bool active,
  required bool isEarthlink,
  required bool timingSupported,
}) =>
    changesPackage && active && !isEarthlink && timingSupported;

/// هل يُرسَل تاريخ الانتهاء مع طلب التعديل؟ (لمن يملكه — [canEditExpiration])
///
/// • ما عدّله المدير بيده: دائماً.
/// • الأصليّ غير المعدَّل: مع تغيير الباقة أمام **خادمٍ أقدم** وحده ([legacyServer]) — يعيده
///   بعد أن يصفّره الساس (الكلاسيك)، وهو ما تسمح به القاعدة السابقة ([packageChangeBlocked]
///   بـkeepsDate). والخادم الذي يعرف «حالاً / عند انتهاء الاشتراك» لا يحتاجه (كالويب): يُبقي
///   تاريخ سوبرنت مع «حالاً» بنفسه، والجدولة لا تمسّ التاريخ، وخارج سوبرنت يلغي الساس الاشتراك
///   كما يقول التنبيه. وإرسال الأصليّ بلا داعٍ قد يُرجع تاريخاً مُدِّد بعد فتح الشيت.
bool sendsExpiration({
  required bool canEditExpiration,
  required bool hasExpiration,
  required bool expirationEdited,
  required bool changesPackage,
  required bool legacyServer,
}) {
  if (!canEditExpiration || !hasExpiration) return false;
  return expirationEdited || (legacyServer && changesPackage);
}

/// Edit subscriber sheet — focused port of v1's _showEditSheet from
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart.
/// First pass covers the 6 most commonly edited fields:
///   • username (rename — risky, allowed because admins do use it)
///   • password (blank → unchanged; only typed value lands in body)
///   • firstname / lastname (Arabic name)
///   • phone
///   • profile / package (dropdown from cached packages catalogue)
///
/// expiration + parent_id are intentionally omitted from this first
/// cut — both need extra plumbing (date picker / managers fetch)
/// and were permission-gated in v1 anyway. They can layer on later
/// without disturbing this sheet's shape.
///
/// Submit calls SubscribersApi.updateSubscriber with ONLY the fields
/// that changed; backend already diffs internally but sending less
/// keeps the request honest and the logs clearer. On success the
/// sheet pops + notifyChange so the open detail screen re-fetches.
Future<bool?> showEditSubscriberSheet(
  BuildContext context,
  Subscriber sub,
) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditSheet(sub: sub),
  );
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _username =
      TextEditingController(text: widget.sub.username);
  // Pre-fill with the SAS4-stored password so the admin can reveal
  // it (eye toggle) to check / copy / decide whether to change.
  // Falls back to '' when the backend hasn't surfaced the field yet
  // (older client + new backend gap window).
  late final TextEditingController _password =
      TextEditingController(text: widget.sub.password ?? '');
  late final TextEditingController _firstname =
      TextEditingController(text: widget.sub.firstname);
  late final TextEditingController _lastname =
      TextEditingController(text: widget.sub.lastname);
  late final TextEditingController _phone = TextEditingController(
    text: (widget.sub.phone?.isNotEmpty ?? false)
        ? widget.sub.phone!
        : (widget.sub.mobile ?? ''),
  );

  /// ايرث لنك وحدها: كلمة سرّ **حساب البوّابة** — نقطةٌ منفصلة عن كلمة سرّ
  /// الخدمة أعلاه، تُقرأ وتُغيَّر عبر `/account-password`.
  final TextEditingController _accountPassword = TextEditingController();

  /// القيمة الأصليّة المجلوبة (أو '' حين تعذّر الجلب) — للمقارنة: لا تُرسَل
  /// كلمة سرّ الحساب إن لم تتغيّر.
  String? _loadedAccountPassword;
  bool _showAccountPassword = false;
  // Set in initState — Dart forbids referencing `widget` at field-
  // initializer level for non-`late` fields, and `late int?` reads
  // awkwardly. Plain field + assignment in initState matches the
  // pattern the other sheets use for nullable mutable state.
  int? _profileId;
  Map<String, PackageInfo>? _packages;
  bool _loadingPackages = true;
  bool _saving = false;

  /// activation-data قالت `provider: 'earthlink'` — احتياطٌ إن لم تُعرف
  /// الجلسة بعد من [ProviderService].
  bool _elFromData = false;

  /// جلسة ايرث لنك ⇒ حقل الباقة يفتح قائمةً ببحث (بلاغ ٢٠٢٦-١٠-١٣)؛
  /// وغيرها يبقى على القائمة المنسدلة كما هي.
  bool get _isEarthlink =>
      _elFromData ||
      // «كل الشركات»: مزوّد شركة المشترك لا الشركة المفتوحة
      (MergedOps.isEarthlink(widget.sub) ??
          (ProviderService.isEarthlink || ActiveCompany.current?.sasCode == 'earthlink'));

  /// Whether the password field is revealed (eye icon toggled on).
  /// مطلب 2026-06-10: pre-fill + eye toggle so admins can verify
  /// the existing password before deciding to change it.
  bool _showPassword = false;

  /// Whether the admin can change the parent ('تابع إلى'). Mirrors
  /// v1's canPickParent = canAccessManagers — مدير بصلاحية إنشاء
  /// المدراء الفرعيين يقدر يعيد إسناد المشترك لمدير آخر.
  bool _canPickParent = false;

  /// Whether the admin can edit the expiration date. Mirrors v1's
  /// canEditExpiration = canAccessManagers OR canAccessPackages.
  /// الأدمن الفرعي العادي ما يقدر يغيّر تاريخ الانتهاء.
  bool _canEditExpiration = false;

  /// Edited expiration date — null means 'keep original'. Format
  /// matches SAS4: 'YYYY-MM-DD HH:mm:ss'.
  DateTime? _expiration;

  /// تاريخ الانتهاء كما قرأه الشيت من الساس (activation-data، وقبلها صفّ القائمة) —
  /// مرجع «فعّال؟» و«هل عدّل المدير التاريخ؟». [_expiration] قيمة المنتقي.
  DateTime? _loadedExpiration;

  /// لمس المدير منتقي التاريخ — فلا تدهس activation-data اختياره حين تصل بعده.
  bool _expirationTouched = false;

  // ── تغيير الباقة «حالاً / عند انتهاء الاشتراك» (SAS4، قرار المالك ١٨ أكتوبر) ──

  /// اختيار المدير — null = لم يختر بعد فتسري «عند انتهاء الاشتراك» (افتراض الساس والويب:
  /// لا يلغي شيئاً ولا يغيّر شيئاً الآن).
  PackageChangeTiming? _timingPick;

  /// حال الباقة من activation-data: فعّال؟ مجدولٌ ينتظر؟ صلاحيّة تغيير باقة الفعّال؟
  /// «حالاً» يُبقي التاريخ؟ — وخادمٌ أقدم لا يرسلها (`supported: false`).
  PackageChangeInfo _pc = const PackageChangeInfo();

  /// وصل ردّ activation-data (نجح أو فشل) — قبله لا يُرسَل تغيير باقة: حال الاشتراك من
  /// الساس لم يُعرف بعد (صفّ القائمة قد يكون قديماً).
  bool _detailsLoaded = false;

  /// activation-data تعذّرت (شبكة/ساس) — لا «خادمٌ أقدم»: تغيير باقة SAS4 يتوقّف مع
  /// «أعد المحاولة» بدل القاعدة السابقة بنسخة القائمة (كانت تُرسل تاريخ الصفّ القديم).
  bool _detailsFailed = false;
  bool _cancellingScheduled = false;

  /// الباقة الآن — من الساس (activation-data) لـSAS4، وإلّا صفّ القائمة. مرجع «تغيّرت؟».
  int? _originalProfileId;

  /// اختار المدير باقةً بيده — فلا تدهسها activation-data حين تصل (والحقل معطّلٌ قبلها
  /// لـSAS4 أصلاً).
  bool _pkgPicked = false;

  /// رفض الساس تغيير الباقة لهذا المدير — `PACKAGE_CHANGE_ACTIVE_FORBIDDEN` (للفعّال) أو
  /// `PACKAGE_CHANGE_FORBIDDEN` (لأيّ مشترك): يُقفل الحقل بسببه، كما لو عرفناه مسبقاً.
  bool _activeChangeRefused = false;
  bool _changeRefused = false;

  /// ايرث لنك: لا تاريخ انتهاء يُضبط (التفعيل وحده يحكمه) ولا مدراء فرعيّون —
  /// الخادم يتجاهل الحقلين («لم يتغيّر شيء») فلا يُعرضان ولا يُرسلان أبداً،
  /// للمالك ولموظّفه (الموظّف بـ`packages.view` كان يرى منتقي التاريخ).
  bool get _showExpiration => _canEditExpiration && !_isEarthlink;
  bool get _showParent => _canPickParent && !_isEarthlink;

  /// Edited parent (تابع إلى) — null means 'keep original'.
  int? _parentId;
  List<({int id, String username, String firstname, String lastname})>?
      _managers;
  bool _loadingManagers = false;

  @override
  void initState() {
    super.initState();
    _profileId = widget.sub.profileId;
    _originalProfileId = widget.sub.profileId;
    // Listen on every text controller so the 'حفظ التغييرات' button
    // re-evaluates _hasChanges on each keystroke — without these the
    // button was stuck disabled because nothing triggered a rebuild
    // when the admin typed (مطلب 2026-06-10).
    void touch() {
      if (mounted) setState(() {});
    }
    _username.addListener(touch);
    _password.addListener(touch);
    _firstname.addListener(touch);
    _lastname.addListener(touch);
    _phone.addListener(touch);
    _accountPassword.addListener(touch);
    _loadPackages();
    // Parse the original expiration so the picker can show it
    // alongside the 'change' control. SAS4 emits both 'YYYY-MM-DD
    // HH:mm:ss' and 'YYYY-MM-DDTHH:mm:ss'; both DateTime.tryParse'able
    // after normalizing the space.
    final exp = widget.sub.expiration?.trim();
    if (exp != null && exp.isNotEmpty) {
      _expiration = DateTime.tryParse(exp.replaceFirst(' ', 'T'));
    }
    _loadedExpiration = _expiration ?? widget.sub.parsedExpiration;
    _loadDetails(); // pre-fill password + parent_id from SAS4
    _resolveSuperAdmin();
  }

  /// Fire two parallel fetches:
  ///   • /api/v2/subscribers/:idx/password → cleartext password
  ///     (SAS4 hides it from /user/:idx; the dedicated endpoint
  ///     reads /user/overview/:idx which exposes it). Matches the
  ///     v2 web edit modal flow.
  ///   • /api/v2/subscribers/:idx/activation-data → parent_id +
  ///     expiration for the super-admin pickers.
  Future<void> _loadDetails() async {
    final idx = widget.sub.idx;
    if (idx == null) return;
    final pwFuture = MergedOps.run(widget.sub, () => SubscribersApi.fetchPassword(idx));
    final dataFuture = MergedOps.run(widget.sub, () => SubscribersApi.fetchActivationData(idx));
    // ايرث لنك: كلمة سرّ حساب البوّابة — تُجلب بالتوازي (نقطةٌ منفصلة عن
    // كلمة سرّ الخدمة). الجلسة تُعرَف متزامنةً عبر [ProviderService].
    final elNow = MergedOps.isEarthlink(widget.sub) ??
        (ProviderService.isEarthlink || ActiveCompany.current?.sasCode == 'earthlink');
    final accFuture = elNow ? MergedOps.run(widget.sub, () => EarthlinkApi.fetchAccountPassword(idx)) : null;
    final pw = await pwFuture;
    final data = await dataFuture;
    final acc = accFuture == null ? null : await accFuture;
    if (!mounted) return;
    setState(() {
      if (pw != null && pw.isNotEmpty && _password.text.isEmpty) {
        _password.text = pw;
      }
      if (data != null) {
        if (data['provider']?.toString() == 'earthlink') _elFromData = true;
        final parent = data['parent_id'];
        final pid =
            parent is int ? parent : int.tryParse(parent?.toString() ?? '');
        if (pid != null) _parentId = pid;
        _applyPackageState(data);
      }
      _detailsLoaded = true;
      _detailsFailed = data == null;
      if (elNow) {
        // '' حين تعذّر الجلب: الحقل يبقى فارغاً ويقدر المدير ضبط قيمةٍ جديدة.
        _loadedAccountPassword = acc ?? '';
        if (acc != null && acc.isNotEmpty && _accountPassword.text.isEmpty) {
          _accountPassword.text = acc;
        }
      }
    });
  }

  /// حال الباقة من activation-data (التحميل الأوّل، و«أعد المحاولة»، وبعد ردٍّ غير حاسم) —
  /// يُنادى داخل setState:
  ///   • تاريخ الساس مرجعاً، والمنتقي لا يُدهس إن لمسه المدير.
  ///   • [_pc] (لا ايرث لنك — قاعدتها canChangeAccount).
  ///   • SAS4: الباقة الآن من الساس أصلاً (صفّ القائمة قد يكون أقدم)، وقفلٌ وصل (صلاحيّة
  ///     الساس) يعيد الباقة لأصلها ويُسقط «متى؟» — فلا شيتٌ عالقٌ على باقةٍ لا تُحفظ ولا تُرجَع.
  void _applyPackageState(Map<String, dynamic> data) {
    final rawExp = data['expiration']?.toString().trim();
    if (rawExp != null && rawExp.isNotEmpty) {
      final parsed = DateTime.tryParse(rawExp.replaceFirst(' ', 'T'));
      if (parsed != null) {
        // الأحدث من الساس مرجعاً؛ والمنتقي لا يُدهس إن لمسه المدير قبل وصوله.
        _loadedExpiration = parsed;
        if (!_expirationTouched) _expiration = parsed;
      }
    }
    if (_isEarthlink) return;
    _pc = PackageChangeInfo.fromActivationData(data);
    if (!_sasRules) return;
    final current = _pc.profileId;
    if (current != null) _originalProfileId = current;
    if (!_pkgPicked || _packageLocked) {
      _profileId = _originalProfileId;
      _pkgPicked = false;
      _timingPick = null;
    }
  }

  /// يعيد قراءة حال الباقة وحده (activation-data) — «أعد المحاولة» بعد تعذّرها، أو بعد ردٍّ
  /// غير حاسم من الساس (PACKAGE_CHANGE_UNCONFIRMED) ليعرض الحقل ما عند الساس فعلاً. الحقل
  /// معطّلٌ أثناءها («لحظةً…»)، وبقيّة الحقول كما عدّلها المدير.
  Future<void> _reloadPackageState() async {
    final idx = widget.sub.idx;
    if (idx == null || !mounted) return;
    setState(() {
      _detailsLoaded = false;
      _detailsFailed = false;
    });
    final data = await MergedOps.run(widget.sub, () => SubscribersApi.fetchActivationData(idx));
    if (!mounted) return;
    setState(() {
      if (data != null) {
        if (data['provider']?.toString() == 'earthlink') _elFromData = true;
        if (_parentId == null) {
          final parent = data['parent_id'];
          _parentId =
              parent is int ? parent : int.tryParse(parent?.toString() ?? '');
        }
        _applyPackageState(data);
      }
      _detailsLoaded = true;
      _detailsFailed = data == null;
    });
  }

  Future<void> _resolveSuperAdmin() async {
    final canManagers = await AuthStorage.readCanAccessManagers();
    final canPackages = await AuthStorage.readCanAccessPackages();
    if (!mounted) return;
    // ايرث لنك: لا قائمة مدراء تُجلب لمنتقٍ لا يُعرض ([_showParent]).
    final loadManagers = canManagers && !_isEarthlink;
    setState(() {
      _canPickParent = canManagers;
      _canEditExpiration = canManagers || canPackages;
      _loadingManagers = loadManagers;
    });
    if (loadManagers) {
      final list = await MergedOps.run(widget.sub, () => SubscribersApi.loadManagers());
      if (!mounted) return;
      setState(() {
        _managers = list;
        _loadingManagers = false;
      });
    }
  }

  Future<void> _loadPackages() async {
    final pkgs = await MergedOps.run(widget.sub, () => SubscribersApi.loadPackages());
    if (!mounted) return;
    setState(() {
      _packages = pkgs;
      _loadingPackages = false;
    });
  }

  /// باقات ايرث لنك للحقل — بترتيب القائمة المنسدلة نفسه (بالاسم)، وبالمعرّفات
  /// الرقميّة وحدها (غيرها لم يكن قابلاً للاختيار فيها أصلاً).
  List<PackageOption> get _elPackageOptions {
    final pkgs = _packages;
    if (pkgs == null) return const [];
    final entries = pkgs.entries
        .where((e) => int.tryParse(e.key) != null)
        .toList()
      ..sort((a, b) => a.value.name.compareTo(b.value.name));
    return [
      for (final e in entries)
        PackageOption(id: e.key, name: e.value.name, price: e.value.price),
    ];
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _firstname.dispose();
    _lastname.dispose();
    _phone.dispose();
    _accountPassword.dispose();
    super.dispose();
  }

  // ═══════════ تغيير الباقة: «حالاً» أو «عند انتهاء الاشتراك» (SAS4) ═══════════
  //
  // قرار المالك ١٨ أكتوبر: لمشتركٍ **فعّال** في أيّ ساس SAS4 (لا ايرث لنك — قاعدتها
  // canChangeAccount) يختار المدير متى تتغيّر الباقة، كلوحة الساس نفسها:
  //   • «حالاً» — الساس يلغي الاشتراك الحاليّ فيُعتبر المشترك منتهياً؛ إلّا سوبرنت: الخادم
  //     يعيد التاريخ الأصليّ لمن يملك تعديله (كالكلاسيك).
  //   • «عند انتهاء الاشتراك» — تُجدوَل، وتُعرض «مجدول: … عند …» بزرّ إلغاء.
  // غير الفعّال «حالاً» وحدها بلا سؤال. وتغيير باقة الفعّال يحتاج صلاحيّة الساس
  // `prm_users_change_profile_active` — بلاها يُقفل الحقل بسببه بدل رفضٍ بعد الحفظ.
  // وتغييرٌ جديد فوق مجدولٍ ينتظر: الخادم يلغي المجدول أوّلاً، فآخر اختيارٍ هو ما يسري.

  /// تتغيّر الباقة في هذا التعديل؟ (عن الباقة الآن في الساس، لا عن صفّ القائمة)
  bool get _changesPackage =>
      _profileId != null && _profileId != _originalProfileId;

  /// SAS4 بلا حال اشتراكٍ واصل من الساس (يُقرأ، أو تعذّر): حقل الباقة معطّلٌ والسبب تحته —
  /// لا تغيير باقةٍ على صفٍّ قد يكون قديماً، ولا على خادمٍ مجهول.
  bool get _pkgWaiting => _sasRules && (!_detailsLoaded || _detailsFailed);

  static const _detailsFailedNote =
      'تعذّر قراءة حال اشتراك المشترك، فتغيير الباقة متوقّفٌ الآن (بقيّة الحقول تُحفظ)';

  /// تاريخ الانتهاء الأصليّ — للعرض ولتقدير «فعّال؟» (لا قيمة المنتقي المعدَّلة).
  DateTime? get _activeUntil => _loadedExpiration ?? widget.sub.parsedExpiration;

  /// فعّالٌ الآن؟ بمعيار الساس إن أرسله الخادم، وإلّا بالتاريخ.
  bool get _isActiveNow {
    final until = _activeUntil;
    return _pc.active ?? (until != null && until.isAfter(DateTime.now()));
  }

  /// القاعدة الجديدة لـSAS4 وحده: لا ايرث لنك، ولا FTTH (قراءةٌ فقط عنده).
  bool get _sasRules => !_isEarthlink && !ProviderService.isFtth;

  /// الخادم يعرف «حالاً / عند انتهاء الاشتراك» (activation-data بحقوله).
  bool get _timingSupported => _sasRules && _pc.supported;

  /// يملك تغيير باقة الفعّال؟ حكم الساس من الخادم أوّلاً (للموظّف: صلاحيّة مديره). وإن لم
  /// يُعرف: المدير بقدراته المعياريّة (الغائب = مسموح)، والموظّف لا مفتاح له بها فيحكم
  /// الساس عند الحفظ (`PACKAGE_CHANGE_ACTIVE_FORBIDDEN`).
  bool get _activeChangeAllowed {
    if (_activeChangeRefused) return false;
    final srv = _pc.canChangeActive;
    if (srv != null) return srv;
    return PermissionsService.isEmployee ||
        Perms.has('subscribers.change_profile_active');
  }

  /// الحقل مقفل: فعّالٌ والمدير لا يملك تغيير باقته — رفضه الساس للتوّ، أو قالها الخادم
  /// الجديد مسبقاً (الأقدم لا يعرفها ويمنع «حالاً» بلا تاريخٍ بقاعدته [packageChangeBlocked]).
  bool get _activeLocked {
    if (!_sasRules || !_isActiveNow) return false;
    if (_activeChangeRefused) return true;
    return _timingSupported && !_activeChangeAllowed;
  }

  /// يملك تغيير باقة أيّ مشترك (`prm_users_change_profile`)؟ حكم الخادم إن أرسله، وإلّا
  /// قدرات المدير المعياريّة (`subscribers.change_profile` — الغائب = مسموح)، والموظّف يحكم
  /// له الساس عند الحفظ (`PACKAGE_CHANGE_FORBIDDEN`).
  bool get _changeAllowed {
    final srv = _pc.canChangeProfile;
    if (srv != null) return srv;
    return PermissionsService.isEmployee ||
        Perms.has('subscribers.change_profile');
  }

  /// الحقل مقفل: لا يملك تغيير باقة أيّ مشترك — رفضه الساس للتوّ، أو عُرف مسبقاً أمام
  /// الخادم الجديد (الأقدم يبقى كما كان).
  bool get _changeLocked =>
      _changeRefused || (_timingSupported && !_changeAllowed);

  bool get _packageLocked => _changeLocked || _activeLocked;

  /// تغييرٌ مجدول ينتظر عند الساس.
  ScheduledPackageChange? get _scheduled =>
      _timingSupported ? _pc.scheduled : null;

  bool get _offersTiming => offersPackageChangeTiming(
        changesPackage: _changesPackage,
        active: _isActiveNow,
        isEarthlink: !_sasRules,
        timingSupported: _timingSupported,
      );

  /// عدّل المدير التاريخ بيده (لا مجرّد إعادة إرسال الأصليّ)؟
  bool get _expirationEdited =>
      _expirationTouched &&
      _expiration != null &&
      _expiration != _loadedExpiration;

  /// «حالاً» يُبقي التاريخ؟ حكم الخادم (سوبرنت لمن يملك تعديله)، أو تاريخٌ عدّله المدير.
  bool get _immediateKeepsDate =>
      _pc.immediateKeepsDate == true ||
      (_showExpiration && _expirationEdited);

  PackageChangeTiming get _timing =>
      _timingPick ?? PackageChangeTiming.schedule;

  /// خادمٌ أقدم لا يعرف «متى؟» — activation-data **وصلت** بلا حقولها. تعذّرُها ليس خادماً
  /// أقدم ([_detailsFailed] ⇒ [_pkgWaiting]): كان يسلك القاعدة السابقة فيرسل تاريخ الصفّ.
  bool get _legacyServer =>
      _sasRules && _detailsLoaded && !_detailsFailed && !_pc.supported;

  bool get _sendsExpiration => sendsExpiration(
        canEditExpiration: _showExpiration,
        hasExpiration: _expiration != null,
        expirationEdited: _expirationEdited,
        changesPackage: _changesPackage,
        legacyServer: _legacyServer,
      );

  /// جدولةٌ مع تعديل التاريخ في الطلب نفسه: الساس يجدول على تاريخ الانتهاء **الحاليّ**
  /// والجديد يُكتب بعده، فيفترقان — يُحفظ التاريخ وحده أوّلاً.
  bool get _scheduleWithDateEdit =>
      _offersTiming &&
      _timing == PackageChangeTiming.schedule &&
      _expirationEdited;

  static const _scheduleDateEditNote =
      'لتغيير الباقة «عند انتهاء الاشتراك» احفظ تعديل التاريخ وحده أوّلاً، '
      'أو اختر «حالاً»';

  static String _day(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String? _packageName(int? id) =>
      id == null ? null : _packages?[id.toString()]?.name;

  String get _scheduledName {
    final s = _scheduled;
    if (s == null) return '';
    if (s.profileName.isNotEmpty) return s.profileName;
    return _packageName(s.profileId) ?? 'باقة أخرى';
  }

  /// « (ينتهي <التاريخ>)» — ذيلٌ للرسائل، فارغٌ بلا تاريخ.
  String get _endsTail {
    final d = _day(_activeUntil);
    return d.isEmpty ? '' : ' (ينتهي ${iso(d)})';
  }

  Map<String, dynamic> _diff() {
    final original = widget.sub;
    final out = <String, dynamic>{};
    final u = _username.text.trim();
    if (u != original.username) out['username'] = u;
    // Diff vs ORIGINAL password — pre-filling with the current
    // value means an untouched field shouldn't fire an update. Only
    // a genuine change lands in the body.
    final pw = _password.text;
    if (pw.isNotEmpty && pw != (original.password ?? '')) {
      out['password'] = pw;
    }
    final fn = _firstname.text.trim();
    if (fn != original.firstname) out['firstname'] = fn;
    final ln = _lastname.text.trim();
    if (ln != original.lastname) out['lastname'] = ln;
    final ph = _phone.text.trim();
    final originalPh = (original.phone ?? '').isNotEmpty
        ? original.phone!
        : (original.mobile ?? '');
    if (ph != originalPh) out['phone'] = ph;
    // مقفلةٌ أو حالها لم يصل ⇒ لا تُرسَل الباقة (وبقيّة الحقول تُحفظ).
    if (_changesPackage && !_packageLocked && !_pkgWaiting) {
      out['profile_id'] = _profileId;
      // «متى؟» للفعّال وحده؛ غيره «حالاً» افتراض الخادم (كالتطبيقات القديمة).
      if (_offersTiming) out['change_type'] = _timing.wire;
    }
    // Super-admin fields. Only diff when the picker has actually
    // moved away from the original — empty/no-pick → not in the body.
    // Permission-gated diffs: only include parent_id when the user
    // can actually pick it, same for expiration. Sending them when
    // the field isn't visible would be a silent bug.
    if (_showParent && _parentId != null) {
      out['parent_id'] = _parentId;
    }
    // التاريخ: ما عدّله المدير، أو الأصليّ مع الباقة أمام خادمٍ أقدم (الكلاسيك) — [sendsExpiration].
    if (_sendsExpiration) {
      final d = _expiration!;
      String two(int n) => n.toString().padLeft(2, '0');
      out['expiration'] =
          '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }
    return out;
  }

  bool get _hasChanges => _diff().isNotEmpty || _accountPasswordChanged;

  /// ايرث لنك: هل تغيّرت كلمة سرّ الحساب عن المجلوبة؟ الفارغة لا تُرسَل
  /// (كحقل كلمة سرّ الخدمة تماماً).
  bool get _accountPasswordChanged =>
      _isEarthlink &&
      _accountPassword.text.isNotEmpty &&
      _accountPassword.text != (_loadedAccountPassword ?? '');

  /// سببٌ يمنع إرسال تغيير الباقة الآن (أو null). الحقل نفسه مقفلٌ في بعضها — هذا لما
  /// سبق القفل (اختارها قبل وصول activation-data)، ولقاعدة ايرث لنك والخادم الأقدم.
  String? _packageBlockReason(Map<String, dynamic> diff) {
    if (!diff.containsKey('profile_id')) return null;
    final until = _activeUntil;
    // ايرث لنك على قاعدتها، وSAS4 أمام خادمٍ لا يعرف «متى؟» على القاعدة السابقة.
    if (_isEarthlink || _legacyServer) {
      if (!packageChangeBlocked(
        changesPackage: true,
        activeUntil: until,
        keepsDate: diff.containsKey('expiration'),
        isEarthlink: _isEarthlink,
        earthlinkAllows: widget.sub.canChangePackage,
      )) {
        return null;
      }
      final d = _day(until);
      return _isEarthlink
          ? (widget.sub.packageChangeNote ??
              'تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ'
                  '${d.isEmpty ? '' : ' — ينتهي $d'}')
          : 'يمكن تغيير الباقة بعد انتهاء التفعيل الحاليّ — ينتهي $d';
    }
    if (!_sasRules) return null;
    // قبل ردّ activation-data لا يُعرف حال الاشتراك من الساس (صفّ القائمة قد يكون قديماً:
    // «منتهٍ» جدّده أحدٌ للتوّ) — لحظاتٌ عادةً: يُجلب مع فتح الشيت كالباقات.
    if (!_detailsLoaded) {
      return 'لحظةً — يُقرأ حال اشتراك المشترك';
    }
    if (_detailsFailed) return _detailsFailedNote;
    if (_changeLocked) {
      return 'صلاحيّتك في الساس لا تسمح بتغيير باقة المشترك';
    }
    if (_activeLocked) {
      return 'المشترك فعّال، وصلاحيّتك في الساس لا تسمح بتغيير باقته قبل '
          'انتهاء اشتراكه$_endsTail';
    }
    if (_scheduleWithDateEdit) {
      return _scheduleDateEditNote;
    }
    return null;
  }

  /// «حالاً» يلغي اشتراك الفعّال (لا تاريخ يبقى) — تأكيدٌ قبل ما لا رجعة فيه.
  Future<bool> _confirmImmediateCancels() async {
    final name = _packageName(_profileId);
    final ok = await showConfirmSheet(
      context,
      title: 'تغيير الباقة الآن؟',
      message: 'سيُعتبر المشترك منتهياً: تغيير الباقة'
          '${name == null ? '' : ' إلى ${iso(name)}'} الآن يلغي اشتراكه الحاليّ'
          '$_endsTail، ويحتاج تفعيلاً جديداً.\n'
          'ولإبقاء اشتراكه حتى نهايته اختر «عند انتهاء الاشتراك».',
      confirmLabel: 'غيّرها الآن',
      cancelLabel: 'تراجع',
      icon: LucideIcons.triangleAlert,
      tone: AppTone.warning,
    );
    return ok == true;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final diff = _diff();
    final accChanged = _accountPasswordChanged;
    if (diff.isEmpty && !accChanged) {
      Navigator.of(context).pop();
      return;
    }
    // تغيير الباقة: ايرث لنك على قاعدتها (canChangeAccount بصفّ المشترك — الخادم يرفض ما
    // سواها)، وSAS4 بالقاعدة الجديدة أعلاه. لا منع لغير المفعَّل أو المنتهي.
    final block = _packageBlockReason(diff);
    if (block != null) {
      showSheetSnack(context, block, isError: true);
      return;
    }
    final timed = diff['change_type'] as String?;
    if (timed == PackageChangeTiming.immediate.wire && !_immediateKeepsDate) {
      if (!await _confirmImmediateCancels() || !mounted) return;
    }
    setState(() => _saving = true);
    bool ok = true;
    String? message;
    String? code;
    Map<String, dynamic>? data;
    bool pendingCancelled = false;
    // ١) حقول الخدمة (SAS4/EL) — تُرسَل فقط إن تغيّرت، كما كانت حرفيّاً.
    if (diff.isNotEmpty) {
      final result = await MergedOps.write(widget.sub, () => SubscribersApi.updateSubscriber(
        idx: widget.sub.idx!,
        username: diff['username'],
        password: diff['password'],
        firstname: diff['firstname'],
        lastname: diff['lastname'],
        phone: diff['phone'],
        profileId: diff['profile_id'],
        changeType: timed,
        parentId: diff['parent_id'],
        expiration: diff['expiration'],
      ));
      ok = result.ok;
      message = result.message;
      code = result.code;
      data = result.data;
      pendingCancelled = result.pendingCancelled;
    }
    // ٢) ايرث لنك: كلمة سرّ حساب البوّابة — نداءٌ مستقلّ، بعد نجاح حقول الخدمة.
    if (ok && accChanged) {
      final accRes = await MergedOps.write(widget.sub, () => EarthlinkApi.setAccountPassword(
        idx: widget.sub.idx!,
        password: _accountPassword.text,
      ));
      ok = accRes.ok;
      if (accRes.ok) {
        _loadedAccountPassword = _accountPassword.text;
      } else {
        message = accRes.message ?? message;
      }
    }
    if (!mounted) return;
    final packageRefused = code != null &&
        (code.startsWith('PACKAGE_CHANGE_') || code == 'PENDING_CANCEL_FAILED');
    setState(() {
      _saving = false;
      // ألغى الخادم المجدول السابق ثمّ رُفض الجديد ⇒ لم يعد عند الساس: يزول سطر «مجدول».
      if (pendingCancelled) _pc = _pc.withoutScheduled();
      // الساس قال كلمته في الصلاحيّة ← يُقفل الحقل بسببه، وتعود الباقة لأصلها فلا يُعاد
      // الطلب نفسه.
      if (code == 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN' ||
          code == 'PACKAGE_CHANGE_FORBIDDEN') {
        if (code == 'PACKAGE_CHANGE_FORBIDDEN') {
          _changeRefused = true;
        } else {
          _activeChangeRefused = true;
        }
        _profileId = _originalProfileId;
        _pkgPicked = false;
        _timingPick = null;
      }
      // لا ردّ حاسم من الساس ولا أثر: لا تُعاد المحاولة على العمى — تعود الباقة لأصلها
      // ويُقرأ الحال من جديد أدناه، فيعرض الحقل ما عند الساس فعلاً.
      if (code == 'PACKAGE_CHANGE_UNCONFIRMED') {
        _profileId = _originalProfileId;
        _pkgPicked = false;
        _timingPick = null;
      }
    });
    if (code == 'PACKAGE_CHANGE_UNCONFIRMED') unawaited(_reloadPackageState());
    // نجاحٌ، أو رفضٌ للباقة قد سبقه حفظُ غيرها (الرسالة تقول «تغيّر اسم المستخدم…») ← تُحدَّث.
    if (ok || packageRefused) SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      ok ? _savedMessage(diff, data) : (message ?? 'تعذّر التعديل'),
      isError: !ok,
    );
    if (ok) Navigator.of(context).pop(true);
  }

  /// رسالة النجاح — بما نفّذه الخادم فعلاً (`change_type`)، لا بما طُلب: غير الفعّال عند
  /// الساس يتغيّر «حالاً» ولو طُلبت الجدولة. و`expiration_kept: false` = صار منتهياً.
  String _savedMessage(Map<String, dynamic> diff, Map<String, dynamic>? data) {
    if (!diff.containsKey('profile_id')) return 'تم تعديل بيانات المشترك';
    final executed =
        data?['change_type']?.toString() ?? diff['change_type']?.toString();
    final name = _packageName(diff['profile_id'] as int?);
    final named = name == null ? '' : ' ${iso(name)}';
    if (executed == PackageChangeTiming.schedule.wire) {
      // الموعد كما سجّله الساس (`updated.profile_change`)، وإلّا تاريخ الانتهاء المعروف.
      final updated = data?['updated'];
      final due = updated is Map
          ? ScheduledPackageChange.tryParse(updated['profile_change'])?.dueDay
          : null;
      final tail = (due == null || due.isEmpty) ? _endsTail : ' (${iso(due)})';
      return 'جُدولت الباقة$named — تتغيّر عند انتهاء الاشتراك$tail';
    }
    final kept = data?['expiration_kept'];
    if (kept == false) {
      return 'تغيّرت الباقة$named — والمشترك منتهٍ الآن، يحتاج تفعيلاً جديداً';
    }
    if (kept == true) {
      return 'تغيّرت الباقة$named — وبقي تاريخ الانتهاء كما هو';
    }
    return 'تم تعديل بيانات المشترك';
  }

  /// يلغي التغيير المجدول (بتأكيد) — كزرّ «Cancel» في لوحة الساس. بلا مال، والباقة
  /// الحاليّة والتاريخ كما هما. الشيت يبقى مفتوحاً: قد يريد المدير باقةً أخرى الآن.
  Future<void> _cancelScheduled() async {
    final idx = widget.sub.idx;
    if (_scheduled == null || idx == null || _cancellingScheduled) return;
    final ok = await showConfirmSheet(
      context,
      title: 'إلغاء تغيير الباقة المجدول',
      message: 'تبقى باقته الحاليّة بعد انتهاء اشتراكه، ولا تتغيّر إلى '
          '${iso(_scheduledName)}.',
      confirmLabel: 'إلغاء الجدولة',
      cancelLabel: 'تراجع',
      icon: LucideIcons.calendarX,
      tone: AppTone.warning,
    );
    if (ok != true || !mounted) return;
    setState(() => _cancellingScheduled = true);
    final r = await MergedOps.write(widget.sub, () => SubscribersApi.cancelProfileChange(idx));
    if (!mounted) return;
    setState(() {
      _cancellingScheduled = false;
      if (r.ok) _pc = _pc.withoutScheduled();
    });
    if (r.ok) SubscriberEvents.notifyChange();
    showSheetSnack(
      context,
      !r.ok
          ? (r.message ?? 'تعذّر إلغاء تغيير الباقة المجدول')
          // لا مجدول عند الساس الآن (ضغطةٌ مكرّرة أو شيتٌ قديم) — لا خطأ، والإطار يزول.
          : (r.cancelled == false
              ? 'لا يوجد تغيير باقة مجدول لهذا المشترك'
              : 'أُلغي تغيير الباقة المجدول'),
      isError: !r.ok,
    );
  }

  /// ما يُقال تحت اختيار «متى؟» — يتبع الاختيار وما سيجري فعلاً.
  ({String text, AppTone tone, IconData icon}) get _timingHint {
    final ends = _day(_activeUntil);
    final name = _packageName(_profileId);
    if (_timing == PackageChangeTiming.schedule) {
      if (_scheduleWithDateEdit) {
        return (
          text: _scheduleDateEditNote,
          tone: AppTone.warning,
          icon: LucideIcons.triangleAlert,
        );
      }
      return (
        text: 'يكمل المشترك اشتراكه الحاليّ، وتتغيّر الباقة'
            '${name == null ? '' : ' إلى ${iso(name)}'} عند انتهائه'
            '${ends.isEmpty ? '' : ' (${iso(ends)})'}',
        tone: AppTone.info,
        icon: LucideIcons.calendarClock,
      );
    }
    if (_showExpiration && _expirationEdited) {
      return (
        text: 'تتغيّر الباقة الآن، ويصير تاريخ الانتهاء '
            '${iso(_day(_expiration))}',
        tone: AppTone.info,
        icon: LucideIcons.calendarCheck,
      );
    }
    if (_pc.immediateKeepsDate == true) {
      return (
        text: 'تتغيّر الباقة الآن، ويبقى تاريخ الانتهاء كما هو'
            '${ends.isEmpty ? '' : ' (${iso(ends)})'}',
        tone: AppTone.info,
        icon: LucideIcons.calendarCheck,
      );
    }
    return (
      text: 'سيُعتبر المشترك منتهياً: تغيير الباقة الآن يلغي اشتراكه الحاليّ'
          '$_endsTail، ويحتاج تفعيلاً جديداً',
      tone: AppTone.warning,
      icon: LucideIcons.triangleAlert,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final timingHint = _offersTiming ? _timingHint : null;
    // حشوة لوحة المفاتيح صارت داخل DesignSheet.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.pencil,
        title: 'تعديل المشترك',
        subtitle: widget.sub.fullName,
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving
            ? 'جاري الحفظ...'
            : (_hasChanges ? 'حفظ التغييرات' : 'لا توجد تغييرات'),
        icon: LucideIcons.save,
        enabled: !_saving && _hasChanges,
        busy: _saving,
        onPressed: _submit,
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          const _FieldLabel(label: 'اسم المستخدم'),
          _Field(
            controller: _username,
            hint: 'username@admin',
            enabled: !_saving,
            icon: LucideIcons.user,
          ),
          const SizedBox(height: Sp.md),
          // ايرث لنك: نميّزها «كلمة سرّ الخدمة» لأنّ تحتها كلمة سرّ الحساب.
          // SAS4: تبقى «كلمة السر» حرفيّاً.
          _FieldLabel(
              label: _isEarthlink ? 'el.service_password'.tr() : 'كلمة السر'),
          _Field(
            controller: _password,
            hint: '••••••••',
            enabled: !_saving,
            icon: LucideIcons.lock,
            obscure: !_showPassword,
            suffix: IconButton(
              icon: Icon(
                _showPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 16,
              ),
              color: AppColors.textMid,
              visualDensity: VisualDensity.compact,
              tooltip: _showPassword ? 'إخفاء' : 'إظهار',
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          // ايرث لنك وحدها: كلمة سرّ حساب البوّابة — مستقلّةٌ عن كلمة سرّ الخدمة.
          if (_isEarthlink) ...[
            const SizedBox(height: Sp.md),
            _FieldLabel(label: 'el.account_password'.tr()),
            _Field(
              controller: _accountPassword,
              hint: '••••••••',
              enabled: !_saving,
              icon: LucideIcons.keyRound,
              obscure: !_showAccountPassword,
              suffix: IconButton(
                icon: Icon(
                  _showAccountPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 16,
                ),
                color: AppColors.textMid,
                visualDensity: VisualDensity.compact,
                tooltip: _showAccountPassword ? 'إخفاء' : 'إظهار',
                onPressed: () =>
                    setState(() => _showAccountPassword = !_showAccountPassword),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'el.account_password_hint'.tr(),
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(fontSize: 11, height: 1.4),
            ),
          ],
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel(label: 'الاسم'),
                    _Field(
                      controller: _firstname,
                      hint: 'الاسم',
                      enabled: !_saving,
                      icon: LucideIcons.user,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel(label: 'الكنية'),
                    _Field(
                      controller: _lastname,
                      hint: 'الكنية',
                      enabled: !_saving,
                      icon: LucideIcons.user,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          const _FieldLabel(label: 'رقم الهاتف'),
          _Field(
            controller: _phone,
            hint: '07XX XXX XXXX',
            enabled: !_saving,
            icon: LucideIcons.phone,
            keyboardType: TextInputType.phone,
            suffix: !ContactPicker.supported ? null : IconButton(
              icon: const Icon(LucideIcons.contact, size: 18),
              color: AppColors.brand,
              visualDensity: VisualDensity.compact,
              tooltip: 'اختر من دليل الأسماء',
              onPressed: _saving
                  ? null
                  : () async {
                      final r = await ContactPicker.pickPhone();
                      if (!mounted || !context.mounted) return;
                      if (r.phone != null) {
                        setState(() => _phone.text = r.phone!);
                      } else if (r.error != null) {
                        showSheetSnack(context, r.error!, isError: true);
                      }
                    },
            ),
          ),
          const SizedBox(height: Sp.md),
          const _FieldLabel(label: 'الباقة'),
          if (_isEarthlink) ...[
            PackagePickerField(
              options: _elPackageOptions,
              selectedId: _profileId?.toString(),
              currentId: widget.sub.profileId?.toString(),
              loading: _loadingPackages,
              // ايرث لنك: تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ، و«More» لا (حكم الخادم بصفّ المشترك).
              enabled: !_saving && widget.sub.canChangePackage != false,
              compact: true,
              emptyText: 'تعذّر جلب الباقات',
              onSelected: (id) {
                final v = int.tryParse(id);
                if (v != null) setState(() => _profileId = v);
              },
            ),
            if (widget.sub.canChangePackage == false) ...[
              const SizedBox(height: Sp.xs),
              Text(
                widget.sub.packageChangeNote ?? 'تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ — هذا المشترك ما زال فعّالاً',
                style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
              ),
            ],
          ] else ...[
            _PackagePicker(
              packages: _packages,
              loading: _loadingPackages,
              selectedId: _profileId,
              // مقفلٌ بسببه تحته: صلاحيّة الساس لا تسمح (لهذا الفعّال، أو لأيّ مشترك).
              // ومعطّلٌ حتى يصل حال الاشتراك من الساس (أو بعد تعذّره). والمجدول لا يقفله:
              // الخادم يلغيه قبل التغيير الجديد.
              enabled: !_saving && !_packageLocked && !_pkgWaiting,
              locked: _packageLocked,
              onSelect: (id) => setState(() {
                _profileId = id;
                _pkgPicked = true;
              }),
            ),
            if (_pkgWaiting && !_packageLocked) ...[
              const SizedBox(height: Sp.sm),
              if (!_detailsLoaded)
                const _PackageNote(
                  icon: LucideIcons.loaderCircle,
                  tone: AppTone.neutral,
                  busy: true,
                  text: 'لحظةً — يُقرأ حال اشتراك المشترك قبل تغيير الباقة',
                )
              else
                _PackageStateRetry(
                  text: _detailsFailedNote,
                  enabled: !_saving,
                  onRetry: _reloadPackageState,
                ),
            ],
            if (_scheduled != null) ...[
              const SizedBox(height: Sp.sm),
              _ScheduledChangeBanner(
                packageName: _scheduledName,
                dueDay: _scheduled!.dueDay,
                busy: _cancellingScheduled,
                enabled: !_saving,
                onCancel: _cancelScheduled,
              ),
            ],
            if (_changeLocked) ...[
              const SizedBox(height: Sp.sm),
              const _PackageNote(
                icon: LucideIcons.lock,
                tone: AppTone.neutral,
                text: 'صلاحيّتك في الساس لا تسمح بتغيير باقة المشترك',
              ),
            ] else if (_activeLocked) ...[
              const SizedBox(height: Sp.sm),
              _PackageNote(
                icon: LucideIcons.lock,
                tone: AppTone.neutral,
                text: 'المشترك فعّال، وصلاحيّتك في الساس لا تسمح بتغيير '
                    'باقته قبل انتهاء اشتراكه$_endsTail',
              ),
            ] else if (timingHint != null) ...[
              const SizedBox(height: Sp.md),
              const _FieldLabel(label: 'متى تتغيّر الباقة؟'),
              _TimingChoice(
                value: _timing,
                enabled: !_saving,
                onSelect: (t) => setState(() => _timingPick = t),
              ),
              const SizedBox(height: Sp.sm),
              _PackageNote(
                icon: timingHint.icon,
                tone: timingHint.tone,
                text: timingHint.text,
              ),
            ],
            // غير الفعّال: «حالاً» وحدها — يُقال بلا سؤال (كالويب).
            if (_sasRules &&
                _changesPackage &&
                !_isActiveNow &&
                !_packageLocked) ...[
              const SizedBox(height: Sp.sm),
              const _PackageNote(
                icon: LucideIcons.info,
                tone: AppTone.neutral,
                text: 'المشترك غير فعّال — تتغيّر الباقة حالاً',
              ),
            ],
            // تغييرٌ جديد فوق مجدولٍ ينتظر: الخادم يلغي المجدول أوّلاً — يُقال صراحةً.
            if (_scheduled != null && _changesPackage && !_packageLocked) ...[
              const SizedBox(height: Sp.sm),
              _PackageNote(
                icon: LucideIcons.info,
                tone: AppTone.neutral,
                text: 'سيُلغى التغيير المجدول إلى ${iso(_scheduledName)}، '
                    'ويسري اختيارك الجديد',
              ),
            ],
          ],
          if (_showExpiration) ...[
            const SizedBox(height: Sp.md),
            const _FieldLabel(label: 'تاريخ الانتهاء'),
            _ExpirationPicker(
              value: _expiration,
              enabled: !_saving,
              onPick: (d) => setState(() {
                _expiration = d;
                _expirationTouched = true;
              }),
            ),
          ],
          if (_showParent) ...[
            const SizedBox(height: Sp.md),
            const _FieldLabel(label: 'تابع إلى (المدير)'),
            _ManagerPicker(
              managers: _managers,
              loading: _loadingManagers,
              selectedId: _parentId,
              enabled: !_saving,
              onSelect: (id) => setState(() => _parentId = id),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 2),
      child: Text(
        label,
        style: AppType.muted(color: AppColors.textMid).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;

  /// Optional trailing widget — used by the password field for the
  /// reveal/hide eye toggle.
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: AppType.input(color: AppColors.textHi),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textLow),
        prefixIcon: Icon(icon, size: 16, color: AppColors.textMid),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.border),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }
}

class _PackagePicker extends StatelessWidget {
  const _PackagePicker({
    required this.packages,
    required this.loading,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
    this.locked = false,
  });
  final Map<String, PackageInfo>? packages;
  final bool loading;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<int> onSelect;

  /// مقفلٌ بصلاحيّة (لا انشغال حفظ): قفلٌ مكان السهم وخلفيّةٌ خافتة — والسبب تحته.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (loading) {
      return SizedBox(
        height: 38,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brand,
            ),
          ),
        ),
      );
    }
    final pkgs = packages;
    if (pkgs == null || pkgs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'تعذّر جلب الباقات',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
      );
    }
    // Sort by name so the picker reads predictably regardless of map
    // insertion order.
    final entries = pkgs.entries.toList()
      ..sort((a, b) => a.value.name.compareTo(b.value.name));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: locked ? AppColors.surfaceDisabled : AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedId,
          hint: Text(
            'اختر الباقة',
            style: AppType.input(color: AppColors.textLow),
          ),
          isExpanded: true,
          icon: Icon(locked ? LucideIcons.lock : LucideIcons.chevronDown,
              size: locked ? 14 : 16, color: AppColors.textMid),
          onChanged: enabled
              ? (v) {
                  if (v != null) onSelect(v);
                }
              : null,
          items: [
            for (final e in entries)
              DropdownMenuItem<int>(
                value: int.tryParse(e.key),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.value.name,
                        style: AppType.input(color: AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (e.value.price != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${e.value.price!.round()} د.ع',
                        style: AppType.muted(color: AppColors.warning).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tap-to-pick expiration date — opens the platform date picker.
/// Renders 'YYYY/MM/DD' or 'لم يُختر' when no value. Super-admin
/// only — non-super admins never see this widget (مطلب 2026-06-10).
class _ExpirationPicker extends StatelessWidget {
  const _ExpirationPicker({
    required this.value,
    required this.enabled,
    required this.onPick,
  });
  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    String two(int n) => n.toString().padLeft(2, '0');
    final label = value == null
        ? 'لم يُختر'
        : '${value!.year}/${two(value!.month)}/${two(value!.day)} '
            '${two(value!.hour)}:${two(value!.minute)}:${two(value!.second)}';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () async {
                final now = DateTime.now();
                final initial = value ?? now;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 5),
                  helpText: 'اختر تاريخ الانتهاء',
                  cancelText: 'إلغاء',
                  confirmText: 'تأكيد',
                );
                if (picked == null) return;
                if (!context.mounted) return;
                // 2026-07-16: بعد التاريخ، منتقي الوقت — كان المدير
                // يقدر يغيّر التاريخ فقط، الوقت يبقى ثابت (20:59:59
                // افتراضي) — شكوى المستخدم الحقيقية.
                final src = value;
                final pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: src?.hour ?? 20,
                    minute: src?.minute ?? 59,
                  ),
                  helpText: 'اختر وقت الانتهاء',
                  cancelText: 'إلغاء',
                  confirmText: 'تأكيد',
                );
                // لو المدير ألغى منتقي الوقت، نحافظ على الوقت الأصلي
                // (لا نخسر معلومات).
                final hour = pickedTime?.hour ?? src?.hour ?? 20;
                final minute = pickedTime?.minute ?? src?.minute ?? 59;
                onPick(DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  hour,
                  minute,
                  src?.second ?? 59,
                ));
              }
            : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.calendar, size: 16, color: AppColors.textMid),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppType.input(
                    color: value == null ? AppColors.textLow : AppColors.textHi,
                  ),
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dropdown of all sub-managers (from /api/v2/managers). Super-admin
/// only — non-super never see this widget. Null selection → no
/// change to parent.
class _ManagerPicker extends StatelessWidget {
  const _ManagerPicker({
    required this.managers,
    required this.loading,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
  });
  final List<({int id, String username, String firstname, String lastname})>?
      managers;
  final bool loading;
  final int? selectedId;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (loading) {
      return SizedBox(
        height: 38,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brand,
            ),
          ),
        ),
      );
    }
    final list = managers;
    if (list == null || list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'لا يوجد مدراء',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: list.any((m) => m.id == selectedId) ? selectedId : null,
          hint: Text(
            'اختر المدير',
            style: AppType.input(color: AppColors.textLow),
          ),
          isExpanded: true,
          icon:
              Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textMid),
          onChanged: enabled
              ? (v) {
                  if (v != null) onSelect(v);
                }
              : null,
          items: [
            for (final m in list)
              DropdownMenuItem<int>(
                value: m.id,
                child: _ManagerItemLabel(
                  firstname: m.firstname,
                  lastname: m.lastname,
                  username: m.username,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 2026-08-26: بديل لعرض displayName المسبَق-التسلسل الذي كان يظهر
/// "admin@ota6 admin@ota6 (admin@ota6)". الآن: اسم رئيسي بارز
/// (Arabic firstname+lastname أو username كـfallback) + @username
/// ثانوي بلون مميّز، ويُخفى الثانوي إذا الاسم == username لتفادي التكرار.
class _ManagerItemLabel extends StatelessWidget {
  const _ManagerItemLabel({
    required this.firstname,
    required this.lastname,
    required this.username,
  });
  final String firstname;
  final String lastname;
  final String username;

  @override
  Widget build(BuildContext context) {
    final full =
        [firstname, lastname].where((s) => s.isNotEmpty).join(' ').trim();
    final primary = full.isNotEmpty ? full : username;
    final showSecondary = full.isNotEmpty && full != username;
    // الاسم `Expanded` والمعرّف بمقاسه: مرنان بالوزن نفسه يقتسمان
    // مناصفةً، فيُقصّ «عبد الرحمن الجبوري» (١٢٨٫٣ نقطة) في حدٍّ قدره
    // ١٢١ بينما «@najaf650» يترك نصفه فارغاً.
    return Row(
      children: [
        Expanded(
          child: Text(
            primary,
            style: AppType.input(color: AppColors.textHi),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showSecondary) ...[
          const SizedBox(width: 6),
          Text(
            '@$username',
            style: AppType.subtitle(color: AppColors.textLow),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// «متى تتغيّر الباقة؟» — «حالاً» / «عند انتهاء الاشتراك» كلوحة الساس. خيارٌ واحد
/// دائماً (لا فراغ): الافتراضيّ «عند انتهاء الاشتراك»، وأوّلاً كالويب. النصّ يلتفّ سطرين بدل
/// أن يُقصّ على شاشة ٣٢٠ أو بخطٍّ مكبَّر.
class _TimingChoice extends StatelessWidget {
  const _TimingChoice({
    required this.value,
    required this.enabled,
    required this.onSelect,
  });

  final PackageChangeTiming value;
  final bool enabled;
  final ValueChanged<PackageChangeTiming> onSelect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    Widget option(PackageChangeTiming t, String label, IconData icon) {
      final on = t == value;
      final fg = on ? AppColors.brand : AppColors.textBody;
      return Expanded(
        child: Semantics(
          key: ValueKey('pkg-timing-${t.wire}'),
          button: true,
          selected: on,
          inMutuallyExclusiveGroup: true,
          child: Material(
            color: on ? AppColors.brandSoftBg : AppColors.surface,
            borderRadius: BorderRadius.circular(R.sm),
            child: InkWell(
              onTap: enabled ? () => onSelect(t) : null,
              borderRadius: BorderRadius.circular(R.sm),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(
                    color: on ? AppColors.brand : AppColors.border,
                    width: on ? BW.selected : BW.normal,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.sm, vertical: Sp.x6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 15, color: fg),
                        const SizedBox(width: Sp.x6),
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.bodyStrong(color: fg).copyWith(
                              fontWeight:
                                  on ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          option(PackageChangeTiming.schedule, 'عند انتهاء الاشتراك',
              LucideIcons.calendarClock),
          const SizedBox(width: Sp.sm),
          option(PackageChangeTiming.immediate, 'حالاً', LucideIcons.zap),
        ],
      ),
    );
  }
}

/// سطر توضيحٍ بنغمة (تنبيه/معلومة/قفل) تحت حقل الباقة. [busy] = دائرة انتظارٍ مكان الأيقونة.
class _PackageNote extends StatelessWidget {
  const _PackageNote({
    required this.icon,
    required this.tone,
    required this.text,
    this.busy = false,
  });

  final IconData icon;
  final AppTone tone;
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = tone == AppTone.neutral ? AppColors.textMid : tone.onSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
            color: tone == AppTone.neutral ? AppColors.border : tone.softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: busy
                ? SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Icon(icon, size: 15, color: fg),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              text,
              style: AppType.body(color: fg).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// حال الاشتراك تعذّرت قراءته: السبب بنغمة تنبيه، و«أعد المحاولة» على سطرٍ مستقلّ (لا يزاحم
/// النصّ على ٣٢٠ — كإطار «مجدول»). ليست لصلاحيّةٍ ناقصة (تلك قفلٌ بسببه، لا «تعذّر»).
class _PackageStateRetry extends StatelessWidget {
  const _PackageStateRetry({
    required this.text,
    required this.enabled,
    required this.onRetry,
  });

  final String text;
  final bool enabled;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const tone = AppTone.warning;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, Sp.sm, Sp.x6, Sp.xxs),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: tone.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(LucideIcons.triangleAlert,
                    size: 15, color: tone.onSoft),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  text,
                  style: AppType.body(color: tone.onSoft).copyWith(height: 1.5),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: const ValueKey('pkg-state-retry'),
              onPressed: enabled ? onRetry : null,
              style: TextButton.styleFrom(
                foregroundColor: tone.onSoft,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                visualDensity: VisualDensity.compact,
                textStyle: AppType.bodyStrong(),
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: const Text('أعد المحاولة'),
            ),
          ),
        ],
      ),
    );
  }
}

/// «مجدول: <الباقة> عند <الموعد>» بزرّ إلغاء — كتنبيه لوحة الساس «Profile is scheduled
/// to be changed on … to … · Cancel Profile Change».
class _ScheduledChangeBanner extends StatelessWidget {
  const _ScheduledChangeBanner({
    required this.packageName,
    required this.dueDay,
    required this.busy,
    required this.enabled,
    required this.onCancel,
  });

  final String packageName;
  final String dueDay;
  final bool busy;
  final bool enabled;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const tone = AppTone.info;
    final when = dueDay.isEmpty ? ' عند انتهاء الاشتراك' : ' عند ${iso(dueDay)}';
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, Sp.sm, Sp.x6, Sp.xxs),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: tone.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // النصّ يلتفّ بجانب أيقونةٍ ضيّقة وحدها — اسم الباقة قد يطول والموعد لا يُقصّ؛
          // وزرّ الإلغاء على سطرٍ مستقلّ فلا يزاحمه (حارس flex_text_guard).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(LucideIcons.calendarClock,
                    size: 16, color: tone.onSoft),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  'مجدول: ${iso(packageName)}$when',
                  style: AppType.bodyStrong(color: tone.onSoft),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.lg, vertical: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.error,
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: enabled ? onCancel : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                      visualDensity: VisualDensity.compact,
                      textStyle: AppType.bodyStrong(),
                    ),
                    icon: const Icon(LucideIcons.x, size: 15),
                    label: const Text('إلغاء الجدولة'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────
