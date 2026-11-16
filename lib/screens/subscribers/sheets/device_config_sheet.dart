import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
import '../../../core/util/ip_input.dart';
import '../../../api/device_probe_api.dart';
import '../../../models/device_health.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// Per-subscriber CPE override editor — opened from the gear button
/// on the DeviceProbeCard. Lets the admin pin device type, custom
/// credentials, custom IP, and a free-form note. All fields optional;
/// empties fall through to admin defaults + library defaults.
class DeviceConfigSheet extends StatefulWidget {
  const DeviceConfigSheet({super.key, required this.username, this.sessionIp = ''});
  final String username;

  /// آيبي جلسة المشترك الآن — لإبطال فحص «الجهاز الثاني» المكتوب «:منفذ» بعد الحفظ.
  final String sessionIp;

  @override
  State<DeviceConfigSheet> createState() => _DeviceConfigSheetState();
}

class _DeviceConfigSheetState extends State<DeviceConfigSheet> {
  DeviceKind? _kind;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _ip = TextEditingController();
  final _port = TextEditingController();
  final _notes = TextEditingController();
  // «الجهاز الثاني» (نانو + راوتر، ١٢ نوفمبر)
  final _ip2 = TextEditingController();
  final _port2 = TextEditingController();
  final _user2 = TextEditingController();
  final _pass2 = TextEditingController();
  bool _obscure2 = true;
  String? _originalSecond;
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  String? _originalIp;

  /// تعذّرت قراءة الإعداد المحفوظ (شبكة، رفض) — الورقة تقول ذلك وتعيد المحاولة، ولا حفظ ولا حذف فوق ما لم يُقرأ: حقولٌ فارغة
  /// سببها التعذّر كانت تُحفظ فتمسح المحفوظ.
  bool _loadFailed = false;

  /// كُتب يوزر/كلمة سرّ «الجهاز الثاني» بلا آيبي ولا منفذ وضُغط الحفظ — سطرٌ تحت عنوانه يقول ما ينقص (يزول حين يُكتب أو يُمسح).
  bool _secondNeedsAddress = false;

  /// اعتماد «الجهاز الثاني» بلا عنوانٍ له: كان يُهمل بصمت والورقة تُغلق كأنّها حفظت (المالك ١٥ نوفمبر: «من اخزن الاعتماد يدوي
  /// مجرد اخرج وادخل يروح الحفظ») — الآن لا حفظ حتى يُكتب عنوانه، والرسالة تدلّ على مكان اعتماد جهاز المشترك نفسه.
  static const secondNeedsAddressText =
      'الجهاز الثاني يحتاج عنوان IP أو منفذاً حتى يُحفظ يوزره وكلمة مروره. إن قصدت جهاز المشترك نفسه فاكتبهما فوق في «بيانات الدخول للجهاز».';

  @override
  void initState() {
    super.initState();
    for (final c in [_ip2, _port2, _user2, _pass2]) {
      c.addListener(_onSecondEdited);
    }
    _load();
  }

  void _onSecondEdited() {
    if (_secondNeedsAddress && !_secondOrphan) setState(() => _secondNeedsAddress = false);
  }

