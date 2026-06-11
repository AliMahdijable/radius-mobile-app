import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/device_config_api.dart';
import '../../api/device_probe_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Admin-wide ONT + Ubiquiti credential defaults. Settings → "اعتمادات ONU/Ubiquiti".
/// Empty fields fall back to the library hardcoded values
/// (telecomadmin/admintelecom and ubnt/ubnt). This is the 2nd tier of
/// the credential chain: per-subscriber override > these > library.
class DeviceDefaultsScreen extends StatefulWidget {
  const DeviceDefaultsScreen({super.key});

  @override
  State<DeviceDefaultsScreen> createState() => _DeviceDefaultsScreenState();
}

class _DeviceDefaultsScreenState extends State<DeviceDefaultsScreen> {
  final _ontUser = TextEditingController();
  final _ontPass = TextEditingController();
  final _ubntUser = TextEditingController();
  final _ubntPass = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _ontObscure = true;
  bool _ubntObscure = true;

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
    super.dispose();
  }

  Future<void> _load() async {
    final d = await AdminDeviceDefaultsApi.fetch();
    if (!mounted) return;
    setState(() {
      _ontUser.text = d.ontUsername ?? '';
      _ontPass.text = d.ontPassword ?? '';
      _ubntUser.text = d.ubntUsername ?? '';
      _ubntPass.text = d.ubntPassword ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await AdminDeviceDefaultsApi.save(
      AdminDeviceDefaults(
        ontUsername:
            _ontUser.text.trim().isEmpty ? null : _ontUser.text.trim(),
        ontPassword: _ontPass.text.isEmpty ? null : _ontPass.text,
        ubntUsername:
            _ubntUser.text.trim().isEmpty ? null : _ubntUser.text.trim(),
        ubntPassword: _ubntPass.text.isEmpty ? null : _ubntPass.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ')),
      );
      return;
    }
    // Defaults changed → every cached snapshot used the old creds.
    DeviceProbeApi.invalidateAdminDefaults();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('حُفظت الاعتمادات'),
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
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'اعتمادات ONU / Ubiquiti',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: [
                  _intro(),
                  const SizedBox(height: Sp.lg),
                  _section(
                    icon: LucideIcons.cable,
                    title: 'Huawei ONT',
                    subtitle:
                        'افتراضي النظام: telecomadmin / admintelecom. اتركها فاضية لتُستخدم.',
                    userController: _ontUser,
                    passController: _ontPass,
                    obscure: _ontObscure,
                    onToggle: () =>
                        setState(() => _ontObscure = !_ontObscure),
                  ),
                  const SizedBox(height: Sp.md),
                  _section(
                    icon: LucideIcons.wifi,
                    title: 'Ubiquiti (UBNT)',
                    subtitle:
                        'افتراضي النظام: ubnt / ubnt. اتركها فاضية لتُستخدم.',
                    userController: _ubntUser,
                    passController: _ubntPass,
                    obscure: _ubntObscure,
                    onToggle: () =>
                        setState(() => _ubntObscure = !_ubntObscure),
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
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.save, size: 16),
                      label: const Text('حفظ الاعتمادات'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
          color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.info, size: 16, color: Color(0xFF7C3AED)),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                'هذه الاعتمادات تُستعمل عند جلب معلومات الأجهزة من كل المشتركين. لو ما حدّدت قيم، يستعمل النظام الافتراضي.',
                style: AppType.muted().copyWith(fontSize: 11.5, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController userController,
    required TextEditingController passController,
    required bool obscure,
    required VoidCallback onToggle,
  }) =>
      Container(
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
                    color: AppColors.brand.withValues(alpha: 0.1),
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
            _labelText('اسم المستخدم'),
            TextField(
              controller: userController,
              style: const TextStyle(fontSize: 13),
              decoration: _dec(),
            ),
            const SizedBox(height: 10),
            _labelText('كلمة السر'),
            TextField(
              controller: passController,
              obscureText: obscure,
              style: const TextStyle(fontSize: 13),
              decoration: _dec(
                suffix: IconButton(
                  icon: Icon(
                    obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                    size: 16,
                    color: AppColors.textMid,
                  ),
                  onPressed: onToggle,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _labelText(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style:
                AppType.label(color: AppColors.textMid).copyWith(fontSize: 11)),
      );

  InputDecoration _dec({Widget? suffix}) => InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        filled: true,
        fillColor: AppColors.surfaceInput,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide:
              BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide:
              BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.4),
        ),
      );
}
