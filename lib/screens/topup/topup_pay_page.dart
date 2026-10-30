import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'pay_nav_policy.dart';

/// نتيجة صفحة الدفع.
@immutable
class PayPageResult {
  /// رجعت الصفحة إلى الساس — [returnUrl] فيه توكن زين كاش.
  const PayPageResult.captured(String this.returnUrl);

  /// أغلقها المدير قبل الرجوع.
  const PayPageResult.closed() : returnUrl = null;

  final String? returnUrl;
  bool get captured => returnUrl != null;
}

/// ما يُبلّغه المتصفّح للصفحة.
@immutable
class PayWebCallbacks {
  const PayWebCallbacks({
    required this.onNavigation,
    required this.onUrl,
    required this.onProgress,
    required this.onLoadError,
  });

  /// تنقّلٌ يوشك أن يبدأ — `true` = يُحمَّل.
  final bool Function(String url, {required bool mainFrame}) onNavigation;

  /// الرابط تغيّر (بدأت صفحة، أو تغيّر الهاش) — شبكة أمانٍ ثانية للالتقاط.
  final void Function(String url) onUrl;
  final void Function(int percent) onProgress;
  final void Function() onLoadError;
}

/// المتصفّح خلف الصفحة — WebView حقيقيّ في التطبيق، وبديلٌ في الاختبار
/// (المنصّة لا تعمل في `flutter test`).
abstract class PayWebEngine {
  Widget view(BuildContext context);
  Future<void> open(Uri url);
  Future<void> reload();

  /// يمحو الكوكيز والكاش والتخزين — قبل الفتح (لا تبقى جلسة زين كاش لمديرٍ
  /// سابق على الهاتف) وبعد الإغلاق.
  Future<void> wipe();
}

typedef PayWebEngineFactory = PayWebEngine Function(PayWebCallbacks callbacks);

/// الـWebView الحقيقيّ.
///
/// • جافاسكربت مفعّل (صفحة زين كاش تحتاجه) — **بلا جسور** (لا
///   `JavaScriptChannel`): الصفحة لا تخاطب التطبيق بشيء.
/// • أخطاء الشهادة تُرفض (السلوك الافتراضيّ حين لا يُضبط `onSslAuthError`).
/// • لا رفع ملفّات ولا نوافذ جديدة ولا تطبيقات خارجيّة.
class WebViewPayEngine implements PayWebEngine {
  WebViewPayEngine(PayWebCallbacks cb) {
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) =>
            cb.onNavigation(r.url, mainFrame: r.isMainFrame)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
        onPageStarted: cb.onUrl,
        onUrlChange: (c) {
          final u = c.url;
          if (u != null) cb.onUrl(u);
        },
        onProgress: cb.onProgress,
        onWebResourceError: (e) {
          if (isFatalLoadError(
              type: e.errorType, code: e.errorCode, mainFrame: e.isForMainFrame)) {
            cb.onLoadError();
          }
        },
      ));
  }

  late final WebViewController _c;

  /// أندرويد: Hybrid Composition — الصفحة عرضٌ أندرويديّ حقيقيّ في الشجرة، لا نسيجٌ يُستورد في Vulkan. على
  /// كرتٍ لا يدعم AHardwareBuffer (محاكي MuMu، ٣٠ أكتوبر: «يصير كراش ويخرج» لحظة فتح صفحة البطاقة — SIGABRT في
  /// vkFreeMemory على خيط الرسم) يطيح الطريق الافتراضيّ (TLHC). ولصفحة إدخالٍ (رقم المحفظة، رمز التحقّق) هو
  /// الأثبت أصلاً؛ كلفته الأداء لا يعني صفحةً قصيرة العمر.
  @override
  Widget view(BuildContext context) {
    final p = _c.platform;
    if (p is AndroidWebViewController) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(controller: p, displayWithHybridComposition: true),
      );
    }
    return WebViewWidget(controller: _c);
  }

  @override
  Future<void> open(Uri url) => _c.loadRequest(url);

  @override
  Future<void> reload() => _c.reload();

  @override
  Future<void> wipe() async {
    await Future.wait<Object?>([
      WebViewCookieManager().clearCookies(),
      _c.clearCache(),
      _c.clearLocalStorage(),
    ]);
  }
}