  /// يوزر أو كلمة سرّ للجهاز الثاني مكتوبان وعنوانه (الآيبي والمنفذ) فارغ.
  bool get _secondOrphan =>
      _ip2.text.trim().isEmpty && _port2.text.trim().isEmpty && (_user2.text.trim().isNotEmpty || _pass2.text.isNotEmpty);

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _ip.dispose();
    _port.dispose();
    _notes.dispose();
    _ip2.dispose();
    _port2.dispose();
    _user2.dispose();
    _pass2.dispose();
    super.dispose();
  }

  /// المحفوظ الآن من الخادم (لا من كاش الدقائق الخمس — جهازٌ آخر قد حفظ بعده). تعذّرت القراءة ⇒ [_loadFailed] لا حقولٌ فارغة.
  Future<void> _load() async {
    final cfg = await DeviceConfigApi.fetchFresh(widget.username);
    if (!mounted) return;
    if (cfg == null) {
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    setState(() {
      _kind = cfg.deviceType;
      _user.text = cfg.username ?? '';
      _pass.text = cfg.password ?? '';
      final a1 = splitAddress(cfg.customIp);
      _ip.text = a1.ip;
      _port.text = a1.port;
      _notes.text = cfg.notes ?? '';
      _originalIp = cfg.customIp;
      final a2 = splitAddress(cfg.secondAddress);
      _ip2.text = a2.ip;
      _port2.text = a2.port;
      _user2.text = cfg.secondUsername ?? '';
      _pass2.text = cfg.secondPassword ?? '';
      _originalSecond = cfg.secondAddress;
      _loading = false;
      _loadFailed = false;
    });
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    _load();
  }

  Future<void> _save() async {
    final main = joinAddress(_ip.text, _port.text);
    if (main.error != null) {
      showSheetSnack(context, 'IP المخصّص: ${main.error}', isError: true);
      return;
    }
    final second = joinAddress(_ip2.text, _port2.text);
    if (second.error != null) {
      showSheetSnack(context, 'الجهاز الثاني: ${second.error}', isError: true);
      return;
    }
    // يوزر/كلمة سرّ للجهاز الثاني بلا عنوان: لا يُحفظان (لا جهاز ثانٍ بلا عنوان) — فلا تُغلق الورقة كأنّها حفظتهما.
    if (_secondOrphan) {
      setState(() => _secondNeedsAddress = true);
      showSheetSnack(context, secondNeedsAddressText, isError: true);
      return;
    }
    setState(() => _saving = true);
    final cfg = DeviceConfig(
      deviceType: _kind,
      username: _user.text.trim().isEmpty ? null : _user.text.trim(),
      password: _pass.text.isEmpty ? null : _pass.text,
      customIp: main.value,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      secondAddress: second.value,
      secondUsername: second.value == null || _user2.text.trim().isEmpty ? null : _user2.text.trim(),
      secondPassword: second.value == null || _pass2.text.isEmpty ? null : _pass2.text,
    );
    final ok = await DeviceConfigApi.saveConfig(widget.username, cfg);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      showSheetSnack(context, 'تعذّر الحفظ', isError: true);
      return;
    }
    // Invalidate any cached probe under the old IP AND the new IP so the
    // detail card re-probes against the freshly-pinned credentials.
    if (_originalIp != null && _originalIp!.isNotEmpty) {
      DeviceProbeApi.invalidateIp(_originalIp!);
    }
    if (cfg.customIp != null && cfg.customIp!.isNotEmpty) {
      DeviceProbeApi.invalidateIp(DeviceProbeApi.addressOf(widget.sessionIp, cfg.customIp));
    }
    // الجهاز الثاني: نتيجته القديمة لا تُعرض لجهازٍ آخر، وعنوانه القديم والجديد (بعد حلّ «:منفذ» على آيبي الجلسة) — اعتمادٌ جديد
    // يُجرَّب ولو رُفض قبله.
    if (_originalSecond != cfg.secondAddress) DeviceProbeApi.forgetUser(widget.username, slot: 2);
    for (final a in {_originalSecond, cfg.secondAddress}) {
      final eff = a == null || a.isEmpty ? '' : DeviceProbeApi.addressOf(widget.sessionIp, a);
      if (eff.isNotEmpty) DeviceProbeApi.invalidateIp(eff);
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    final ok = await DeviceConfigApi.resetConfig(widget.username);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      showSheetSnack(context, 'تعذّر الحذف', isError: true);
      return;
    }
    if (_originalIp != null && _originalIp!.isNotEmpty) {
      DeviceProbeApi.invalidateIp(_originalIp!);
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // ترتيب المخطّط: نوع الجهاز (شريط مقسّم) → بيانات الدخول (مجموعة
    // صفوف في حاوية واحدة) → IP مخصّص → ملاحظات، وزرّ حذف 50×50 يسبق
    // زرّ الحفظ في الشريط السفلي.
    const kinds = [null, DeviceKind.ont, DeviceKind.ubiquiti];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.router,
        title: 'إعدادات جهاز المشترك',
        subtitle: widget.username,
        subtitleLtr: true,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving ? 'جارٍ الحفظ...' : 'حفظ وفحص الجهاز',
        icon: LucideIcons.save,
        busy: _saving,
        enabled: !_loading && !_loadFailed,
        onPressed: _save,
        leading: SheetFooterIconButton(
          icon: LucideIcons.trash2,
          color: AppColors.error,
          onTap: _saving || _loading || _loadFailed ? null : _reset,
        ),
      ),
      body: _loadFailed
          ? _loadFailedBody()
          : _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.mega),
              child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.brandAccent, strokeWidth: 2.5),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetSection(
                  label: 'نوع الجهاز',
                  hint: 'تلقائي يتعرّف وحده: Ubiquiti · TP-Link · ONT',
                  gap: Sp.sm,
                  child: SheetSegmented(
                    labels: const ['تلقائي', 'ONT', 'Ubiquiti'],
                    selectedIndex: kinds.indexOf(_kind),
                    onSelect: (i) => setState(() => _kind = kinds[i]),
                  ),
                ),
                const SizedBox(height: Sp.lg),
                // المخطّط يجمع اليوزر والباس في **حاوية واحدة** بصفّين
                // يفصلهما خطّ شعري — لا حقلين منفصلين بتسميتين.
                SheetSection(
                  label: 'بيانات الدخول للجهاز',
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(R.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        _credRow(
                          icon: LucideIcons.user,
                          label: 'اسم المستخدم',
                          controller: _user,
                          hint: credHint,
                        ),
                        Divider(height: 1, color: AppColors.divider),
                        _credRow(
                          icon: LucideIcons.lock,
                          label: 'كلمة المرور',
                          controller: _pass,
                          hint: credHint,
                          obscure: _obscure,
                          trailing: InkWell(
                            onTap: () => setState(() => _obscure = !_obscure),
                            borderRadius: BorderRadius.circular(R.pill),
                            child: Icon(
                              _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                              size: 18,
                              color: AppColors.brandAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Sp.lg),
                SheetSection(
                  label: 'IP مخصص (اختياري)',
                  footnote: 'مفيد للأجهزة خلف NAT · المنفذ للإدارة عن بعد على منفذٍ غير 80 (مثل 8080)',
                  child: _addressRow(_ip, _port, hint: 'يستخدم IP الساس إذا فارغ'),
                ),
                const SizedBox(height: Sp.lg),
                // «الجهاز الثاني» (١٢ نوفمبر — المالك: «المشترك اكو عدهم نانو وراوتر… لازم نضيف فحصين»)
                SheetSection(
                  label: 'الجهاز الثاني — نانو + راوتر (اختياري)',
                  // بلا «⇒»: لا محرف له في خطّ التطبيق (مربّعٌ فارغ في لقطات الاختبار) — نقطتان بدله.
                  footnote: 'الاتّصال على النانو والراوتر خلفه: اكتب المنفذ المحوّل للراوتر (تحويل المنافذ في النانو) وحده · '
                      'الاتّصال على الراوتر: اكتب عنوان IP الثابت للنانو',
                  gap: Sp.sm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _addressRow(_ip2, _port2, hint: 'عنوان IP للمشترك إذا كان فارغاً'),
                      if (_secondNeedsAddress) ...[
                        const SizedBox(height: 6),
                        Text(
                          'اكتب عنوان IP للجهاز الثاني أو منفذه — بلا عنوانٍ لا يُحفظ يوزره وكلمة مروره.',
                          key: const ValueKey('second-needs-address'),
                          style: AppType.micro(color: AppColors.error),
                        ),
                      ],
                      const SizedBox(height: Sp.sm),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(R.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            _credRow(
                              icon: LucideIcons.user,
                              label: 'اسم المستخدم',
                              controller: _user2,
                              hint: credHint,
                            ),
                            Divider(height: 1, color: AppColors.divider),
                            _credRow(
                              icon: LucideIcons.lock,
                              label: 'كلمة المرور',
                              controller: _pass2,
                              hint: credHint,
                              obscure: _obscure2,
                              trailing: InkWell(
                                onTap: () => setState(() => _obscure2 = !_obscure2),
                                borderRadius: BorderRadius.circular(R.pill),
                                child: Icon(
                                  _obscure2 ? LucideIcons.eye : LucideIcons.eyeOff,
                                  size: 18,
                                  color: AppColors.brandAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Sp.lg),
                SheetSection(
                  label: 'ملاحظات',
                  child: SheetBox(
                    icon: LucideIcons.fileText,
                    alignTop: true,
                    child: TextField(
                      controller: _notes,
                      minLines: 2,
                      maxLines: 4,
                      style: AppType.body(color: AppColors.textHi),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'مثال: VLAN 102، تقسيم فايبر للطابق الثاني',
                        hintStyle:
                            AppType.body(color: AppColors.textPlaceholder),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// تلميح حقول اليوزر وكلمة السرّ الفارغة — للجهازين. (كان الأوّل يعرض افتراض المصنّع «telecomadmin / admintelecom» رماديّاً
  /// فيبدو كأنّه محفوظ، والاعتماد يُكتب في خانتَي الجهاز الثاني بدله.)
  static const credHint = 'من «بيانات الدخول» إذا فارغ';

  static const loadFailedText = 'تعذّر تحميل إعداد الجهاز الآن';
  static const noPermissionText = 'لا صلاحيّة لإعداد أجهزة المشتركين';

  /// تعذّرت قراءة الإعداد: السبب وزرّ إعادة المحاولة — لا حقول تُملأ ولا حفظ. موظّفٌ بلا صلاحيّة الأجهزة (الخادم يرفضه)
  /// يقرأ «لا صلاحيّة» لا «أعد المحاولة».
  Widget _loadFailedBody() {
    final denied = DeviceConfigApi.lacksPermission;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(denied ? LucideIcons.lock : LucideIcons.wifiOff, size: 28, color: AppColors.textHint),
            const SizedBox(height: Sp.sm),
            Text(
              denied ? noPermissionText : loadFailedText,
              key: const ValueKey('device-config-load-failed'),
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textHi),
            ),
            const SizedBox(height: 4),
            Text(
              denied ? 'اطلبها من مديرك (صلاحيّات «الأجهزة»).' : 'لا شيء تغيّر في المحفوظ — أعد المحاولة.',
              textAlign: TextAlign.center,
              style: AppType.muted(),
            ),
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(
              key: const ValueKey('device-config-retry'),
              onPressed: _retryLoad,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
  }

  /// عنوان: آيبي (لوحة أرقامٍ بنقطة) + منفذٌ بحقلٍ مستقلّ (لوحة الأرقام على الآيفون بلا «:»).
  Widget _addressRow(TextEditingController ip, TextEditingController port, {required String hint}) {
    return Row(
      textDirection: ui.TextDirection.ltr,
      children: [
        Expanded(
          child: SheetBox(
            icon: LucideIcons.network,
            child: TextField(
              controller: ip,
              keyboardType: ipKeyboard,
              inputFormatters: const [IpInputFormatter()],
              textDirection: ui.TextDirection.ltr,
              style: AppType.input(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x6),
          child: Text(':', style: AppType.input(color: AppColors.textHint)),
        ),
        SizedBox(
          width: 96,
          child: SheetBox(
            child: TextField(
              controller: port,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              textDirection: ui.TextDirection.ltr,
              textAlign: TextAlign.center,
              style: AppType.input(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'منفذ',
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// صفّ داخل حاوية بيانات الدخول — أيقونة + تسمية خافتة + الحقل
  /// محاذىً لليسار بالـltr كما في المخطّط.
  Widget _credRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textHint),
          const SizedBox(width: 10),
          Text(label, style: AppType.muted()),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              textAlign: TextAlign.left,
              textDirection: ui.TextDirection.ltr,
              style: AppType.input(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing],
        ],
      ),
    );
  }
}

/// «IP» أو «IP:منفذ» أو «:منفذ» ⇒ حقلا الشاشة.
({String ip, String port}) splitAddress(String? raw) {
  final r = (raw ?? '').trim();
  final i = r.lastIndexOf(':');
  if (i < 0) return (ip: r, port: '');
  return (ip: r.substring(0, i), port: r.substring(i + 1));
}

/// حقلا الشاشة ⇒ العنوان المحفوظ (null = فارغ) أو سبب الرفض.
({String? value, String? error}) joinAddress(String ipText, String portText) {
  final ip = IpInputFormatter.normalize(ipText.trim());
  final port = portText.trim();
  if (ip.isEmpty && port.isEmpty) return (value: null, error: null);
  if (ip.isNotEmpty) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts.any((p) => p.isEmpty || int.parse(p) > 255)) {
      return (value: null, error: 'عنوان IP غير صحيح (مثل 10.0.0.5)');
    }
  }
  if (port.isNotEmpty) {
    final n = int.tryParse(port);
    if (n == null || n < 1 || n > 65535) return (value: null, error: 'المنفذ بين 1 و65535');
  }
  final cleanIp = ip.isEmpty ? '' : ip.split('.').map((p) => int.parse(p).toString()).join('.');
  if (port.isEmpty) return (value: cleanIp, error: null);
  return (value: '$cleanIp:$port', error: null);
}
