import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../api/api_client.dart';
import '../../api/sas_ftth_api.dart';
import '../../core/platform/app_platform.dart';
import '../../services/app_resumed_signal.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../topup/topup_pay_page.dart' show isFatalLoadError;

/// «المشروع الوطني» (١٩ نوفمبر — الوطني البصرة/الناصريّة): أقسام إضافة الساس نفسها — التذاكر، الطلبات، عروض الاشتراك، تفاصيل
/// الاشتراك — كما يرسمها ساس الشركة، في WebView على غلاف الخادم (`/sas-ftth/f/<id>/wrap` — إطارٌ معزول؛ صفحات الإضافة ترفض الفتح
/// خارج إطار). كالموقع (/v2/national): كلّ قسمٍ فُتح يبقى حيّاً مخفيّاً حين تنتقل لغيره، ويُجدَّد قبل انتهاء نافذته (ساعتان) حين يعود
/// للعرض أو يعود التطبيق للواجهة؛ «تحديث» نافذةٌ جديدة. الحاسبة (ويندوز — بلا WebView): كلّ قسمٍ يُفتح في المتصفّح.
class SasFtthScreen extends StatefulWidget {
  const SasFtthScreen({super.key, this.engineFactory, this.probe, this.mint});

  /// للاختبار: متصفّحٌ بديل (المنصّة لا تعمل في `flutter test`).
  final SasFtthEngineFactory? engineFactory;

  /// للاختبار: الأقسام بلا سؤال.
  final SasFtthProbe? probe;

  /// للاختبار: إصدار النافذة.
  final Future<SasFtthFrameResult> Function(String section)? mint;

  @override
  State<SasFtthScreen> createState() => _SasFtthScreenState();
}

/// تجديد النافذة قبل انتهائها (ساعتان بالخادم).
const sasFtthRefreshAfter = Duration(minutes: 100);

class _Tab {
  _Tab(this.engine);
  final SasFtthWebEngine engine;
  DateTime? at;
  bool loaded = false;
  bool loading = false;
  String? error;
}

class _SasFtthScreenState extends State<SasFtthScreen> {
  SasFtthProbe? _probe;
  bool _probing = true;
  String? _active;
  final Map<String, _Tab> _tabs = {};
  final Map<String, int> _gen = {};

  bool get _desktop => AppPlatform.isDesktop;

  @override
  void initState() {
    super.initState();
    AppResumedSignal.tick.addListener(_onResume);
    final given = widget.probe;
    if (given != null) {
      _probe = given;
      _probing = false;
      _pickFirst();
    } else {
      final cached = SasFtthState.gate.value;
      if (cached != null && cached.shown) {
        _probe = cached;
        _probing = false;
        _pickFirst();
      }
      unawaited(_loadSections());
    }
  }

  @override
  void dispose() {
    AppResumedSignal.tick.removeListener(_onResume);
    super.dispose();
  }

  Future<void> _loadSections() async {
    await SasFtthState.ensureFresh(force: _probe == null);
    if (!mounted) return;
    setState(() {
      _probe = SasFtthState.gate.value ?? _probe;
      _probing = false;
    });
    _pickFirst();
  }

  void _pickFirst() {
    final p = _probe;
    if (p == null || !p.shown) return;
    final keep = _active != null && p.sections.any((s) => s.key == _active);
    _select(keep ? _active! : p.sections.first.key);
  }

  void _onResume() {
    final a = _active;
    if (a != null) unawaited(_open(a));
  }

  void _select(String key) {
    if (_active != key) setState(() => _active = key);
    unawaited(_open(key));
  }

  Future<void> _open(String key, {bool force = false}) async {
    if (_desktop) return; // الحاسبة: زرّ «افتح في المتصفّح» يصدر نافذته عند النقر
    final t = _tabs[key];
    if (!force && t != null && (t.loading || (t.at != null && DateTime.now().difference(t.at!) < sasFtthRefreshAfter))) return;
    final gen = (_gen[key] ?? 0) + 1;
    _gen[key] = gen;
    final tab = t ?? _Tab(_newEngine(key));
    setState(() {
      _tabs[key] = tab;
      tab.loading = true;
      tab.error = null;
      tab.loaded = force ? false : tab.loaded;
    });
    final r = await (widget.mint ?? SasFtthApi.frame)(key);
    if (!mounted || _gen[key] != gen) return;
    final url = r.url == null ? null : sasFtthWrapUri(r.url!);
    if (url == null) {
      setState(() {
        tab.loading = false;
        tab.at = null;
        tab.error = r.message ?? 'تعذّر فتح القسم — حاول مرّةً أخرى';
      });
      return;
    }
    setState(() {
      tab.loading = false;
      tab.loaded = false;
      tab.at = DateTime.now();
    });
    await tab.engine.open(url);
  }

