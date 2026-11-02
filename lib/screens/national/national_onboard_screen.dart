import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_device_api.dart' show NationalNetRef;
import '../../api/national_onboard_api.dart';
import '../../api/national_sheet_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../subscribers/sheets/location_picker_screen.dart';
import 'national_edit_widgets.dart';
import 'national_task_sheet.dart' show NationalPortalLockBox;
import 'national_widgets.dart';

/// «إضافة مشترك» — طلب «تسجيل زبون جديد» في بوّابة المشروع الوطنيّ (٢ نوفمبر — نسخة الموقع `WataniOnboardSheet.tsx`؛ المالك:
/// «هي نفسها بالطلبات الي اضافة مشترك»). صفحةٌ واحدة بأقسام: المشترك (اسمه الرباعيّ واللقب واسم أمّه وهاتفه)، البطاقة الموحّدة (تُفحص
/// صلاحيتها هنا أوّلاً: ١٠ سنوات من الإصدار — سبب الإلغاء الحيّ — ثمّ في البوّابة) وصورتاها، بطاقة السكن وصورتاها، العنوان والموقع من
/// الخريطة، الباقة، والعقد وتوقيع المشترك ⇒ «إرسال الطلب» ⇒ رمز التأكيد الذي يصل لهاتف المشترك. الصور تُرفع للبوّابة وحدها لحظة
/// اختيارها ولا تُحفظ في التطبيق ولا عندنا.

/// يفتح الصفحة؛ يرجع true إن أُرسل طلب (فتُعاد قراءة «الطلبات»).
Future<bool?> showNationalOnboardScreen(BuildContext context) =>
    Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NationalOnboardScreen()));

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// نوع الصورة من أوّل بايتاتها.
String? onboardImageType(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  return null;
}

enum _Up { idle, busy, done, error }

class _Photo {
  _Up state = _Up.idle;
  String? id;
  String? error;
  Uint8List? preview;
}

class NationalOnboardScreen extends StatefulWidget {
  const NationalOnboardScreen({super.key, this.picker, this.locate});

  /// مُختار الصور (يُبدَّل في الاختبار).
  final Future<Uint8List?> Function(BuildContext context, {required bool camera})? picker;

  /// مُختار الموقع (يُبدَّل في الاختبار؛ الافتراضيّ الخريطة).
  final Future<({double lat, double lng})?> Function(BuildContext context)? locate;

  @override
  State<NationalOnboardScreen> createState() => _NationalOnboardScreenState();
}

class _NationalOnboardScreenState extends State<NationalOnboardScreen> {
  OnboardMeta? _meta;
  String? _err;
  NationalLock? _lock;
  Timer? _poll;
  int _polls = 0;

  final _c = <String, TextEditingController>{
    for (final k in const ['first', 'second', 'third', 'fourth', 'family', 'mFirst', 'mSecond', 'mThird', 'mFourth', 'mobile', 'idNumber', 'familyNumber', 'idPlace', 'resNumber', 'resPlace', 'address', 'neighbourhood', 'street', 'house', 'apartment', 'otp', 'idIssued', 'birthday', 'resIssued'])
      k: TextEditingController(),
  };

  /// التواريخ تُكتب كما على البطاقة (أسرع من التقويم) أو تُختار منه.
  DateTime? get _idIssued => parseOnboardDate(_c['idIssued']!.text);
  DateTime? get _birthday => parseOnboardDate(_c['birthday']!.text);
  DateTime? get _resIssued => parseOnboardDate(_c['resIssued']!.text);
  ({double lat, double lng})? _gps;
  String? _zone;
  String? _plan;
  String? _option;
  final _photos = <String, _Photo>{for (final k in const ['id_front', 'id_back', 'res_front', 'res_back', 'signature']) k: _Photo()};
  final _sigKey = GlobalKey();
  final _strokes = <List<Offset>>[];
  bool _signed = false;

