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
