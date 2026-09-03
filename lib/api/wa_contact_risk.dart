import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// درجة خطر مراسلة رقم عبر واتساب.
///
/// 🐛 طلب المستخدم ٢٠٢٦-٠٩-٠٢: حارسٌ قبل مراسلة من لم يسبق أن راسلك،
/// لأنّ ذلك يعرّض جلستك للحظر.
enum WaRiskTier {
  /// بادرَك بالمراسلة — الحوار قائم. لا شيء يُعرض.
  safe,

  /// لم يراسلك، ورسائلك له قليلة. سطرٌ هادئ لا نافذة.
  notice,

  /// ستّ رسائل فأكثر بلا ردّ، أو رقمٌ ثبت أنّه ميّت. نافذة تُوقف.
  confirm,
}

@immutable
class WaContactRisk {
  const WaContactRisk({
    required this.tier,
    this.ignored = 0,
    this.dead = false,
  });

  final WaRiskTier tier;

  /// كم رسالةً وصلته بلا ردٍّ واحد.
  final int ignored;

  /// رقمٌ ثبت أنّه لا يستقبل — إرسالٌ إليه يُهدر السمعة بلا فائدة.
  final bool dead;

  /// الافتراضيّ عند تعذّر السؤال.
  ///
  /// ⚠️ **آمن لا خطر**: الحارس لا يجوز أن يُعطّل الإرسال حين يعجز عن
  /// الحكم. عجزُ الشبكة ليس دليلَ خطر، وتحذيرٌ بلا أساسٍ يُفقد
  /// التحذيراتِ كلَّها قيمتَها.
  static const unknown = WaContactRisk(tier: WaRiskTier.safe);
}

class WaContactRiskApi {
  WaContactRiskApi._();

  /// يسأل عن دفعةٍ من الأرقام بطلبٍ واحد.
  ///
  /// المفاتيح في الناتج **مطبَّعة** كما يُطبّعها الخادم — استعمل
  /// [riskFor] للبحث بدل المطابقة الحرفيّة.
  static Future<Map<String, WaContactRisk>> fetch(List<String> phones) async {
    if (phones.isEmpty) return {};
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/whatsapp/contact-risk',
        data: {'phones': phones},
      );
      final raw = r.data?['risks'];
      if (raw is! Map) return {};
      final out = <String, WaContactRisk>{};
      for (final e in raw.entries) {
        final v = e.value;
        if (v is! Map) continue;
        out['${e.key}'] = WaContactRisk(
          tier: switch ('${v['tier']}') {
            'confirm' => WaRiskTier.confirm,
            'notice' => WaRiskTier.notice,
            _ => WaRiskTier.safe,
          },
          ignored: (v['ignored'] as num?)?.toInt() ?? 0,
          dead: v['dead'] == true,
        );
      }
      return out;
    } on DioException catch (e) {
      if (kDebugMode) print('⚠️ contact-risk: ${e.message}');
      return {};
    }
  }

  /// يسأل عن رقمٍ واحد.
  static Future<WaContactRisk> one(String phone) async {
    final m = await fetch([phone]);
    return riskFor(m, phone);
  }

  /// يبحث عن رقمٍ في نتيجةٍ مفاتيحُها مطبَّعة.
  ///
  /// ⚠️ لا نُطابق حرفيّاً: الخادم يُعيد `9647XXXXXXXXX` بينما الواجهة
  /// تحمل `+964 770 …` أو `0770…`. فنُقارن آخر تسع خانات — وهي ما
  /// يُميّز المشترك في العراق مهما اختلفت البادئة.
  static WaContactRisk riskFor(Map<String, WaContactRisk> m, String phone) {
    if (m.isEmpty) return WaContactRisk.unknown;
    final tail = _tail(phone);
    if (tail.isEmpty) return WaContactRisk.unknown;
    for (final e in m.entries) {
      if (_tail(e.key) == tail) return e.value;
    }
    return WaContactRisk.unknown;
  }

  /// آخر تسع خانات، بعد تحويل الأرقام العربيّة الهنديّة.
  ///
  /// ⚠️ `\d` في دارت **لاتينيّةٌ فقط**: `٧٧٠…` تُمحى كاملةً لا
  /// تُبقى، فيصير المفتاح فارغاً ويسقط الحارس صامتاً. والمستخدم
  /// العراقيّ يلصق الأرقام بلوحة مفاتيح عربيّة كثيراً.
  static String _tail(String raw) {
    final sb = StringBuffer();
    for (final r in raw.runes) {
      if (r >= 0x30 && r <= 0x39) {
        sb.writeCharCode(r); // ٠-٩ لاتينيّة
      } else if (r >= 0x0660 && r <= 0x0669) {
        sb.writeCharCode(r - 0x0660 + 0x30); // عربيّة هنديّة
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        sb.writeCharCode(r - 0x06F0 + 0x30); // فارسيّة
      }
    }
    final d = sb.toString();
    return d.length <= 9 ? d : d.substring(d.length - 9);
  }
}

