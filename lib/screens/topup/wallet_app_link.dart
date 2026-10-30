import 'package:flutter/foundation.dart';

/// رابط تطبيق محفظةٍ تعطيه صفحة الدفع نفسها — يُفتح **بتطبيقه** خارج التطبيق، وتبقى صفحة الدفع هنا.
///
/// المالك ٣٠ أكتوبر: «من ينقر بواسطه سوبر كي يتوقف ماكو اي حدث». صفحة كي كارد (3ds-api.qi.iq) تطلب من خادمها رابط
/// دفعٍ لـSuperQi (`POST …/payment/<id>/requisites {type: ALIPAY}` ⇒ `paymentUrl` = https://m.banqi.qi.iq/shortlink/h5/…)
/// ثمّ **تعرضه QR على الحاسبة وتتجاهله على الهاتف** (`Hp() && …`، و`Hp` = ليس موبايل) وتنتظر الدفع (`form-status` كلّ
/// ٢ ثمّ ٥ ثوانٍ). فلا يحدث شيءٌ على الهاتف — في متصفّحنا وفي أيّ متصفّح.
///
/// والرابط مسجَّلٌ لتطبيق SuperQi نفسه (assetlinks.json ⇒ iq.qicard.qipay.prod، apple-app-site-association ⇒
/// `/shortlink/*`) ⇒ فتحه خارجاً يفتح SuperQi على الدفعة. فـ[qiHookScript] يُحقن في صفحة كي ويقرأ ردّ ذلك الطلب؛ إن
/// كان رابط SuperQi نقل الصفحة إليه، والتنقّل يُمنع عندنا ويُفتح الرابط بتطبيقه ([of])، فتبقى صفحة كي حيّةً تنتظر الدفع،
/// وحين ينجح تذهب وحدها إلى رابط الرجوع (موقع الشحن) فيُلتقط كما يُلتقط رجوع البطاقة.
@immutable
class WalletAppLink {
  const WalletAppLink._(this.url, this.name);

  final Uri url;

  /// اسم التطبيق كما يعرفه الوكيل — «SuperQi».
  final String name;

  /// صفحات الدفع التي يُحقن فيها [qiHookScript].
  static const hookHosts = {'3ds-api.qi.iq'};

  static const _apps = {'m.banqi.qi.iq': (path: '/shortlink/', name: 'SuperQi')};

  /// رابط محفظةٍ مسجَّل؟ — https بلا مستخدمٍ ولا منفذٍ غريب، على مضيفٍ معروف ومساره. غير ذلك ⇒ null (لا يُفتح شيء).
  static WalletAppLink? of(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || u.scheme.toLowerCase() != 'https' || u.userInfo.isNotEmpty) return null;
    if (u.hasPort && u.port != 443) return null;
    final app = _apps[u.host.toLowerCase()];
    if (app == null || !u.path.startsWith(app.path) || u.path.length <= app.path.length) return null;
    return WalletAppLink._(u, app.name);
  }

  /// صفحة دفعٍ يُحقن فيها [qiHookScript]؟
  static bool hooks(String url) {
    final u = Uri.tryParse(url.trim());
    return u != null && u.scheme.toLowerCase() == 'https' && hookHosts.contains(u.host.toLowerCase());
  }

  /// يُحقن في صفحة كي بعد تحميلها — **يقرأ ولا يرسل شيئاً**: يراقب ردّ طلب `…/requisites` الذي يرسله زرّ SuperQi
  /// (XHR أو fetch)، فإن كان `type: ALIPAY` ومعه رابط SuperQi نقل الصفحة إليه. لا جسر بين الصفحة والتطبيق: التنقّل
  /// يمرّ على قاعدة صفحة الدفع نفسها ([of]) فلا يُفتح خارجاً إلّا رابطٌ مسجَّل. ومرّةً لكلّ صفحة.
  static const qiHookScript = r'''
(function () {
  if (window.__mysvcsWalletHook) return;
  window.__mysvcsWalletHook = true;
  var REQ = /\/payment\/[^\/?#]+\/requisites(?:[?#]|$)/;
  var LINK = /^https:\/\/m\.banqi\.qi\.iq\/shortlink\//;
  function pick(body) {
    try {
      var d = typeof body === 'string' ? JSON.parse(body) : body;
      if (d && d.type === 'ALIPAY' && typeof d.paymentUrl === 'string' && LINK.test(d.paymentUrl)) {
        window.location.href = d.paymentUrl;
      }
    } catch (e) {}
  }
  var X = window.XMLHttpRequest;
  if (X && X.prototype) {
    var open = X.prototype.open, send = X.prototype.send;
    X.prototype.open = function (m, u) {
      try { this.__mysvcsUrl = String(u || ''); } catch (e) {}
      return open.apply(this, arguments);
    };
    X.prototype.send = function () {
      var x = this;
      try {
        if (REQ.test(x.__mysvcsUrl || '')) {
          x.addEventListener('load', function () {
            if (x.status >= 200 && x.status < 300) pick(x.responseType === 'json' ? x.response : x.responseText);
          });
        }
      } catch (e) {}
      return send.apply(this, arguments);
    };
  }
  if (typeof window.fetch === 'function') {
    var f = window.fetch;
    window.fetch = function (input) {
      var p = f.apply(this, arguments);
      try {
        var u = typeof input === 'string' ? input : (input && input.url) || '';
        if (REQ.test(String(u))) {
          p.then(function (r) { if (r && r.ok) r.clone().text().then(pick, function () {}); }, function () {});
        }
      } catch (e) {}
      return p;
    };
  }
})();
''';
}