/// خطأ تحميلٍ يستحقّ «تعذّر التحميل»؟ — لا لتنقّلٍ منعناه نحن (التقاط
/// الرجوع، رابطٌ خارجيّ)، ولا لإطارٍ داخليّ.
///
/// أندرويد يصنّف الخطأ ([type])؛ آيفون يرسل رمز `NSError` وحده: السالب أخطاء
/// شبكة (‎-1009 لا نت، ‎-1001 مهلة، ‎-1200 شهادة…) عدا ‎-999 (أُلغي) و‎-1002
/// (رابطٌ غير مدعوم)، والموجب أخطاء WebKit (‎102 «أوقفته السياسة» = منعنا).
bool isFatalLoadError({
  WebResourceErrorType? type,
  required int code,
  bool? mainFrame,
}) {
  if (mainFrame == false) return false;
  if (type != null) {
    return switch (type) {
      WebResourceErrorType.hostLookup ||
      WebResourceErrorType.connect ||
      WebResourceErrorType.timeout ||
      WebResourceErrorType.failedSslHandshake ||
      WebResourceErrorType.io ||
      WebResourceErrorType.redirectLoop ||
      WebResourceErrorType.badUrl ||
      WebResourceErrorType.tooManyRequests ||
      WebResourceErrorType.webContentProcessTerminated ||
      WebResourceErrorType.unknown =>
        true,
      _ => false,
    };
  }
  return code < 0 && code != -999 && code != -1002;
}

/// صفحة الدفع داخل التطبيق — زين كاش.
///
/// ⚠️ **لماذا لا متصفّحٌ خارجيّ ولا Custom Tabs:** زين كاش يرجع بعد الدفع إلى
/// رابط الساس `#/zaincash/process?token=…`، والساس لا يضيف الرصيد إلّا إن
/// أُرسل له هذا التوكن بجلسة المدير. المتصفّح الخارجيّ بلا جلسة الساس ولا
/// نملك رجوعه — فيُخصم المال ولا يُضاف شيء. هنا يُلتقط الرجوع قبل أن يُحمَّل
/// ([PayNavPolicy])، ويُحفظ ([onCaptured]) ثمّ يُسلَّم لخادمنا.
///
/// والإغلاق قبل الرجوع يُسأل عنه: من دفع وأغلق قبل الرجوع يتأخّر رصيده حتى
/// يُتحقَّق منه.
class TopupPayPage extends StatefulWidget {
  const TopupPayPage({
    super.key,
    required this.payUrl,
    required this.policy,
    required this.methodLabel,
    this.onCaptured,
    this.engineFactory,
  });

  final Uri payUrl;
  final PayNavRule policy;

  /// «زين كاش».
  final String methodLabel;

  /// يُنادى بالرابط الملتقَط **قبل** إغلاق الصفحة — ليُحفظ أوّلاً.
  final Future<void> Function(String returnUrl)? onCaptured;

  final PayWebEngineFactory? engineFactory;

  /// للاختبار وحده: متصفّحٌ بديل.
  @visibleForTesting
  static PayWebEngineFactory? debugEngineFactory;

  @override
  State<TopupPayPage> createState() => _TopupPayPageState();
}

class _TopupPayPageState extends State<TopupPayPage> {
  late final PayWebEngine _engine;
  late String _host = widget.payUrl.host;
  int _progress = 0;
  bool _failed = false;
  bool _capturing = false;

