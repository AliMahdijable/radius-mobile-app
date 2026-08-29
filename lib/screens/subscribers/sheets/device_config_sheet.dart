import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
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
      showSheetSnack(context, 'تعذّر الحفظ', isError: true);
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
        enabled: !_loading,
        onPressed: _save,
        leading: SheetFooterIconButton(
          icon: LucideIcons.trash2,
          color: AppColors.error,
          onTap: _saving ? null : _reset,
        ),
      ),
      body: _loading
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
                  hint: 'تلقائي يجرب Ubiquiti ثم ONT',
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
                          hint: _kind == DeviceKind.ubiquiti
                              ? 'ubnt'
                              : 'telecomadmin',
                        ),
                        Divider(height: 1, color: AppColors.divider),
                        _credRow(
                          icon: LucideIcons.lock,
                          label: 'كلمة السر',
                          controller: _pass,
                          hint: _kind == DeviceKind.ubiquiti
                              ? 'ubnt'
                              : 'admintelecom',
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
                  footnote: 'مفيد للأجهزة خلف NAT',
                  child: SheetBox(
                    icon: LucideIcons.network,
                    child: TextField(
                      controller: _ip,
                      keyboardType: TextInputType.number,
                      textDirection: ui.TextDirection.ltr,
                      style: AppType.input(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'يستخدم IP الساس إذا فارغ',
                        hintStyle:
                            AppType.input(color: AppColors.textPlaceholder),
                      ),
                    ),
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
