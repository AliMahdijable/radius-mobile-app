import 'dart:io';
import 'dart:typed_data';
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
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// Bottom sheet لتوليد رمز QR دخول المشترك (30 يوم). المشترك يمسحه
/// من تطبيق البورتال فيسجّل دخول تلقائياً بلا كتابة username/password.
Future<void> showQrLoginSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SheetScaffold(child: _QrLoginSheet(sub: sub)),
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
    final r = await SubscribersApi.generatePortalQrToken(idx: idx);
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
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
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
        text:
            'مرحباً $greet 👋\n\nهذا رمز QR لتسجيل دخولك في تطبيق بوابة المشترك:\n\n${_linkUrl!}\n\nالرمز صالح لمدة 30 يوم.',
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
      final message = 'مرحباً $greet 👋\n\n'
          'هذا رمز QR لتسجيل دخولك في تطبيق بوابة المشترك:\n\n'
          '${_linkUrl!}\n\n'
          'الرمز صالح لمدة 30 يوم. لو انتهى، اطلب واحد جديد من الأدمن.\n\n'
          'شكراً 🙏';
      final result = await WhatsAppApi.sendMessage(to: phone, message: message);
      if (!mounted) return;
      if (result.ok) {
        _snack('qr_login.wa_sent'.tr(), isError: false);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMid.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: Icon(LucideIcons.qrCode,
                        size: 18, color: AppColors.brand),
                  ),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'qr_login.title'.tr(),
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.sub.fullName.trim().isEmpty
                              ? widget.sub.username
                              : widget.sub.fullName,
                          style: AppType.subtitle(color: AppColors.textMid)
                              .copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.textMid,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Sp.md),
              _buildBody(),
            ],
          ),
        ),
      ),
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
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.08),
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
        const SizedBox(height: Sp.md),
        // Link preview
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.md, vertical: Sp.sm),
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
                        .copyWith(fontSize: 10),
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
                  child: Icon(LucideIcons.copy,
                      size: 14, color: AppColors.brand),
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
                      .copyWith(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: AppColors.brand.withOpacity(0.4)),
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
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(LucideIcons.messageCircle, size: 14),
                label: Text(
                  'qr_login.send_wa'.tr(),
                  style: AppType.button(color: Colors.white)
                      .copyWith(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
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
