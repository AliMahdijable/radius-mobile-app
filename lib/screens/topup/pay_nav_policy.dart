import '../../api/self_deposit_api.dart';
import 'wallet_app_link.dart';

/// ما يُفعل بتنقّلٍ في صفحة الدفع.
enum PayNavAction {
  /// صفحة زين كاش وما يتبعها — تُحمَّل.
  allow,

  /// الرجوع إلى الساس — **لا يُحمَّل**: يُلتقط رابطه (وفيه التوكن) ويُسلَّم
  /// لخادمنا. الساس في هذا المتصفّح بلا جلسة، فلو حُمِّل لما أُضيف شيء.
  capture,

  /// ما لا يلزم الدفع: رابطٌ غير مشفَّر، أو تطبيقٌ خارجيّ (`intent:`،
  /// `tel:`…) يُخرج الدفع من هنا فيضيع رجوعه، أو `javascript:`/`data:`.
  block,

  /// رابط تطبيق محفظةٍ مسجَّل أعطته صفحة الدفع ([WalletAppLink] — SuperQi): **لا يُحمَّل هنا** بل يُفتح بتطبيقه،
  /// وتبقى صفحة الدفع مفتوحةً تنتظر النتيجة وتلتقط الرجوع.
  external,
}

/// قاعدة تنقّلٍ لصفحة الدفع ([TopupPayPage]) — منطقٌ صافٍ يُختبر وحده.
abstract interface class PayNavRule {
  PayNavAction decide(String url);

  /// سكربتٌ يُحقن في الصفحة [url] بعد تحميلها، أو null.
  String? scriptFor(String url);
}

/// قاعدة التنقّل في صفحة الدفع — منطقٌ صافٍ بلا WebView، فيُختبر وحده.
///
/// الرجوع رابطٌ **يحمل دليل الدفع** (`token=` أو `waiting_webhook=1`، في الهاش
/// أو الاستعلام) ويُعرف موضعه بطريقين، يكفي أحدهما:
///   ١. **المضيف**: مضيف الساس (من الخادم مع رابط الدفع).
///   ٢. **المسار**: `#/zaincash/process` أو `#/zaincashv2/process` (أو مسارٌ
///      أرسله الخادم) — للساس نفسه بمضيفٍ آخر (رقم IP بدل الاسم مثلاً).
///      ولا يُطبَّق على مضيف صفحة الدفع نفسها، فلا يلتقطها رابطٌ يحمل مسار
///      الرجوع في معاملاته.
///
/// ⚠️ **بلا دليلٍ لا التقاط.** رابطٌ إلى الساس بلا توكن (تحويلٌ وسيطٌ قد يصل
/// بلا هاشه) لو التُقط لأُوقف التحميل ولما جاء بعده الرابط الكامل، ولرفضه
/// الخادم («ليس رابط رجوع») فضاع الدفع. فيُترك يُحمَّل — الساس هنا بلا جلسة
/// فلا يُنفّذ شيئاً — ويُلتقط الرابط الكامل حين يظهر (`onUrlChange`).
///
/// **والالتقاط الأوسع من قبول الخادم مقصود:** ما يحمل دليلاً ولا يعرفه الخادم
/// (مسارٌ عارٍ على مضيفٍ غير المسجَّل مثلاً) لا يُرفض هناك فيضيع — يحفظه مشفّراً
/// للمراجعة ويردّ `received` (sasSelfDeposit.complete). أمّا تركه يُحمَّل هنا
/// فيُضيّع الرمز يقيناً (الساس بلا جلسة). والمضيف يُطبَّع بلا نقطةٍ ختاميّة في
/// الطرفين.
class PayNavPolicy implements PayNavRule {
  PayNavPolicy({
    required this.capture,
    required Uri payUrl,
    Iterable<String> payHosts = const [],
  }) : _payHosts = {
          _norm(payUrl.host),
          for (final h in payHosts) _norm(h),
        }..remove('');

  final SelfDepositCapture capture;
  final Set<String> _payHosts;

  static String _norm(String host) {
    final h = host.trim().toLowerCase();
    return h.endsWith('.') ? h.substring(0, h.length - 1) : h;
  }

