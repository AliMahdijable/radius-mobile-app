import '../api/company_route.dart';
import '../api/merged_dashboard_api.dart';
import '../models/merged_company.dart';
import 'merged_mode.dart';
import 'merged_text.dart';

/// تقرير شركةٍ واحدة في «كل الشركات». [rows] null = لم يُقرأ (تعذّر أو نوعها لا يخدمه) — لا قائمةٌ فارغة تبدو ناجحة.
class MergedReportPart<T> {
  const MergedReportPart({
    required this.company,
    this.rows,
    this.error,
    this.note,
    this.unsupported = false,
    this.denied = false,
  });
  final MergedCompany company;
  final List<T>? rows;

  /// سبب التعذّر (نصّ الخادم إن وُجد).
  final String? error;

  /// ملاحظة الخادم مع تقريرٍ مقروء (سجلٌّ ناقص، مدى محدود…).
  final String? note;

  /// نوع الشركة لا يخدم هذا التقرير (الخادم لا يوجّهه لها) — لم يُطلب.
  final bool unsupported;

  /// «كل الصفحات»: لا صلاحيّة للموظّف على هذا التقرير في هذه الصفحة (خريطتها) — لم يُطلب، ويُسمّى.
  final bool denied;

  bool get ok => rows != null;
}

/// تقارير الشركات معاً: صفوف كلّ شركةٍ بمفتاحها، ومن لم يدخل ولماذا.
class MergedReport<T> {
  const MergedReport(this.parts, this.missing);
  final List<MergedReportPart<T>> parts;

  /// شركاتٌ لا تُعرض في «كل الشركات» (تحتاج دخول، من الموقع…).
  final List<MergedCompany> missing;

  /// جزء الشركة — وربطٌ ثانٍ للمدير نفسه يُقرأ من أصله (قائمتهما واحدة).
  MergedReportPart<T>? partOf(String key) {
    final k = MergedDashboardApi.canonicalKey(key);
    for (final p in parts) {
      if (p.company.key == k) return p;
    }
    return null;
  }

  /// صفوف الكلّ (بترتيب الشركات) أو الشركة [key] وحدها — كلّ صفٍّ بمفتاح شركته.
  List<({String key, T row})> rowsFor(String? key) {
    final only = key == null ? null : MergedDashboardApi.canonicalKey(key);
    return [
      for (final p in parts)
        if (only == null || p.company.key == only)
          for (final r in p.rows ?? <T>[]) (key: p.company.key, row: r),
    ];
  }

  int? countOf(MergedCompany c) => partOf(c.key)?.rows?.length;
  int get total => [for (final p in parts) p.rows?.length ?? 0].fold(0, (a, b) => a + b);

  /// شارة الشركة في الشريط حين لم تُقرأ: «تعذّرت» أو [unsupportedLabel].
  String? problemOf(MergedCompany c, {required String failedLabel, required String unsupportedLabel}) {
    final p = partOf(c.key);
    if (p == null || p.ok) return null;
    if (p.denied) return 'merged.chip_denied'.trm();
    return p.unsupported ? unsupportedLabel : failedLabel;
  }

  /// سطر الشريط: من لم يُقرأ ولماذا، وملاحظات الخادم — كلٌّ باسم شركته. شركةٌ مختارة: ما يخصّها وحده.
  /// [nameUnsupported] false: لا تُذكر في «الكل» شركاتٌ لا يخدمها التقرير أصلاً (تقارير ايرث لنك — شارتها تقول ذلك).
  String? noteFor(String? focusKey,
      {required String unsupportedText, required String missingText, bool nameUnsupported = true}) {
    final focus = focusKey == null ? null : partOf(focusKey);
    final shown = focus == null ? parts : [focus];
    final lines = <String>[
      for (final p in shown)
        if (p.unsupported && (nameUnsupported || focus != null))
          '«${p.company.name}»: $unsupportedText'
        else if (!p.unsupported && !p.ok)
          '«${p.company.name}»: ${p.error ?? 'تعذّر جلب التقرير الآن'}'
        else if (p.ok && p.note != null)
          '«${p.company.name}»: ${p.note}',
      if (focus == null && missing.isNotEmpty) missingText,
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }
}

/// «كل الشركات» في تقارير القوائم (٧ نوفمبر — المالك: «التقارير… بنفس فكرة عرض المشتركين والاختيار بين الكل وشركة»): تقرير كلّ
/// شركةٍ بطلبٍ موجَّه لها (x-company-key) — قائمتان معاً على الأكثر، وربطان للمدير نفسه يُطلبان مرّة. فشل شركةٍ يُحفظ باسمها ولا يوقف
/// البقيّة؛ وشركةٌ لا يخدم نوعُها التقرير ([supports]) لا تُطلب وتُسمّى.
///
/// [perms] (٩ نوفمبر — «كل الصفحات» للموظّف): مفاتيح التقرير (أيٌّ منها) — صفحةٌ لا يملك فيها أيّاً منها بخريطتها لا تُطلب، وتُسمّى
/// «لا صلاحيّة لك على هذا التقرير فيها». المالك أو خادمٌ بلا خرائط ⇒ كما كان.
Future<MergedReport<T>> loadMergedReport<T>({
  required bool Function(MergedCompany c) supports,
  required Future<({bool ok, List<T> rows, String? error, String? note})> Function(MergedCompany c) fetch,
  int concurrency = 2,
  List<String> perms = const [],
}) async {
  final cs = MergedDashboardApi.countable();
  final missing = MergedMode.companies.where((c) => !c.usable).toList();
  final out = List<MergedReportPart<T>?>.filled(cs.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < cs.length) {
      final i = next++;
      final c = cs[i];
      if (!supports(c)) {
        out[i] = MergedReportPart<T>(company: c, unsupported: true);
        continue;
      }
      if (perms.isNotEmpty && MergedMode.pagePermAny(c.key, perms) == false) {
        out[i] = MergedReportPart<T>(company: c, error: MergedMode.noAccess('هذا التقرير فيها'), denied: true);
        continue;
      }
      try {
        final r = await CompanyRoute.run(c.key, () => fetch(c));
        out[i] = r.ok
            ? MergedReportPart<T>(company: c, rows: List.unmodifiable(r.rows), note: r.note)
            : MergedReportPart<T>(company: c, error: r.error);
      } catch (_) {
        out[i] = MergedReportPart<T>(company: c);
      }
    }
  }

  await Future.wait([for (var w = 0; w < concurrency && w < cs.length; w++) worker()]);
  return MergedReport<T>(List.unmodifiable(out.whereType<MergedReportPart<T>>()), missing);
}