  SasFtthWebEngine _newEngine(String key) {
    final cb = SasFtthWebCallbacks(
      onLoaded: () {
        final t = _tabs[key];
        if (t != null && mounted && !t.loaded) setState(() => t.loaded = true);
      },
      onLoadError: () {
        final t = _tabs[key];
        if (t != null && mounted) setState(() => t.error = 'تعذّر تحميل القسم — تحقّق من الاتّصال وحاول مرّةً أخرى');
      },
    );
    return (widget.engineFactory ?? WebViewSasFtthEngine.new)(cb);
  }

  Future<void> _openInBrowser(String key) async {
    final r = await (widget.mint ?? SasFtthApi.frame)(key);
    if (!mounted) return;
    final url = r.url == null ? null : sasFtthWrapUri(r.url!);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'تعذّر فتح القسم')));
      return;
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = _active;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('المشروع الوطني', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
              Text('أقسام الوطني في ساس شركتك', style: AppType.muted().copyWith(fontSize: 11)),
            ],
          ),
          actions: [
            if (a != null && !_desktop)
              IconButton(
                tooltip: 'تحديث',
                icon: const Icon(LucideIcons.refreshCw, size: 20),
                onPressed: (_tabs[a]?.loading ?? false) ? null : () => _open(a, force: true),
              ),
          ],
        ),
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    final p = _probe;
    if (_probing && p == null) return const Center(child: CircularProgressIndicator());
    if (p == null) {
      return _Message(
        icon: LucideIcons.triangleAlert,
        title: 'تعذّرت قراءة الأقسام',
        text: 'تحقّق من الاتّصال وحاول مرّةً أخرى',
        action: ('إعادة المحاولة', () {
          setState(() => _probing = true);
          unawaited(_loadSections());
        }),
      );
    }
    if (!p.shown) {
      return const _Message(
        icon: LucideIcons.landmark,
        title: 'لا أقسام للمشروع الوطني',
        text: 'ساس هذه الشركة لا يحمل أقسام الوطني (التذاكر والطلبات والعروض وتفاصيل الاشتراك) لحسابك.',
      );
    }
    final a = _active ?? p.sections.first.key;
    final note = p.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
          child: SasFtthTabs(sections: p.sections, active: a, onSelect: _select),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
            child: Text(note, key: const ValueKey('sas-ftth-note'), style: AppType.muted().copyWith(fontSize: 12.5, height: 1.5)),
          ),
        const SizedBox(height: Sp.md),
        Expanded(child: _desktop ? _desktopBody(p, a) : _frames(p, a)),
      ],
    );
  }

  Widget _frames(SasFtthProbe p, String a) {
    final keys = [for (final s in p.sections) s.key];
    final idx = keys.indexOf(a);
    final t = _tabs[a];
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // صفحات الشركة فاتحةٌ دائماً — خلفيّتها بيضاء في الداكن أيضاً (لا وميضٌ أسود قبل الرسم)
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          IndexedStack(
            index: idx < 0 ? 0 : idx,
            children: [
              for (final k in keys)
                _tabs[k] == null ? const SizedBox.shrink() : KeyedSubtree(key: ValueKey('frame-$k'), child: _tabs[k]!.engine.view(context)),
            ],
          ),
          if (t?.error != null)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.surface,
                child: _Message(
                  icon: LucideIcons.triangleAlert,
                  title: 'تعذّر فتح القسم',
                  text: t!.error!,
                  action: ('إعادة المحاولة', () => _open(a, force: true)),
                ),
              ),
            )
          else if (t == null || t.loading || !t.loaded)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: AppColors.paper.withValues(alpha: 0.7),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: Sp.sm),
                        Text('جارٍ فتح القسم…', style: AppType.muted()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _desktopBody(SasFtthProbe p, String a) {
    final title = p.sections.firstWhere((s) => s.key == a, orElse: () => p.sections.first).title;
    return _Message(
      icon: LucideIcons.externalLink,
      title: title,
      text: 'يُفتح القسم في المتصفّح كما تعرضه الشركة نفسها — رابطٌ لساعتين باسم حسابك.',
      action: ('افتح في المتصفّح', () => _openInBrowser(a)),
    );
  }
}

/// تبويبات الأقسام: عمودان على الهاتف (اسمٌ طويل ينزل سطراً لا يُقصّ)، وصفٌّ واحد حين يتّسع.
class SasFtthTabs extends StatelessWidget {
  const SasFtthTabs({super.key, required this.sections, required this.active, required this.onSelect});

  final List<SasFtthSection> sections;
  final String active;
  final ValueChanged<String> onSelect;

