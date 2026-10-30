import 'package:flutter/foundation.dart';

/// صفحةٌ من سجلّ العمليّات — `?limit=&before=&q=` ⇒ الصفوف و`has_more` (الخادم 824b597): «شحن رصيد الصفحة»
/// و«شحن من pay الجزيرة».
@immutable
class HistoryPage<T> {
  const HistoryPage(this.rows, {required this.hasMore});

  final List<T> rows;

  /// بعدها صفوفٌ أقدم («عرض المزيد»).
  final bool hasMore;
}
