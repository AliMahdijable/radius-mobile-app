import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/device_config_api.dart';
import '../../api/device_probe_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';

/// Admin-wide ONT + Ubiquiti + TP-Link credential defaults. Settings → "اعتمادات ONU / Ubiquiti / TP-Link".
/// Empty fields fall back to the library hardcoded values
/// (telecomadmin/admintelecom and ubnt/ubnt). This is the 2nd tier of
/// the credential chain: per-subscriber override > these > library.
///
/// ⑦ (٢٩ أكتوبر — المالك: «نضيف ٣ اختيارات بقسم اعتمادات الأجهزة… مرات عدهم أكثر من يوزر وباسورد موحّد»): لكلّ نوعٍ
/// لحدّ اعتمادين إضافيّين فوق الأوّل؛ الفحص يجرّبها بالترتيب حين يُرفض الأوّل ويحفظ الذي يعمل لكلّ جهاز.
///
/// TP-Link (١٠ نوفمبر — المالك: «صنف جديد من النانوات tplink يحتاج نضيفه ضمن الاعتمادات»): قسمٌ ثالث بلا افتراض مصنّع
/// — ما لم يُكتب هنا (أو للمشترك) لا يُجرَّب شيءٌ على الجهاز.
class DeviceDefaultsScreen extends StatefulWidget {
  const DeviceDefaultsScreen({super.key});

  @override
  State<DeviceDefaultsScreen> createState() => _DeviceDefaultsScreenState();
}

/// خانةٌ إضافيّة: يوزر + باسورد.
typedef _ExtraField = ({TextEditingController user, TextEditingController pass});

