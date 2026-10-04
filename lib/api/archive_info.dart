import '../core/util/server_time.dart';

/// وصف الأرشيف الذي يرجع بجوار بيانات أيّ شاشةٍ تعرض «الآن».
///
/// ما غطّته تسويةٌ فعّالة يختفي **افتراضيّاً** من الصرفيات والتقرير
/// الماليّ وإيراد اللوحة، ويبقى في القاعدة ويُرى بـ`include_archived=1`
/// أو من سند التسوية. (`docs/settlements-prompt.md` §٤)
///
/// ⚠️ **موضعه يختلف بين المسارات.** في `/api/admin/expenses` هو على
/// **جذر** الجسم بجوار `expenses` و`total`، أمّا في
/// `/api/reports/finance` وإيراد اللوحة فهو تحت `data`. فلا يُنسخ
/// المسار من مستدعٍ إلى آخر.
///
/// ونموذجٌ واحدٌ يقرؤه المستدعون الثلاثة، لا ثلاثة نماذجَ متطابقة —
/// وإلّا لم يستطع شريط الأرشيف قبول أنواعهم.
class ArchiveInfo {
  const ArchiveInfo({
    required this.hidden,
    required this.included,
    required this.settlements,
    this.lastNumber,
    this.lastCutAt,
  });

  /// يوجد مؤرشفٌ وهو مخفيٌّ في هذه الاستجابة.
  final bool hidden;

  /// أُرسلت `include_archived=1` فرجع كلّ شيء.
  final bool included;

  /// عدد التسويات الفعّالة. صفرٌ ⇒ لا يُعرض شيء.
  final int settlements;

  /// رقم آخر تسوية ووقتها — الوقت بتوقيت الجهاز بعد [parseServerUtc].
  final int? lastNumber;
  final DateTime? lastCutAt;

  /// الشرط الوحيد لعرض شريط الأرشيف: الغائب أو الصفر لا يُعرض (§٤).
  bool get show => settlements > 0;

  static ArchiveInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final n = j['settlements'];
    return ArchiveInfo(
      hidden: j['hidden'] == true,
      included: j['included'] == true,
      settlements: n is int ? n : int.tryParse(n?.toString() ?? '') ?? 0,
      lastNumber: int.tryParse(j['last_number']?.toString() ?? ''),
      // ⚠️ `parseServerUtc` لا `DateTime.tryParse`: العارية تُقدّم ثلاث
      // ساعات على توقيتات جدولنا (بلاغ ٢٠٢٦-٠٩-٠٤ في رأس `server_time`).
      lastCutAt: parseServerUtc(j['last_cut_at']?.toString()),
    );
  }
}
