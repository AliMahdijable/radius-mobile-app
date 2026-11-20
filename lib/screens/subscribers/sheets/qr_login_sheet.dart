import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../api/subscribers_api.dart';
import '../../../api/whatsapp_api.dart';
import '../../../models/subscriber.dart';
import '../../../services/image_saver.dart';
import '../../../services/merged_mode.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../widgets/manual_wa_chip.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';

/// اسم تطبيق المشترك كما يراه على هاتفه في المتجرين: «MyServices» (كان «MySub»،
/// وأبل طلبت ترك الاسم القديم) — كـ`SubscriberApp.name` في تبويب «رمز الوكيل».
const _portalApp = 'MyServices';

/// زرّ الدخول بالرمز في شاشة دخول ذلك التطبيق (2.0.7) بنصّه حرفيّاً — كان
/// «تسجيل الدخول بواسطة QR» في نسخته القديمة (باسم MySub).
const _portalQrButton = 'الدخول برمز QR من وكيلك';

/// نصّ المشاركة وتعليق الصورة المرسلة بواتساب — يرافق صورة الرمز.
///
/// ١٩ نوفمبر (المالك: «رابط معرفة الاشتراك… نريد نلغيه بالتطبيق وبالويب»): لا رابط في أيّ نصّ — الرمز صورةٌ تُمسح من داخل
/// تطبيق المشترك (كاميرا الهاتف تفتح صفحة تعليماتٍ وحدها). قبله (تدقيق البوّابة ٢٠٢٦-١٠-١٧ §2.3) كان الرابط «معلومات اشتراكك».
String qrShareText({required String greet}) =>
    'مرحباً $greet 👋\n\n'
    'للدخول إلى تطبيق $_portalApp: افتح التطبيق واختر «$_portalQrButton»'
    '، ثمّ امسح هذا الرمز أو ارفع صورته من المعرض.\n\n'
    'الرمز صالح لمدة 30 يوم.';

/// Bottom sheet لتوليد رمز QR دخول المشترك (30 يوم). المشترك يمسحه
/// من **داخل** تطبيق MyServices فيسجّل دخول تلقائياً بلا كتابة username/password
/// (كاميرا الهاتف تفتح صفحة تعليماتٍ وحدها). الرمز يُحفظ صورةً، يُشارَك، أو يُرسَل للمشترك بواتساب — بلا رابط.
/// التقاط صورة الرمز — يُستبدل في الاختبارات (لا رسم حقيقيّاً هناك): يأخذ الدقّة ويعيد بايتات PNG.
@visibleForTesting
Future<Uint8List?> Function(double pixelRatio)? debugQrCapture;

/// نافذة المشاركة — تُستبدل في الاختبارات (لا قناة منصّة هناك).
@visibleForTesting
Future<void> Function(Uint8List bytes, String text)? debugQrShare;

