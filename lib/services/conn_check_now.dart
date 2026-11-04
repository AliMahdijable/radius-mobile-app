import 'package:flutter/foundation.dart';

import '../api/connection_auto_api.dart';
import 'auth_storage.dart';
import 'connection_readings_uploader.dart';
import 'device_warm_service.dart';

/// «افحص الآن» في «تنبيهات المشتركين» (٤ نوفمبر — المالك: «زر فحص الان هذا فكرته من هو خارج شبكه او داخله يستدعي داله الفحص
/// وينتظر لحد مايكمل الفحص ويعطي النتيجه وانتبه من تكرار النقر ع الزر»):
///   ١. من شبكة الوكيل (عيّنةٌ تردّ): التطبيق يفحص أجهزة المتّصلين بنفسه ويرفع القراءات الآن ⇒ بلا حِملٍ على خادمنا.
///   ٢. خارجها: جولةٌ واحدة عبر VPN الخادم (POST/GET /api/v2/conn-vpn/check-now) تُنتظر حتى تكتمل.
/// ضغطةٌ والفحص جارٍ ⇒ الفحص نفسه (هنا وفي الخادم). بعده تتحدّث كلّ التبويبات ([ConnectionAutoApi.changes]).
class ConnCheckNow {
  ConnCheckNow._();

  static final ValueNotifier<bool> running = ValueNotifier(false);
  static final ValueNotifier<String?> progress = ValueNotifier(null);

  /// آخر نتيجة (تبقى ظاهرةً إن خرج الوكيل من الشاشة ورجع).
  static final ValueNotifier<ConnCheckResult?> last = ValueNotifier(null);

  /// حساب آخر نتيجة: بعد تبديل الشركة لا تظهر نتيجة حسابٍ آخر (٤ نوفمبر — ظهر «لا مشاكل» لفحص الشركة الجديدة فوق مشاكل سوبرنت).
  static String? _lastAdmin;

  static Future<ConnCheckResult>? _flight;

  @visibleForTesting
  static void debugReset() {
    _flight = null;
    running.value = false;
    progress.value = null;
    last.value = null;
    _lastAdmin = null;
  }

  /// عند فتح «تنبيهات المشتركين»: نتيجةٌ لحسابٍ غير المفتوح الآن تُمسح.
  static Future<void> forgetOtherAccount() async {
    if (last.value == null) return;
    final cur = await AuthStorage.readAdminId();
    if (cur != _lastAdmin) last.value = null;
  }

  static Future<ConnCheckResult> run() {
    final f = _flight;
    if (f != null) return f;
    late final Future<ConnCheckResult> mine;
    mine = _run().whenComplete(() {
      if (identical(_flight, mine)) _flight = null;
    });
    _flight = mine;
    return mine;
  }

  static Future<ConnCheckResult> _run() async {
    running.value = true;
    progress.value = 'يتأكّد من شبكتك…';
    ConnCheckResult res;
    String? admin;
    try {
      admin = await AuthStorage.readAdminId();
      final local = await DeviceWarmService.checkNow(
        onProgress: (done, total) => progress.value = 'يفحص أجهزة مشتركيك من شبكتك… $done/$total',
      );
      if (local.onNet) {
        progress.value = 'يرسل القراءات…';
        final st = await ConnectionReadingsUploader.collectNow(local.subs);
        res = st == null
            ? const ConnCheckResult(ok: false, via: 'local', message: 'فُحصت أجهزتك لكن تعذّر إرسال القراءات — حاول بعد قليل')
            : ConnCheckResult(ok: true, via: 'local', message: localMessage(st), readable: st.usable, atMs: DateTime.now().millisecondsSinceEpoch);
      } else if (local.reason == 'no_devices') {
        res = const ConnCheckResult(ok: false, via: 'none', message: 'شركتك لا تعطي عناوين أجهزة المشتركين — لا يُفحص منها');
      } else {
        progress.value = 'خارج شبكتك — يفحص عبر VPN… (قد يأخذ دقيقة)';
        res = await ConnectionAutoApi.vpnCheckNow();
      }
    } catch (_) {
      res = const ConnCheckResult(ok: false, via: 'none', message: 'تعذّر الفحص الآن — حاول بعد قليل');
    } finally {
      running.value = false;
      progress.value = null;
    }
    _lastAdmin = admin;
    last.value = res;
    ConnectionAutoApi.changes.value++;
    ConnectionAutoApi.unawaitedLoad();
    return res;
  }

  /// نصّ نتيجة الفحص من الشبكة: المقروء، ومن صار «تحت المراقبة»، ومن تأكّد، ومن حُلّ — أو «لا مشاكل جديدة».
  @visibleForTesting
  static String localMessage(({int sent, int usable, int watching, int confirmed, int resolved}) st) {
    final parts = <String>['فُحص من شبكتك ✓ — قُرئ ${st.usable} جهازاً'];
    if (st.watching > 0) parts.add('${st.watching} صار تحت المراقبة');
    if (st.confirmed > 0) parts.add('${st.confirmed} تأكّدت مشكلته');
    if (st.resolved > 0) parts.add('${st.resolved} حُلّت');
    if (st.watching == 0 && st.confirmed == 0) parts.add('لا مشاكل جديدة');
    return parts.join(' — ');
  }
}
