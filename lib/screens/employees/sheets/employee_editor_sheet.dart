import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/employees_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/platform/store_policy.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../services/active_company.dart';
import '../../../services/auth_storage.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';

/// Sheet إنشاء/تعديل موظف. tab1 = معلومات، tab2 = صلاحيات. الـpresets
/// (3 افتراضية من backend: cashier/assistant_manager/viewer) تطبّق
/// مجموعة جاهزة بضغطة واحدة.
///
/// [isEarthlink]: المالك موزّع ايرث لنك — المحرّر يعرض صلاحيّات موظّفي
/// ايرث لنك وحدها بأدوارها الجاهزة، ولا قيد بمدير فرعي (شجرة ساس لا وجود
/// لها هناك)، ويقول تحت أيّ شركة سيعمل الموظف، وبعد الإنشاء يبقى مفتوحاً
/// على لوحة بيانات الدخول. [onCreated] يُستدعى لحظة الإنشاء عندها، فتُحدَّث
/// القائمة خلف اللوحة (قد تُغلق بالسحب فلا يرجع الشيت `true`).
Future<bool?> showEmployeeEditorSheet(
  BuildContext context, {
  required PermissionsCatalog catalog,
  Employee? employee,
  bool isEarthlink = false,
  VoidCallback? onCreated,
}) {
  return showAppSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EmployeeEditorSheet(
      catalog: catalog,
      employee: employee,
      isEarthlink: isEarthlink,
      onCreated: onCreated,
    ),
  );
}

/// ايرث لنك: الشركة التي يعمل تحتها موظّفو المالك ويوزره فيها.
///
/// الموظّف يُنشأ تحت معرّف الشركة التي دخلها المالك **الآن**
/// (`parent_admin_id`)، فالمرجع الشركة المفتوحة ([ActiveCompany]) — اسمها من
/// الدليل/«شركاتي» إن حُسم، وإلّا الاسم العامّ. [fallbackOwner] يوزر الجلسة
/// المخزَّن إن لم تعرفه الشركة المفتوحة.
({String company, String owner}) elWorkplace(
  ActiveCompanyInfo? info, {
  String fallbackOwner = '',
}) {
  final label = info?.label.trim() ?? '';
  final company = (info != null && info.resolved && label.isNotEmpty)
      ? label
      : 'ايرث لنك (Earthlink)';
  final owner = info?.shownUsername.trim() ?? '';
  return (
    company: company,
    owner: owner.isNotEmpty ? owner : fallbackOwner.trim(),
  );
}

class _EmployeeEditorSheet extends StatefulWidget {
  const _EmployeeEditorSheet({
    required this.catalog,
    this.employee,
    this.isEarthlink = false,
    this.onCreated,
  });
  final PermissionsCatalog catalog;
  final Employee? employee;
  final bool isEarthlink;
  final VoidCallback? onCreated;

  @override
  State<_EmployeeEditorSheet> createState() => _EmployeeEditorSheetState();
}

