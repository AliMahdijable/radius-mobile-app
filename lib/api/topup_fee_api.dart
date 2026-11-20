import 'api_client.dart';
import '../core/util/format.dart';

/// «الفائدة» على شحن المدراء (المالك ٢٠ نوفمبر ٢٠٢٦: «ضيف بقسم المدراء بالشحن بايرث او غير ايرث نسبه الفائده او مبلغ معين… من
/// يشحن لوكيل اجل ام دين تنضاف ع الرصيد… لازم بالتقارير الحركه هاي تبين شنو جانت وكم فائده»؛ ثمّ ٢١ نوفمبر: «لا هي مفروض بالحالاتين
/// حبي اجل او نقدي»).
///
/// الرصيد يصل المدير كما هو، والفائدة فوقه — حين يفتحها الخادم للصفحة: مع الآجل دينٌ في «ديون أخرى» مربوطٌ بالشحنة، ومع النقديّ
/// تُستلم نقداً معه بلا دين (حين يقبلها الخادم: [TopupFeeConfig.cash]).
/// الحساب هنا للعرض قبل التأكيد وحده: الخادم (server/managerTopupFees.js) يحسبها بالمعادلة نفسها ويرفض (FEE_CHANGED) ما يخالف
/// ما رآه الوكيل، والموقع (client-v2 src/lib/topup-fee.ts) بالقواعد نفسها.
///
///   GET /api/v2/manager-topup-fees/config?provider=sas4|earthlink&manager=<id> ⇒ { success, enabled, last:{kind,value}|null, max_percent,
///       collects:['debt','cash'] }
///   جسم الشحن: fee = { kind: percent|fixed, value, amount } ⇒ الردّ: fee = { amount, debt_id, recorded, label, collect } (+ warning بالساس)
enum TopupFeeKind { none, percent, fixed }

/// هل الفائدة مفتوحةٌ للصفحة، وآخر فائدةٍ طُبّقت لهذا المدير (مقترحةٌ عند فتح النافذة).
class TopupFeeConfig {
  const TopupFeeConfig({this.enabled = false, this.lastKind, this.lastValue, this.cash = false});
  final bool enabled;
  final TopupFeeKind? lastKind;
  final num? lastValue;

  /// الخادم يقبلها مع الشحن النقديّ أيضاً (٢١ نوفمبر — collects يضمّ cash). خادمٌ أقدم ⇒ مع الآجل وحده كما كان.
  final bool cash;

  static const off = TopupFeeConfig();

  /// ردٌّ غير ناجح أو غير مفهوم ⇒ مطفأة (لا حقلٌ بلا يقين).
  static TopupFeeConfig fromBody(Map body) {
    if (body['success'] != true) return off;
    TopupFeeKind? kind;
    num? value;
    final last = body['last'];
    if (last is Map) {
      final k = '${last['kind']}';
      final v = num.tryParse('${last['value']}');
      if ((k == 'percent' || k == 'fixed') && v != null && v > 0) {
        kind = k == 'percent' ? TopupFeeKind.percent : TopupFeeKind.fixed;
        value = v;
      }
    }
    final collects = body['collects'];
    return TopupFeeConfig(
      enabled: body['enabled'] == true,
      lastKind: kind,
      lastValue: value,
      cash: collects is List && collects.contains('cash'),
    );
  }
}

/// ما ردّه الخادم عن الفائدة بعد شحنٍ ناجح.
class TopupFeeOutcome {
  const TopupFeeOutcome({required this.amount, required this.recorded, this.label, this.cash = false});
  final num amount;

  /// استُلمت نقداً مع الشحن (لا دين) — وإلّا دينٌ في «ديون أخرى».
  final bool cash;

  /// سُجّل دينها في «ديون أخرى». false: الشحن تمّ ودينها لم يُسجَّل — يُقال صريحاً (أضفها من «ديون أخرى»).
  final bool recorded;

  /// «فائدة 2% (2,000 د.ع)» من الخادم.
  final String? label;

  static TopupFeeOutcome? fromJson(dynamic j) {
    if (j is! Map) return null;
    final a = num.tryParse('${j['amount']}');
    if (a == null) return null;
    final l = j['label'];
    return TopupFeeOutcome(
      amount: a,
      recorded: j['recorded'] == true,
      label: l == null || '$l'.trim().isEmpty ? null : '$l',
      cash: j['collect'] == 'cash',
    );
  }
}

/// حساب الفائدة ونصوصها — كالخادم والموقع حرفاً بحرف.
class TopupFee {
  TopupFee._();

