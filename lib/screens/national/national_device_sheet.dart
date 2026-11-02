import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_device_api.dart';
import '../../api/national_sheet_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'national_edit_widgets.dart';
import 'national_task_sheet.dart' show NationalPortalLockBox;
import 'national_widgets.dart';

/// «تعديل معلومات الجهاز» للمشروع الوطنيّ في التطبيق (٢ نوفمبر — المالك: «تعديل الفات والماك والرمز بصفحه وحده» ثمّ «لو تخليهن
/// كلهن المتغيرات بصفحه وحده… مفروض تجلب الرمز وتظهره السابق قبل التغير»). نسخة الموقع (`WataniFatEdit.tsx`): الفات، السيريال، الماك
/// (قفلٌ وفكّ)، الرمز (الحاليّ نقاطٌ بإظهارٍ ونسخ)، ونوع الجهاز — أقسامٌ متتالية بصفحةٍ واحدة، كلٌّ بـ«الحاليّ» وزرّ حفظه، نداءٌ واحد بلا
/// إعادة. [fatOn] = `lookups.fat_edit`، [devOn] = `lookups.device_edit` (الخادم يقرّرهما بمفاتيحهما والكتابة وصلاحيّات البوّابة).

Future<bool?> showNationalDeviceSheet(BuildContext context, {required String sid, String? name, required bool fatOn, required bool devOn}) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NationalDeviceSheet(sid: sid, name: name, fatOn: fatOn, devOn: devOn),
  );
}

final _serialOk = RegExp(r'^[A-Za-z0-9]{6,20}$');
final _macOk = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');

class NationalDeviceSheet extends StatefulWidget {
  const NationalDeviceSheet({super.key, required this.sid, this.name, required this.fatOn, required this.devOn});
  final String sid;
  final String? name;
  final bool fatOn;
  final bool devOn;

  @override
  State<NationalDeviceSheet> createState() => _NationalDeviceSheetState();
}

class _NationalDeviceSheetState extends State<NationalDeviceSheet> {
  NationalNetInfo? _net;
  String? _netErr;
  NationalLock? _netLock;
  NationalDeviceInfo? _dev;
  String? _devErr;
  NationalLock? _devLock;
  Timer? _poll;
  int _polls = 0;

  /// ما يُحفظ الآن (قسمٌ واحد في كلّ مرّة): fat · serial · mac · password · vendor.
  String? _busy;
  bool _changed = false;

  // الفات
  String? _fdtPick;
  String? _fatPick;
  List<NationalNetRef>? _otherFats;
  bool _fatsLoading = false;
  String? _fatsErr;

