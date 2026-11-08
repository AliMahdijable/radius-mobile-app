import 'package:flutter/foundation.dart';

/// صفحةٌ من قائمة تنبيهات (٩ نوفمبر — المالك: «تنبيهات المشتركين والأجهزة — خلّي بيها ١٠ قراءات وتحميل المزيد»): عناصرها
/// (الأحدث أوّلاً)، وهل بعدها المزيد، ومؤشّر التالية كما أعطاه الخادم.
@immutable
class AlertsPage<T> {
  const AlertsPage(this.items, {required this.hasMore, this.next, this.total, this.sendable});

  final List<T> items;

  /// بعدها المزيد («تحميل المزيد»).
  final bool hasMore;

  /// مؤشّر الصفحة التالية (نصٌّ معتم من الخادم)؛ null = خادمٌ أقدم بلا مؤشّر ⇒ التالية بالعدد (أوّل N ثمّ تُقصّ).
  final String? next;

  /// مع الصفحة الأولى من «تنبيهات المشتركين»: كم في هذه الحالة بالخادم، وكم منهم يُرسَل له (غير «لا ترسل له») — لا عدد الصفحة.
  final int? total;
  final int? sendable;
}