  static IconData iconOf(String key) => switch (key) {
        'tickets' => LucideIcons.ticket,
        'requests' => LucideIcons.clipboardList,
        'offers' => LucideIcons.tags,
        'subscription_details' => LucideIcons.info,
        _ => LucideIcons.landmark,
      };

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 560 ? sections.length : 2;
      final rows = <Widget>[];
      for (var i = 0; i < sections.length; i += cols) {
        final chunk = sections.sublist(i, (i + cols).clamp(0, sections.length));
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) const SizedBox(width: 4),
                Expanded(child: j < chunk.length ? _tab(chunk[j]) : const SizedBox.shrink()),
              ],
            ],
          ),
        ));
      }
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.surfaceInput, borderRadius: BorderRadius.circular(R.md)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              rows[i],
            ],
          ],
        ),
      );
    });
  }

  Widget _tab(SasFtthSection s) {
    final on = s.key == active;
    return Semantics(
      selected: on,
      button: true,
      child: InkWell(
        key: ValueKey('sas-ftth-tab-${s.key}'),
        onTap: () => onSelect(s.key),
        borderRadius: BorderRadius.circular(R.sm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(R.sm),
            border: on ? Border.all(color: AppColors.border) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconOf(s.key), size: 16, color: on ? AppColors.brandAccent : AppColors.textMid),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s.title,
                  textAlign: TextAlign.center,
                  style: AppType.bodyStrong(color: on ? AppColors.textHi : AppColors.textMid).copyWith(fontSize: 13.5, height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, this.action});

  final IconData icon;
  final String title;
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppColors.textMid),
            const SizedBox(height: Sp.md),
            Text(title, textAlign: TextAlign.center, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
            const SizedBox(height: Sp.sm),
            Text(text, textAlign: TextAlign.center, style: AppType.muted().copyWith(height: 1.5)),
            if (action != null) ...[
              const SizedBox(height: Sp.lg),
              OutlinedButton.icon(
                onPressed: action!.$2,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(action!.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ المتصفّح ═════════════════════════

class SasFtthWebCallbacks {
  const SasFtthWebCallbacks({required this.onLoaded, required this.onLoadError});

  /// انتهى تحميل صفحة (الغلاف أو تنقّلٌ داخله).
  final void Function() onLoaded;
  final void Function() onLoadError;
}

/// المتصفّح خلف القسم — WebView حقيقيّ في التطبيق، وبديلٌ في الاختبار.
abstract class SasFtthWebEngine {
  Widget view(BuildContext context);
  Future<void> open(Uri url);
}

typedef SasFtthEngineFactory = SasFtthWebEngine Function(SasFtthWebCallbacks callbacks);

/// تنقّلٌ يبقى داخل الـWebView: خادمنا وحده (الغلاف والممرّ)، و`about:blank`/`data:`. غيره (رابطٌ خارجيّ في صفحة الشركة) يُفتح
/// خارج التطبيق — لا موقعٌ آخر داخله.
bool sasFtthKeepsInside(String url, {String base = ApiClient.baseUrl}) {
  if (url.startsWith('about:') || url.startsWith('data:') || url.startsWith('blob:')) return true;
  final u = Uri.tryParse(url);
  final b = Uri.parse(base);
  return u != null && u.scheme == 'https' && u.host == b.host;
}

/// الـWebView الحقيقيّ: جافاسكربت (الصفحات تحتاجه) بلا جسور؛ أندرويد: اختيار الملفّات (مستمسكات التذكرة/الزبون — كاميرا حين
/// تطلبها الصفحة) وإذن الموقع (زبونٌ جديد على الخريطة) بإذن النظام؛ آيفون يعرضهما بنفسه. أخطاء الشهادة تُرفض (الافتراضيّ).
class WebViewSasFtthEngine implements SasFtthWebEngine {
  WebViewSasFtthEngine(SasFtthWebCallbacks cb) {
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (sasFtthKeepsInside(r.url)) return NavigationDecision.navigate;
          if (r.isMainFrame) {
            final u = Uri.tryParse(r.url);
            if (u != null && (u.scheme == 'https' || u.scheme == 'http')) {
              unawaited(launchUrl(u, mode: LaunchMode.externalApplication));
            }
          }
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) => cb.onLoaded(),
        onWebResourceError: (e) {
          if (isFatalLoadError(type: e.errorType, code: e.errorCode, mainFrame: e.isForMainFrame)) cb.onLoadError();
        },
      ));
    final p = _c.platform;
    if (p is AndroidWebViewController) {
      unawaited(p.setOnShowFileSelector(_pickFiles));
      unawaited(p.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (req) async => GeolocationPermissionsResponse(allow: await _locationAllowed(), retain: false),
      ));
    }
  }

  late final WebViewController _c;

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

  static Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final images = params.acceptTypes.isNotEmpty && params.acceptTypes.every((t) => t.startsWith('image/'));
      if (params.isCaptureEnabled && images) {
        final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
        return f == null ? const [] : [Uri.file(f.path).toString()];
      }
      final groups = images ? const [XTypeGroup(label: 'صور', mimeTypes: ['image/*'])] : const <XTypeGroup>[];
      if (params.mode == FileSelectorMode.openMultiple) {
        final fs = await openFiles(acceptedTypeGroups: groups);
        return [for (final f in fs) Uri.file(f.path).toString()];
      }
      final f = await openFile(acceptedTypeGroups: groups);
      return f == null ? const [] : [Uri.file(f.path).toString()];
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 [SasFtth] pick: ${e.runtimeType}');
      return const [];
    }
  }

  static Future<bool> _locationAllowed() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }
}
