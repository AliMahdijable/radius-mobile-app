import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../models/device_health.dart';

/// Direct port of mobile-app/lib/core/services/huawei_ont_service.dart —
/// keeps the same login flow, base URL fallback order, and HTML
/// parsing so behavior matches v1 1:1.
class HuaweiOntService {
  static Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      // مطلب المستخدم 2026-07-12: يطابق v1 (15s كل واحد). Huawei ONTs
      // بطيئة الاستجابة على SoC ضعيف. 4s كانت تفشل مبكراً.
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
      followRedirects: false,
      headers: {'Accept': 'text/html,application/xhtml+xml,*/*'},
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final c = HttpClient();
      c.badCertificateCallback = (_, __, ___) => true;
      return c;
    };
    return dio;
  }

  /// ⚠️ **ميزانيّة زمنيّة للسلسلة كلّها، لا لكلّ محاولة.**
  ///
  /// السلسلة تمشي على أربعة عناوين بالتسلسل، كلٌّ بمهلة ١٥ ثانية —
  /// فالعنوان الصامت يكلّفها **ستّين ثانية**. والمستدعي
  /// (`DeviceProbeApi._probeAndStore`) يتخلّى عنها عند ١٥ بـ`.timeout`،
  /// لكنّ `.timeout` في Dart **لا يُلغي العمل تحته**: مستقبَلات Dart
  /// غير قابلة للإلغاء، و`_firstNonNull` يتجاهل الخاسر ولا يوقفه.
  ///
  /// فكانت كلّ محاولةٍ مهجورة تُكمل خمساً وأربعين ثانيةً بعد تحرير
  /// عاملها — سلاسل يتيمة تتراكم بلا أن يقرأ أحدٌ نتيجتها. وعلى موجةٍ
  /// بأربعين عاملاً يعني ذلك نحو **١٦٠ سلسلةً حيّة** في وقتٍ واحد،
  /// كلٌّ بمقبسها. وضغط المقابس يُفشل جهازاً حيّاً بطيئاً فيُعلَن
  /// ميّتاً — وهو بالضبط العطب الذي لا نقبله.
  ///
  /// و[budget] يوقف السلسلة حين تنفد المهلة: لا نبدأ محاولةً جديدة
  /// وقد انقضى الوقت المتاح. فتقصر حياة اليتيمة من ٦٠ ثانيةً إلى ١٥،
  /// ويهبط عددها إلى ربعه.
  ///
  /// ⚠️ ولا تُخفَّض `connectTimeout` نفسها: خمس عشرة مضبوطةٌ بطلب
  /// صاحب المشروع (٢٠٢٦-٠٧-١٢) بعد أن كانت أربعاً «تفشل مبكراً».
  /// وهذا لا يمسّها — الجهاز الحيّ يُعطى محاولته الأولى كاملة، ولا
  /// يُقطع عليه شيء. المقطوع محاولاتٌ لا يقرأ أحدٌ نتيجتها أصلاً.
  static Future<OntLoginResult?> login(
    String host,
    String user,
    String pass, {
    Duration? budget,
  }) async {
    final bases = [
      'https://$host:80',
      'https://$host:443',
      'https://$host',
      'http://$host',
    ];
    final deadline = budget == null ? null : DateTime.now().add(budget);
    for (final base in bases) {
      // ⚠️ الفحص **قبل** المحاولة لا بعدها: بعدها لا يوفّر شيئاً،
      //    والمحاولة الأخيرة تكون قد وقعت كاملة.
      if (deadline != null && !DateTime.now().isBefore(deadline)) return null;
      final result = await _tryLogin(base, user, pass);
      if (result != null) return result;
    }
    return null;
  }

  static Future<OntLoginResult?> _tryLogin(
      String base, String user, String pass) async {
    final dio = _buildDio(base);
    try {
      await dio.get('/');
      final tokRes = await dio.post(
        '/asp/GetRandCount.asp',
        data: '',
        options: Options(headers: {'Referer': '$base/'}),
      );
      final raw = (tokRes.data ?? '').toString().trim();
      final m = RegExp(r'[0-9a-fA-F]{16,}').firstMatch(raw);
      final token = m?.group(0);
      if (token == null) return null;

      final b64Pass = base64Encode(utf8.encode(pass));
      final body = 'UserName=${Uri.encodeQueryComponent(user)}'
          '&PassWord=${Uri.encodeQueryComponent(b64Pass)}'
          '&x.X_HW_Token=${Uri.encodeQueryComponent(token)}';
      final res = await dio.post(
        '/login.cgi',
        data: body,
        options: Options(headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Origin': base,
          'Referer': '$base/',
          'Cookie': 'Cookie=body:Language:english:id=-1',
        }),
      );

      final sessionCookie = _extractSid(res);
      final bodyStr = (res.data ?? '').toString();
      final success =
          bodyStr.contains("pageName = 'index.asp'") && sessionCookie != null;
      if (!success) return null;
      return OntLoginResult(sessionCookie: sessionCookie, baseUrl: base);
    } catch (_) {
      return null;
    }
  }

  static String? _extractSid(Response res) {
    final raw = res.headers.map['set-cookie'] ?? const [];
    for (final line in raw) {
      final nameVal = line.split(';').first;
      final eq = nameVal.indexOf('=');
      if (eq > 0) {
        final name = nameVal.substring(0, eq).trim();
        final val = nameVal.substring(eq + 1).trim();
        if (name == 'Cookie' && val.contains('sid=')) {
          return '$name=$val';
        }
      }
    }
    return null;
  }

  static Future<OntOpticalInfo?> fetchOptical(OntLoginResult session) async {
    final dio = _buildDio(session.baseUrl);
    try {
      final res = await dio.get(
        '/html/amp/opticinfo/opticinfo.asp',
        options: Options(headers: {
          'Cookie': session.sessionCookie,
          'Referer': '${session.baseUrl}/index.asp',
        }),
      );
      return _parseOptical((res.data ?? '').toString());
    } catch (_) {
      return null;
    }
  }

  /// **إعادة تشغيل ONU** — العمليّة الوحيدة غير القرائيّة هنا.
  ///
  /// المسار مُستخرَجٌ من أجهزةٍ حقيقيّة لا مُخمَّن، و**الإصدارات تختلف
  /// اختلافاً جوهريّاً** — ولهذا نجرّب صيغتين:
  ///
  /// **(أ) صفحة إعادة تشغيل مستقلّة** (`/html/ssmp/reset/reset.asp`):
  /// ```js
  /// Form.setAction('set.cgi?x=InternetGatewayDevice.X_HW_DEBUG.SMP.DM.ResetBoard'
  ///                + '&RequestFile=html/ssmp/reset/reset.asp');
  /// ```
  ///
  /// **(ب) داخل صفحة ملفّ الإعدادات** (`/html/ssmp/cfgfile/cfgfile.asp`)
  /// على إصداراتٍ لا صفحة إعادة تشغيل فيها أصلاً — زرّها
  /// `btnsaveandreboot`:
  /// ```js
  /// set.cgi?x=...SSP.DBSave&y=...SMP.DM.ResetBoard
  /// ```
  /// ⚠️ هذه الصيغة **تحفظ الإعدادات ثمّ تُعيد التشغيل** — وهو ما يفعله
  /// زرّ الجهاز نفسه؛ لا نملك على هذا الإصدار إقلاعاً مجرّداً.
  ///
  /// وفي الصيغتين يُقرأ الرمز من حقلٍ مخفيّ اسمه `onttoken` **في
  /// الصفحة نفسها**، لا من `GetRandCount.asp` التي يستعملها الدخول —
  /// ولكلّ صفحةٍ رمزها، ويُبطَل بعد الاستعمال.
  ///
  /// يرجع `true` إن قُبل الأمر. وقطعُ الجهاز للاتّصال بلا ردّ **نجاح**
  /// لا فشل.
  static Future<bool> reboot(OntLoginResult session) async {
    const variants = [
      (
        page: '/html/ssmp/reset/reset.asp',
        dir: '/html/ssmp/reset',
        query: 'x=InternetGatewayDevice.X_HW_DEBUG.SMP.DM.ResetBoard'
            '&RequestFile=html/ssmp/reset/reset.asp',
      ),
      (
        page: '/html/ssmp/cfgfile/cfgfile.asp',
        dir: '/html/ssmp/cfgfile',
        query: 'x=InternetGatewayDevice.X_HW_DEBUG.SSP.DBSave'
            '&y=InternetGatewayDevice.X_HW_DEBUG.SMP.DM.ResetBoard'
            '&RequestFile=html/ssmp/cfgfile/cfgfile.asp',
      ),
    ];

    for (final v in variants) {
      final dio = _buildDio(session.baseUrl);
      try {
        final pageRes = await dio.get(
          v.page,
          options: Options(headers: {
            'Cookie': session.sessionCookie,
            'Referer': '${session.baseUrl}/index.asp',
          }),
        );
        // الصفحة غير موجودة على هذا الإصدار — جرّب الصيغة التالية.
        if (pageRes.statusCode != 200) continue;
        final token = RegExp(r'name="onttoken"[^>]*value="([0-9a-fA-F]+)"')
            .firstMatch((pageRes.data ?? '').toString())
            ?.group(1);
        if (token == null || token.isEmpty) continue;

        await dio.post(
          '${v.dir}/set.cgi?${v.query}',
          data: 'x.X_HW_Token=${Uri.encodeQueryComponent(token)}',
          options: Options(headers: {
            'Cookie': session.sessionCookie,
            'Referer': '${session.baseUrl}${v.page}',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': session.baseUrl,
          }),
        );
        return true;
      } on DioException catch (e) {
        // انقطاع الاتّصال بعد الإرسال = الجهاز بدأ يقلع.
        final t = e.type;
        if (t == DioExceptionType.connectionError ||
            t == DioExceptionType.receiveTimeout) {
          return true;
        }
        continue;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  static String _unescapeJs(String s) {
    return s.replaceAllMapped(
      RegExp(r'\\x([0-9a-fA-F]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
  }

  static OntOpticalInfo? _parseOptical(String html) {
    final m = RegExp(
      r'new stOpticInfo\s*\(\s*"[^"]*"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"',
    ).firstMatch(html);
    if (m == null) return null;
    final ssm = RegExp(r'new stSendStatus\s*\(\s*"([^"]*)"').firstMatch(html);
    return OntOpticalInfo(
      txPower: _unescapeJs(m.group(1)!).trim(),
      rxPower: _unescapeJs(m.group(2)!).trim(),
      voltage: _unescapeJs(m.group(3)!).trim(),
      temperature: _unescapeJs(m.group(4)!).trim(),
      bias: _unescapeJs(m.group(5)!).trim(),
      sendStatus: _unescapeJs(ssm?.group(1) ?? '--').trim(),
    );
  }
}