Future<void> showQrLoginSheet(BuildContext context, Subscriber sub) {
  return showAppSheet(
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
  bool _saving = false;
  bool _sendingWa = false;
  final GlobalKey _qrKey = GlobalKey();

  /// أقصى حجمٍ لصورةٍ تمرّ بالخادم (محلّل الجسم العامّ هناك 100KB، والترميز يزيد الثلث).
  static const int _maxSendBytes = 70 * 1024;

  String get _greet => widget.sub.fullName.trim().isNotEmpty ? widget.sub.fullName.trim() : widget.sub.username;

  /// اسم ملفّ الصورة (لاتينيّ آمن) — باسم المشترك حتى تُعرف بين الصور.
  String get _fileStem => 'myservices_qr_${ImageSaver.safeName(widget.sub.username)}';

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

  Future<Uint8List?> _captureQr({double pixelRatio = 3.5}) async {
    final fake = debugQrCapture;
    if (fake != null) return fake(pixelRatio);
    try {
      final ctx = _qrKey.currentContext;
      if (ctx == null) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// صورةٌ تمرّ بالخادم: تُخفَّض الدقّة حتى ≤ [_maxSendBytes] (الرمز يبقى مقروءاً)؛ null إن لم تصغر كفايةً أو تعذّر الالتقاط.
  Future<Uint8List?> _captureForSend() async {
    for (final ratio in const [2.5, 1.8, 1.3]) {
      final bytes = await _captureQr(pixelRatio: ratio);
      if (bytes == null) return null;
      if (bytes.length <= _maxSendBytes) return bytes;
    }
    return null;
  }

  /// «حفظ الصورة»: بالهاتف إلى الصور، وبالحاسبة حيث يختار. هاتفٌ بلا حفظٍ مباشر (أندرويد أقدم من 10) ⇒ نافذة المشاركة.
  Future<void> _saveQr() async {
    if (_saving || _linkUrl == null) return;
    setState(() => _saving = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final bytes = await _captureQr();
      if (bytes == null) {
        _snack('qr_login.capture_failed'.tr(), isError: true);
        return;
      }
      final r = await ImageSaver.savePng(bytes, name: _fileStem);
      if (!mounted) return;
      switch (r) {
        case ImageSaveResult.saved:
          _snack('qr_login.saved'.tr(), isError: false);
        case ImageSaveResult.cancelled:
          break;
        case ImageSaveResult.denied:
          _snack('qr_login.save_denied'.tr(), isError: true);
        case ImageSaveResult.unsupported:
          _snack('qr_login.save_use_share'.tr(), isError: false);
          await _shareBytes(bytes);
        case ImageSaveResult.failed:
          _snack('qr_login.save_failed'.tr(), isError: true);
      }
    } catch (e) {
      if (mounted) _snack('qr_login.save_failed'.tr(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// نافذة المشاركة بصورة الرمز ونصّه (بلا رابط).
  Future<void> _shareBytes(Uint8List bytes) async {
    final text = qrShareText(greet: _greet);
    final fake = debugQrShare;
    if (fake != null) return fake(bytes, text);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileStem}_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);

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
      text: text,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _shareQr() async {
    if (_sharing || _linkUrl == null) return;
    // 2026-07-13: crash تقارير على Android+iOS (toImage قبل الرسم، وiPad بلا sharePositionOrigin) ⇒ انتظار frame واحد قبل
    // الالتقاط، والموضع من الـcontext (_shareBytes).
    setState(() => _sharing = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final bytes = await _captureQr();
      if (bytes == null) {
        _snack('qr_login.capture_failed'.tr(), isError: true);
        return;
      }
      await _shareBytes(bytes);
    } catch (e) {
      if (mounted) {
        _snack('${'qr_login.share_failed'.tr()}: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// «إرسال بواتساب»: صورة الرمز بتعليقها من واتساب الصفحة (الخادم) — أو «واتسابي» ⇒ نافذة المشاركة (رابط wa.me لا يحمل صورة).
  Future<void> _sendWhatsApp() async {
    if (_sendingWa || _linkUrl == null) return;
    final phone = widget.sub.displayPhone;
    if (phone.isEmpty) {
      _snack('subscribers.no_phone'.tr(), isError: true);
      return;
    }
    setState(() => _sendingWa = true);
    try {
      final caption = qrShareText(greet: _greet);
      // 2026-08-26: preview sheet مع chip auto/manual لهذه العمليّة أيضاً.
      if (!mounted) return;
      final choice = await showManualWaPreviewSheet(
        context,
        title: 'رمز QR دخول',
        phone: phone,
        messagePreview: caption,
        accent: const Color(0xFF7C3AED),
        // «كل الشركات» (٢١ نوفمبر): التلقائيّ يخرج من واتساب شركة المشترك نفسها (send-media موجَّه بمدير شركته أدناه) — صفحة
        // موظّفٍ كتابتها مقفلةٌ من هنا ⇒ «افتح واتسابي» وحده وسببها قبل التأكيد.
        autoBlockedReason: MergedOps.writeLock(widget.sub),
      );
      if (!mounted || choice == null || !choice.confirmed) return;

      if (choice.manualMode) {
        final bytes = await _captureQr();
        if (!mounted) return;
        if (bytes == null) {
          _snack('qr_login.capture_failed'.tr(), isError: true);
          return;
        }
        _snack('qr_login.manual_share_hint'.tr(), isError: false);
        await _shareBytes(bytes);
        return;
      }

      final locked = MergedOps.writeLock(widget.sub);
      if (locked != null) {
        _snack(locked, isError: true);
        return;
      }
      final bytes = await _captureForSend();
      if (!mounted) return;
      if (bytes == null) {
        _snack('qr_login.capture_failed'.tr(), isError: true);
        return;
      }
      // «كل الشركات» (٢١ نوفمبر): من واتساب شركة المشترك — موجَّهٌ لها بمعرّف مديرها (الخادم whatsapp-send-media bodyAdmin)؛
      // بلا مفتاح كما كان.
      final result = await MergedOps.run(
        widget.sub,
        () => WhatsAppApi.sendMedia(
          to: phone,
          bytes: bytes,
          filename: '$_fileStem.png',
          caption: caption,
          sas4Idx: widget.sub.idx,
        ),
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
            // ما يُحفظ ويُرسَل: الرمز وتحته اسم المشترك وما هو — صورةٌ تُعرف بين الصور، بيضاء في الوضعين
            child: Container(
              padding: const EdgeInsets.all(Sp.md),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
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
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 230,
                    child: Text(
                      _greet,
                      key: const ValueKey('qr-image-name'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title(color: Colors.black).copyWith(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: Text(
                      'qr_login.image_caption'.tr(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: Colors.black54).copyWith(fontSize: 10.5),
                    ),
                  ),
                ],
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
              Icon(_expired ? LucideIcons.clock : LucideIcons.infinity, size: 12, color: AppColors.brand),
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
        // أين يُمسح: من داخل تطبيق المشترك وحده (كاميرا الهاتف تفتح صفحة تعليمات).
        Text(
          'qr_login.scan_in_app'.tr(),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppType.muted(color: AppColors.textMid)
              .copyWith(fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: Sp.md),
        // Actions — حفظ · مشاركة ثمّ إرسال للمشترك
        Row(
          children: [
            Expanded(
              child: _outlineAction(
                key: const ValueKey('qr-save'),
                busy: _saving,
                icon: LucideIcons.download,
                label: 'qr_login.save'.tr(),
                onPressed: _saveQr,
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _outlineAction(
                key: const ValueKey('qr-share'),
                busy: _sharing,
                icon: LucideIcons.share2,
                label: 'qr_login.share'.tr(),
                onPressed: _shareQr,
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const ValueKey('qr-send-wa'),
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
    );
  }

  Widget _outlineAction({
    required Key key,
    required bool busy,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 14),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.button(color: AppColors.brand).copyWith(fontSize: 12.5),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: AppColors.brandSoftBorder),
        foregroundColor: AppColors.brand,
      ),
    );
  }

  /// رمزٌ انتهى فعلاً (قديمٌ عُرض قبل تحديث الخادم).
  bool get _expired {
    final exp = _expiresAt;
    return exp != null && exp <= DateTime.now().millisecondsSinceEpoch;
  }

  /// (١٩ نوفمبر — المالك: «الوكيل جاي يرتبك من يشوف تحت qr من يولده ٢٩ يووم»): بعد المسح يبقى المشترك مسجّلاً على هاتفه (جلسته
  /// تتجدّد وحدها، والرمز نفسه سنة) — فلا عدّاد أيّام يُفهم أنّ الدخول ينتهي بعده.
  String _expiresLabel() => (_expired ? 'qr_login.expired' : 'qr_login.stays_signed_in').tr();
}
