import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_device_api.dart';
import '../../api/national_sheet_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'national_edit_widgets.dart';
import 'national_task_sheet.dart' show NationalPortalLockBox;
import 'national_ticket_write.dart';
import 'national_widgets.dart';

/// «تنصيب الجهاز» — مهمّة «اعداد مشترك» من طلب تسجيلٍ في بوّابة المشروع الوطنيّ (٢ نوفمبر، المالك: «اكو طلبات تتطلب تدخل يعني النقر
/// على زر تنصيب الجهاز install يفتح نافذه ثانيه» ثمّ «تنصيب الجهاز مفروض تكمله»). نسخة الموقع (`WataniInstall.tsx`) بصفحةٍ واحدة:
/// اسم مستخدم الجهاز (يُفحص حيّاً هل هو متاح)، رمزه، رقم توريد النقطة (HTWC)، FDT والفات من زون المهمّة، سيريال الجهاز ونوعه، وكود
/// التفعيل ⇒ «تأشير كمكتمل» بتأكيدٍ بملخّص ⇒ طلبٌ واحد بلا إعادة. المكتملة: «معلومات التنصيب» (ما سُجّل، والرمز مخفيّاً بإظهارٍ ونسخ
/// لمن يُسمح له). الرمز والكود لا يُخزَّنان في التطبيق.

/// يفتح النافذة؛ يرجع true إن سُجّل التنصيب (أو أُرسل ولم يتأكّد) — فتُعاد قراءة المهمّة.
Future<bool?> showNationalInstallSheet(BuildContext context, {required String taskId, String? customer}) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    builder: (_) => NationalInstallSheet(taskId: taskId, customer: customer),
  );
}

final _serialOk = RegExp(r'^[A-Za-z0-9]{6,20}$');
final _pointOk = RegExp(r'^[A-Za-z0-9]{1,20}$');
final _codeOk = RegExp(r'^\S{1,40}$');
final _userFallback = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d\-_]{3,30}$');

class NationalInstallSheet extends StatefulWidget {
  const NationalInstallSheet({super.key, required this.taskId, this.customer});
  final String taskId;
  final String? customer;

  @override
  State<NationalInstallSheet> createState() => _NationalInstallSheetState();
}

class _NationalInstallSheetState extends State<NationalInstallSheet> {
  NationalInstallInfo? _info;
  String? _err;
  NationalLock? _lock;
  Timer? _poll;
  int _polls = 0;

  final _user = TextEditingController();
  final _pw = TextEditingController();
  final _point = TextEditingController();
  final _serial = TextEditingController();
  final _code = TextEditingController();
  String? _fdtPick;
  String? _fatId;
  String? _vendorId;
  List<NationalNetRef>? _fats;
  String? _fatsFor;
  bool _fatsLoading = false;
  String? _fatsErr;

  // فحص الاسم
  Timer? _userTimer;
  String _checked = '';
  NationalUserCheck? _check;
  bool _checking = false;

  bool _tried = false; // ضُغط «تأشير كمكتمل» ⇒ تُبيَّن كلّ الأخطاء
  bool _busy = false;
  String? _unconfirmed;
  ({String? field, String text})? _serverErr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _userTimer?.cancel();
    for (final c in [_user, _pw, _point, _serial, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    final r = await NationalDeviceApi.install(widget.taskId);
    if (!mounted) return;
    if (r.ok && r.data == null) {
      if (_polls++ < 12) _poll = Timer(const Duration(milliseconds: 2500), _load);
      return;
    }
    setState(() {
      _lock = r.lock;
      _err = r.locked ? null : r.error;
      if (r.ok) _info = r.data;
    });
    final i = r.data;
    if (i != null && !i.done && i.fdts.length == 1) unawaited(_loadFats(i.fdts.first.id));
  }

  String get _fdtId => _fdtPick ?? ((_info?.fdts.length ?? 0) == 1 ? _info!.fdts.first.id : '');

  Future<void> _loadFats(String fdtId) async {
    setState(() {
      _fatsLoading = true;
      _fatsErr = null;
      _fatsFor = fdtId;
      _fats = null;
    });
    for (var i = 0; i < 8; i++) {
      final r = await NationalDeviceApi.installFats(widget.taskId, fdtId);
      if (!mounted || _fatsFor != fdtId) return;
      if (r.ok && r.data != null) {
        setState(() {
          _fats = r.data;
          _fatsLoading = false;
        });
        return;
      }
      if (!r.ok) {
        setState(() {
          _fatsErr = r.error ?? 'تعذّر جلب فاتات هذا الـFDT';
          _fatsLoading = false;
        });
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2500));
    }
    if (mounted) setState(() => _fatsLoading = false);
  }