  bool _tried = false;
  bool _busy = false;
  String? _serverErr;
  ({bool? valid, String? text})? _idCheck;
  bool _idChecking = false;
  ({String? rid, String? to})? _done;
  ({bool? valid, String? text})? _otpRes;
  bool _otpBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    final r = await NationalOnboardApi.meta();
    if (!mounted) return;
    if (r.ok && r.data == null) {
      if (_polls++ < 12) _poll = Timer(const Duration(milliseconds: 2500), _load);
      return;
    }
    setState(() {
      _lock = r.lock;
      _err = r.locked ? null : r.error;
      if (r.ok) {
        _meta = r.data;
        if ((_meta?.options.length ?? 0) == 1) _option = _meta!.options.first.id;
      }
    });
  }

  String _t(String k) => _c[k]!.text.trim();

  /* ───────── القواعد ───────── */

  Map<String, String> _errors() {
    final e = <String, String>{};
    void need(String k, String label) {
      if (_t(k).isEmpty) e[k] = 'اكتب $label';
    }

    void name(String k, String label, {bool required = true}) {
      final t = _t(k);
      if (t.isEmpty) {
        if (required) e[k] = 'اكتب $label';
      } else if (t.length < 2 || !RegExp(r"^[A-Za-zء-ي٠-٩پچکگی\s'.-]+$").hasMatch(t)) {
        e[k] = '$label بحروفٍ فقط';
      }
    }

    String? date(String k, DateTime? v, String label) {
      if (v != null) return null;
      return _t(k).isEmpty ? label : 'تاريخٌ غير صحيح — مثل 2018-03-21';
    }

    name('first', 'الاسم');
    name('second', 'اسم الأب');
    name('third', 'اسم الجدّ');
    name('fourth', 'الاسم الرابع', required: false);
    name('family', 'اللقب');
    name('mFirst', 'اسم الأمّ');
    name('mSecond', 'اسم أبيها');
    name('mThird', 'اسم جدّها');
    name('mFourth', 'الاسم الرابع للأمّ', required: false);
    if (!RegExp(r'^07\d{9}$').hasMatch(onboardLatin(_t('mobile')).replaceAll(RegExp(r'\D'), ''))) e['mobile'] = 'هاتف المشترك 07XXXXXXXXX';
    if (!RegExp(r'^\d{12}$').hasMatch(onboardLatin(_t('idNumber')).replaceAll(RegExp(r'\D'), ''))) e['idNumber'] = 'رقم البطاقة ١٢ رقماً';
    if (!RegExp(r'^[0-9A-Za-z]{10,24}$').hasMatch(onboardLatin(_t('familyNumber')).replaceAll(RegExp(r'\s'), ''))) e['familyNumber'] = 'الرقم العائليّ كما على البطاقة';
    need('idPlace', 'جهة الإصدار');
    final issued = _idIssued, birth = _birthday;
    final exp = onboardCardExpiry(issued, _meta?.cardYears ?? 10);
    final idDate = date('idIssued', issued, 'تاريخ الإصدار');
    if (idDate != null) {
      e['idIssued'] = idDate;
    } else if (exp != null && exp.expired) {
      e['idIssued'] = 'البطاقة منتهية (انتهت ${exp.on}) — الشركة تلغي الطلب، جدّد البطاقة أوّلاً';
    }
    final birthDate = date('birthday', birth, 'تاريخ الميلاد');
    if (birthDate != null) {
      e['birthday'] = birthDate;
    } else if (birth != null) {
      final n = DateTime.now();
      final age = n.year - birth.year - ((n.month < birth.month || (n.month == birth.month && n.day < birth.day)) ? 1 : 0);
      if (age < 18) {
        e['birthday'] = 'المشترك يجب أن يكون بالغاً (١٨ سنة فأكثر)';
      } else if (issued != null && !birth.isBefore(issued)) {
        e['birthday'] = 'الميلاد بعد الإصدار — راجع التاريخين';
      }
    }
    if (!RegExp(r'^\d{1,12}$').hasMatch(onboardLatin(_t('resNumber')).replaceAll(RegExp(r'\D'), ''))) e['resNumber'] = 'رقم بطاقة السكن';
    need('resPlace', 'جهة الإصدار');
    final resDate = date('resIssued', _resIssued, 'تاريخ الإصدار');
    if (resDate != null) e['resIssued'] = resDate;
    if (_zone == null) e['zone'] = 'اختر الزون';
    need('address', 'أقرب نقطة دالّة');
    void short(String k, String label, {bool required = true}) {
      final t = onboardLatin(_t(k)).replaceAll(RegExp(r'\s'), '');
      if (t.isEmpty) {
        if (required) e[k] = 'اكتب $label';
      } else if (!RegExp(r'^[0-9A-Za-zء-ي/-]{1,10}$').hasMatch(t)) {
        e[k] = '$label أرقامٌ (حتى ١٠)';
      }
    }

    short('neighbourhood', 'المحلّة');
    short('street', 'الزقاق');
    short('house', 'الدار');
    short('apartment', 'الشقّة', required: false);
    if (_gps == null) e['gps'] = 'حدّد الموقع على الخريطة';
    if (_plan == null) e['plan'] = 'اختر الباقة';
    if (_option == null && (_meta?.options.length ?? 0) != 1) e['option'] = 'اختر خيار التركيب';
    for (final k in _photos.keys) {
      if (_photos[k]!.state != _Up.done) e[k] = k == 'signature' ? 'وقّع المشترك' : 'صوّرها';
    }
    return e;
  }

  String? _show(Map<String, String> e, String k) => _tried ? e[k] : null;

  /* ───────── الصور والتوقيع ───────── */

  Future<Uint8List?> _pickImage({required bool camera}) async {
    if (widget.picker != null) return widget.picker!(context, camera: camera);
    final f = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    return f?.readAsBytes();
  }

  Future<void> _upload(String kind, Uint8List bytes) async {
    final type = onboardImageType(bytes);
    final p = _photos[kind]!;
    if (type == null) {
      setState(() {
        p.state = _Up.error;
        p.error = 'الملف ليس صورة — أعد التصوير';
      });
      return;
    }
    setState(() {
      p.state = _Up.busy;
      p.error = null;
      p.preview = kind == 'signature' ? null : bytes;
    });
    final r = await NationalOnboardApi.upload(kind, bytes, contentType: type);
    if (!mounted) return;
    setState(() {
      p.state = r.id != null ? _Up.done : _Up.error;
      p.id = r.id;
      p.error = r.error;
    });
  }

  Future<void> _pick(String kind, {required bool camera}) async {
    final b = await _pickImage(camera: camera);
    if (b == null || !mounted) return;
    await _upload(kind, b);
  }

  Future<void> _saveSignature() async {
    if (!_signed) return;
    final o = _sigKey.currentContext?.findRenderObject();
    if (o is! RenderRepaintBoundary) return;
    final img = await o.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || !mounted) return;
    await _upload('signature', data.buffer.asUint8List());
  }

  void _clearSignature() {
    setState(() {
      _strokes.clear();
      _signed = false;
      final p = _photos['signature']!;
      p.state = _Up.idle;
      p.id = null;
      p.error = null;
    });
  }

  /* ───────── الفحص والإرسال ───────── */

  Future<void> _checkId() async {
    setState(() => _idChecking = true);
    final r = await NationalOnboardApi.validateId({
      'id_number': _t('idNumber'),
      'family_number': _t('familyNumber'),
      'place_of_issue': _t('idPlace'),
      'issued_at': _idIssued == null ? '' : _ymd(_idIssued!),
      'birthday': _birthday == null ? '' : _ymd(_birthday!),
    });
    if (!mounted) return;
    setState(() {
      _idChecking = false;
      _idCheck = r.error != null
          ? (valid: false, text: r.error)
          : (valid: r.valid, text: r.valid == true ? (r.warn ?? 'صالحة — تنتهي ${r.expiresOn ?? ''}') : (r.message ?? 'رفضت البوّابة بيانات البطاقة'));
    });
  }

  Future<void> _submit({bool confirmRepeat = false}) async {
    final e = _errors();
    setState(() {
      _tried = true;
      _serverErr = null;
    });
    final m = _meta;
    if (e.isNotEmpty || m == null || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final r = await NationalOnboardApi.create({
      'name': {'first': _t('first'), 'second': _t('second'), 'third': _t('third'), 'fourth': _t('fourth'), 'family': _t('family')},
      'mother': {'first': _t('mFirst'), 'second': _t('mSecond'), 'third': _t('mThird'), 'fourth': _t('mFourth')},
      'mobile': _t('mobile'),
      'national_id': {
        'id_number': _t('idNumber'),
        'family_number': _t('familyNumber'),
        'place_of_issue': _t('idPlace'),
        'issued_at': _ymd(_idIssued!),
        'birthday': _ymd(_birthday!),
      },
      'residence': {'card_number': _t('resNumber'), 'place_of_issue': _t('resPlace'), 'issued_at': _ymd(_resIssued!)},
      'site': {
        'lat': _gps!.lat,
        'lng': _gps!.lng,
        'address': _t('address'),
        'house': _t('house'),
        'neighbourhood': _t('neighbourhood'),
        'street': _t('street'),
        'apartment': _t('apartment'),
        'zone_id': _zone,
      },
      'plan_name': _plan,
      'install_option_id': _option ?? '',
      'files': {for (final k in _photos.keys) k: _photos[k]!.id},
    }, confirmRepeat: confirmRepeat);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r.state) {
      case OnboardState.applied:
        setState(() => _done = (rid: r.requestId, to: r.sentTo));
        showSheetSnack(context, 'أُرسل الطلب — أدخل الرمز الذي وصل للمشترك');
      case OnboardState.unconfirmed:
        showSheetSnack(context, r.message ?? 'لم يتأكّد إرسال الطلب — تحقّق من «الطلبات»', isError: true, duration: const Duration(seconds: 12), autoExplain: false);
        Navigator.of(context).pop(true);
      case OnboardState.repeated:
        final go = await showConfirmSheet(
          context,
          title: 'طلبٌ آخر لصاحب البطاقة نفسها؟',
          message: r.message ?? 'أُرسل طلبٌ لصاحب هذه البطاقة قبل قليل',
          confirmLabel: 'أرسله',
          cancelLabel: 'تراجع',
          icon: LucideIcons.copy,
          tone: AppTone.warning,
        );
        if (go == true && mounted) await _submit(confirmRepeat: true);
      case OnboardState.failed:
        setState(() => _serverErr = r.message);
        showSheetSnack(context, r.message ?? 'تعذّر إرسال الطلب', isError: true, autoExplain: false);
    }
  }

  Future<void> _checkOtp() async {
    final rid = _done?.rid;
    if (rid == null) return;
    setState(() => _otpBusy = true);
    final r = await NationalOnboardApi.otp(rid, mobile: _t('mobile'), code: onboardLatin(_t('otp')));
    if (!mounted) return;
    setState(() {
      _otpBusy = false;
      _otpRes = (valid: r.valid, text: r.valid == true ? 'الرمز صحيح — تأكّد هاتف المشترك والطلب بانتظار الشركة' : (r.message ?? 'الرمز غير صحيح'));
    });
  }

  /* ───────── العرض ───────── */

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: AppType.label(color: AppColors.textLabel)));

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: AppType.cardTitle(color: AppColors.textHi)),
          const SizedBox(height: Sp.sm),
          ...children,
        ]),
      );

  Widget _text(String k, String label, Map<String, String> e, {bool ltr = false, TextInputType? kb, String? hint, Widget? suffix, String? liveErr}) {
    final err = liveErr ?? _show(e, k);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label(label),
        SheetBox(
          padding: suffix == null ? const EdgeInsets.symmetric(horizontal: 15, vertical: 13) : const EdgeInsets.fromLTRB(4, 2, 15, 2),
          borderColor: err != null ? AppColors.error : null,
          child: Row(children: [
            Expanded(
              child: Semantics(
                label: label,
                child: TextField(
                  controller: _c[k],
                  enabled: !_busy,
                  keyboardType: kb,
                  textDirection: ltr ? TextDirection.ltr : null,
                  textAlign: ltr ? TextAlign.left : TextAlign.start,
                  onChanged: (_) => setState(() {}),
                  style: AppType.input(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint,
                    hintTextDirection: ltr ? TextDirection.ltr : null,
                    hintStyle: AppType.input(color: AppColors.textPlaceholder),
                  ),
                ),
              ),
            ),
            if (suffix != null) suffix,
          ]),
        ),
        if (err != null) ...[const SizedBox(height: 4), Text(err, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.error))],
      ]),
    );
  }

  /// تاريخٌ يُكتب كما على البطاقة (2018-03-21 أو 21/3/2018) أو يُختار من التقويم.
  Widget _date(String k, String label, Map<String, String> e, {String? live}) {
    return _text(
      k,
      label,
      e,
      liveErr: live,
      ltr: true,
      kb: TextInputType.datetime,
      hint: 'YYYY-MM-DD',
      suffix: IconButton(
        tooltip: 'من التقويم',
        visualDensity: VisualDensity.compact,
        icon: Icon(LucideIcons.calendar, size: 18, color: AppColors.textMid),
        onPressed: _busy
            ? null
            : () async {
                final cur = parseOnboardDate(_c[k]!.text);
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: cur ?? DateTime(now.year - (k == 'birthday' ? 30 : 5), 1, 1),
                  firstDate: DateTime(1920),
                  lastDate: now,
                );
                if (d != null && mounted) setState(() => _c[k]!.text = _ymd(d));
              },
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: Sp.sm),
        Expanded(child: b),
      ]);

  Widget _photo(String kind, String label, Map<String, String> e) {
    final p = _photos[kind]!;
    final err = p.error ?? _show(e, kind);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: _busy || p.state == _Up.busy ? null : () => _pick(kind, camera: true),
            borderRadius: BorderRadius.circular(R.md),
            child: Container(
              height: 92,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: err != null ? AppColors.error : (p.state == _Up.done ? AppColors.success : AppColors.border)),
              ),
              child: Stack(fit: StackFit.expand, children: [
                if (p.preview != null)
                  Opacity(
                    opacity: 0.75,
                    // معاينةٌ صغيرة (لا تُفكّ الصورة كاملة)، وصورةٌ تالفة تُبقي الأيقونة بلا خطأ
                    child: Image.memory(p.preview!, fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.sm)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (p.state == _Up.busy)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(p.state == _Up.done ? LucideIcons.check : LucideIcons.camera, size: 15, color: p.state == _Up.done ? AppColors.success : AppColors.textMid),
                      const SizedBox(width: Sp.xs),
                      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textHi))),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
        TextButton(
          onPressed: _busy || p.state == _Up.busy ? null : () => _pick(kind, camera: false),
          child: Text('من الصور', style: AppType.micro(color: AppColors.brand)),
        ),
        if (err != null) Text(err, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.error)),
      ]),
    );
  }

  Widget _pickRow(String label, List<NationalNetRef> items, String? selected, ValueChanged<String> onPick, String? err, String title) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _label(label),
          NationalPickField(
            title: title,
            items: items,
            selectedId: selected,
            enabled: !_busy,
            placeholder: title,
            error: err,
            ltr: false,
            onPicked: (r) => setState(() => onPick(r.id)),
          ),
        ]),
      );

  Widget _signature(Map<String, String> e) {
    final p = _photos['signature']!;
    final err = p.error ?? _show(e, 'signature');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RepaintBoundary(
        key: _sigKey,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: AppColors.onBrand,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: err != null ? AppColors.error : AppColors.border),
          ),
          child: Semantics(
            label: 'توقيع المشترك',
            child: GestureDetector(
              key: const ValueKey('onboard-signature-pad'),
              onPanStart: _busy
                  ? null
                  : (d) => setState(() {
                        _strokes.add([d.localPosition]);
                        _signed = true;
                      }),
              onPanUpdate: _busy ? null : (d) => setState(() => _strokes.last.add(d.localPosition)),
              onPanEnd: _busy ? null : (_) => _saveSignature(),
              child: CustomPaint(painter: _SignaturePainter(_strokes, AppColors.brandSurface), size: Size.infinite),
            ),
          ),
        ),
      ),
      Row(children: [
        TextButton.icon(
          onPressed: _busy ? null : _clearSignature,
          icon: const Icon(LucideIcons.eraser, size: 15),
          label: const Text('مسح التوقيع'),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text(
            p.state == _Up.busy ? 'يُرفع التوقيع…' : p.state == _Up.done ? 'حُفظ التوقيع ✓' : (err ?? 'يوقّع المشترك داخل المربّع بعد قراءة العقد'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.micro(color: err != null ? AppColors.error : AppColors.textMid),
          ),
        ),
      ]),
    ]);
  }

  Widget _form(OnboardMeta m) {
    final e = _errors();
    final exp = onboardCardExpiry(_idIssued, m.cardYears);
    final plan = m.plans.where((p) => p.name == _plan).firstOrNull;
    const digits = TextInputType.datetime; // أرقامٌ و«/» و«-» على الهاتفين
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('المشترك', [
        _pair(_text('first', 'الاسم', e), _text('second', 'اسم الأب', e)),
        _pair(_text('third', 'اسم الجدّ', e), _text('fourth', 'الرابع (اختياريّ)', e)),
        _pair(_text('family', 'اللقب', e), _text('mobile', 'الهاتف (يصله الرمز)', e, ltr: true, kb: TextInputType.phone, hint: '07XXXXXXXXX')),
        _pair(_text('mFirst', 'اسم الأمّ', e), _text('mSecond', 'اسم أبيها', e)),
        _pair(_text('mThird', 'اسم جدّها', e), _text('mFourth', 'الرابع (اختياريّ)', e)),
      ]),
      _section('البطاقة الموحّدة', [
        _text('idNumber', 'رقم البطاقة (١٢ رقماً)', e, ltr: true, kb: TextInputType.number),
        _pair(_text('familyNumber', 'الرقم العائليّ', e, ltr: true), _text('idPlace', 'جهة الإصدار', e)),
        _pair(
          _date('idIssued', 'تاريخ الإصدار', e, live: (exp?.expired ?? false) ? e['idIssued'] : null),
          _date('birthday', 'تاريخ الميلاد', e),
        ),
        if (exp != null && !exp.expired && exp.days <= m.warnDays)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Text('تنتهي صلاحية البطاقة خلال ${exp.days} يوماً (${exp.on})', style: AppType.micro(color: AppColors.warning)),
          ),
        OutlinedButton.icon(
          onPressed: _idChecking || _busy || ['idNumber', 'familyNumber', 'idPlace', 'idIssued', 'birthday'].any(e.containsKey) ? null : _checkId,
          icon: _idChecking ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(LucideIcons.shieldCheck, size: 16),
          label: const Text('فحص البطاقة'),
        ),
        if (_idCheck != null)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Text(_idCheck!.text ?? '', style: AppType.micro(color: _idCheck!.valid == true ? AppColors.success : AppColors.error)),
          ),
        const SizedBox(height: Sp.md),
        Row(children: [_photo('id_front', 'وجه البطاقة', e), const SizedBox(width: Sp.sm), _photo('id_back', 'ظهر البطاقة', e)]),
      ]),
      _section('بطاقة السكن', [
        _pair(_text('resNumber', 'رقم بطاقة السكن', e, ltr: true, kb: TextInputType.number), _text('resPlace', 'جهة الإصدار', e)),
        _date('resIssued', 'تاريخ الإصدار', e),
        Row(children: [_photo('res_front', 'وجه بطاقة السكن', e), const SizedBox(width: Sp.sm), _photo('res_back', 'ظهر بطاقة السكن', e)]),
      ]),
      _section('العنوان والموقع', [
        _pickRow('الزون', [for (final z in m.zones) NationalNetRef(z.id, z.name)], _zone, (v) => _zone = v, _show(e, 'zone'), 'اختر الزون'),
        _text('address', 'أقرب نقطة دالّة', e),
        _pair(_text('neighbourhood', 'المحلّة', e, kb: digits), _text('street', 'الزقاق', e, kb: digits)),
        _pair(_text('house', 'الدار', e, kb: digits), _text('apartment', 'الشقّة (اختياريّ)', e, kb: digits)),
        _label('الموقع'),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final ({double lat, double lng})? p;
                  if (widget.locate != null) {
                    p = await widget.locate!(context);
                  } else {
                    final g = await showLocationPickerScreen(context);
                    p = g == null ? null : (lat: g.latitude, lng: g.longitude);
                  }
                  if (p != null && mounted) setState(() => _gps = p);
                },
          icon: Icon(_gps == null ? LucideIcons.mapPin : LucideIcons.mapPinCheck, size: 16),
          label: Text(_gps == null ? 'حدّد على الخريطة' : '${_gps!.lat.toStringAsFixed(6)}, ${_gps!.lng.toStringAsFixed(6)}', textDirection: TextDirection.ltr),
        ),
        if (_show(e, 'gps') != null) Text(_show(e, 'gps')!, style: AppType.micro(color: AppColors.error)),
      ]),
      _section('الباقة والتركيب', [
        _pickRow('الباقة', [for (final p in m.plans) NationalNetRef(p.name, p.price == null ? p.title : '${p.title} — ${formatIQD(p.price!)}')], _plan,
            (v) => _plan = v, _show(e, 'plan'), 'اختر الباقة'),
        if (plan?.speed != null) Text('السرعة: ${plan!.speed}', style: AppType.micro(color: AppColors.textMid)),
        if (m.options.length > 1)
          _pickRow('خيار التركيب', [for (final o in m.options) NationalNetRef(o.id, o.name)], _option, (v) => _option = v, _show(e, 'option'), 'اختر')
        else if (m.options.isNotEmpty)
          Text('التركيب: ${m.options.first.name}${(m.options.first.price ?? 0) > 0 ? ' — ${formatIQD(m.options.first.price!)}' : ' — مجّاناً'}',
              style: AppType.muted(color: AppColors.textMid))
        else if (_show(e, 'option') != null)
          Text('لم تُرجع البوّابة خيار التركيب — أعد فتح الصفحة', style: AppType.micro(color: AppColors.error)),
      ]),
      _section('العقد وتوقيع المشترك', [
        if (m.contract != null)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
            child: SingleChildScrollView(child: Text(m.contract!, style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.6))),
          ),
        const SizedBox(height: Sp.sm),
        _signature(e),
      ]),
      if (_serverErr != null) Padding(padding: const EdgeInsets.only(bottom: Sp.md), child: Text(_serverErr!, style: AppType.muted(color: AppColors.error))),
      if (_tried && e.isNotEmpty) Text('أكمل الحقول المؤشَّرة بالأحمر (${e.length})', textAlign: TextAlign.center, style: AppType.micro(color: AppColors.error)),
    ]);
  }

  Widget _doneView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(color: AppColors.successSoftBg, borderRadius: BorderRadius.circular(R.md)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text('أُرسل الطلب لبوّابة المشروع الوطني ويظهر في «الطلبات». وصل رمزٌ لهاتف المشترك ${_done?.to ?? ''}.',
                  style: AppType.body(color: AppColors.success)),
            ),
          ]),
        ),
        const SizedBox(height: Sp.lg),
        if (_done?.rid != null) ...[
          _label('رمز التأكيد من هاتف المشترك'),
          SheetBox(
            child: Semantics(
              label: 'رمز التأكيد',
              child: TextField(
                controller: _c['otp'],
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]'))],
                onChanged: (_) => setState(() {}),
                style: AppType.input().copyWith(letterSpacing: 4),
                decoration: const InputDecoration(isDense: true, counterText: '', border: InputBorder.none, contentPadding: EdgeInsets.zero),
              ),
            ),
          ),
          const SizedBox(height: Sp.sm),
          FilledButton.icon(
            onPressed: _otpBusy || !RegExp(r'^\d{4,8}$').hasMatch(onboardLatin(_t('otp'))) ? null : _checkOtp,
            icon: _otpBusy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(LucideIcons.shieldCheck, size: 16),
            label: const Text('تأكيد الرمز'),
          ),
          if (_otpRes != null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text(_otpRes!.text ?? '', style: AppType.muted(color: _otpRes!.valid == true ? AppColors.success : AppColors.error)),
            ),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final m = _meta;
    late final Widget body;
    if (_lock != null) {
      body = NationalPortalLockBox(title: _lock!.title, text: _lock!.message);
    } else if (_err != null && m == null) {
      body = NationalStateBox.error(text: _err!, onRetry: () {
        setState(() => _err = null);
        _polls = 0;
        _load();
      });
    } else if (m == null) {
      body = const NationalStateBox.pending(text: 'جارٍ قراءة الزونات والباقات من البوّابة…');
    } else {
      body = _done != null ? _doneView() : _form(m);
    }
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text('إضافة مشترك', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
            iconTheme: IconThemeData(color: AppColors.textHi),
            leading: IconButton(
              tooltip: 'رجوع',
              icon: const Icon(LucideIcons.arrowRight),
              onPressed: _busy ? null : () => Navigator.of(context).pop(_done != null),
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge), children: [
            if (_done == null && m != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.md),
                child: Text('طلب «تسجيل زبون جديد» في بوّابة المشروع الوطني — الصور تُرسل للبوّابة وحدها ولا تُحفظ عندنا',
                    style: AppType.micro(color: AppColors.textMid)),
              ),
            body,
          ]),
        ),
        bottomNavigationBar: _done != null || m == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
                  child: FilledButton.icon(
                    onPressed: _busy || _photos.values.any((p) => p.state == _Up.busy) ? null : () => _submit(),
                    icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(LucideIcons.userPlus, size: 18),
                    label: const Text('إرسال الطلب'),
                  ),
                ),
              ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, this.color);
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.2, p..style = PaintingStyle.fill);
        p.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
