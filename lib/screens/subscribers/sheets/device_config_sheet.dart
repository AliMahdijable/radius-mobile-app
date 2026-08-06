import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
import '../../../api/device_probe_api.dart';
import '../../../models/device_health.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// Per-subscriber CPE override editor — opened from the gear button
/// on the DeviceProbeCard. Lets the admin pin device type, custom
/// credentials, custom IP, and a free-form note. All fields optional;
/// empties fall through to admin defaults + library defaults.
class DeviceConfigSheet extends StatefulWidget {
  const DeviceConfigSheet({super.key, required this.username});
  final String username;

  @override
  State<DeviceConfigSheet> createState() => _DeviceConfigSheetState();
}

class _DeviceConfigSheetState extends State<DeviceConfigSheet> {
  DeviceKind? _kind;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _ip = TextEditingController();
  final _notes = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  String? _originalIp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _ip.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await DeviceConfigApi.fetchConfig(widget.username);
    if (!mounted) return;
    setState(() {
      _kind = cfg?.deviceType;
      _user.text = cfg?.username ?? '';
      _pass.text = cfg?.password ?? '';
      _ip.text = cfg?.customIp ?? '';
      _notes.text = cfg?.notes ?? '';
      _originalIp = cfg?.customIp;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final cfg = DeviceConfig(
      deviceType: _kind,
      username: _user.text.trim().isEmpty ? null : _user.text.trim(),
      password: _pass.text.isEmpty ? null : _pass.text,
      customIp: _ip.text.trim().isEmpty ? null : _ip.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final ok = await DeviceConfigApi.saveConfig(widget.username, cfg);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      showSheetSnack(context, 'تعذّر الحفظ', isError: false);
      return;
    }
    // Invalidate any cached probe under the old IP AND the new IP so the
    // detail card re-probes against the freshly-pinned credentials.
    if (_originalIp != null && _originalIp!.isNotEmpty) {
      DeviceProbeApi.invalidateIp(_originalIp!);
    }
    if (cfg.customIp != null && cfg.customIp!.isNotEmpty) {
      DeviceProbeApi.invalidateIp(cfg.customIp!);
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    final ok = await DeviceConfigApi.resetConfig(widget.username);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      showSheetSnack(context, 'تعذّر الحذف', isError: false);
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
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
                children: [
                  _grabber(),
                  const SizedBox(height: Sp.md),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: const Icon(LucideIcons.router,
                            size: 16, color: Color(0xFF7C3AED)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إعدادات جهاز المشترك',
                              style: AppType.title(color: AppColors.textHi)
                                  .copyWith(fontSize: 15),
                            ),
                            Text(
                              widget.username,
                              style: AppType.muted().copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'اتركه تلقائياً ليُجرَّب ONT ثم Ubiquiti.',
                    style: AppType.muted().copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  _kindSegmented(),
                  const SizedBox(height: 14),
                  _label('اسم المستخدم'),
                  TextField(
                    controller: _user,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(_kind == DeviceKind.ubiquiti
                        ? 'ubnt'
                        : 'telecomadmin'),
                  ),
                  const SizedBox(height: 10),
                  _label('كلمة السر'),
                  TextField(
                    controller: _pass,
                    obscureText: _obscure,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(
                      _kind == DeviceKind.ubiquiti ? 'ubnt' : 'admintelecom',
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                          size: 16,
                          color: AppColors.textMid,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _label('IP مخصص (اختياري)'),
                  TextField(
                    controller: _ip,
                    style: const TextStyle(fontSize: 13),
                    keyboardType: TextInputType.number,
                    decoration: _dec('يستخدم IP الساس إذا فارغ'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'IP المخصص مفيد لـ Ubiquiti خلف NAT.',
                    style: AppType.muted().copyWith(fontSize: 10.5),
                  ),
                  const SizedBox(height: 14),
                  _label('ملاحظات'),
                  TextField(
                    controller: _notes,
                    style: const TextStyle(fontSize: 13),
                    minLines: 2,
                    maxLines: 4,
                    decoration: _dec(
                        'مثال: VLAN 102، تقسيم فايبر للطابق الثاني، إلخ'),
                  ),
                  const SizedBox(height: 22),
                  // مطلب 2026-06-11: تنسيق الأزرار — 'حذف الإعداد' كان
                  // يلتف على سطرين بسبب flex 1:2. صار الترتيب: زر
                  // 'حفظ' كبير ممتد، وزر دائري صغير للحذف بجانبه —
                  // يحرّر مساحة + يبيّن وضوحه بالأيقونة وحدها بدل
                  // النص المضغوط.
                  SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(LucideIcons.save, size: 16),
                            label: const Text(
                              'حفظ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brand,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(R.md),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _saving ? null : _reset,
                            borderRadius: BorderRadius.circular(R.md),
                            child: Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(R.md),
                                border: Border.all(
                                  color: AppColors.error.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Icon(
                                LucideIcons.trash2,
                                size: 18,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Sp.lg),
                ],
              ),
      ),
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _kindSegmented() => Row(
        children: [
          for (final entry in const [
            (null, 'تلقائي'),
            (DeviceKind.ont, 'ONT'),
            (DeviceKind.ubiquiti, 'Ubiquiti'),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 4),
                child: _segChip(entry.$1, entry.$2),
              ),
            ),
        ],
      );

  Widget _segChip(DeviceKind? kind, String label) {
    final selected = _kind == kind;
    return GestureDetector(
      onTap: () => setState(() => _kind = kind),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand
              : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppType.label(
              color: selected ? Colors.white : AppColors.textHi,
            ).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style:
                AppType.label(color: AppColors.textMid).copyWith(fontSize: 11)),
      );

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle:
            AppType.input(color: AppColors.textLow).copyWith(fontSize: 12),
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