  bool _userShape(String u) => u.isNotEmpty && u.length <= 30 && (_info?.usernameRule?.passes(u, fallback: _userFallback) ?? _userFallback.hasMatch(u));

  void _onUser(String v) {
    _edited('username');
    _userTimer?.cancel();
    final u = v.trim();
    if (!_userShape(u)) {
      setState(() {
        _check = null;
        _checking = false;
      });
      return;
    }
    setState(() => _checking = true);
    _userTimer = Timer(const Duration(milliseconds: 700), () => _runCheck(u, 0));
  }

  Future<void> _runCheck(String u, int attempt) async {
    final r = await NationalDeviceApi.checkUsername(widget.taskId, u);
    if (!mounted || _user.text.trim() != u) return;
    if (r.retry && attempt < 4) {
      _userTimer = Timer(const Duration(milliseconds: 1400), () => _runCheck(u, attempt + 1));
      return;
    }
    setState(() {
      _checked = u;
      _check = r.retry ? null : r;
      _checking = false;
    });
  }

  void _edited(String field) {
    if (_serverErr != null && (_serverErr!.field == field || _serverErr!.field == null)) _serverErr = null;
    setState(() {});
  }

  /* ───────── التحقّق ───────── */

  Map<String, String?> _errors() {
    final i = _info!;
    final u = _user.text.trim();
    final check = _checked == u ? _check : null;
    final pw = _pw.text;
    final serial = _serial.text.trim();
    final fats = _fats ?? const <NationalNetRef>[];
    return {
      'username': u.isEmpty
          ? 'اكتب اسم مستخدم الجهاز'
          : !_userShape(u)
              ? (i.usernameRule?.description ?? 'حروفٌ إنكليزيّة وأرقام وفيه حرفٌ ورقم (٣–٣٠)')
              : check?.valid == false
                  ? (check!.message ?? 'البوّابة لا تقبل هذا الاسم')
                  : null,
      'password': pw.isEmpty
          ? 'اكتب رمز الجهاز'
          : (pw.length > 64 || !(i.passwordRule?.passes(pw) ?? true))
              ? (i.passwordRule?.description ?? 'الرمز لا يطابق شروط البوّابة')
              : null,
      'point': _pointOk.hasMatch(_point.text.trim()) ? null : 'حروفٌ وأرقام إنكليزيّة فقط (حتى ٢٠)',
      'fdt': _fdtId.isEmpty ? 'اختر الـFDT' : null,
      'fat': (_fatId != null && fats.any((f) => f.id == _fatId)) ? null : 'اختر الفات',
      'serial': _serialOk.hasMatch(serial) ? null : 'حروفٌ وأرقام إنكليزيّة، من ٦ إلى ٢٠',
      'vendor': (_vendorId != null && i.vendors.any((v) => v.id == _vendorId)) ? null : 'اختر نوع الجهاز',
      'code': _codeOk.hasMatch(_code.text.trim()) ? null : 'اكتب كود التفعيل (بلا مسافات)',
    };
  }

  String? _errOf(Map<String, String?> errs, String f, {bool typed = false}) {
    if (_serverErr?.field == f) return _serverErr!.text;
    if (_tried || typed) return errs[f];
    return null;
  }

  /* ───────── الإرسال ───────── */

