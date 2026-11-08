import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/renew_requests_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'renew_requests_screen.dart';

/// «طلب التجديد من التطبيق» في «بوابة المشترك» (٤ نوفمبر): مفتاح الوكيل (مشتركوه يرون زرّ الطلب) + أين يحوّلون (زين كاش/الماستر)
/// + ملاحظة لهم. يظهر حين يُفتح المفتاح العامّ لحسابه وحده؛ والحفظ بـ«تعديل إعدادات النظام» (بدونها للقراءة بقفل).
class RenewSettingsCard extends StatefulWidget {
  const RenewSettingsCard({super.key});

  @override
  State<RenewSettingsCard> createState() => _RenewSettingsCardState();
}

class _RenewSettingsCardState extends State<RenewSettingsCard> {
  RenewAccess? _a;
  bool _busy = false;
  final _zain = TextEditingController();
  final _master = TextEditingController();
  final _note = TextEditingController();
  String _base = '';

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_zain, _master, _note]) {
      c.addListener(_onEdit);
    }
  }

  @override
  void dispose() {
    _zain.dispose();
    _master.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onEdit() => setState(() {});

  String get _current => '${_zain.text.trim()}|${_master.text.trim()}|${_note.text.trim()}';
  bool get _dirty => _current != _base;

  void _fill(RenewAccess a) {
    _zain.text = a.zaincash ?? '';
    _master.text = a.master ?? '';
    _note.text = a.note ?? '';
    _base = _current;
  }

  Future<void> _load() async {
    final a = await RenewRequestsApi.access();
    if (!mounted || a == null) return;
    setState(() {
      _a = a;
      _fill(a);
    });
  }

  Future<void> _save({bool? enabled}) async {
    setState(() => _busy = true);
    final r = enabled != null
        ? await RenewRequestsApi.saveSettings(enabled: enabled)
        : await RenewRequestsApi.saveSettings(zaincash: _zain.text.trim(), master: _master.text.trim(), note: _note.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      final s = r.settings;
      if (s != null) {
        _a = RenewAccess(
          available: s.available,
          canUse: _a?.canUse ?? s.canUse,
          canEdit: _a?.canEdit ?? s.canEdit,
          enabled: s.enabled,
          zaincash: s.zaincash,
          master: s.master,
          note: s.note,
        );
        if (enabled == null) _fill(_a!);
      }
    });
    final ok = r.ok;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(ok
          ? (enabled == null ? 'تم الحفظ' : enabled ? 'مشتركوك يقدرون يطلبون التجديد من تطبيقهم' : 'أُوقف طلب التجديد من التطبيق')
          : (r.message ?? 'تعذّر الحفظ')),
      backgroundColor: ok ? AppColors.brand : AppColors.errorFill,
    ));
    if (ok) await RenewRequestsState.ensureFresh(force: true);
  }

  /// حقلٌ بطراز «بوابة المشترك» (portal_settings_screen._field): عنوانٌ صغير فوق حقلٍ ممتلئٍ بإطار.
  Widget _field(Key key, String label, TextEditingController c, String hint,
      {required bool enabled, TextInputType? keyboard, bool ltr = false, int? maxLength, int maxLines = 1}) {
    OutlineInputBorder border(Color color) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: color));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 11)),
      const SizedBox(height: 4),
      TextField(
        key: key,
        controller: c,
        enabled: enabled,
        keyboardType: keyboard,
        textDirection: ltr ? TextDirection.ltr : null,
        maxLength: maxLength,
        minLines: maxLines > 1 ? 2 : 1,
        maxLines: maxLines,
        style: AppType.subtitle(color: AppColors.textHi),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppType.subtitle(color: AppColors.textMid.withValues(alpha: 0.5)),
          filled: true,
          fillColor: AppColors.surfaceInput,
          border: border(AppColors.textMid.withValues(alpha: 0.2)),
          enabledBorder: border(AppColors.textMid.withValues(alpha: 0.2)),
          disabledBorder: border(AppColors.textMid.withValues(alpha: 0.12)),
          focusedBorder: border(AppColors.brand),
          contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          counterText: '',
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = _a;
    if (a == null || !a.available) return const SizedBox.shrink();
    final canEdit = a.canEdit;
    if (!canEdit && !a.canUse) return const SizedBox.shrink();
    final edit = canEdit && !_busy;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xl),
      child: Container(
        key: const ValueKey('renew-settings-card'),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.md, Sp.md),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: a.enabled ? AppColors.successSoftBg : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(LucideIcons.refreshCcw, size: 20, color: a.enabled ? AppColors.success : AppColors.textMid),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('طلب التجديد من التطبيق', style: AppType.bodyBold(color: AppColors.textHi)),
                  const SizedBox(height: 2),
                  Text(
                    a.enabled ? 'مشتركوك يطلبون التجديد ويرفقون صورة التحويل — تصلك بإشعار' : 'موقوف — لا يظهر زرّ «طلب التجديد» لمشتركيك',
                    style: AppType.micro(color: AppColors.textMid),
                  ),
                ]),
              ),
              Switch(
                key: const ValueKey('renew-enabled-switch'),
                value: a.enabled,
                onChanged: edit ? (v) => _save(enabled: v) : null,
              ),
            ]),
          ),
          Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.all(Sp.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('يراها المشترك حين يطلب التجديد ليعرف أين يحوّل:', style: AppType.micro(color: AppColors.textMid)),
              const SizedBox(height: Sp.md),
              _field(const ValueKey('renew-zaincash'), 'رقم زين كاش', _zain, '07XXXXXXXXX',
                  enabled: edit, keyboard: TextInputType.phone, ltr: true, maxLength: 20),
              const SizedBox(height: Sp.md),
              _field(const ValueKey('renew-master'), 'رقم الماستر / كي كارد', _master, '1234 5678 9012 3456',
                  enabled: edit, keyboard: TextInputType.number, ltr: true, maxLength: 30),
              const SizedBox(height: Sp.md),
              _field(const ValueKey('renew-note'), 'ملاحظة للمشترك (اختياريّ)', _note, 'مثلاً: حوّل باسم علي واكتب يوزرك',
                  enabled: edit, maxLength: 300, maxLines: 3),
              const SizedBox(height: Sp.md),
              if (canEdit)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: const ValueKey('renew-settings-save'),
                    onPressed: edit && _dirty ? () => _save() : null,
                    icon: const Icon(LucideIcons.check, size: 18),
                    label: const Text('حفظ'),
                  ),
                )
              else
                Row(children: [
                  Icon(LucideIcons.lock, size: 14, color: AppColors.textLow),
                  const SizedBox(width: Sp.xs),
                  Expanded(
                    child: Text('ليس لديك صلاحيّة لتغيير هذا الإعداد — «تعديل إعدادات النظام»',
                        style: AppType.micro(color: AppColors.textLow)),
                  ),
                ]),
            ]),
          ),
          if (a.canUse) ...[
            Divider(height: 1, color: AppColors.divider),
            InkWell(
              key: const ValueKey('renew-open-list'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RenewRequestsScreen.mergedPage())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
                child: Row(children: [
                  Expanded(child: Text('افتح «طلبات التفعيل»', style: AppType.bodyBold(color: AppColors.brand))),
                  Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.brand),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