  // الجهاز
  final _serial = TextEditingController();
  final _mac = TextEditingController();
  final _pw = TextEditingController();
  String? _vendorPick;
  bool _serialTouched = false;
  bool _macTouched = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _serial.dispose();
    _mac.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    var pending = false;
    if (widget.fatOn) {
      final r = await NationalDeviceApi.network(widget.sid);
      if (!mounted) return;
      setState(() {
        _netLock = r.lock;
        _netErr = r.locked ? null : r.error;
        if (r.ok && r.data != null) _net = r.data;
      });
      if (r.ok && r.data == null) pending = true;
    }
    if (widget.devOn) {
      final r = await NationalDeviceApi.device(widget.sid);
      if (!mounted) return;
      setState(() {
        _devLock = r.lock;
        _devErr = r.locked ? null : r.error;
        if (r.ok && r.data != null) {
          _dev = r.data;
          // الحقول تبدأ بالحاليّ — ما لم يكتب المستخدم شيئاً
          if (!_serialTouched) _serial.text = r.data!.serial ?? '';
          if (!_macTouched) _mac.text = r.data!.lockedMac ?? r.data!.mac ?? '';
        }
      });
      if (r.ok && r.data == null) pending = true;
    }
    if (pending && _polls++ < 12) _poll = Timer(const Duration(milliseconds: 2500), _load);
  }

  Future<void> _reload() async {
    _polls = 0;
    await _load();
  }

  /* ───────── الفات ───────── */

  String get _fdtId => _fdtPick ?? _net?.fdt?.id ?? '';
  bool get _otherFdt => _net != null && _fdtId.isNotEmpty && _fdtId != _net!.fdt?.id;
  List<NationalNetRef> get _fats => _otherFdt ? (_otherFats ?? const []) : (_net?.fats ?? const []);
  String get _fatId => _fatPick ?? (_otherFdt ? '' : _net?.fat?.id ?? '');

  Future<void> _pickFdt(NationalNetRef f) async {
    setState(() {
      _fdtPick = f.id;
      _fatPick = null;
      _otherFats = null;
      _fatsErr = null;
    });
    if (f.id == _net?.fdt?.id) return;
    setState(() => _fatsLoading = true);
    for (var i = 0; i < 8; i++) {
      final r = await NationalDeviceApi.networkFats(widget.sid, f.id);
      if (!mounted || _fdtPick != f.id) return;
      if (r.ok && r.data != null) {
        setState(() {
          _otherFats = r.data;
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

  Future<void> _saveFat() async {
    final n = _net;
    if (n == null || _busy != null) return;
    final fdt = _fdtId;
    final fat = _fatId;
    setState(() => _busy = 'fat');
    final r = await NationalDeviceApi.saveNetwork(widget.sid, fdtId: fdt, fatId: fat);
    if (!mounted) return;
    setState(() => _busy = null);
    nationalEditSnack(context, r, 'تغيير الفات');
    if (r.ok || r.unconfirmed) {
      _changed = true;
      setState(() {
        _fdtPick = null;
        _fatPick = null;
        _otherFats = null;
      });
      await _reload();
    }
  }

  /* ───────── الجهاز ───────── */

  Future<void> _saveDevice(String field, String value, String what) async {
    if (_busy != null) return;
    setState(() => _busy = field);
    final r = await NationalDeviceApi.saveDevice(widget.sid, field: field, value: value);
    if (!mounted) return;
    setState(() => _busy = null);
    nationalEditSnack(context, r, what);
    if (r.ok || r.unconfirmed) {
      _changed = true;
      if (field == 'password') _pw.clear();
      if (field == 'serial') _serialTouched = false;
      if (field == 'mac') _macTouched = false;
      if (field == 'vendor') _vendorPick = null;
      await _reload();
    }
  }

  Widget _saveButton(String key, String label, {required bool enabled, required VoidCallback onPressed, IconData icon = LucideIcons.save}) {
    final busy = _busy == key;
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: enabled && _busy == null ? onPressed : null,
        icon: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 17),
        label: Text(label, style: AppType.label(color: enabled && _busy == null ? AppColors.onBrand : AppColors.textHint)),
        style: FilledButton.styleFrom(backgroundColor: AppColors.brand, disabledBackgroundColor: AppColors.surfaceDisabled),
      ),
    );
  }

  Widget _note(String text, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: warn ? AppColors.warningSoftBg : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Text(text, style: AppType.micro(color: warn ? AppColors.warningOnSoft : AppColors.textMid)),
      );

  Widget _state({String? err, NationalLock? lock, required VoidCallback retry, required String loading}) {
    if (lock != null) return NationalPortalLockBox(title: lock.title, text: lock.message);
    if (err != null) return NationalStateBox.error(text: err, onRetry: retry);
    return Row(children: [
      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: Sp.sm),
      Expanded(child: Text(loading, style: AppType.muted())),
    ]);
  }

  List<Widget> _fatSection({required bool first}) {
    final n = _net;
    final frozen = _busy != null;
    final same = n != null && _fdtId == n.fdt?.id && _fatId == n.fat?.id;
    final ready = n != null && !n.locked && _fdtId.isNotEmpty && _fatId.isNotEmpty && !same && _fats.any((f) => f.id == _fatId);
    return [
      NationalEditSection(
        first: first,
        icon: LucideIcons.network,
        title: 'الفات',
        now: n == null ? null : NationalNowValue(n.path),
        child: n == null
            ? _state(err: _netErr, lock: _netLock, retry: _reload, loading: 'جارٍ قراءة الـFDT والفات من البوّابة…')
            : n.locked
                ? _note('البوّابة تمنع تغيير الفات لهذا الاشتراك الآن (عناصر الشبكة مقفلة).', warn: true)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('FDT', style: AppType.micro(color: AppColors.textMid)),
                    const SizedBox(height: 6),
                    NationalPickField(title: 'اختر الـFDT', items: n.fdts, selectedId: _fdtId, enabled: !frozen, placeholder: 'اختر الـFDT', onPicked: _pickFdt),
                    const SizedBox(height: Sp.md),
                    Text('الفات', style: AppType.micro(color: AppColors.textMid)),
                    const SizedBox(height: 6),
                    if (_otherFdt && _fatsLoading)
                      Text('جارٍ جلب فاتات هذا الـFDT…', style: AppType.muted())
                    else if (_otherFdt && _fatsErr != null)
                      Text(_fatsErr!, style: AppType.micro(color: AppColors.error))
                    else
                      NationalPickField(
                        title: 'اختر الفات',
                        items: _fats,
                        selectedId: _fatId,
                        enabled: !frozen,
                        placeholder: _fats.isEmpty ? 'لا فاتات لهذا الـFDT' : 'اختر الفات',
                        onPicked: (f) => setState(() => _fatPick = f.id),
                      ),
                    const SizedBox(height: Sp.md),
                    _saveButton('fat', 'حفظ الفات', enabled: ready, onPressed: _saveFat),
                  ]),
      ),
    ];
  }

  List<Widget> _deviceSections({required bool first}) {
    final d = _dev;
    if (d == null) {
      return [
        NationalEditSection(
          first: first,
          icon: LucideIcons.cpu,
          title: 'الجهاز',
          child: _state(err: _devErr, lock: _devLock, retry: _reload, loading: 'جارٍ قراءة معلومات الجهاز من البوّابة…'),
        ),
      ];
    }
    final frozen = _busy != null;
    // السيريال
    final serial = _serial.text.trim();
    final serialOk = _serialOk.hasMatch(serial) && serial.toUpperCase() != (d.serial ?? '').toUpperCase();
    // الماك
    final mac = _mac.text.trim().toUpperCase();
    final macOk = _macOk.hasMatch(mac) && mac != (d.lockedMac ?? '').toUpperCase();
    // الرمز
    final pw = _pw.text;
    final pwOk = pw.isNotEmpty && pw.length <= 64 && (d.passwordRule?.passes(pw) ?? true) && pw != d.password;
    // النوع
    final vendorId = _vendorPick ?? d.vendor?.id ?? '';
    return [
      NationalEditSection(
        first: first,
        icon: LucideIcons.cpu,
        title: 'السيريال',
        now: NationalNowValue(d.serial),
        child: d.locked
            ? _note('البوّابة تمنع تغيير السيريال لهذا الاشتراك الآن (عناصر الشبكة مقفلة).', warn: true)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                NationalLatinField(
                  controller: _serial,
                  hint: 'ZTEGC0FFEE01',
                  maxLength: 20,
                  upper: true,
                  enabled: !frozen,
                  semanticLabel: 'السيريال الجديد',
                  error: serial.isNotEmpty && !_serialOk.hasMatch(serial) ? 'حروفٌ وأرقام إنكليزيّة، من ٦ إلى ٢٠' : null,
                  helper: Text('تأكّد منه: سيريالٌ خطأ يقطع الخدمة عن المشترك.', style: AppType.micro(color: AppColors.textMid)),
                  onChanged: (_) => setState(() => _serialTouched = true),
                ),
                const SizedBox(height: Sp.md),
                _saveButton('serial', 'حفظ السيريال', enabled: serialOk, onPressed: () => _saveDevice('serial', serial, 'تغيير السيريال')),
              ]),
      ),
      NationalEditSection(
        icon: LucideIcons.router,
        title: 'الماك',
        now: NationalNowValue(d.mac),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(d.lockedMac != null ? 'مقفلٌ على ${d.lockedMac}' : 'غير مقفل',
              style: AppType.micro(color: d.lockedMac != null ? AppColors.textHi : AppColors.textMid)),
          const SizedBox(height: Sp.sm),
          NationalLatinField(
            controller: _mac,
            hint: 'AA:BB:CC:DD:EE:FF',
            maxLength: 17,
            upper: true,
            enabled: !frozen,
            semanticLabel: 'قفل الماك على',
            error: mac.isNotEmpty && !_macOk.hasMatch(mac) ? 'بصيغة AA:BB:CC:DD:EE:FF' : null,
            onChanged: (_) => setState(() => _macTouched = true),
          ),
          const SizedBox(height: Sp.md),
          Row(children: [
            Expanded(child: _saveButton('mac', 'قفل الماك', icon: LucideIcons.lock, enabled: macOk, onPressed: () => _saveDevice('mac', mac, 'قفل الماك'))),
            if (d.lockedMac != null) ...[
              const SizedBox(width: Sp.sm),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: frozen ? null : () => _saveDevice('mac', '', 'فكّ قفل الماك'),
                  icon: const Icon(LucideIcons.lockOpen, size: 17),
                  label: const Text('فكّ القفل'),
                ),
              ),
            ],
          ]),
        ]),
      ),
      NationalEditSection(
        icon: LucideIcons.keyRound,
        title: 'الرمز',
        now: NationalSecretValue(value: d.password, hidden: d.passwordHidden),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NationalLatinField(
            controller: _pw,
            hint: 'الرمز الجديد',
            maxLength: 64,
            secret: true,
            enabled: !frozen,
            semanticLabel: 'الرمز الجديد',
            error: pw.isNotEmpty && !(d.passwordRule?.passes(pw) ?? true) ? 'الرمز لا يطابق شروط البوّابة' : null,
            helper: d.passwordRule?.description == null ? null : Text(d.passwordRule!.description!, style: AppType.micro(color: AppColors.textMid)),
            onChanged: (_) => setState(() {}),
          ),
          if (pw.isNotEmpty && pw == d.password) ...[
            const SizedBox(height: 6),
            Text('هذا هو الرمز الحاليّ نفسه.', style: AppType.micro(color: AppColors.textMid)),
          ],
          const SizedBox(height: Sp.md),
          _saveButton('password', 'حفظ الرمز', enabled: pwOk, onPressed: () => _saveDevice('password', pw, 'تغيير الرمز')),
        ]),
      ),
      NationalEditSection(
        icon: LucideIcons.cable,
        title: 'نوع الجهاز',
        now: NationalNowValue(d.vendor?.name),
        child: d.locked
            ? _note('البوّابة تمنع تغيير نوع الجهاز لهذا الاشتراك الآن (عناصر الشبكة مقفلة).', warn: true)
            : d.vendors == null
                ? _note('تعذّرت قراءة أنواع الأجهزة من البوّابة (صلاحيّة عناصر الشبكة).')
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    NationalPickField(
                      title: 'نوع الجهاز',
                      items: d.vendors!,
                      selectedId: vendorId,
                      enabled: !frozen,
                      placeholder: 'اختر نوع الجهاز',
                      onPicked: (v) => setState(() => _vendorPick = v.id),
                    ),
                    const SizedBox(height: Sp.md),
                    _saveButton('vendor', 'حفظ النوع',
                        enabled: vendorId.isNotEmpty && vendorId != d.vendor?.id, onPressed: () => _saveDevice('vendor', vendorId, 'تغيير نوع الجهاز')),
                  ]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final title = widget.devOn ? 'تعديل معلومات الجهاز' : 'تغيير الفات';
    final d = _dev;
    return PopScope(
      canPop: _busy == null,
      onPopInvokedWithResult: (didPop, _) {},
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: widget.devOn ? LucideIcons.cpu : LucideIcons.network,
          title: title,
          subtitle: widget.name ?? 'يُحفظ في بوّابة المشروع الوطني',
          onClose: () {
            if (_busy == null) Navigator.of(context).pop(_changed);
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (d?.username != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
                child: Row(children: [
                  Text('اسم الجهاز', style: AppType.muted(color: AppColors.textMid)),
                  const Spacer(),
                  Flexible(child: Text(d!.username!, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.labelBold(color: AppColors.textHi))),
                ]),
              ),
              const SizedBox(height: Sp.lg),
            ],
            if (widget.fatOn) ..._fatSection(first: true),
            if (widget.devOn) ..._deviceSections(first: !widget.fatOn),
            const SizedBox(height: Sp.lg),
            Text('كلّ قسمٍ يُحفظ بزرّه في بوّابة المشروع الوطني — طلبٌ واحد بلا إعادة.', style: AppType.micro(color: AppColors.textHint)),
          ],
        ),
      ),
    );
  }
}
