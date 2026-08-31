import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// يحوّل أيّ خطأ إلى جملة عربيّة قصيرة تصلح للعرض.
///
/// 🐛 بلاغ 2026-08-31 بصورة: شاشة الأجهزة تعرض
///   «DioException [connection timeout]: The request connection took longer
///    than 0:00:20.000000 … try raising the RequestOptions.connectTimeout»
///
/// نصٌّ إنجليزيّ يخاطب مبرمجاً لا مديراً، ويطلب منه تعديل إعداد في كود
/// لا يملكه. والمعلومة الوحيدة المفيدة فيه — «الشبكة لم تستجب» — مدفونة
/// في سطرين من تفاصيل داخليّة.
///
/// ⚠️ ولا يُصلَح هذا بترقيع موضع الشاشة: 91 موضعاً في المشروع تلمس نصّ
/// الاستثناء. مترجمٌ واحد يجعل الإصلاح لموضعٍ واحد، والجديد يرثه.
///
/// التفاصيل التقنيّة لا تضيع — تُطبع في وضع التطوير وتُرسَل إلى
/// Crashlytics كما كانت.
String humanError(Object? e, {String? fallback}) {
  if (kDebugMode) debugPrint('🔎 humanError: $e');

  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'انتهت مهلة الاتصال — تحقّق من الشبكة وأعد المحاولة';
      case DioExceptionType.connectionError:
        return 'تعذّر الوصول إلى الخادم — تحقّق من الإنترنت';
      case DioExceptionType.badCertificate:
        return 'شهادة أمان غير صالحة';
      case DioExceptionType.cancel:
        return 'أُلغي الطلب';
      case DioExceptionType.badResponse:
        return _fromStatus(e.response?.statusCode, e.response?.data);
      case DioExceptionType.transformTimeout:
        return 'الردّ أكبر ممّا يمكن معالجته — أعد المحاولة';
      case DioExceptionType.unknown:
        // ⚠️ `unknown` بلا ردّ = عطل نقل غالباً (مقبس مقطوع، DNS).
        // Dio يضعه هنا حين لا يعرف، فنقرأ السبب لا النوع.
        final inner = e.error;
        if (inner is SocketException || inner is HttpException) {
          return 'انقطع الاتصال بالخادم — أعد المحاولة';
        }
        if (inner is TimeoutException) {
          return 'انتهت مهلة الاتصال — تحقّق من الشبكة';
        }
        return fallback ?? 'تعذّر إتمام العمليّة';
    }
  }
  if (e is TimeoutException) return 'انتهت المهلة — أعد المحاولة';
  if (e is SocketException) return 'تعذّر الوصول إلى الخادم — تحقّق من الإنترنت';
  if (e is HttpException) return 'انقطع الاتصال بالخادم — أعد المحاولة';
  if (e is FormatException) return 'ردّ غير مفهوم من الخادم';
  return fallback ?? 'تعذّر إتمام العمليّة';
}

/// رسالة الخادم إن كانت عربيّةً مفهومة، وإلّا جملةٌ حسب رمز الحالة.
///
/// الخادم يرسل `{success:false, message:'...'}` بالعربيّة في معظم
/// مساراته — وهي أدقّ من أيّ تعميم، فنقدّمها. لكن لا نعرض أيّ نصّ
/// إنجليزيّ قادمٍ منه: قد يكون أثر مكدّس أو نصّ إطار.
String _fromStatus(int? code, Object? body) {
  if (body is Map) {
    final m = body['message'];
    if (m is String && m.trim().isNotEmpty && _looksArabic(m)) return m.trim();
  }
  switch (code) {
    case 400:
      return 'طلب غير صالح';
    case 401:
      return 'انتهت الجلسة — سجّل الدخول من جديد';
    case 403:
      return 'لا تملك صلاحيّة هذه العمليّة';
    case 404:
      return 'غير موجود';
    case 409:
      return 'تعارض — القيمة مستعملة سلفاً';
    case 429:
      return 'محاولات كثيرة — انتظر قليلاً';
    case 502:
    case 503:
    case 504:
      return 'الخادم لا يستجيب مؤقّتاً — أعد المحاولة';
    default:
      if (code != null && code >= 500) return 'خطأ في الخادم';
      return 'تعذّر إتمام العمليّة';
  }
}

/// أفيها حرفٌ عربيّ؟ يكفي للتمييز بين رسالة موجَّهة للمستخدم وأثرٍ تقنيّ.
bool _looksArabic(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);