class _DeviceDefaultsScreenState extends State<DeviceDefaultsScreen> {
  final _ontUser = TextEditingController();
  final _ontPass = TextEditingController();
  final _ubntUser = TextEditingController();
  final _ubntPass = TextEditingController();
  final _tplinkUser = TextEditingController();
  final _tplinkPass = TextEditingController();
  // راوتر TP-Link الحديث «Agile» (Archer…): كلمة سرٍّ فقط بلا يوزر.
  final _tprouterPass = TextEditingController();
  final List<_ExtraField> _ontExtra = [];
  final List<_ExtraField> _ubntExtra = [];
  final List<_ExtraField> _tplinkExtra = [];
  final List<TextEditingController> _tprouterExtra = [];
  bool _loading = true;
  bool _saving = false;
  bool _ontObscure = true;
  bool _ubntObscure = true;
  bool _tplinkObscure = true;
  bool _tprouterObscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ontUser.dispose();
    _ontPass.dispose();
    _ubntUser.dispose();
    _ubntPass.dispose();
    _tplinkUser.dispose();
    _tplinkPass.dispose();
    _tprouterPass.dispose();
    for (final f in [..._ontExtra, ..._ubntExtra, ..._tplinkExtra]) {
      f.user.dispose();
      f.pass.dispose();
    }
    for (final c in _tprouterExtra) {
      c.dispose();
    }
    super.dispose();
  }

  static _ExtraField _field([DeviceCred? c]) => (
        user: TextEditingController(text: c?.username ?? ''),
        pass: TextEditingController(text: c?.password ?? ''),
      );

  Future<void> _load() async {
    final d = await AdminDeviceDefaultsApi.fetch();
    if (!mounted) return;
    setState(() {
      _ontUser.text = d.ontUsername ?? '';
      _ontPass.text = d.ontPassword ?? '';
      _ubntUser.text = d.ubntUsername ?? '';
      _ubntPass.text = d.ubntPassword ?? '';
      _tplinkUser.text = d.tplinkUsername ?? '';
      _tplinkPass.text = d.tplinkPassword ?? '';
      _tprouterPass.text = d.tprouterPassword ?? '';
      _ontExtra.addAll(d.ontExtra.map(_field));
      _ubntExtra.addAll(d.ubntExtra.map(_field));
      _tplinkExtra.addAll(d.tplinkExtra.map(_field));
      _tprouterExtra.addAll(d.tprouterExtra.map((p) => TextEditingController(text: p)));
      _loading = false;
    });
  }

  /// الخانات الإضافيّة ⇒ اعتمادات (اليوزر الفارغ يُسقط).
  static List<DeviceCred> _credsOf(List<_ExtraField> fields) => [
        for (final f in fields)
          if (f.user.text.trim().isNotEmpty) DeviceCred(f.user.text.trim(), f.pass.text),
      ];

  void _addExtra(List<_ExtraField> list) {
    if (list.length >= AdminDeviceDefaults.maxExtra) return;
    setState(() => list.add(_field()));
  }

  void _removeExtra(List<_ExtraField> list, int i) {
    final f = list[i];
    setState(() => list.removeAt(i));
    // بعد الإطار: حقلا الخانة المحذوفة ما زالا مرسومين حتى يُعاد البناء.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      f.user.dispose();
      f.pass.dispose();
    });
  }

  void _addPwdExtra() {
    if (_tprouterExtra.length >= AdminDeviceDefaults.maxExtra) return;
    setState(() => _tprouterExtra.add(TextEditingController()));
  }

  void _removePwdExtra(int i) {
    final c = _tprouterExtra[i];
    setState(() => _tprouterExtra.removeAt(i));
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await AdminDeviceDefaultsApi.save(
      AdminDeviceDefaults(
        ontUsername: _ontUser.text.trim().isEmpty ? null : _ontUser.text.trim(),
        ontPassword: _ontPass.text.isEmpty ? null : _ontPass.text,
        ubntUsername:
            _ubntUser.text.trim().isEmpty ? null : _ubntUser.text.trim(),
        ubntPassword: _ubntPass.text.isEmpty ? null : _ubntPass.text,
        tplinkUsername: _tplinkUser.text.trim().isEmpty ? null : _tplinkUser.text.trim(),
        tplinkPassword: _tplinkPass.text.isEmpty ? null : _tplinkPass.text,
        ontExtra: _credsOf(_ontExtra),
        ubntExtra: _credsOf(_ubntExtra),
        tplinkExtra: _credsOf(_tplinkExtra),
        tprouterPassword: _tprouterPass.text.isEmpty ? null : _tprouterPass.text,
        tprouterExtra: [
          for (final c in _tprouterExtra)
            if (c.text.isNotEmpty) c.text,
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('devices.save_failed'.tr())),
      );
      return;
    }
    // Defaults changed → every cached snapshot used the old creds.
    DeviceProbeApi.invalidateAdminDefaults();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('devices.creds_saved'.tr()),
        backgroundColor: AppColors.brand,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'settings.device_creds'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: [
                  _intro(),
                  const SizedBox(height: Sp.lg),
                  _section(
                    icon: LucideIcons.cable,
                    // ZTE أيضاً منذ MH80 والنكست (HS8546V6) — لا هواوي وحده.
                    title: 'ONT — Huawei / ZTE',
                    subtitle: 'devices.ont_default_hint'.tr(),
                    userController: _ontUser,
                    passController: _ontPass,
                    obscure: _ontObscure,
                    onToggle: () => setState(() => _ontObscure = !_ontObscure),
                    extras: _ontExtra,
                    onAdd: () => _addExtra(_ontExtra),
                    onRemove: (i) => _removeExtra(_ontExtra, i),
                  ),
                  const SizedBox(height: Sp.md),
                  _section(
                    icon: LucideIcons.wifi,
                    title: 'Ubiquiti (UBNT)',
                    subtitle: 'devices.ubnt_default_hint'.tr(),
                    userController: _ubntUser,
                    passController: _ubntPass,
                    obscure: _ubntObscure,
                    onToggle: () =>
                        setState(() => _ubntObscure = !_ubntObscure),
                    extras: _ubntExtra,
                    onAdd: () => _addExtra(_ubntExtra),
                    onRemove: (i) => _removeExtra(_ubntExtra, i),
                  ),
                  const SizedBox(height: Sp.md),
                  _section(
                    key: const ValueKey('creds-tplink'),
                    icon: LucideIcons.radioTower,
                    title: 'TP-Link — يوزر + باسورد (CPE / راوتر قديم)',
                    subtitle: 'devices.tplink_default_hint'.tr(),
                    userController: _tplinkUser,
                    passController: _tplinkPass,
                    obscure: _tplinkObscure,
                    onToggle: () => setState(() => _tplinkObscure = !_tplinkObscure),
                    extras: _tplinkExtra,
                    onAdd: () => _addExtra(_tplinkExtra),
                    onRemove: (i) => _removeExtra(_tplinkExtra, i),
                    // جملة الإضافيّ العامّة تتكلّم عن ZTE — هنا بكلمات TP-Link.
                    extraHint: 'devices.tplink_extra_hint'.tr(),
                  ),
                  const SizedBox(height: Sp.md),
                  // راوتر TP-Link الحديث (Agile/Archer): كلمة سرٍّ محلّيّة فقط بلا يوزر (المالك ١١ نوفمبر: «النوع الي يدور فقط باسورد»).
                  _passwordSection(
                    key: const ValueKey('creds-tprouter'),
                    title: 'راوتر TP-Link حديث — باسورد فقط (Archer)',
                    subtitle: 'devices.tprouter_default_hint'.tr(),
                  ),
                  const SizedBox(height: Sp.lg),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onBrand,
                              ),
                            )
                          : const Icon(LucideIcons.save, size: 16),
                      label: Text('devices.save_creds'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: AppColors.onBrand,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14, height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.brandSoftBg,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.brandSoftBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.info, size: 16, color: AppColors.brandAccent),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                'devices.info_hint'.tr(),
                style: AppType.muted().copyWith(fontSize: 11.5, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _section({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController userController,
    required TextEditingController passController,
    required bool obscure,
    required VoidCallback onToggle,
    required List<_ExtraField> extras,
    required VoidCallback onAdd,
    required ValueChanged<int> onRemove,
    String? extraHint,
  }) =>
      Container(
        key: key,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Icon(icon, size: 14, color: AppColors.brand),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppType.muted().copyWith(fontSize: 10.5, height: 1.4),
            ),
            const SizedBox(height: Sp.md),
            _labelText('login.username'.tr()),
            TextField(
              controller: userController,
              style: const TextStyle(fontSize: 13, height: 1.45),
              decoration: _dec(),
            ),
            const SizedBox(height: 10),
            _labelText('login.password'.tr()),
            TextField(
              controller: passController,
              obscureText: obscure,
              style: const TextStyle(fontSize: 13, height: 1.45),
              decoration: _dec(suffix: _eye(obscure, onToggle)),
            ),
            for (var i = 0; i < extras.length; i++) ...[
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'devices.extra_cred'.tr(args: ['${i + 2}']),
                      style: AppType.label(color: AppColors.textMid)
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'devices.remove_cred'.tr(),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.error),
                    onPressed: () => onRemove(i),
                  ),
                ],
              ),
              TextField(
                controller: extras[i].user,
                style: const TextStyle(fontSize: 13, height: 1.45),
                decoration: _dec(hint: 'login.username'.tr()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: extras[i].pass,
                obscureText: obscure,
                style: const TextStyle(fontSize: 13, height: 1.45),
                decoration: _dec(hint: 'login.password'.tr(), suffix: _eye(obscure, onToggle)),
              ),
            ],
            if (extras.length < AdminDeviceDefaults.maxExtra) ...[
              const SizedBox(height: Sp.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: Text('devices.add_cred'.tr()),
                ),
              ),
            ],
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                extraHint ?? 'devices.extra_hint'.tr(),
                style: AppType.muted().copyWith(fontSize: 10.5, height: 1.4),
              ),
            ],
          ],
        ),
      );

  /// قسم «باسورد فقط» (راوتر TP-Link الحديث — دخولٌ بكلمة سرٍّ محلّيّة بلا يوزر). كلمةٌ أولى + [maxExtra] إضافيّة.
  Widget _passwordSection({Key? key, required String title, required String subtitle}) => Container(
        key: key,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Icon(LucideIcons.router, size: 14, color: AppColors.brand),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppType.muted().copyWith(fontSize: 10.5, height: 1.4),
            ),
            const SizedBox(height: Sp.md),
            _labelText('login.password'.tr()),
            TextField(
              controller: _tprouterPass,
              obscureText: _tprouterObscure,
              style: const TextStyle(fontSize: 13, height: 1.45),
              decoration: _dec(suffix: _eye(_tprouterObscure, () => setState(() => _tprouterObscure = !_tprouterObscure))),
            ),
            for (var i = 0; i < _tprouterExtra.length; i++) ...[
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'devices.extra_cred'.tr(args: ['${i + 2}']),
                      style: AppType.label(color: AppColors.textMid)
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'devices.remove_cred'.tr(),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(LucideIcons.trash2, size: 15, color: AppColors.error),
                    onPressed: () => _removePwdExtra(i),
                  ),
                ],
              ),
              TextField(
                controller: _tprouterExtra[i],
                obscureText: _tprouterObscure,
                style: const TextStyle(fontSize: 13, height: 1.45),
                decoration: _dec(hint: 'login.password'.tr()),
              ),
            ],
            if (_tprouterExtra.length < AdminDeviceDefaults.maxExtra) ...[
              const SizedBox(height: Sp.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _addPwdExtra,
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: Text('devices.add_cred'.tr()),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _eye(bool obscure, VoidCallback onToggle) => IconButton(
        icon: Icon(
          obscure ? LucideIcons.eye : LucideIcons.eyeOff,
          size: 16,
          color: AppColors.textMid,
        ),
        onPressed: onToggle,
      );

  Widget _labelText(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style:
                AppType.label(color: AppColors.textMid).copyWith(fontSize: 11)),
      );

  InputDecoration _dec({Widget? suffix, String? hint}) => InputDecoration(
        isDense: true,
        hintText: hint,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        filled: true,
        fillColor: AppColors.surfaceInput,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide(color: AppColors.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide(color: AppColors.brand, width: 1.4),
        ),
      );
}