class _EmployeeEditorSheetState extends State<_EmployeeEditorSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late TextEditingController _userCtrl;
  late TextEditingController _fullNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _passCtrl;
  late bool _isActive;
  late Map<String, bool> _perms;
  bool _saving = false;

  /// 2026-08-26: scope — يقيّد الموظّف بمدير فرعي محدَّد.
  /// null = يشاهد بيانات الأب كاملة (الافتراضي).
  String? _scopeAdminId;

  /// قائمة المدراء الفرعيّين للـdropdown — تُحمَّل في initState.
  List<({int id, String username, String firstname, String lastname})>?
      _managers;

  /// رسالة الخطأ المعروضة بأعلى الـsheet. تنمسح عند بدء الكتابة في
  /// أي حقل عشان المستخدم ما يشوف خطأ قديم بعد ما يصحّح. لو null لا
  /// banner.
  String? _error;

  /// ايرث لنك: حقل اسم المستخدم يُركَّز عليه حين يُرفض الاسم (محجوز/غير صالح).
  final FocusNode _userFocus = FocusNode();

  /// ايرث لنك: يوزر الجلسة المخزَّن — احتياط سطر «سيعمل الموظف على».
  String _storedOwnerUsername = '';

  /// ايرث لنك: الموظف الذي أُنشئ للتوّ. وجوده يقلب الشيت إلى لوحة بيانات
  /// الدخول بدل الإغلاق.
  ({String username, String password, String name})? _created;

  bool get _isEdit => widget.employee != null;
  bool get _el => widget.isEarthlink;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final e = widget.employee;
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _fullNameCtrl = TextEditingController(text: e?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _passCtrl = TextEditingController();
    _isActive = e?.isActive ?? true;
    _scopeAdminId = e?.scopeAdminId; // null = بدون قيد
    _perms = {
      ...widget.catalog.defaults,
      if (e != null) ...e.permissions,
    };
    if (_el) {
      // ايرث لنك: لا قيد بمدير فرعي فلا قائمة مدراء. ويوزر المالك احتياطاً
      // لسطر «سيعمل الموظف على» إن لم تعرفه الشركة المفتوحة.
      if ((ActiveCompany.current?.shownUsername.trim() ?? '').isEmpty) {
        () async {
          try {
            final u = (await AuthStorage.readAdminUsername())?.trim() ?? '';
            if (mounted && u.isNotEmpty) {
              setState(() => _storedOwnerUsername = u);
            }
          } catch (_) {/* السطر يُعرض بلا يوزر */}
        }();
      }
    } else {
      // حمّل قائمة المدراء الفرعيّين للـdropdown (best-effort).
      () async {
        try {
          final list = await SubscribersApi.loadManagers();
          if (mounted && list != null) {
            setState(() => _managers = list);
          }
        } catch (_) {/* fallback: hide dropdown */}
      }();
    }
    // مسح الـerror banner تلقائياً لما المستخدم يبدأ يصحّح أي حقل.
    void clearOnEdit() {
      if (_error != null) setState(() => _error = null);
    }

    // ايرث لنك: يُمسح عند تغيّر **النصّ** وحده. رفضُ الاسم (محجوز/غير صالح)
    // يركّز حقله آليّاً ([_showUsernameError])، ولوحة مفاتيح أندرويد تعلّم
    // الكلمة عندها (منطقة تركيب) فيُبلَّغ المستمع بلا أيّ كتابة — فكانت
    // رسالة الرفض تُمحى لحظة ظهورها.
    void listen(TextEditingController c) {
      if (!_el) {
        c.addListener(clearOnEdit);
        return;
      }
      var last = c.text;
      c.addListener(() {
        if (c.text == last) return;
        last = c.text;
        clearOnEdit();
      });
    }

    listen(_userCtrl);
    listen(_passCtrl);
    listen(_fullNameCtrl);
    listen(_phoneCtrl);
  }

  @override
  void dispose() {
    _tab.dispose();
    _userCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    super.dispose();
  }

  void _applyPreset(PermPreset p) {
    setState(() => _perms = Map<String, bool>.from(p.permissions));
    showSheetSnack(context, 'تم تطبيق ${p.label}', isError: false);
  }

  /// ايرث لنك: الدور يضبط مفاتيح ايرث لنك كلّها (المدرجة تُفعَّل والباقي
  /// يُطفأ)، ثمّ يعدّل المالك ما يشاء.
  ///
  /// بلا إشعار: الشريحة نفسها تُملأ بعلامة ✓ ويتبدّل سطر الوصف تحتها —
  /// والإشعار يغطّي زرّ «حفظ» ثلاث ثوانٍ، والمعتاد «دورٌ ثمّ حفظ» مباشرةً
  /// فكانت أوّل ضغطةٍ على الحفظ تُغلق الإشعار لا تحفظ.
  /// ما لا يعرضه الكتالوج لا يُلمس — كان يُعَدّ في «الصلاحيات (N)» ولا يُرسَل.
  void _applyElPreset(ElPermPreset p) {
    setState(() {
      for (final k
          in ElEmployeePerms.offered(widget.catalog.permissions.keys)) {
        _perms[k] = p.keys.contains(k);
      }
    });
  }

  void _setAll(bool v) {
    setState(() {
      for (final k in _perms.keys) {
        _perms[k] = v;
      }
    });
  }

  /// يعرض الخطأ في الـbanner أعلى الـsheet ويرجع الـadmin للـtab
  /// المعلوم للحقل المتأثّر.
  void _showError(String msg, {int tabIndex = 0}) {
    setState(() => _error = msg);
    if (_tab.index != tabIndex) _tab.animateTo(tabIndex);
  }

  /// ايرث لنك: خطأٌ في اسم المستخدم — الرسالة ثمّ التركيز على الحقل بعد أن
  /// يستقرّ تبويب المعلومات (قد يكون الحفظ ضُغط من تبويب الصلاحيّات).
  void _showUsernameError(String msg) {
    final switching = _tab.index != 0;
    _showError(msg);
    Future<void>.delayed(
      switching ? kTabScrollDuration : Duration.zero,
      () {
        if (mounted && _created == null) _userFocus.requestFocus();
      },
    );
  }

  Future<void> _save() async {
    final username = _userCtrl.text.trim();
    if (username.isEmpty) {
      _showError('اسم المستخدم مطلوب');
      return;
    }
    if (_el) {
      // ايرث لنك: قواعد الخادم نفسها (createEmployee/updateEmployee) تُفحص
      // قبل الإرسال برسالةٍ أوضح من رفضه.
      if (!_isEdit &&
          !RegExp(r'^[a-z0-9._@-]{3,100}$').hasMatch(username.toLowerCase())) {
        _showUsernameError(
            'اسم المستخدم: ٣ أحرف على الأقل — حروف إنجليزيّة وأرقام و . _ - @ فقط');
        return;
      }
      final pass = _passCtrl.text;
      if ((!_isEdit || pass.isNotEmpty) && pass.length < 6) {
        _showError('كلمة المرور ٦ أحرف على الأقل');
        return;
      }
    } else if (!_isEdit && _passCtrl.text.length < 4) {
      _showError('كلمة المرور ٤ أحرف على الأقل');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // ايرث لنك: المحرّر يعرض مفاتيح موظّفي ايرث لنك وحدها، فما سواها يُرسَل
    // false دائماً — لا يُمنح ما لم يره المالك.
    // غير ايرث لنك: مفاتيح الكتالوج المعروض وحدها — مفتاحٌ مخفيّ عنه (المساعد
    // الذكي قبل تفعيله) لا يُرسَل، فيُبقي الخادم قيمته المحفوظة.
    final perms = _el
        ? ElEmployeePerms.outgoing(widget.catalog.permissions.keys, _perms)
        : {
            for (final e in _perms.entries)
              if (widget.catalog.permissions.containsKey(e.key)) e.key: e.value,
          };
    // مطلب 2026-06-11: الـrecords في Dart لا تُكسر cast عبر dynamic،
    // فنحلّ كل فرع بنفسه ونستخرج ok/message محلياً.
    bool ok;
    String? message;
    int? status;
    String? createdUsername;
    if (_isEdit) {
      // scopeAdminId ثلاثيّ: null (لا تغيير)، '' (مسح)، id (تحديد).
      // نستفسر: هل الـscope تغيّر عن الأصلي؟
      // ايرث لنك: لا قيد بمدير فرعي أبداً — لا يُرسَل الحقل.
      final currentEditScope = widget.employee!.scopeAdminId;
      final scopeChanged = !_el && _scopeAdminId != currentEditScope;
      final r = await EmployeesApi.update(
        id: widget.employee!.id,
        fullName: _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passCtrl.text.isEmpty ? null : _passCtrl.text,
        isActive: _isActive,
        permissions: perms,
        scopeAdminId: scopeChanged
            ? (_scopeAdminId ?? '') // '' = clear
            : null, // null = no change
      );
      ok = r.ok;
      message = r.message;
    } else {
      final r = await EmployeesApi.create(
        username: username,
        password: _passCtrl.text,
        fullName: _fullNameCtrl.text.trim().isEmpty
            ? null
            : _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        isActive: _isActive,
        permissions: perms,
        scopeAdminId: _el ? null : _scopeAdminId,
      );
      ok = r.ok;
      message = r.message;
      status = r.status;
      createdUsername = r.employee?.username;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      if (_el && !_isEdit) {
        // ايرث لنك: لوحة بيانات الدخول بدل الإغلاق، والقائمة تُحدَّث خلفها.
        // اليوزر كما حفظه الخادم (يصغّر الحروف) — به يدخل الموظف.
        final saved = createdUsername?.trim() ?? '';
        widget.onCreated?.call();
        FocusScope.of(context).unfocus();
        setState(() => _created = (
              username: saved.isNotEmpty ? saved : username.toLowerCase(),
              password: _passCtrl.text,
              name: _fullNameCtrl.text.trim(),
            ));
        return;
      }
      _snack(_isEdit ? 'تم حفظ التعديلات' : 'تم إنشاء الموظف');
      Navigator.of(context).pop(true);
    } else if (_el &&
        !_isEdit &&
        (status == 409 || (message ?? '').contains('محجوز'))) {
      // الأسماء فريدةٌ على مستوى النظام كلّه، لا عند المالك وحده — فقد
      // يكون الاسم لموظّف شركةٍ أخرى لا يراه.
      _showUsernameError('اسم المستخدم «${username.toLowerCase()}» محجوز — '
          'أسماء الموظفين فريدة على مستوى النظام كلّه، اختر اسماً آخر');
    } else {
      // آيفون: حدّ الموظّفين بلا «رقِّ باقتك لإضافة المزيد».
      _showError(StorePolicy.storeSafe(message ?? 'فشل الحفظ'));
    }
  }

  void _snack(String msg, {bool warn = false}) {
    // 2026-08-25 (bug fix): كان isError مُثبَّت true دائماً حتى للنجاح
    // ("تم حفظ التعديلات" كان يظهر بأحمر). الآن يحترم warn.
    showSheetSnack(context, msg, isError: warn);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final created = _created;
    if (created != null) return _elCreatedSheet(created);
    // بلا «المساعد الذكي» في الحالين — كبلاطة القائمة ([Employee.activePermsCount]).
    final activeCount = _el
        ? ElEmployeePerms.activeCount(_perms)
        : _perms.entries
            .where((e) => e.value && e.key != ElEmployeePerms.assistantKey)
            .length;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: _isEdit ? LucideIcons.userCog : LucideIcons.userPlus,
        title: _isEdit ? 'تعديل موظف' : 'موظف جديد',
        subtitle: '',
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving ? 'جاري الحفظ...' : 'حفظ',
        icon: LucideIcons.save,
        color: AppColors.brandAccent,
        busy: _saving,
        onPressed: _save,
      ),
      maxHeightFactor: 0.95,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.dangerSoftBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.circleAlert,
                      size: 14, color: AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppType.bodyBold(color: AppColors.error),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _error = null),
                    borderRadius: BorderRadius.circular(R.pill),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child:
                          Icon(LucideIcons.x, size: 14, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          // ⚠️ `TabBar` سقط عند نقل الشيت إلى القوقعة: بقي `TabBarView`
          // و`TabController` بلا أيّ مبدّل ظاهر، فلا سبيل للوصول إلى
          // تبويب الصلاحيات إلّا برمجيّاً عند فشل التحقّق (سطر 128).
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.md),
            child: AnimatedBuilder(
              animation: _tab,
              builder: (_, __) => SheetSegmented(
                labels: ['المعلومات', 'الصلاحيات ($activeCount)'],
                icons: const [LucideIcons.userCog, LucideIcons.shieldCheck],
                selectedIndex: _tab.index,
                onSelect: (i) => _tab.animateTo(i),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _infoTab(),
                _permsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
      children: [
        // ايرث لنك: تحت أيّ شركة سيعمل الموظف — الشركة المفتوحة الآن.
        if (_el) ...[
          _elCompanyBanner(),
          const SizedBox(height: Sp.md),
        ],
        _field(
          ctrl: _userCtrl,
          hint:
              _isEdit ? _userCtrl.text : 'اسم المستخدم — يستعمله الموظف للدخول',
          icon: LucideIcons.atSign,
          enabled: !_isEdit, // username غير قابل للتعديل بعد الإنشاء
          focusNode: _el ? _userFocus : null,
          // ايرث لنك: اسم دخولٍ لا كلمة — التصحيح التلقائيّ يبدّل الكلمة قبل
          // «.» أو «_» فيُنشأ الموظف باسمٍ غير الذي كتبه المالك.
          plainLogin: _el && !_isEdit,
          // ايرث لنك: ما يقبله الخادم وحده، وبالحروف الصغيرة التي يحفظها —
          // فيرى المالك الاسم كما سيكتبه الموظف عند الدخول.
          formatters: _el && !_isEdit
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._@-]')),
                  TextInputFormatter.withFunction((_, v) =>
                      v.copyWith(text: v.text.toLowerCase())),
                ]
              : null,
        ),
        if (_el && !_isEdit)
          _fieldNote('حروف إنجليزيّة وأرقام و . _ - @ — '
              'الاسم فريد على مستوى النظام كلّه'),
        const SizedBox(height: Sp.md),
        _field(
          ctrl: _passCtrl,
          hint: _isEdit
              ? 'كلمة مرور جديدة (اتركها فارغة لإبقائها)'
              : _el
                  ? 'كلمة المرور (6 أحرف على الأقل)'
                  : 'كلمة المرور (4 أحرف على الأقل)',
          icon: LucideIcons.key,
          obscure: true,
        ),
        const SizedBox(height: Sp.md),
        _field(
          ctrl: _fullNameCtrl,
          hint: 'الاسم الكامل',
          icon: LucideIcons.user,
        ),
        const SizedBox(height: Sp.md),
        _field(
          ctrl: _phoneCtrl,
          hint: 'الهاتف',
          icon: LucideIcons.phone,
          keyboard: TextInputType.phone,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: Sp.md),
        // 2026-08-26: قيد الـscope — الموظّف مقيَّد بمدير فرعي؟
        // ايرث لنك: لا شجرة مدراء ساس، والخادم يرفض القيد هناك — لا يُعرض.
        if (!_el) ...[
          _scopePicker(),
          const SizedBox(height: Sp.md),
        ],
        // يلفّه Material شفّاف ليجد ListTile سطحه المادّيّ — يُسكِت خطأ
        // «ListTile background color or ink splashes may be invisible»
        // (SwitchListTile داخل سطح DesignSheet الملوّن). شفّافٌ ⇒ لا تغيير
        // في المظهر لمحرّري ايرث لنك وSAS4 معاً.
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            title: Text('الحساب مفعّل',
                style: AppType.label(color: AppColors.textHi)
                    .copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text(
              _isActive
                  ? 'يقدر يسجّل دخول وينفّذ الصلاحيات المُمنوحة'
                  : 'الموظف لا يقدر يسجّل دخول حالياً',
              style: AppType.muted().copyWith(fontSize: 11),
            ),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.brand,
          ),
        ),
      ],
    );
  }

  /// سطر شرحٍ خافت تحت حقل.
  Widget _fieldNote(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 5),
      child: Text(text, style: AppType.micro(color: AppColors.textLow)),
    );
  }

  /// ايرث لنك: «سيعمل الموظف على: <الشركة> · <يوزر المالك>». يتبع الشركة
  /// المفتوحة حيّاً (قد يُحسم اسمها من الدليل والشيت مفتوح).
  Widget _elCompanyBanner() {
    return ValueListenableBuilder<ActiveCompanyInfo?>(
      valueListenable: ActiveCompany.listenable,
      builder: (context, info, _) {
        final w = elWorkplace(info, fallbackOwner: _storedOwnerUsername);
        final fg = AppColors.brandOnSoft;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.brandSoftBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(LucideIcons.building2, size: 15, color: fg),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // كلّ مقطعٍ معزولٌ اتّجاهيّاً: اسمٌ عربيّ بجانب يوزرٍ
                    // لاتينيّ يتفكّك ترتيبه بلا عزل (core/util/bidi.dart).
                    Text.rich(TextSpan(children: [
                      TextSpan(
                        text: 'سيعمل الموظف على: ',
                        style: AppType.body(color: fg),
                      ),
                      TextSpan(
                        text: iso(w.company),
                        style: AppType.bodyBold(color: fg),
                      ),
                      if (w.owner.isNotEmpty) ...[
                        TextSpan(text: ' · ', style: AppType.body(color: fg)),
                        TextSpan(
                          text: iso(w.owner),
                          style: AppType.bodyStrong(color: fg),
                        ),
                      ],
                    ])),
                    const SizedBox(height: 2),
                    Text(
                      'يتبع الشركة المفتوحة الآن — لموظفٍ في شركةٍ أخرى ادخلها أوّلاً',
                      style: AppType.micro(color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _permsTab() {
    if (_el) return _elPermsTab();
    final presets = widget.catalog.presets.values.toList();
    final byCat = widget.catalog.permsByCategory;
    final cats = widget.catalog.categories;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
      children: [
        // Presets
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'أدوار جاهزة',
            style: AppType.muted(color: AppColors.textMid).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in presets)
              _PresetChip(
                preset: p,
                onTap: () => _applyPreset(p),
              ),
            _ActionChip(
              icon: LucideIcons.checkCheck,
              label: 'تفعيل الكل',
              onTap: () => _setAll(true),
              color: AppColors.brand,
            ),
            _ActionChip(
              icon: LucideIcons.eraser,
              label: 'إلغاء الكل',
              onTap: () => _setAll(false),
              color: AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: Sp.lg),
        // الصلاحيات بحسب الفئة
        for (final entry in byCat.entries) ...[
          _categoryHeader(cats[entry.key]?.label ?? entry.key, entry.value),
          for (final p in entry.value) _permRow(p),
          const SizedBox(height: Sp.md),
        ],
      ],
    );
  }

  /// ايرث لنك: مفاتيح موظّفي ايرث لنك وحدها ([ElEmployeePerms]) بفئاتها
  /// وتسمياتها من الكتالوج، وأدوارها الجاهزة أعلاها. «تفعيل الكل» لا يُعرض:
  /// «موظّف عام» هو نفسه.
  Widget _elPermsTab() {
    final byCat =
        widget.catalog.permsByCategoryWhere(ElEmployeePerms.keys.contains);
    final cats = widget.catalog.categories;
    final current = ElEmployeePerms.matching(_perms,
        catalogKeys: widget.catalog.permissions.keys);
    final none = ElEmployeePerms.activeCount(_perms) == 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'أدوار جاهزة',
            style: AppType.muted(color: AppColors.textMid).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in ElEmployeePerms.presets)
              _ElPresetChip(
                label: p.label,
                icon: switch (p.id) {
                  'general' => LucideIcons.briefcase,
                  'collect' => LucideIcons.handCoins,
                  _ => LucideIcons.eye,
                },
                selected: p.id == current?.id,
                onTap: () => _applyElPreset(p),
              ),
            _ActionChip(
              icon: LucideIcons.eraser,
              label: 'إلغاء الكل',
              onTap: () => _setAll(false),
              color: AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          current?.description ??
              (none
                  ? 'بلا صلاحيّات — لن يرى الموظف شيئاً بعد الدخول'
                  : 'مخصّص — عدّلت الصلاحيّات يدويّاً'),
          style: AppType.muted(color: none ? AppColors.error : AppColors.textMid),
        ),
        const SizedBox(height: Sp.lg),
        for (final entry in byCat.entries) ...[
          _categoryHeader(cats[entry.key]?.label ?? entry.key, entry.value),
          for (final p in entry.value)
            _permRow(p, hint: ElEmployeePerms.hints[p.key]),
          const SizedBox(height: Sp.md),
        ],
        _elOwnerOnlyNote(),
      ],
    );
  }

  /// ايرث لنك: ما لا يُمنح لموظّفٍ أصلاً (لا مفتاح له) — كي لا يبحث المالك عنه.
  Widget _elOwnerOnlyNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.lock, size: 14, color: AppColors.textMid),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'تبقى لك وحدك ولا تُمنح لموظّف: تحويل الرصيد وكشف الإيداع، '
              'إلغاء التسوية، وإدارة الموظفين.',
              style: AppType.body(color: AppColors.textMid),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryHeader(String label, List<PermissionDef> perms) {
    final activeInCat = perms.where((p) => _perms[p.key] == true).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Row(
        children: [
          Icon(LucideIcons.folder, size: 12, color: AppColors.textMid),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppType.label(color: AppColors.textHi)
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Text(
              '$activeInCat / ${perms.length}',
              style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [hint]: ايرث لنك — ما يشمله المفتاح هناك ولا تقوله تسميته.
  Widget _permRow(PermissionDef p, {String? hint}) {
    final value = _perms[p.key] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.label,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 12.5),
                ),
                if (hint != null)
                  Text(hint, style: AppType.micro(color: AppColors.brandAccent)),
                Text(
                  p.key,
                  style: TextStyle(
                    color: AppColors.textLow,
                    fontSize: 10.5, height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (v) => setState(() => _perms[p.key] = v),
          ),
        ],
      ),
    );
  }

  // ═══════════════ ايرث لنك: لوحة «تمّ إنشاء الموظف» ═══════════════

  /// بيانات الدخول + زرّ نسخها + كيف يدخل الموظف. الإغلاق (أيّاً كان) لا
  /// يُفقد شيئاً: القائمة حُدّثت لحظة الإنشاء ([_EmployeeEditorSheet.onCreated])،
  /// وكلمة السرّ تُستعاد لاحقاً من زرّ المفتاح في القائمة.
  Widget _elCreatedSheet(
      ({String username, String password, String name}) c) {
    final w = elWorkplace(ActiveCompany.current,
        fallbackOwner: _storedOwnerUsername);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.userCheck,
        title: 'تمّ إنشاء الموظف',
        subtitle: c.name,
        tint: AppColors.success,
        tintBg: AppColors.successSoftBg,
        onClose: () => Navigator.of(context).pop(true),
      ),
      footer: SheetFooterBar(
        label: 'تم',
        icon: LucideIcons.check,
        color: AppColors.brandAccent,
        onPressed: () => Navigator.of(context).pop(true),
      ),
      maxHeightFactor: 0.95,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'بيانات الدخول',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _credentialRow('اسم المستخدم', c.username),
                  Divider(height: 1, color: AppColors.divider),
                  _credentialRow('كلمة المرور', c.password),
                ],
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          SizedBox(
            height: H.search,
            child: OutlinedButton.icon(
              onPressed: () => _copyText(
                'اسم المستخدم: ${c.username}\nكلمة المرور: ${c.password}',
                'بيانات الدخول',
              ),
              icon: const Icon(LucideIcons.copy, size: 16),
              label: Text(
                'نسخ اسم المستخدم وكلمة المرور',
                style: AppType.rowLabelBold(color: AppColors.brandAccent),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandAccent,
                side: BorderSide(color: AppColors.brandSoftBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.md),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.lg),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
            decoration: BoxDecoration(
              color: AppTone.info.softBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppTone.info.softBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.logIn,
                      size: 15, color: AppTone.info.fill),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    'الموظف يدخل من شاشة «دخول موظف» باسم المستخدم وكلمة '
                    'المرور — جلسة واحدة فقط (الدخول من جهازٍ ثانٍ يُخرج الأوّل)',
                    style: AppType.body(color: AppTone.info.onSoft),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Icon(LucideIcons.building2, size: 13, color: AppColors.textLow),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text(
                  'يعمل على: ${iso(w.company)}'
                  '${w.owner.isEmpty ? '' : ' · ${iso(w.owner)}'}',
                  style: AppType.muted(color: AppColors.textMid),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// صفّ بيانات دخول: التسمية فوق القيمة (لاتينيّة، قابلة للتحديد) وزرّ نسخها.
  Widget _credentialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.label()),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  textDirection: TextDirection.ltr,
                  style: AppType.rowValue().copyWith(
                    fontSize: 15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.copy,
                size: 16, color: AppColors.brandAccent),
            onPressed: () => _copyText(value, label),
            tooltip: 'نسخ $label',
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  /// نسخٌ للحافظة بتأكيدٍ فوق الشيت — `ScaffoldMessenger` يرسم تحته فلا يُرى.
  Future<void> _copyText(String text, String what) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSheetSnack(context, 'تمّ نسخ $what');
  }

  /// 2026-08-26: قيد الـscope — يظهر بشكل حقل form مطابق للـfields
  /// الأخرى (اسم/باسورد/هاتف). أيقونة يمين + Dropdown ملء العرض + شرح
  /// hint صغير تحت. تصميم نظيف بلا Row مزدوج.
  Widget _scopePicker() {
    final list = _managers;
    if (list == null) {
      // Loading skeleton بنفس ارتفاع الحقول الأخرى
      return _fieldContainer(
        child: Row(
          children: [
            Icon(LucideIcons.userCheck, size: 16, color: AppColors.textMid),
            const SizedBox(width: 10),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Text('جارٍ تحميل المدراء...',
                style: AppType.body(color: AppColors.textLow)),
          ],
        ),
      );
    }
    if (list.isEmpty) return const SizedBox.shrink();
    final selected = _scopeAdminId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldContainer(
          child: Row(
            children: [
              Icon(LucideIcons.userCheck, size: 16, color: AppColors.textMid),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selected,
                    isExpanded: true,
                    icon: Icon(LucideIcons.chevronDown,
                        size: 16, color: AppColors.textMid),
                    hint: Text(
                      'مقيَّد بمدير فرعي (بلا قيد)',
                      style: AppType.subtitle(color: AppColors.textLow),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'بلا قيد — يشاهد كل بياناتك',
                          style: TextStyle(
                            fontFamily: AppType.family,
                            fontSize: 13, height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textHi,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final m in list)
                        DropdownMenuItem<String?>(
                          value: m.id.toString(),
                          child: Text(
                            _managerLabel(m),
                            style: TextStyle(
                              fontFamily: AppType.family,
                              fontSize: 13, height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textHi,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _scopeAdminId = v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Hint خفيف تحت الحقل — يوضّح الأثر بدون ازدحام
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, top: 5),
          child: Text(
            selected == null
                ? 'الموظّف يشاهد كل مشتركين ومدراء حسابك.'
                : 'الموظّف مقيَّد — يرى بيانات المدير الفرعي المختار فقط.',
            style: TextStyle(
              fontFamily: AppType.family,
              fontSize: 10.5, height: 1.3,
              fontWeight: FontWeight.w500,
              color:
                  selected == null ? AppColors.textLow : AppColors.brandAccent,
            ),
          ),
        ),
      ],
    );
  }

  /// Container مطابق لتصميم الـTextField في _field() — نفس المقاسات
  /// والحدود، يعطي الـdropdown مظهر form-field متسق.
  Widget _fieldContainer({required Widget child}) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: child,
    );
  }

  String _managerLabel(
      ({int id, String username, String firstname, String lastname}) m) {
    final full =
        [m.firstname, m.lastname].where((s) => s.isNotEmpty).join(' ').trim();
    if (full.isNotEmpty && full != m.username) return '$full · ${m.username}';
    return m.username;
  }

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool enabled = true,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    FocusNode? focusNode,

    /// اسم دخول: بلا تصحيحٍ تلقائيّ ولا اقتراحات (ايرث لنك وحده).
    bool plainLogin = false,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      autocorrect: !plainLogin,
      enableSuggestions: !plainLogin,
      obscureText: obscure,
      enabled: enabled,
      keyboardType: keyboard,
      inputFormatters: formatters,
      style: AppType.input(color: AppColors.textHi),
      decoration: InputDecoration(
        // مطلب 2026-06-11: hint فقط، لا label عائم. التصميم أنظف
        // والـplaceholder يختفي تلقائياً لما تكتب.
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textLow),
        prefixIcon: Icon(icon, size: 16),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.preset, required this.onTap});
  final PermPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.brandSoftBg,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.brandSoftBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.sparkles,
                  size: 11, color: AppColors.brandAccent),
              const SizedBox(width: 4),
              Text(
                preset.label,
                style: AppType.pillBold(color: AppColors.brandAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ايرث لنك: شريحة دورٍ جاهز — مملوءةٌ بالبراند حين تطابق الصلاحيّات المفعّلة
/// الدورَ تماماً، فيرى المالك أيّ دورٍ مطبَّق وأنّ تعديله جعله «مخصّصاً».
class _ElPresetChip extends StatelessWidget {
  const _ElPresetChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = selected ? AppColors.onBrand : AppColors.brandAccent;
    return Material(
      color: selected ? AppColors.brand : AppColors.brandSoftBg,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.brandSoftBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? LucideIcons.check : icon, size: 11, color: fg),
              const SizedBox(width: 4),
              Text(label, style: AppType.pillBold(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppType.pillBold(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
