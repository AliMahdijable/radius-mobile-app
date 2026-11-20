import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/el_managers_api.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// رقم واتساب مدير ايرث لنك التابع لإشعاره بعد الشحن (٢٠ نوفمبر — المالك: «اشعار الوكيل الفرعي بالتطبيق والواتساب»). يُستعمل حين لا
/// جلسة واتساب له في البرو (رقم جلسته يغلب). الفارغ يحذفه. الخادم يطبّعه ويرفض الخاطئ.
Future<bool?> showElWaPhoneSheet(BuildContext context, {required ElManagerRow manager}) {
  return showAppSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ElWaPhoneSheet(manager: manager),
  );
}

class _ElWaPhoneSheet extends StatefulWidget {
  const _ElWaPhoneSheet({required this.manager});
  final ElManagerRow manager;

  @override
  State<_ElWaPhoneSheet> createState() => _ElWaPhoneSheetState();
}

class _ElWaPhoneSheetState extends State<_ElWaPhoneSheet> {
  late final _ctrl = TextEditingController(text: widget.manager.waPhone ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ElManagersApi.saveContact(widget.manager.index, _ctrl.text.trim());
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = r.message ?? 'تعذّر حفظ الرقم';
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final had = widget.manager.waPhone != null;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.messageCircle,
        title: had ? 'رقم واتساب المدير' : 'أضف رقم واتساب',
        subtitle: widget.manager.name,
        tint: AppColors.channelWhatsApp,
        tintBg: AppColors.channelWhatsAppSoftBg,
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving ? 'جارٍ الحفظ…' : (had && _ctrl.text.trim().isEmpty ? 'حذف الرقم' : 'حفظ'),
        icon: LucideIcons.check,
        color: AppColors.brand,
        enabled: !_saving,
        busy: _saving,
        onPressed: _save,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('يصله عليه إشعار الشحن من واتسابك المربوط',
                style: AppType.muted().copyWith(fontSize: 12)),
            const SizedBox(height: Sp.md),
            TextField(
              controller: _ctrl,
              enabled: !_saving,
              autofocus: true,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {}),
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: '07701234567',
                hintStyle: AppType.input(color: AppColors.textLow),
                errorText: _error,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