  Future<void> _submit() async {
    final i = _info;
    if (i == null || _busy || _unconfirmed != null) return;
    final errs = _errors();
    setState(() => _tried = true);
    if (errs.values.any((e) => e != null)) {
      showSheetSnack(context, 'أكمل الحقول المؤشَّرة', isError: true, autoExplain: false);
      return;
    }
    final fdt = i.fdts.firstWhere((x) => x.id == _fdtId);
    final fat = (_fats ?? const <NationalNetRef>[]).firstWhere((x) => x.id == _fatId);
    final vendor = i.vendors.firstWhere((x) => x.id == _vendorId);
    final go = await showConfirmSheet(
      context,
      title: 'تأكيد التنصيب',
      message: [
        'يُرسل مرّةً واحدة ويغلق المهمّة في البوّابة:',
        'اسم مستخدم الجهاز: ${_user.text.trim()}',
        'السيريال: ${_serial.text.trim()}',
        'نوع الجهاز: ${vendor.name}',
        'FDT ← الفات: ${fdt.name} ← ${fat.name}',
        'رقم توريد النقطة (HTWC): ${_point.text.trim()}',
      ].join('\n'),
      confirmLabel: 'تأكيد وإرسال',
      cancelLabel: 'رجوع',
      icon: LucideIcons.wrench,
    );
    if (go != true || !mounted) return;
    setState(() {
      _busy = true;
      _serverErr = null;
    });
    final r = await NationalDeviceApi.submitInstall(
      widget.taskId,
      username: _user.text.trim(),
      password: _pw.text,
      pointSupply: _point.text.trim(),
      serial: _serial.text.trim(),
      vendorId: vendor.id,
      fdtId: fdt.id,
      fatId: fat.id,
      code: _code.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showSheetSnack(context, r.message ?? (r.applied ? 'تمّ التنصيب — المهمّة مكتملة' : 'قبلت البوّابة التنصيب'));
      Navigator.of(context).pop(true);
      return;
    }
    if (r.unconfirmed) {
      setState(() => _unconfirmed = r.message ?? 'لم يتأكّد التنصيب — لا تُعده الآن؛ افتح المهمّة بعد دقيقة وتحقّق من حالتها');
      return;
    }
    if (r.code == 'ALREADY_DONE' || r.code == 'REPEATED') {
      showSheetSnack(context, r.message ?? 'سُجّل تنصيب هذه المهمّة للتوّ', duration: const Duration(seconds: 8));
      Navigator.of(context).pop(true);
      return;
    }
    final field = r.code == 'INVALID_CODE' ? 'code' : r.code == 'USERNAME_INVALID' ? 'username' : null;
    setState(() => _serverErr = (field: field, text: r.text));
    if (field == null) showSheetSnack(context, r.text, isError: true, duration: const Duration(seconds: 10), autoExplain: false);
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_unconfirmed != null) {
      Navigator.of(context).pop(true);
      return;
    }
    final dirty = [_user, _pw, _point, _serial, _code].any((c) => c.text.isNotEmpty);
    if (dirty) {
      final go = await showConfirmSheet(
        context,
        title: 'إغلاق بلا تنصيب؟',
        message: 'ما كتبته يُمسح ولا يُرسل شيء.',
        confirmLabel: 'إغلاق',
        cancelLabel: 'البقاء',
        icon: LucideIcons.triangleAlert,
        tone: AppTone.warning,
      );
      if (go != true || !mounted) return;
    }
    Navigator.of(context).pop(false);
  }

  /* ───────── العرض ───────── */

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: AppType.label(color: AppColors.textLabel)));

  Widget _infoBox(NationalInstallInfo i) => NationalInfoGroup(children: [
        NationalInfoRow(icon: LucideIcons.user, label: 'المشترك', value: i.customer ?? widget.customer ?? '—'),
        NationalInfoRow(icon: LucideIcons.mapPin, label: 'الزون', value: i.zone ?? '—', ltr: true),
      ]);

  Widget _doneView(NationalInstallInfo i) {
    final s = i.saved;
    if (s == null) {
      return Text(i.completed ? 'المهمّة مكتملة — تعذّرت قراءة ما سُجّل بها الآن.' : 'المهمّة ملغاة — لا تنصيب فيها.', style: AppType.muted());
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.successSoftBg, borderRadius: BorderRadius.circular(R.md)),
        child: Row(children: [
          Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text('المهمّة مكتملة — هذا ما سُجّل بالتنصيب', style: AppType.label(color: AppColors.success))),
        ]),
      ),
      const SizedBox(height: Sp.md),
      NationalInfoGroup(children: [
        NationalInfoRow(icon: LucideIcons.user, label: 'اسم مستخدم الجهاز', value: s.username ?? '—', ltr: true),
        NationalInfoRow(icon: LucideIcons.cpu, label: 'السيريال', value: s.serial ?? '—', ltr: true),
        NationalInfoRow(icon: LucideIcons.cable, label: 'نوع الجهاز', value: s.vendor?.name ?? '—', ltr: true),
        NationalInfoRow(
          icon: LucideIcons.network,
          label: 'FDT ← الفات',
          value: [if (s.fdt != null) s.fdt!.name, if (s.fat != null) s.fat!.name].join(' ← ').ifEmpty('—'),
          ltr: true,
        ),
        NationalInfoRow(icon: LucideIcons.hash, label: 'رقم توريد النقطة (HTWC)', value: s.pointSupply ?? '—', ltr: true),
      ]),
      const SizedBox(height: Sp.md),
      Row(children: [
        Text('رمز الجهاز', style: AppType.muted(color: AppColors.textMid)),
        const Spacer(),
        NationalSecretValue(value: s.password, hidden: s.passwordHidden, prefix: ''),
      ]),
    ]);
  }

  Widget _form(NationalInstallInfo i) {
    final errs = _errors();
    final frozen = _busy || _unconfirmed != null;
    final u = _user.text.trim();
    final fats = _fats ?? const <NationalNetRef>[];
    final Widget? userStatus = !_userShape(u)
        ? null
        : (_checking || _checked != u)
            ? Text('يُفحص الاسم…', style: AppType.micro(color: AppColors.textMid))
            : _check?.valid == true
                ? Row(children: [
                    Icon(LucideIcons.circleCheck, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text('الاسم متاح', style: AppType.micro(color: AppColors.success)),
                  ])
                : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('اسم مستخدم الجهاز'),
      NationalLatinField(
        controller: _user,
        hint: 'fbg-user1',
        maxLength: 30,
        enabled: !frozen,
        semanticLabel: 'اسم مستخدم الجهاز',
        error: _errOf(errs, 'username', typed: u.isNotEmpty && (!_userShape(u) || (_checked == u && _check?.valid == false))),
        helper: userStatus ?? (i.usernameRule?.description == null ? null : Text(i.usernameRule!.description!, style: AppType.micro(color: AppColors.textMid))),
        onChanged: _onUser,
      ),
      const SizedBox(height: Sp.lg),
      _label('رمز الجهاز'),
      NationalLatinField(
        controller: _pw,
        maxLength: 64,
        secret: true,
        enabled: !frozen,
        semanticLabel: 'رمز الجهاز',
        error: _errOf(errs, 'password'),
        helper: i.passwordRule?.description == null ? null : Text(i.passwordRule!.description!, style: AppType.micro(color: AppColors.textMid)),
        onChanged: (_) => _edited('password'),
      ),
      const SizedBox(height: Sp.lg),
      _label('رقم توريد النقطة (HTWC)'),
      NationalLatinField(
        controller: _point,
        maxLength: 20,
        enabled: !frozen,
        semanticLabel: 'رقم توريد النقطة',
        error: _errOf(errs, 'point'),
        onChanged: (_) => _edited('point'),
      ),
      const SizedBox(height: Sp.lg),
      _label('FDT'),
      if (i.fdts.isEmpty)
        Text('لا FDT لزون هذه المهمّة في البوّابة', style: AppType.micro(color: AppColors.error))
      else
        NationalPickField(
          title: 'اختر الـFDT',
          items: i.fdts,
          selectedId: _fdtId,
          enabled: !frozen,
          placeholder: 'اختر الـFDT',
          error: _errOf(errs, 'fdt'),
          onPicked: (f) {
            setState(() {
              _fdtPick = f.id;
              _fatId = null;
            });
            _loadFats(f.id);
          },
        ),
      const SizedBox(height: Sp.lg),
      _label('الفات'),
      if (_fdtId.isEmpty)
        Text('اختر الـFDT أوّلاً', style: AppType.muted())
      else if (_fatsLoading)
        Text('جارٍ جلب الفاتات…', style: AppType.muted())
      else if (_fatsErr != null)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_fatsErr!, style: AppType.micro(color: AppColors.error)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: () => _loadFats(_fdtId), child: const Text('إعادة')),
          ),
        ])
      else
        NationalPickField(
          title: 'اختر الفات',
          items: fats,
          selectedId: _fatId,
          enabled: !frozen,
          placeholder: fats.isEmpty ? 'لا فاتات لهذا الـFDT' : 'اختر الفات',
          error: _errOf(errs, 'fat'),
          onPicked: (f) => setState(() => _fatId = f.id),
        ),
      const SizedBox(height: Sp.lg),
      _label('سيريال الجهاز (ONT)'),
      NationalLatinField(
        controller: _serial,
        hint: 'ZTEGC0FFEE01',
        maxLength: 20,
        upper: true,
        enabled: !frozen,
        semanticLabel: 'سيريال الجهاز',
        error: _errOf(errs, 'serial'),
        onChanged: (_) => _edited('serial'),
      ),
      const SizedBox(height: Sp.lg),
      _label('نوع الجهاز'),
      NationalPickField(
        title: 'نوع الجهاز',
        items: i.vendors,
        selectedId: _vendorId,
        enabled: !frozen,
        placeholder: 'اختر نوع الجهاز',
        error: _errOf(errs, 'vendor'),
        onPicked: (v) => setState(() => _vendorId = v.id),
      ),
      const SizedBox(height: Sp.lg),
      _label('كود التفعيل'),
      NationalLatinField(
        controller: _code,
        maxLength: 40,
        enabled: !frozen,
        semanticLabel: 'كود التفعيل',
        error: _errOf(errs, 'code'),
        helper: Text('كود التفعيل الخاصّ بطلب هذا المشترك', style: AppType.micro(color: AppColors.textMid)),
        onChanged: (_) => _edited('code'),
      ),
      if (_unconfirmed != null) ...[
        const SizedBox(height: Sp.lg),
        NationalUnconfirmedBox(text: _unconfirmed!),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final i = _info;
    final done = i?.done == true;
    final Widget body;
    if (_lock != null) {
      body = NationalPortalLockBox(title: _lock!.title, text: _lock!.message);
    } else if (i == null && _err != null) {
      body = NationalStateBox.error(text: _err!, onRetry: () {
        setState(() => _err = null);
        _polls = 0;
        _load();
      });
    } else if (i == null) {
      body = const NationalStateBox.pending(text: 'جارٍ قراءة المهمّة ومراجعها من البوّابة…');
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _infoBox(i),
        const SizedBox(height: Sp.lg),
        if (done) _doneView(i) else _form(i),
      ]);
    }
    return PopScope(
      canPop: !_busy,
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.wrench,
          title: done ? 'معلومات التنصيب' : 'تنصيب الجهاز',
          subtitle: '«اعداد مشترك» — يُسجَّل في بوّابة المشروع الوطني',
          onClose: _close,
        ),
        body: body,
        footer: i == null || done
            ? null
            : SheetFooterBar(
                label: _unconfirmed != null ? 'إغلاق والتحقّق لاحقاً' : 'تأشير كمكتمل',
                icon: _unconfirmed != null ? LucideIcons.x : LucideIcons.circleCheck,
                busy: _busy,
                onPressed: _unconfirmed != null ? _close : _submit,
              ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