  /// انتهت الصفحة (التُقط الرجوع أو أُغلقت) — لا نتيجة ثانية.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final factory = widget.engineFactory ??
        TopupPayPage.debugEngineFactory ??
        WebViewPayEngine.new;
    _engine = factory(PayWebCallbacks(
      onNavigation: _onNavigation,
      onUrl: _onUrl,
      onProgress: _onProgress,
      onLoadError: _onLoadError,
    ));
    _start();
  }

  Future<void> _start() async {
    try {
      await _engine.wipe().timeout(const Duration(seconds: 3));
    } catch (_) {/* المحو أفضل جهد — لا يمنع الدفع */}
    if (!mounted || _done) return;
    try {
      await _engine.open(widget.payUrl);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  bool _onNavigation(String url, {required bool mainFrame}) {
    if (_done) return false;
    switch (widget.policy.decide(url)) {
      case PayNavAction.capture:
        _capture(url);
        return false;
      case PayNavAction.allow:
        if (mainFrame) _noteHost(url);
        return true;
      case PayNavAction.block:
        // الإطارات الداخليّة لصفحة الدفع تمضي؛ الرئيسيّ وحده يُمنع.
        if (!mainFrame) return true;
        _noteBlocked();
        return false;
    }
  }

  void _onUrl(String url) {
    if (_done) return;
    if (widget.policy.decide(url) == PayNavAction.capture) {
      _capture(url);
    } else {
      _noteHost(url);
    }
  }

  void _onProgress(int p) {
    if (!mounted || _done) return;
    setState(() => _progress = p.clamp(0, 100));
  }

  void _onLoadError() {
    if (!mounted || _done) return;
    setState(() => _failed = true);
  }

  void _noteHost(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return;
    if (u.host != _host && mounted) setState(() => _host = u.host);
  }

  DateTime? _blockedAt;

  void _noteBlocked() {
    final now = DateTime.now();
    final last = _blockedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _blockedAt = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('هذا الرابط يخرج من صفحة الدفع — أكمل الدفع هنا'),
      ));
  }

  Future<void> _capture(String url) async {
    if (_done) return;
    _done = true;
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _capturing = true);
    try {
      await widget.onCaptured?.call(url);
    } catch (_) {/* الحفظ أفضل جهد — الرابط يعود مع النتيجة أيضاً */}
    await _finish(PayPageResult.captured(url));
  }

  Future<void> _finish(PayPageResult result) async {
    try {
      await _engine.wipe().timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (!mounted) return;
    final nav = Navigator.of(context);
    final me = ModalRoute.of(context);
    // 🐛 الرجوع قد يصل وسؤال «إغلاق صفحة الدفع؟» مفتوحٌ فوقها: `pop` وحده
    // يُغلق السؤال لا الصفحة، فتبقى عالقةً بلا مخرج (`_done` يمنع الإغلاق،
    // و`PopScope` يمنع الرجوع). فيُغلق ما فوقها أوّلاً ثمّ هي.
    if (me != null && !me.isCurrent) nav.popUntil((r) => r == me);
    nav.pop(result);
  }

  Future<void> _askClose() async {
    if (_done) return;
    final sure = await showConfirmSheet(
      context,
      title: 'إغلاق صفحة الدفع؟',
      message: 'إن كنت دفعت فانتظر حتى يرجع التطبيق وحده — بالإغلاق الآن '
          'قد يتأخّر الرصيد حتى يُتحقَّق منه.\nوإن لم تدفع فلن يُخصم شيء.',
      confirmLabel: 'إغلاق',
      cancelLabel: 'متابعة الدفع',
      icon: LucideIcons.triangleAlert,
      tone: AppTone.warning,
    );
    if (sure != true || _done || !mounted) return;
    _done = true;
    await _finish(const PayPageResult.closed());
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    try {
      await _engine.reload();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final loading = _progress < 100 && !_failed && !_capturing;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askClose();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: Sp.xs,
          leading: IconButton(
            onPressed: _askClose,
            tooltip: 'إغلاق',
            icon: Icon(LucideIcons.x, color: AppColors.textHi, size: 22),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الدفع عبر ${widget.methodLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 16),
              ),
              const SizedBox(height: Sp.xxs),
              // المضيف وقفله — كما يفعل كلّ متصفّح: المدير يرى أنّها صفحة
              // زين كاش نفسها قبل أن يكتب رقم محفظته.
              Row(
                children: [
                  Icon(LucideIcons.lock, size: 11, color: AppColors.success),
                  const SizedBox(width: Sp.xs),
                  Flexible(
                    child: Text(
                      _host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: SizedBox(
              height: 2,
              child: loading
                  ? LinearProgressIndicator(
                      value: _progress <= 0 ? null : _progress / 100,
                      minHeight: 2,
                      color: AppColors.brandAccent,
                      backgroundColor: Colors.transparent,
                    )
                  : null,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _engine.view(context)),
                  if (_failed && !_capturing)
                    Positioned.fill(child: _LoadFailed(onRetry: _retry)),
                  if (_capturing) const Positioned.fill(child: _Confirming()),
                ],
              ),
            ),
            const _SafetyNote(),
          ],
        ),
      ),
    );
  }
}

/// سطرٌ ثابت أسفل الصفحة: ما يحفظ مال المدير.
class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: AppColors.textMid),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  'لا تغلق الصفحة بعد الدفع — يرجع التطبيق وحده',
                  style: AppType.body(color: AppColors.textBody)
                      .copyWith(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.wifiOff, size: 36, color: AppColors.textLow),
              const SizedBox(height: Sp.md),
              Text('تعذّر تحميل صفحة الدفع',
                  textAlign: TextAlign.center,
                  style: AppType.cardTitleBold(color: AppColors.textHi)),
              const SizedBox(height: Sp.xs),
              Text('تحقّق من الاتصال ثمّ أعد المحاولة',
                  textAlign: TextAlign.center,
                  style: AppType.body(color: AppColors.textMid)),
              const SizedBox(height: Sp.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Confirming extends StatelessWidget {
  const _Confirming();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: AppColors.brandAccent),
            ),
            const SizedBox(height: Sp.lg),
            Text('جارٍ تأكيد الدفع…',
                style: AppType.cardTitleBold(color: AppColors.textHi)),
            const SizedBox(height: Sp.xs),
            Text('لا تغلق التطبيق',
                style: AppType.body(color: AppColors.textMid)),
          ],
        ),
      ),
    );
  }
}
