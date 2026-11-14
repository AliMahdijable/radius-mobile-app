import 'dart:async';

import 'package:flutter/foundation.dart';

/// «المشتركون أوّلاً» في الرئيسيّة (المالك ١٤ نوفمبر ٢٠٢٦: «الاولية تكون لتحميل المشتركين للداش بورد ثم بقيه الامور»).
///
/// قائمة المشتركين (حلقة الأعداد والمدينون والجرس) أهمّ ما في الرئيسيّة وأثقله. كانت تنطلق مع الإيرادات وتوزيع الباقات
/// وآخر النشاطات والرصيد وحبّة الواتساب دفعةً واحدة فتتقاسم معها الشبكة والخادم — بل كانت كروت الإيرادات والباقات تسبقها
/// (تجلب من `initState` قبل أن تقرأ الرئيسيّة تفضيلات أقسامها).
///
/// الآن جولةٌ ([begin]) تُفتح قبل أيّ جلبٍ تلقائيّ للرئيسيّة، وكلّ طلبٍ غير المشتركين ينتظر [afterSubscribers]: نهاية
/// جلب المشتركين ([subscribersDone]) أو [maxWait] أيّهما أسبق — قائمةٌ بطيئة (حسابٌ كبير، شبكةٌ ضعيفة) لا تحبس الباقي.
/// بلا جولةٍ مفتوحة لا انتظار (نقرة المدير على «أسبوع» مثلاً تجلب فوراً).
class DashboardLoadOrder {
  DashboardLoadOrder._();

  /// أقصى انتظارٍ لطلبٍ خلف المشتركين.
  static const Duration maxWait = Duration(seconds: 6);

  static Completer<void>? _round;

  /// يفتح جولةً إن لم تكن مفتوحة (المفتوحة تبقى — من ينتظرها ينتظر الجلب الجاري نفسه).
  static void begin() {
    final r = _round;
    if (r == null || r.isCompleted) _round = Completer<void>();
  }

  /// انتهى جلب المشتركين (نجح أو فشل أو لا صلاحيّة له) ⇒ الباقي يمضي.
  static void subscribersDone() {
    final r = _round;
    if (r != null && !r.isCompleted) r.complete();
  }

  /// جولةٌ مفتوحة الآن (للاختبار والقراءة).
  static bool get waiting {
    final r = _round;
    return r != null && !r.isCompleted;
  }

  /// ينتظر المشتركين إن كانت جولةٌ مفتوحة — بحدّ [maxWait] — وإلّا يعود فوراً.
  static Future<void> afterSubscribers({Duration? max}) {
    final r = _round;
    if (r == null || r.isCompleted) return Future<void>.value();
    return r.future.timeout(max ?? maxWait, onTimeout: () {});
  }

  @visibleForTesting
  static void debugReset() {
    final r = _round;
    if (r != null && !r.isCompleted) r.complete();
    _round = null;
  }
}