  static const _ar = '٠١٢٣٤٥٦٧٨٩';
  static const _fa = '۰۱۲۳۴۵۶۷۸۹';
  static final _drop = RegExp(r'[,\s٬،]');
  static final _number = RegExp(r'^\d+(\.\d{1,2})?$');

  /// ما يكتبه الوكيل (أرقامٌ عربيّة أو لاتينيّة، فواصل، منزلتان عشريّتان) ⇒ عدد، وغيره null — كالخادم (valueOf).
  static num? parseValue(String raw) {
    final b = StringBuffer();
    for (final ch in raw.split('')) {
      final ar = _ar.indexOf(ch);
      final fa = _fa.indexOf(ch);
      if (ar >= 0) {
        b.write(ar);
      } else if (fa >= 0) {
        b.write(fa);
      } else if (ch == '٫') {
        b.write('.');
      } else if (!_drop.hasMatch(ch)) {
        b.write(ch);
      }
    }
    final s = b.toString();
    if (!_number.hasMatch(s)) return null;
    return (double.parse(s) * 100).round() / 100;
  }

  /// الفائدة بالدينار على مبلغ الشحن [base] — معادلة الخادم نفسها (feeAmountFor).
  static int? amount(TopupFeeKind kind, num? value, num base) {
    if (kind == TopupFeeKind.none || value == null || !(value > 0) || !(base > 0)) return null;
    return kind == TopupFeeKind.percent ? (base * value / 100).round() : value.round();
  }

  /// سبب رفضها قبل الإرسال (كرسائل الخادم)، أو null حين تصحّ.
  static String? problem(TopupFeeKind kind, String raw, num base) {
    if (kind == TopupFeeKind.none) return null;
    final v = parseValue(raw);
    if (v == null || !(v > 0)) return 'اكتب الفائدة رقماً أكبر من صفر';
    if (kind == TopupFeeKind.percent && v > 100) return 'النسبة أكبر من 100%';
    if (!(base > 0)) return null; // المبلغ لم يُكتب بعد — زرّ التنفيذ معطّلٌ أصلاً
    if (kind == TopupFeeKind.fixed && v > base) return 'الفائدة أكبر من مبلغ الشحن';
    final a = amount(kind, v, base);
    if (a == null || a < 1) return 'الفائدة أقلّ من دينار';
    return null;
  }

  /// «2» · «2.5» — منزلتان على الأكثر بلا أصفارٍ زائدة.
  static String pct(num v) {
    final r = (v * 100).round() / 100;
    if (r == r.roundToDouble()) return r.toInt().toString();
    var s = r.toStringAsFixed(2);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// قيمةٌ مقترحة في الحقل: النسبة كما هي («2.5»)، والمبلغ مفصولاً («5,000»).
  static String valueText(TopupFeeKind kind, num v) =>
      kind == TopupFeeKind.fixed && v == v.roundToDouble() ? formatIQD(v) : pct(v);

  /// «فائدة 2% (2,000 د.ع)» أو «فائدة 2,000 د.ع» — نصّ الخادم نفسه (feeLabel).
  static String label(TopupFeeKind kind, num value, num amount) {
    if (kind == TopupFeeKind.none) return '';
    return kind == TopupFeeKind.percent
        ? 'فائدة ${pct(value)}% (${formatIQD(amount)} د.ع)'
        : 'فائدة ${formatIQD(amount)} د.ع';
  }

  /// جسم الطلب { kind, value, amount } (ما رآه الوكيل)، أو null بلا فائدة.
  static Map<String, Object>? body(TopupFeeKind kind, String raw, num base) {
    if (kind == TopupFeeKind.none) return null;
    final v = parseValue(raw);
    final a = amount(kind, v, base);
    if (v == null || a == null) return null;
    return {'kind': kind == TopupFeeKind.percent ? 'percent' : 'fixed', 'value': v, 'amount': a};
  }
}

class TopupFeeApi {
  TopupFeeApi._();

  /// إعداد نافذة الشحن لهذا المدير ([manager]: رقمه بالساس، أو index حسابه التابع بايرث لنك). تعذّره ⇒ مطفأة.
  static Future<TopupFeeConfig> config({required bool earthlink, required String manager}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/manager-topup-fees/config',
        queryParameters: {'provider': earthlink ? 'earthlink' : 'sas4', 'manager': manager},
      );
      return TopupFeeConfig.fromBody(r.data ?? const {});
    } catch (_) {
      return TopupFeeConfig.off;
    }
  }
}
