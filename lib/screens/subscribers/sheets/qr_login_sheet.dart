import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/subscribers_api.dart';
import '../../../api/whatsapp_api.dart';
import '../../../models/subscriber.dart';
import '../../../services/merged_mode.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../widgets/manual_wa_chip.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// اسم تطبيق المشترك كما يراه على هاتفه في المتجرين: «MyServices» (كان «MySub»،
/// وأبل طلبت ترك الاسم القديم) — كـ`SubscriberApp.name` في تبويب «رمز الوكيل».
const _portalApp = 'MyServices';

/// زرّ الدخول بالرمز في شاشة دخول ذلك التطبيق (2.0.7) بنصّه حرفيّاً — كان
/// «تسجيل الدخول بواسطة QR» في نسخته القديمة (باسم MySub).
const _portalQrButton = 'الدخول برمز QR من وكيلك';

/// نصّ «حفظ / مشاركة» — يرافق صورة الرمز.
///
/// 🐛 تدقيق البوّابة ٢٠٢٦-١٠-١٧ (§2.3): الرمز والرابط يفتحان في المتصفّح
/// (كاميرا الهاتف، نقرة الرابط) **بطاقة معلومات** من الساس وحدها لا البوّابة،
/// والنصّ كان يقول «رمز QR لتسجيل دخولك» — فيُمسح بالكاميرا ويُظنّ أنّ البوّابة
/// لا تعكس تعديلات المدير. الدخول من ماسح التطبيق وحده.
String qrShareText({required String greet, required String link}) =>
    'مرحباً $greet 👋\n\n'
    'للدخول إلى تطبيق $_portalApp: افتح التطبيق واختر «$_portalQrButton»'
    '، ثمّ امسح هذا الرمز أو ارفع صورته من المعرض.\n\n'
    'ومعلومات اشتراكك على الرابط:\n$link\n\n'
    'الرمز صالح لمدة 30 يوم.';

/// نصّ «إرسال بواتساب» — رابطٌ بلا صورة، فلا يقول «هذا رمز دخولك».
String qrWhatsAppText({required String greet, required String link}) =>
    'مرحباً $greet 👋\n\n'
    'معلومات اشتراكك على الرابط:\n$link\n\n'
    'وللدخول إلى تطبيق $_portalApp امسح رمز QR من داخل التطبيق '
    '(«$_portalQrButton») لا بكاميرا الهاتف.\n\n'
    'الرابط صالح لمدة 30 يوم. لو انتهى، اطلب واحد جديد من الأدمن.\n\n'
    'شكراً 🙏';

/// Bottom sheet لتوليد رمز QR دخول المشترك (30 يوم). المشترك يمسحه
/// من **داخل** تطبيق MyServices فيسجّل دخول تلقائياً بلا كتابة username/password
/// (كاميرا الهاتف تفتح بطاقة المعلومات وحدها).
Future<void> showQrLoginSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _QrLoginSheet(sub: sub),
  );
}

class _QrLoginSheet extends StatefulWidget {
  const _QrLoginSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_QrLoginSheet> createState() => _QrLoginSheetState();
}

