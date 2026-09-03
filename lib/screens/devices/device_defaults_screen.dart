import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin_device_defaults.dart';
import '../../providers/device_provider.dart';

/// Admin-wide credentials form — "الإعدادات الافتراضية لأجهزتك".
/// Empty fields mean the system falls back to the built-in defaults
/// (ubnt/ubnt for Ubiquiti, telecomadmin/admintelecom for Huawei ONT).
class DeviceDefaultsScreen extends ConsumerStatefulWidget {
  const DeviceDefaultsScreen({super.key});

  @override
  ConsumerState<DeviceDefaultsScreen> createState() => _DeviceDefaultsScreenState();
}

class _DeviceDefaultsScreenState extends ConsumerState<DeviceDefaultsScreen> {
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

  Future<void> _load() async {
    final d = await ref.read(adminDeviceDefaultsProvider.future);
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
    final ok = await saveAdminDeviceDefaults(
      ref,
      AdminDeviceDefaults(
        ontUsername: _ontUser.text.trim().isEmpty ? null : _ontUser.text.trim(),
        ontPassword: _ontPass.text.isEmpty ? null : _ontPass.text,
        ubntUsername: _ubntUser.text.trim().isEmpty ? null : _ubntUser.text.trim(),
        ubntPassword: _ubntPass.text.isEmpty ? null : _ubntPass.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'تم الحفظ' : 'تعذّر الحفظ')),
    );
    if (ok) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات الافتراضية لأجهزتك')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هذه الإعدادات تُستخدم لكل مشتركيك تلقائياً. '
                            'لو تركت الحقول فارغة، النظام يرجع للافتراضيات:\n'
                            '• ONT: telecomadmin / admintelecom\n'
                            '• Ubiquiti: ubnt / ubnt\n'
                            'يمكن تخصيص جهاز مشترك واحد من صفحة المشترك.',
                            style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionCard(
                    context,
                    icon: Icons.sensors,
                    title: 'أجهزة الألياف الضوئية (ONT)',
                    subtitle: 'Huawei HG8145C وما شابه',
                    children: [
                      _field(_ontUser, 'اسم المستخدم', 'telecomadmin'),
                      const SizedBox(height: 10),
                      _field(_ontPass, 'كلمة السر', 'admintelecom',
                          obscure: _ontObscure,
                          onToggleObscure: () => setState(() => _ontObscure = !_ontObscure)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    icon: Icons.wifi,
                    title: 'أجهزة Ubiquiti',
                    subtitle: 'NanoStation / LiteBeam / airCube …',
                    children: [
                      _field(_ubntUser, 'اسم المستخدم', 'ubnt'),
                      const SizedBox(height: 10),
                      _field(_ubntPass, 'كلمة السر', 'ubnt',
                          obscure: _ubntObscure,
                          onToggleObscure: () => setState(() => _ubntObscure = !_ubntObscure)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'جاري الحفظ...' : 'حفظ'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(subtitle,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: const OutlineInputBorder(),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                onPressed: onToggleObscure,
              ),
      ),
    );
  }
}