  /// يحمل دليل الدفع؟ — التوكن أو انتظار إشعار زين كاش، في الهاش أو الاستعلام.
  static bool hasProof(Uri u) {
    final frag = u.fragment;
    final q = frag.indexOf('?');
    Map<String, String> fragQuery = const {};
    if (q >= 0) {
      try {
        fragQuery = Uri.splitQueryString(frag.substring(q + 1));
      } catch (_) {
        fragQuery = const {};
      }
    }
    String? param(String k) {
      final a = fragQuery[k];
      if (a != null && a.isNotEmpty) return a;
      try {
        final b = u.queryParameters[k];
        return (b != null && b.isNotEmpty) ? b : null;
      } catch (_) {
        return null;
      }
    }

    return param('token') != null || param('waiting_webhook') == '1';
  }

  /// [u] رجوعٌ إلى الساس بدليل الدفع؟
  bool isReturn(Uri u) => hasProof(u) && _atReturn(u);

  bool _atReturn(Uri u) {
    final host = _norm(u.host);
    if (host.isNotEmpty && capture.hosts.contains(host)) return true;
    if (host.isNotEmpty && _payHosts.contains(host)) return false;
    final path = u.path.toLowerCase();
    // الهاش: `#/zaincash/process?token=…` ← المسار قبل `?`.
    final frag = u.fragment;
    final q = frag.indexOf('?');
    final fragPath = (q < 0 ? frag : frag.substring(0, q)).toLowerCase();
    for (final r in capture.routes) {
      if (fragPath == r || fragPath.startsWith('$r/')) return true;
      if (path == r || path.endsWith(r)) return true;
    }
    return false;
  }

  @override
  PayNavAction decide(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return PayNavAction.block;
    final scheme = u.scheme.toLowerCase();
    if (scheme == 'about') {
      final rest = url.trim().toLowerCase();
      return rest == 'about:blank' || rest.startsWith('about:srcdoc')
          ? PayNavAction.allow
          : PayNavAction.block;
    }
    if ((scheme == 'https' || scheme == 'http') && isReturn(u)) {
      return PayNavAction.capture;
    }
    if (scheme == 'https' && u.host.isNotEmpty) return PayNavAction.allow;
    return PayNavAction.block;
  }

  /// صفحة الساس وزين كاش لا تحتاج شيئاً.
  @override
  String? scriptFor(String url) => null;
}

/// «شحن من pay الجزيرة»: رجوع البوّابة (زين كاش/كي كارد) = **أوّل** انتقالٍ إلى موقع الشحن ([returnHost]) — يُلتقط
/// ولا يُحمَّل (الموقع هنا بلا جلسة الوكيل؛ الخادم يسلّمه بجلسته)، بدليلٍ أو بلا دليل: لا شيء على موقع الشحن يلزم
/// صفحة الدفع، وتركه يُحمَّل يضيّعه. ورابط SuperQi يُفتح بتطبيقه ([WalletAppLink]). وما سواه كقاعدة الشحن: https
/// يُحمَّل، والباقي يُمنع.
class HostReturnNavPolicy implements PayNavRule {
  HostReturnNavPolicy({required String returnHost}) : _host = _norm(returnHost);

  final String _host;

  static String _norm(String host) {
    final h = host.trim().toLowerCase();
    return h.endsWith('.') ? h.substring(0, h.length - 1) : h;
  }

  @override
  PayNavAction decide(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return PayNavAction.block;
    final scheme = u.scheme.toLowerCase();
    if (scheme == 'about') {
      final rest = url.trim().toLowerCase();
      return rest == 'about:blank' || rest.startsWith('about:srcdoc') ? PayNavAction.allow : PayNavAction.block;
    }
    if ((scheme == 'https' || scheme == 'http') && _host.isNotEmpty && _norm(u.host) == _host) {
      return PayNavAction.capture;
    }
    if (WalletAppLink.of(url) != null) return PayNavAction.external;
    if (scheme == 'https' && u.host.isNotEmpty) return PayNavAction.allow;
    return PayNavAction.block;
  }

  /// صفحة كي: زرّ SuperQi لا يفعل شيئاً على الهاتف — يُقرأ ردّه ويُفتح التطبيق ([WalletAppLink.qiHookScript]).
  @override
  String? scriptFor(String url) => WalletAppLink.hooks(url) ? WalletAppLink.qiHookScript : null;
}