class _QrLoginSheetState extends State<_QrLoginSheet> {
  bool _loading = true;
  String? _error;
  String? _linkUrl;
  int? _expiresAt;
  bool _sharing = false;
  bool _sendingWa = false;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final idx = widget.sub.idx;
    if (idx == null || idx.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'qr_login.no_idx'.tr();
      });
      return;
    }
    final r = await MergedOps.write(widget.sub, () => SubscribersApi.generatePortalQrToken(idx: idx));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _linkUrl = r.linkUrl;
        _expiresAt = r.expiresAt;
      } else {
        _error = r.message ?? 'qr_login.gen_failed'.tr();
      }
    });
  }

  Future<Uint8List?> _captureQr() async {
    try {
      final ctx = _qrKey.currentContext;
      if (ctx == null) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareQr() async {
    if (_sharing || _linkUrl == null) return;
    // 2026-07-13: crash تقارير على Android+iOS. السبب:
    //   1) Share.shareXFiles القديم deprecated في share_plus 10+ ويسبب
    //      native crashes على Android 14+ و iOS 17+.
    //   2) على iPad، عدم تمرير sharePositionOrigin = crash فوري.
    //   3) toImage قد يفشل لو الـwidget ما اترسم بعد.
    // الحلّ: SharePlus.instance.share(ShareParams(...)) الحديث +
    // sharePositionOrigin مبني من الـcontext + انتظار frame واحد قبل
    // التقاط الصورة لضمان الرسم.
    setState(() => _sharing = true);
    // انتظار frame واحد لضمان أن الـRepaintBoundary أُنشئ + رُسِم
    await WidgetsBinding.instance.endOfFrame;
    try {
      final bytes = await _captureQr();
      if (bytes == null) {
        _snack('qr_login.capture_failed'.tr(), isError: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/portal_qr_${widget.sub.username}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      final greet = widget.sub.fullName.trim().isNotEmpty
          ? widget.sub.fullName.trim()
          : widget.sub.username;

      // sharePositionOrigin: مطلوب لـiPad — بدونه UIActivityViewController
      // يرمي NSInvalidArgumentException. على iPhone/Android مُتجاهَل.
      Rect origin = Rect.zero;
      if (mounted) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          origin = box.localToGlobal(Offset.zero) & box.size;
        }
      }

      // 2026-07-14: رجعنا لـShare.shareXFiles (deprecated في 10.x بس يشتغل)
      // بعد فشل build على Mac رغم share_plus 10.1.4 مثبَّت. الـAPI الجديد
      // (SharePlus.instance.share + ShareParams) كان يعطي "getter isn't
      // defined" في kernel snapshot بسبب Flutter tools cache stale.
      // الـAPI القديم يشتغل على كل الإصدارات (7.x → 10.x).
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text: qrShareText(greet: greet, link: _linkUrl!),
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (mounted) {
        _snack('${'qr_login.share_failed'.tr()}: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    if (_sendingWa || _linkUrl == null) return;
    final phone = widget.sub.displayPhone;
    if (phone.isEmpty) {
      _snack('subscribers.no_phone'.tr(), isError: true);
      return;
    }
    setState(() => _sendingWa = true);
    try {
      final greet = widget.sub.fullName.trim().isNotEmpty
          ? widget.sub.fullName.trim()
          : widget.sub.username;
      final message = qrWhatsAppText(greet: greet, link: _linkUrl!);
      // 2026-08-26: preview sheet مع chip auto/manual لهذه العمليّة أيضاً.
      if (!mounted) return;
      final choice = await showManualWaPreviewSheet(
        context,
        title: 'رمز QR دخول',
        phone: phone,
        messagePreview: message,
        accent: const Color(0xFF7C3AED),
      );
      if (!mounted || choice == null || !choice.confirmed) return;

      if (choice.manualMode) {
        final ok = await openManualWa(
          phone: phone,
          message: message,
          context: context,
        );
        if (!mounted) return;
        if (ok) {
          _snack('افتح واتساب واضغط "إرسال" لإتمام العمليّة', isError: false);
        } else {
          _snack('تعذّر فتح واتساب', isError: true);
        }
        return;
      }

      // رسائل واتساب المباشرة خارج جدول التوجيه — في «كل الشركات» للشركة وحدها
      final blocked = MergedOps.unsupported(widget.sub);
      if (blocked != null) {
        _snack(blocked, isError: true);
        return;
      }
      final result = await WhatsAppApi.sendMessage(
        to: phone,
        message: message,
        sas4Idx: widget.sub.idx,
      );
      if (!mounted) return;
      if (result.ok) {
        final okMsg = 'qr_login.wa_sent'.tr();
        final chArabic = result.channelArabic;
        _snack(
          chArabic != null ? '$okMsg · عبر $chArabic' : okMsg,
          isError: false,
        );
      } else {
        _snack(result.message ?? 'qr_login.wa_send_failed'.tr(), isError: true);
      }
    } catch (e) {
      _snack('${'qr_login.wa_send_failed'.tr()}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sendingWa = false);
    }
  }

  Future<void> _copyLink() async {
    if (_linkUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _linkUrl!));
    _snack('common.copied'.tr(), isError: false);
  }

  Future<void> _openLink() async {
    if (_linkUrl == null) return;
    final uri = Uri.tryParse(_linkUrl!);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    showSheetSnack(context, msg, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.qrCode,
        title: 'qr_login.title'.tr(),
        subtitle: widget.sub.fullName.trim().isEmpty
            ? widget.sub.username
            : widget.sub.fullName,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.brand),
              const SizedBox(height: Sp.md),
              Text(
                'qr_login.generating'.tr(),
                style: AppType.subtitle(color: AppColors.textMid),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Sp.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.triangleAlert,
                    size: 40, color: AppColors.error),
                const SizedBox(height: Sp.md),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppType.subtitle(color: AppColors.textHi)
                      .copyWith(fontSize: 13),
                ),
                const SizedBox(height: Sp.md),
                OutlinedButton.icon(
                  onPressed: _generate,
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  label: Text('common.retry'.tr()),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // نجاح: نعرض الـQR + الأزرار
    return Column(
      children: [
        // QR
        Center(
          child: RepaintBoundary(
            key: _qrKey,
            child: Container(
              padding: const EdgeInsets.all(Sp.md),
              color: Colors.white,
              child: QrImageView(
                data: _linkUrl!,
                version: QrVersions.auto,
                size: 230,
                gapless: false,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
        ),
        const SizedBox(height: Sp.md),
        // Expiry line
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.clock, size: 12, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                _expiresLabel(),
                style: AppType.button(color: AppColors.brand)
                    .copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.sm),
        // أين يُمسح: من يفحص بكاميرا هاتفه يرى بطاقة معلومات من الساس لا
        // البوّابة، فيظنّ تعديلاته لا تظهر (تدقيق البوّابة ٢٠٢٦-١٠-١٧ §2.3).
        Text(
          'qr_login.scan_in_app'.tr(),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppType.muted(color: AppColors.textMid)
              .copyWith(fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: Sp.md),
        // Link preview
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceInput,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: Text(
                    _linkUrl!,
                    style: AppType.subtitle(color: AppColors.textMid)
                        .copyWith(fontSize: 10.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              InkWell(
                onTap: _copyLink,
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(LucideIcons.copy, size: 14, color: AppColors.brand),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: _openLink,
                borderRadius: BorderRadius.circular(R.sm),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(LucideIcons.externalLink,
                      size: 14, color: AppColors.brand),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        // Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sharing ? null : _shareQr,
                icon: _sharing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.share2, size: 14),
                label: Text(
                  'qr_login.share_or_save'.tr(),
                  style: AppType.button(color: AppColors.brand)
                      .copyWith(fontSize: 12.5),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: AppColors.brandSoftBorder),
                  foregroundColor: AppColors.brand,
                ),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _sendingWa ? null : _sendWhatsApp,
                icon: _sendingWa
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(LucideIcons.messageCircle, size: 14),
                label: Text(
                  'qr_login.send_wa'.tr(),
                  style: AppType.button(color: Colors.white)
                      .copyWith(fontSize: 12.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.channelWhatsApp,
                  foregroundColor: AppColors.onBrand,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _expiresLabel() {
    if (_expiresAt == null) {
      return 'qr_login.valid_30d'.tr();
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainMs = _expiresAt! - now;
    if (remainMs <= 0) return 'qr_login.expired'.tr();
    final days = (remainMs / (24 * 3600 * 1000)).floor();
    return 'qr_login.valid_for_days'.tr(namedArgs: {'d': days.toString()});
  }
}