/// ملخّص خطر **دفعةٍ كاملة** — يُقرأ قبل الضغط على إرسال.
///
/// ⚠️ لماذا ملخّصٌ لا قائمة درجات: `WaContactRiskApi.fetch` تُرجع صفّاً
/// لكلّ رقم، وهي كافيةٌ لبطاقةٍ واحدة. أمّا مئتا رقم فتُرجع مئتَي صفّ
/// لا يقرؤها أحد. الحارس الجماعيّ جملةٌ واحدة أو لا شيء.
@immutable
class WaBulkRisk {
  const WaBulkRisk({
    required this.total,
    required this.noInbound,
    required this.highRisk,
    this.sample = const [],
  });

  /// عدد الأرقام الفريدة بعد التطبيع — لا طول المصفوفة المُرسَلة.
  final int total;

  /// من لم يبادر بمراسلتك. **لا يُستبعَد**: قياسٌ على البيانات الحيّة
  /// قال إنّ نصف جمهور البثّ منهم، فاستبعادُهم يُعطّل البثّ لا يحرسه.
  final int noInbound;

  /// من تجاهل ستّ رسائل فأكثر، أو ثبت أنّ رقمه ميّت. **يُستبعَد
  /// افتراضيّاً** — قِيست نسبتُه على ستّة مدراء حقيقيّين: ٦٪ وسطيّاً
  /// (٢٫٢٪ إلى ١٢٫٣٪). نادرٌ بما يكفي ليبقى التحذير مقروءاً.
  final int highRisk;

  /// عيّنةٌ من المستبعَدين لعرضها في الحوار (٢٠ كحدّ أقصى من الخادم).
  final List<({String phone, String reason})> sample;

  bool get hasWarning => noInbound > 0 || highRisk > 0;

  /// الافتراضيّ حين يتعذّر السؤال — **بلا تحذير**.
  ///
  /// عجزُ الشبكة ليس دليل خطر، وحارسٌ يصرخ عند كلّ انقطاع يُطفَأ.
  static const none = WaBulkRisk(total: 0, noInbound: 0, highRisk: 0);
}

class WaBulkRiskApi {
  /// POST /api/v2/whatsapp/bulk-risk
  ///
  /// لا ترمي أبداً: الفشل يُرجع [WaBulkRisk.none] فيمضي الإرسال.
  static Future<WaBulkRisk> fetch(List<String> phones) async {
    final clean = phones.where((p) => p.trim().isNotEmpty).toList();
    if (clean.isEmpty) return WaBulkRisk.none;
    try {
      final res = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/whatsapp/bulk-risk',
        data: {'phones': clean},
      );
      final d = res.data;
      if (d == null || d['success'] != true) return WaBulkRisk.none;
      final raw = (d['highRiskSample'] as List?) ?? const [];
      return WaBulkRisk(
        total: (d['total'] as num?)?.toInt() ?? 0,
        noInbound: (d['noInbound'] as num?)?.toInt() ?? 0,
        highRisk: (d['highRisk'] as num?)?.toInt() ?? 0,
        sample: [
          for (final e in raw.whereType<Map>())
            (
              phone: '${e['phone'] ?? ''}',
              reason: '${e['reason'] ?? ''}',
            ),
        ],
      );
    } on DioException catch (_) {
      return WaBulkRisk.none;
    } catch (_) {
      return WaBulkRisk.none;
    }
  }
}
