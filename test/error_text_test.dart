import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/error_text.dart';

/// لا نصّ تقنيّ إنجليزيّ يصل المستخدم.
///
/// 🐛 بلاغ 2026-08-31 بصورة: شاشة الأجهزة عرضت
///   «DioException [connection timeout]: … try raising the
///    RequestOptions.connectTimeout above the duration of 0:00:20»
/// نصٌّ يخاطب مبرمجاً لا مديراً، ويطلب منه تعديل إعدادٍ في كودٍ لا
/// يملكه. والمعلومة المفيدة الوحيدة — «الشبكة لم تستجب» — مدفونة فيه.
void main() {
  final req = RequestOptions(path: '/x');

  /// لا شيء ممّا يظهر للمستخدم يحمل أثراً تقنيّاً.
  void expectHuman(String out) {
    for (final leak in [
      'DioException',
      'RequestOptions',
      'connectTimeout',
      'SocketException',
      'Exception',
      'null',
      '0:00:',
    ]) {
      expect(out.contains(leak), isFalse, reason: 'تسريب «$leak» في: $out');
    }
    expect(out.trim(), isNotEmpty);
    // عربيّة: أيّ حرف عربيّ يكفي للتمييز.
    expect(RegExp(r'[؀-ۿ]').hasMatch(out), isTrue, reason: 'ليست عربيّة: $out');
  }

  test('المهلة — وهي الحالة المبلَّغ عنها بالضبط', () {
    expectHuman(humanError(DioException(
        requestOptions: req, type: DioExceptionType.connectionTimeout)));
  });

  test('كلّ أنواع Dio تُترجَم', () {
    for (final t in DioExceptionType.values) {
      expectHuman(humanError(DioException(requestOptions: req, type: t)));
    }
  });

  test('رموز الحالة الشائعة', () {
    for (final code in [400, 401, 403, 404, 409, 429, 500, 502, 503, 504]) {
      expectHuman(humanError(DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: req, statusCode: code),
      )));
    }
  });

  test('رسالة الخادم العربيّة تُقدَّم — أدقّ من أيّ تعميم', () {
    final out = humanError(DioException(
      requestOptions: req,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: req,
        statusCode: 400,
        data: {'message': 'رقم الهاتف مستعمل سلفاً'},
      ),
    ));
    expect(out, 'رقم الهاتف مستعمل سلفاً');
  });

  test('رسالة خادم إنجليزيّة تُرفض — قد تكون أثر مكدّس', () {
    final out = humanError(DioException(
      requestOptions: req,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: req,
        statusCode: 500,
        data: {'message': 'TypeError: Cannot read property x of undefined'},
      ),
    ));
    expectHuman(out);
    expect(out.contains('TypeError'), isFalse);
  });

  test('استثناءات دارت العاديّة', () {
    expectHuman(humanError(TimeoutException('x')));
    expectHuman(humanError(const SocketException('failed')));
    expectHuman(humanError(const HttpException('reset')));
    expectHuman(humanError(const FormatException('bad json')));
    expectHuman(humanError(Exception('anything at all')));
    expectHuman(humanError(null));
  });

  test('unknown بسبب مقبس يُقرأ من السبب لا من النوع', () {
    final out = humanError(DioException(
      requestOptions: req,
      type: DioExceptionType.unknown,
      error: const SocketException('reset by peer'),
    ));
    expectHuman(out);
    // يجب أن يقول «انقطع» لا «تعذّر إتمام العمليّة» العامّة.
    expect(out.contains('انقطع'), isTrue);
  });

  test('الاحتياط المخصَّص يُحترم حين لا يُعرف السبب', () {
    expect(humanError(Exception('x'), fallback: 'فشل التحميل'), 'فشل التحميل');
  });
}
