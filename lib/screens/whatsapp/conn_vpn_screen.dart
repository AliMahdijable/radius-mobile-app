import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/conn_vpn_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «ربط VPN» بالتطبيق (٣ نوفمبر — كالويب /v2/connection-alerts): نفق الشركة أو الربط التلقائيّ أو ملفّ الوكيل، و«فحص الاتصال»،
/// و«الاتصال العكسي عند الخروج من الشبكة». الأسرار تُرسل للخادم مرّةً وتُحفظ مشفّرة هناك — لا تبقى في التطبيق.
class ConnVpnScreen extends StatefulWidget {
  const ConnVpnScreen({super.key});

  @override
  State<ConnVpnScreen> createState() => _ConnVpnScreenState();
}

class _ConnVpnScreenState extends State<ConnVpnScreen> {
  ConnVpnStatus? _st;
  bool _loading = true;
  String? _busy; // analyze | save | delete | test | reverse
  ConnVpnTest? _test;
  String? _ovpn;
  String _fileName = '';
  ConnVpnAnalysis? _analysis;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _keyPass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _keyPass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final st = await ConnVpnApi.status();
    if (!mounted) return;
    setState(() {
      _st = st;
      _loading = false;
    });
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pick() async {
    // الهاتف: أيّ ملفّ (امتداد .ovpn لا نوع MIME ثابتاً له)؛ الحاسبة: ملفّات OpenVPN
    final desktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final f = await openFile(acceptedTypeGroups: [
      if (desktop) const XTypeGroup(label: 'OpenVPN', extensions: ['ovpn', 'conf', 'txt']),
    ]);
    if (f == null) return;
    if (await f.length() > ConnVpnApi.maxFileBytes) {
      _say('الملفّ أكبر من المعقول');
      return;
    }
    final String text;
    try {
      text = await f.readAsString();
    } catch (_) {
      _say('تعذّرت قراءة الملفّ — اختر ملفّ ‎.ovpn');
      return;
    }
    setState(() {
      _busy = 'analyze';
      _ovpn = text;
      _fileName = f.name;
      _analysis = null;
    });
    final r = await ConnVpnApi.analyze(text);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _analysis = r.analysis;
      if (r.analysis == null) _ovpn = null;
    });
    if (r.analysis == null) _say(r.message ?? 'تعذّر فحص الملفّ');
  }

  bool get _canSave {
    final a = _analysis;
    if (a == null || !a.ok || _busy != null) return false;
    if (a.needsAuth && (_user.text.trim().isEmpty || _pass.text.isEmpty)) return false;
    if (a.needsKeyPassword && _keyPass.text.isEmpty) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _busy = 'save');
    final r = await ConnVpnApi.save(
      ovpn: _ovpn!,
      username: _user.text.trim(),
      password: _pass.text,
      keyPassword: _keyPass.text,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    _say(r.message ?? (r.ok ? 'حُفظ الملفّ مشفّراً' : 'تعذّر الحفظ'));
    if (r.ok) {
      _cancel();
      await _load();
    }
  }

  void _cancel() {
    setState(() {
      _ovpn = null;
      _analysis = null;
      _fileName = '';
    });
    _pass.clear();
    _keyPass.clear();
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف ملفّ الـVPN؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = 'delete');
    final r = await ConnVpnApi.remove();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _test = null;
    });
    if (!r.ok) _say(r.message ?? 'تعذّر الحذف');
    await _load();
  }

  Future<void> _runTest() async {
    setState(() {
      _busy = 'test';
      _test = null;
    });
    final r = await ConnVpnApi.test();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _test = r.result;
    });
    if (r.result == null) _say(r.message ?? 'تعذّر الفحص');
    await _load();
  }

  Future<void> _reverse(bool on) async {
    setState(() => _busy = 'reverse');
    final r = await ConnVpnApi.reverse(on);
    if (!mounted) return;
    setState(() => _busy = null);
    _say(r.message ?? (r.ok ? 'تم' : 'تعذّر الحفظ'));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.textHi),
        title: Text('ربط VPN', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _st == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Sp.xl),
                    child: Text('«ربط VPN» غير متاحٍ لحسابك بعد — لصاحب الحساب حين يُفتح له «تنبيه المشترك».',
                        textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                    children: _body(_st!),
                  ),
                ),
    );
  }

  List<Widget> _body(ConnVpnStatus st) {
    final shown = _test ?? st.lastTest;
    return [
      Text(
        'حين لا يكون تطبيقك على شبكتك (خارج المكتب، أو الحاسبة مطفأة) يقيس النظام أجهزة مشتركيك عبر نفق VPN — '
        'كلّ نصف ساعة نهاراً وكلّ ساعة ليلاً.',
        style: AppType.muted(color: AppColors.textMid),
      ),
      const SizedBox(height: Sp.md),
      if (st.covered)
        _note(
          text: 'شركتك (${st.companyLabel}) مربوطة عبر نفق النظام — لا تحتاج ملفّاً. ${st.companyHealthy ? 'النفق قائم' : 'النفق يعيد الاتّصال'}',
        )
      else ...[
        if (st.autoLinked && _analysis == null) ...[
          _note(
            text: 'تُربط تلقائيّاً عبر ${st.autoLabel} بحسابك ${iso(st.autoUser ?? '')} — جرّب «فحص الاتصال».',
            hint: 'يوزرك هناك مختلف؟ ارفع ملفّك بيوزرك وباسوردك.',
          ),
          const SizedBox(height: Sp.sm),
        ],
        if (st.profileSaved && _analysis == null)
          _box(
            child: Row(children: [
              Icon(LucideIcons.fileLock, size: 18, color: AppColors.brand),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text('ملفّك محفوظ مشفّراً${st.profileHasAuth ? ' مع اليوزر والباسورد' : ''}',
                    style: AppType.body(color: AppColors.textHi)),
              ),
              TextButton.icon(
                onPressed: _busy == null ? _pick : null,
                icon: const Icon(LucideIcons.upload, size: 16),
                label: const Text('استبدال'),
              ),
              IconButton(
                tooltip: 'حذف',
                onPressed: _busy == null ? _remove : null,
                icon: Icon(LucideIcons.trash2, size: 18, color: AppColors.dangerOnSoft),
              ),
            ]),
          )
        else if (_analysis == null)
          OutlinedButton.icon(
            onPressed: _busy == null ? _pick : null,
            icon: _busy == 'analyze'
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.upload, size: 18),
            label: Text(st.autoLinked ? 'ارفع ملفّك بيوزرك (اختياريّ)' : 'ارفع ملفّ VPN (‎.ovpn)'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        if (_analysis != null) ...[const SizedBox(height: Sp.sm), _analysisBox(_analysis!)],
      ],
      if (st.canTest) ...[
        const SizedBox(height: Sp.md),
        OutlinedButton.icon(
          onPressed: _busy == null ? _runTest : null,
          icon: _busy == 'test'
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(LucideIcons.refreshCw, size: 18),
          label: Text(_busy == 'test' ? 'يفحص… (قد يأخذ دقيقة)' : 'فحص الاتصال'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (shown != null && _busy != 'test') ...[
          const SizedBox(height: Sp.sm),
          _box(
            color: shown.connected ? AppColors.successSoftBg : AppColors.dangerSoftBg,
            border: shown.connected ? AppColors.successSoftBorder : AppColors.dangerSoftBorder,
            child: Text(
              '${shown.message}${shown.atMs != null ? ' · ${timeAgoAr(DateTime.fromMillisecondsSinceEpoch(shown.atMs!))}' : ''}',
              style: AppType.body(color: shown.connected ? AppColors.textHi : AppColors.dangerOnSoft),
            ),
          ),
        ],
        const SizedBox(height: Sp.md),
        _box(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('الاتصال العكسي عند الخروج من الشبكة', style: AppType.bodyStrong(color: AppColors.textHi)),
                const SizedBox(height: 2),
                Text('مفعّلاً: حين لا يقيس تطبيقك من شبكتك ٢٠ دقيقة، يقيس النظام عبر الـVPN.',
                    style: AppType.micro(color: AppColors.textMid)),
              ]),
            ),
            Switch.adaptive(
              value: st.reverse,
              activeTrackColor: AppColors.brand,
              onChanged: _busy == null ? _reverse : null,
            ),
          ]),
        ),
        if (st.sweepAtMs != null) ...[
          const SizedBox(height: Sp.sm),
          Text(
            'آخر جولة ${timeAgoAr(DateTime.fromMillisecondsSinceEpoch(st.sweepAtMs!))}: ${st.sweepOnline} متّصلاً، '
            'وصل ${st.sweepReachable}، وقُرئ ${st.sweepReadable}.',
            style: AppType.micro(color: AppColors.textMid),
          ),
        ],
      ],
    ];
  }

  Widget _analysisBox(ConnVpnAnalysis a) {
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_fileName, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
        const SizedBox(height: Sp.xs),
        if (!a.ok) ...[
          Text('الملفّ مرفوض:', style: AppType.bodyStrong(color: AppColors.dangerOnSoft)),
          for (final e in a.errors) Text('• $e', style: AppType.body(color: AppColors.dangerOnSoft)),
          const SizedBox(height: Sp.sm),
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: _cancel, child: const Text('إغلاق'))),
        ] else ...[
          Text('✓ الملفّ سليم — ${a.servers} خادم${a.embeddedAuth ? '، وبيانات الدخول داخله' : ''}',
              style: AppType.bodyStrong(color: AppColors.success)),
          if (a.needsAuth) ...[
            const SizedBox(height: Sp.sm),
            _field(_user, 'يوزر الـVPN'),
            const SizedBox(height: Sp.sm),
            _field(_pass, 'باسورد الـVPN', secret: true),
          ],
          if (a.needsKeyPassword) ...[
            const SizedBox(height: Sp.sm),
            _field(_keyPass, 'كلمة سرّ المفتاح', secret: true),
            const SizedBox(height: 2),
            Text('مفتاح هذا الملفّ مشفّر — غير باسورد الدخول (تعطيك إيّاها شركتك مع الملفّ).',
                style: AppType.micro(color: AppColors.textMid)),
          ],
          const SizedBox(height: Sp.md),
          Row(children: [
            Expanded(
              child: SheetFooterBar(label: 'احفظ', icon: LucideIcons.check, busy: _busy == 'save', enabled: _canSave, onPressed: _save),
            ),
          ]),
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: _cancel, child: const Text('إلغاء'))),
        ],
      ]),
    );
  }

  Widget _field(TextEditingController c, String label, {bool secret = false}) => TextField(
        controller: c,
        obscureText: secret,
        enableSuggestions: false,
        autocorrect: false,
        textDirection: TextDirection.ltr,
        onChanged: (_) => setState(() {}),
        style: AppType.input(color: AppColors.textHi),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surfaceInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.borderSoft),
          ),
          isDense: true,
        ),
      );

  // بلا أيقونةٍ ولا لون (المالك ٣ نوفمبر: «التنبيه الاعلى ايقونه اللون الاخضر الغيها»)
  Widget _note({required String text, String? hint}) => _box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(text, style: AppType.body(color: AppColors.textHi)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint, style: AppType.micro(color: AppColors.textMid)),
          ],
        ]),
      );

  Widget _box({required Widget child, Color? color, Color? border}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: border ?? AppColors.border),
        ),
        child: child,
      );
}
