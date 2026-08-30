import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/whatsapp_api.dart';
import '../../../models/dashboard.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../whatsapp/whatsapp_status_screen.dart';

/// شريط «الجلسة تحتاج إعادة ربط» أعلى الداشبورد.
///
/// ⚠️ انقطاع جلسة واتساب لا يُعطّل التطبيق فيبقى صامتاً — لكنّه يوقف
/// كلّ التنبيهات والفواتير التي تُرسل للمشتركين. الحالة الوحيدة التي
/// كانت تدلّ عليه هي حبّة صغيرة في الترويسة **غير قابلة للنقر**،
/// وتختفي كليّاً عند التمرير لأنّ الترويسة تنكمش. أي أنّ عطلاً صامتاً
/// كان يُعلَن بإشارة صامتة تختفي.
///
/// الشريط لا يظهر إلّا عند العطل فعلاً — لا يأكل مساحة في الحالة
/// السويّة، وهي الغالبة.
class ReconnectBanner extends StatefulWidget {
  const ReconnectBanner({super.key, required this.status, required this.onDone});

  final WhatsAppStatus? status;

  /// يُستدعى بعد محاولة ناجحة ليُعيد الداشبورد جلب الحالة.
  final VoidCallback onDone;

  @override
  State<ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends State<ReconnectBanner> {
  bool _busy = false;

  Future<void> _reconnect() async {
    setState(() => _busy = true);
    final r = await WhatsAppApi.reconnect();
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.ok) {
      widget.onDone();
      return;
    }
    // الفشل الصامت أسوأ من العطل: إن لم تُفلح المحاولة السريعة نأخذ
    // المدير إلى الشاشة التي تعرض QR ورمز الاقتران.
    if (!Perms.has('whatsapp.connect')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.message ?? 'wa.needs_pairing'.tr(),
            style: AppType.body(color: AppColors.onBrand)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WhatsAppStatusScreen()),
    );
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.status;
    // لا شريط ما لم تكن الحالة معروفة **وسيّئة**: أثناء التحميل (null)
    // نصمت بدل أن نومض بتحذير ثمّ نسحبه.
    if (s == null || (s.connected && !s.needsPairing)) {
      return const SizedBox.shrink();
    }

    final tone = s.needsPairing ? AppTone.warning : AppTone.danger;
    final label =
        s.needsPairing ? 'wa.needs_pairing_title'.tr() : 'wa.disconnected'.tr();

    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 17, color: tone.fill),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: AppType.bodyBold(color: tone.onSoft),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: tone.fill,
            borderRadius: BorderRadius.circular(R.pill),
            child: InkWell(
              onTap: _busy ? null : _reconnect,
              borderRadius: BorderRadius.circular(R.pill),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onBrand,
                        ),
                      )
                    : Text('wa.reconnect'.tr(),
                        style: AppType.label(color: AppColors.onBrand)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
