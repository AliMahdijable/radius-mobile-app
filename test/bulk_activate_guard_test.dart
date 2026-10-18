import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bulk_activate_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/bulk_activate_guard.dart';

/// حارس التجديد الجماعيّ — المنطق وحده (بلا واجهة)، أمام خادمٍ وهميّ.
///
/// ⚠️ لا تفعيل حقيقيّ هنا ولا في أيّ اختبارٍ لهذا البند: كلّ تفعيلٍ مالٌ من
/// رصيد المدير. الردود مأخوذةٌ من عقد الخادم (server/bulkActivateGuard.js
/// ومسار activate) لا من ساسٍ حيّ.

ActivateOutcome _out({
  bool ok = false,
  String? code,
  String? message,
  int? status,
  String? sas4Code,
  bool noReply = false,
  bool lastUncertain = false,
}) =>
    (
      result: (
        ok: ok,
        message: message,
        code: code,
        wa: null,
        waPreview: null,
        card: null,
        debtWriteFailed: false,
        debtWriteMessage: null,
      ),
      status: status ?? (ok ? 200 : 422),
      sas4Code: sas4Code,
      noReply: noReply,
      lastUncertain: lastUncertain,
    );

/// خادمٌ وهميّ على `ApiClient.dio`: يعدّ الطلبات ويردّ بما يُضبط له.
class _Fake implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  (int, Object?) Function(RequestOptions o) reply = (_) => (200, {});
  Duration delay = Duration.zero;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final (status, body) = reply(o);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// عقد الخادم: `{success, data:{provider, supported, code, reason, method,
/// checked, limits:{max_batch, prefetch_concurrency, run_concurrency}}}`.
Map<String, Object?> _capBody({
  required bool supported,
  String code = 'OK',
  String? reason,
  bool checked = true,
  String provider = 'sas4',
}) =>
    {
      'success': true,
      'data': {
        'provider': provider,
        'supported': supported,
        'code': code,
        'reason': reason,
        'method': supported ? 'credit' : null,
        'checked': checked,
        'limits': {
          'max_batch': 100,
          'prefetch_concurrency': 4,
          'run_concurrency': 1,
        },
      },
    };

void main() {
  // ═══════════════════════ حكم القدرة ═══════════════════════
  group('BulkActivateCapability.fromJson — عقد الخادم', () {
    test('ساسٌ يقدر (OK) ⇒ معروفٌ ومسموح، والحدود تُقرأ', () {
      final c = BulkActivateCapability.fromJson(_capBody(supported: true));
      expect(c.known, isTrue);
      expect(c.allowed, isTrue);
      expect(c.blocked, isFalse);
      expect(c.maxBatch, 100);
      expect(c.prefetchConcurrency, 4);
      expect(c.message, isNull);
    });

    test('🚨 كارت فقط (CARD_ONLY) ⇒ ممنوعٌ بسبب الخادم حرفيّاً', () {
      const reason =
          'هذا الحساب في الساس يفعّل بالكارت فقط، والتفعيل الجماعيّ يخصم من الرصيد — فعّل كلّ مشترك من نافذته';
      final c = BulkActivateCapability.fromJson(
          _capBody(supported: false, code: 'CARD_ONLY', reason: reason));
      expect(c.known, isTrue);
      expect(c.blocked, isTrue);
      expect(c.code, 'CARD_ONLY');
      expect(c.message, reason);
    });

    test('موظّفٌ بلا subscribers.activate (NO_EMPLOYEE_PERMISSION) ⇒ مقفلٌ بنصّ الخادم',
        () {
      final c = BulkActivateCapability.fromJson(_capBody(
          supported: false,
          code: 'NO_EMPLOYEE_PERMISSION',
          reason: 'ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك'));
      expect(c.blocked, isTrue);
      expect(c.message, contains('اطلبها من مديرك'));
    });

    test('ايرث لنك (EL_BULK_UNSUPPORTED) ⇒ ممنوع', () {
      final c = BulkActivateCapability.fromJson(_capBody(
          supported: false,
          code: 'EL_BULK_UNSUPPORTED',
          provider: 'earthlink',
          reason: 'ايرث لنك: التفعيل الجماعيّ غير متاح'));
      expect(c.blocked, isTrue);
    });

    test('🚨 «لا نعرف» ليست «ممنوع»: UNKNOWN · checked:false · بلا supported', () {
      for (final raw in <Object?>[
        _capBody(supported: true, code: 'UNKNOWN', checked: false),
        // ساسٌ لا يعرف صلاحيّات الطرق أصلاً (نسخةٌ أقدم): checked:true وUNKNOWN.
        _capBody(supported: true, code: 'UNKNOWN'),
        // حكمٌ سالب لم يُفحص فعلاً لا يقفل.
        _capBody(supported: false, code: 'NO_CREDIT', checked: false),
        _capBody(supported: false, code: 'UNKNOWN'),
        {'success': true, 'data': const []}, // خادمٌ أقدم/مسارٌ مجهول
        {'success': true, 'data': {'supported': null}},
        {'success': false, 'message': 'x'},
        'نصّ',
        null,
      ]) {
        final c = BulkActivateCapability.fromJson(raw);
        expect(c.known, isFalse, reason: '$raw');
        expect(c.allowed, isTrue, reason: '$raw');
        expect(c.blocked, isFalse, reason: '$raw');
      }
    });

    test('الحدود تُقرأ حتى مع المجهول، والقيم الفاسدة تُهمل', () {
      final c = BulkActivateCapability.fromJson({
        'success': true,
        'data': {
          'supported': true,
          'code': 'UNKNOWN',
          'checked': false,
          'limits': {'max_batch': 50, 'run_concurrency': 0, 'prefetch_concurrency': 'x'},
        },
      });
      expect(c.known, isFalse);
      expect(c.maxBatch, 50);
      expect(c.prefetchConcurrency, isNull);
    });
  });

  // ═══════════════════════ حكم الصفّ ═══════════════════════
  group('judgeBulkActivate — أيّ ردٍّ يقف الدفعة', () {
    test('نجاح ⇒ تمّ، بلا توقّف', () {
      final s = judgeBulkActivate(_out(ok: true));
      expect(s.status, BulkRowStatus.done);
      expect(s.stop, isNull);
    });

    test('🚨 الجلسة: 401، أو 409 SAS_SESSION_EXPIRED (الجماعيّ) ⇒ يقف', () {
      for (final o in [
        _out(status: 401, message: 'انتهت صلاحية الجلسة'),
        _out(
            status: 409,
            code: 'SAS_SESSION_EXPIRED',
            message: 'انتهت جلسة الساس — لم يُفعَّل هذا المشترك'),
      ]) {
        final s = judgeBulkActivate(o);
        expect(s.status, BulkRowStatus.failed);
        expect(s.stop, BulkStopKind.session);
      }
    });

    test('🚨 الرصيد: 422 INSUFFICIENT_BALANCE، أو رمز الساس وحده ⇒ يقف', () {
      for (final o in [
        _out(
            status: 422,
            code: 'INSUFFICIENT_BALANCE',
            sas4Code: 'rsp_insufficient_balance',
            message: 'رصيد المدير غير كافٍ لإتمام العملية'),
        _out(status: 422, sas4Code: 'rsp_insufficient_balance'),
      ]) {
        expect(judgeBulkActivate(o).stop, BulkStopKind.balance);
      }
    });

    test('🚨 الحساب: 403، CREDIT_NOT_ALLOWED، و409 BULK_ACTIVATE_UNSUPPORTED ⇒ يقف',
        () {
      for (final o in [
        _out(status: 403, message: 'فشل التفعيل', sas4Code: ''),
        _out(status: 403, code: 'CREDIT_NOT_ALLOWED'),
        _out(status: 403, code: 'EMPLOYEE_ACCESS_DENIED'),
        _out(status: 409, code: 'BULK_ACTIVATE_UNSUPPORTED', message: 'كارت فقط'),
      ]) {
        final s = judgeBulkActivate(o);
        expect(s.status, BulkRowStatus.failed);
        expect(s.stop, BulkStopKind.permission, reason: '${o.result.code}');
      }
    });

    test('رفضٌ للدفعة: 429، 402 (اشتراكٌ منتهٍ)، EL_METHOD_REQUIRED، وأيّ BULK_* آخر ⇒ يقف',
        () {
      for (final o in [
        _out(status: 429),
        _out(status: 402, message: 'انتهى اشتراكك — فعّل كوداً للمتابعة'),
        _out(status: 409, code: 'EL_METHOD_REQUIRED'),
        _out(status: 409, code: 'BULK_SOMETHING_NEW'),
        _out(status: 422, sas4Code: 'rsp_rate_limited'),
      ]) {
        expect(judgeBulkActivate(o).stop, BulkStopKind.refused,
            reason: '${o.status} ${o.result.code}');
      }
    });

    test('🚨 «ربّما تفعّل» يقف ولا يُعدّ رفضاً: بلا ردّ · OUTCOME_UNKNOWN · NOT_CONFIRMED · 5xx',
        () {
      for (final o in [
        _out(noReply: true, status: null, code: SubscribersApi.activateOutcomeUnknown),
        _out(status: 409, code: 'OUTCOME_UNKNOWN'),
        _out(status: 409, code: 'NOT_CONFIRMED'),
        _out(status: 524),
        _out(status: 502),
      ]) {
        final s = judgeBulkActivate(o);
        expect(s.status, BulkRowStatus.unclear, reason: '${o.status} ${o.result.code}');
        expect(s.stop, BulkStopKind.unclear);
      }
    });

    test('تمّ وتعذّر ما بعده (APPLIED_WITH_ERRORS) ⇒ تمّ بتنبيه، والدفعة تكمل', () {
      final s = judgeBulkActivate(_out(
          status: 409,
          code: 'APPLIED_WITH_ERRORS',
          message: 'تمّ التفعيل في الساس، لكن تعذّر إكمال ما بعده'));
      expect(s.status, BulkRowStatus.done);
      expect(s.stop, isNull);
      expect(s.message, contains('تمّ التفعيل'));
    });

    test('فُعِّل قبل لحظات / عمليّةٌ جارية عليه ⇒ لم يُنفَّذ، والدفعة تكمل', () {
      for (final code in ['RECENT_DUPLICATE', 'IN_PROGRESS']) {
        final s = judgeBulkActivate(
            _out(status: 409, code: code, message: 'رسالة الخادم'));
        expect(s.status, BulkRowStatus.skipped);
        expect(s.stop, isNull);
        expect(s.message, 'رسالة الخادم');
      }
    });

    test('🚨 حارس التكرار ومحاولةٌ سابقة لم يُعرف إن نُفّذت (last.uncertain) ⇒ غير مؤكّد لا «لم يُنفَّذ»، والدفعة تكمل',
        () {
      final s = judgeBulkActivate(_out(
          status: 409,
          code: 'RECENT_DUPLICATE',
          message: 'محاولةٌ سابقة لم يتأكّد إن نُفّذت',
          lastUncertain: true));
      expect(s.status, BulkRowStatus.unclear);
      expect(s.stop, isNull, reason: 'الطلب نفسه لم يلمس الساس');
      expect(s.message, 'محاولةٌ سابقة لم يتأكّد إن نُفّذت');
      // IN_PROGRESS لا يحمل last — يبقى «لم يُنفَّذ».
      expect(
          judgeBulkActivate(_out(status: 409, code: 'IN_PROGRESS', lastUncertain: true))
              .status,
          BulkRowStatus.skipped);
    });

    test('رفضٌ يخصّ الصفّ وحده (باقةٌ لا تُفعَّل له، غير موجود) ⇒ رُفض، تكمل', () {
      for (final o in [
        _out(status: 422, sas4Code: 'rsp_profile_not_allowed', message: 'الباقة غير مسموحة'),
        _out(status: 404, message: 'المشترك غير موجود'),
        _out(status: 400, message: 'idx غير صالح'),
      ]) {
        final s = judgeBulkActivate(o);
        expect(s.status, BulkRowStatus.failed);
        expect(s.stop, isNull);
      }
    });
  });

  // ═══════════════════════ تشغيل الدفعة ═══════════════════════
  group('runBulkActivations — يقف عند أوّل رفضٍ قاطع', () {
    test('🚨 رصيدٌ نفد عند الثالث: لا نداء بعده، والباقون «لم يُنفَّذ»', () async {
      final sent = <int>[];
      final steps = <int, BulkStep>{};
      final report = await runBulkActivations<int>(
        items: [1, 2, 3, 4, 5, 6],
        activate: (i) async {
          sent.add(i);
          return i == 3
              ? _out(status: 422, code: 'INSUFFICIENT_BALANCE', message: 'رصيد المدير غير كافٍ')
              : _out(ok: true);
        },
        onStep: (i, s) => steps[i] = s,
      );
      expect(sent, [1, 2, 3], reason: 'لا شيء بعد الرفض القاطع');
      expect(report.done, 2);
      expect(report.failed, 1);
      expect(report.skipped, 3);
      expect(report.unclear, 0);
      expect(report.stoppedBy, BulkStopKind.balance);
      expect(report.stopMessage, 'رصيد المدير غير كافٍ');
      expect(steps[4]!.status, BulkRowStatus.skipped);
      expect(steps[6]!.status, BulkRowStatus.skipped);
      expect(report.total, 6);
    });

    test('🚨 غير مؤكّد يقف أيضاً — لا يُبنى تفعيلٌ فوق «ربّما»', () async {
      final sent = <int>[];
      final report = await runBulkActivations<int>(
        items: [1, 2, 3],
        activate: (i) async {
          sent.add(i);
          return i == 1 ? _out(noReply: true, status: null) : _out(ok: true);
        },
        onStep: (_, __) {},
      );
      expect(sent, [1]);
      expect(report.unclear, 1);
      expect(report.skipped, 2);
      expect(report.stoppedBy, BulkStopKind.unclear);
    });

    test('🚨 رفضٌ يخصّ صفّاً لا يقف أبداً — ولو تتالى (لا يحبس «تجديد الباقين»)',
        () async {
      final sent = <int>[];
      final report = await runBulkActivations<int>(
        items: [1, 2, 3, 4, 5, 6, 7],
        activate: (i) async {
          sent.add(i);
          // كلّها مرفوضةٌ لسببها (باقةٌ لا تُفعَّل له) إلّا الثاني.
          return i == 2
              ? _out(ok: true)
              : _out(
                  status: 422,
                  sas4Code: 'rsp_profile_not_allowed',
                  message: 'الباقة غير مسموحة لهذا المشترك');
        },
        onStep: (_, __) {},
      );
      expect(sent, [1, 2, 3, 4, 5, 6, 7], reason: 'كالويب: لا وقوف على رفض صفّ');
      expect(report.done, 1);
      expect(report.failed, 6);
      expect(report.skipped, 0);
      expect(report.stopped, isFalse);
    });

    test('فُعِّل قبل لحظات (RECENT_DUPLICATE) لا يقف ولا يُعدّ رفضاً', () async {
      final report = await runBulkActivations<int>(
        items: [1, 2, 3],
        activate: (i) async => i == 2
            ? _out(status: 409, code: 'RECENT_DUPLICATE', message: 'فُعِّل قبل 20 ثانية')
            : _out(ok: true),
        onStep: (_, __) {},
      );
      expect(report.done, 2);
      expect(report.skipped, 1);
      expect(report.stopped, isFalse);
    });

    test('🚨 تزامنٌ محدود: لا يتجاوز المطلوب، وسقفه ٣ مهما طُلب', () async {
      Future<int> maxInFlight(int concurrency) async {
        var inFlight = 0;
        var peak = 0;
        await runBulkActivations<int>(
          items: List.generate(12, (i) => i),
          concurrency: concurrency,
          activate: (i) async {
            inFlight++;
            peak = inFlight > peak ? inFlight : peak;
            await Future<void>.delayed(const Duration(milliseconds: 2));
            inFlight--;
            return _out(ok: true);
          },
          onStep: (_, __) {},
        );
        return peak;
      }

      expect(await maxInFlight(1), 1, reason: 'الافتراض: واحدٌ تلو واحد');
      expect(await maxInFlight(2), 2);
      expect(await maxInFlight(50), bulkMaxActivateConcurrency);
      expect(await maxInFlight(0), 1);
    });

    test('بتزامنٍ ٢: بعد الرفض القاطع لا يُرسَل جديد (الجاري يكمل)', () async {
      final sent = <int>[];
      final report = await runBulkActivations<int>(
        items: List.generate(8, (i) => i),
        concurrency: 2,
        activate: (i) async {
          sent.add(i);
          await Future<void>.delayed(Duration(milliseconds: i == 0 ? 1 : 5));
          return i == 0 ? _out(status: 401) : _out(ok: true);
        },
        onStep: (_, __) {},
      );
      expect(sent, [0, 1], reason: 'الثاني كان جارياً لحظة الرفض — لا ثالث');
      expect(report.stoppedBy, BulkStopKind.session);
      expect(report.done + report.failed + report.skipped, 8);
    });

    test('الإيقاف من المستخدم: بعد الحاليّ لا شيء، والباقون «لم يُنفَّذ»', () async {
      var stop = false;
      final sent = <int>[];
      final report = await runBulkActivations<int>(
        items: [1, 2, 3, 4],
        shouldStop: () => stop,
        activate: (i) async {
          sent.add(i);
          if (i == 2) stop = true; // ضغط «أوقف» أثناء الثاني
          return _out(ok: true);
        },
        onStep: (_, __) {},
      );
      expect(sent, [1, 2]);
      expect(report.done, 2);
      expect(report.skipped, 2);
      expect(report.stoppedBy, BulkStopKind.cancelled);
    });

    test('نداءٌ يرمي ⇒ غير مؤكّد ويقف (لا نعرف إن وصل الطلب)', () async {
      final report = await runBulkActivations<int>(
        items: [1, 2],
        activate: (i) async => throw StateError('boom'),
        onStep: (_, __) {},
      );
      expect(report.unclear, 1);
      expect(report.skipped, 1);
      expect(report.stoppedBy, BulkStopKind.unclear);
    });

    test('onStart قبل كلّ إرسال، وonStep لكلّ صفّ مرّةً واحدة', () async {
      final started = <int>[];
      final stepped = <int>[];
      await runBulkActivations<int>(
        items: [1, 2, 3],
        activate: (i) async => i == 2 ? _out(status: 403) : _out(ok: true),
        onStart: started.add,
        onStep: (i, _) => stepped.add(i),
      );
      expect(started, [1, 2]);
      expect(stepped, [1, 2, 3]);
    });
  });

  // ═══════════════════════ جلسة الساس في المنتصف ═══════════════════════
  group('activateWithSessionRetry — 409 SAS_SESSION_EXPIRED يُجدَّد ويُعاد مرّةً', () {
    ActivateOutcome expired() => _out(
        status: 409,
        code: 'SAS_SESSION_EXPIRED',
        message: 'انتهت جلسة الساس — لم يُفعَّل هذا المشترك.');

    test('🚨 التجديد ينجح ⇒ يُعاد الصفّ مرّةً ويُحكم بالإعادة', () async {
      var sends = 0;
      var refreshes = 0;
      final o = await activateWithSessionRetry(
        send: () async => ++sends == 1 ? expired() : _out(ok: true),
        refresh: () async {
          refreshes++;
          return true;
        },
      );
      expect([sends, refreshes], [2, 1]);
      expect(judgeBulkActivate(o).status, BulkRowStatus.done);
    });

    test('التجديد مرفوض (موظّف/جلسةٌ ميتة) أو يرمي ⇒ لا إعادة، والدفعة تقف بالجلسة', () async {
      for (final refresh in <Future<bool> Function()>[
        () async => false,
        () async => throw StateError('net'),
      ]) {
        var sends = 0;
        final o = await activateWithSessionRetry(
          send: () async {
            sends++;
            return expired();
          },
          refresh: refresh,
        );
        expect(sends, 1);
        expect(judgeBulkActivate(o).stop, BulkStopKind.session);
      }
    });

    test('لا حلقة: انتهت ثانيةً بعد التجديد ⇒ حكم الإعادة (تقف) بلا تجديدٍ ثانٍ', () async {
      var sends = 0;
      var refreshes = 0;
      final o = await activateWithSessionRetry(
        send: () async {
          sends++;
          return expired();
        },
        refresh: () async {
          refreshes++;
          return true;
        },
      );
      expect([sends, refreshes], [2, 1]);
      expect(judgeBulkActivate(o).stop, BulkStopKind.session);
    });

    test('أيّ ردٍّ آخر لا يجدّد شيئاً (نجاح، رصيد، 401، صلاحيّة)', () async {
      for (final r in [
        _out(ok: true),
        _out(status: 422, code: 'INSUFFICIENT_BALANCE'),
        _out(status: 401),
        _out(status: 403, code: 'CREDIT_NOT_ALLOWED'),
      ]) {
        var refreshes = 0;
        var sends = 0;
        await activateWithSessionRetry(
          send: () async {
            sends++;
            return r;
          },
          refresh: () async {
            refreshes++;
            return true;
          },
        );
        expect([sends, refreshes], [1, 0], reason: '${r.status} ${r.result.code}');
      }
    });

    test('في الدفعة: الصفّ المُعاد يُحسب مرّةً واحدة والدفعة تكمل', () async {
      final sent = <int>[];
      final calls = <int, int>{};
      final report = await runBulkActivations<int>(
        items: [1, 2, 3],
        activate: (i) => activateWithSessionRetry(
          send: () async {
            sent.add(i);
            calls[i] = (calls[i] ?? 0) + 1;
            return i == 2 && calls[i] == 1 ? expired() : _out(ok: true);
          },
          refresh: () async => true,
        ),
        onStep: (_, __) {},
      );
      expect(sent, [1, 2, 2, 3]);
      expect(report.done, 3);
      expect(report.stopped, isFalse);
    });
  });

  // ═══════════════════════ الجلب المسبق ═══════════════════════
  group('boundedFetch — تزامنٌ محدود ويقف عند رفضٍ قاطع', () {
    test('🚨 لا يتجاوز التزامن، ويحفظ الترتيب', () async {
      var inFlight = 0;
      var peak = 0;
      final out = await boundedFetch<int, int>(
        items: List.generate(20, (i) => i),
        concurrency: 4,
        fetch: (i) async {
          inFlight++;
          peak = inFlight > peak ? inFlight : peak;
          await Future<void>.delayed(Duration(milliseconds: 1 + (i % 3)));
          inFlight--;
          return i * 10;
        },
      );
      expect(peak, 4);
      expect(out, [for (var i = 0; i < 20; i++) i * 10]);
    });

    test('🚨 رفضٌ قاطع ⇒ لا طلب جديد بعده (مئتا صفٍّ بجلسةٍ منتهية = طلباتٌ قليلة)',
        () async {
      var calls = 0;
      final out = await boundedFetch<int, int>(
        items: List.generate(200, (i) => i),
        concurrency: 4,
        fetch: (i) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return 401;
        },
        stopAfter: (r) => r == 401,
      );
      expect(calls, lessThanOrEqualTo(4));
      expect(out.whereType<int>().length, calls);
      expect(out.where((r) => r == null).length, 200 - calls);
    });

    test('قائمةٌ فارغة لا تنادي شيئاً', () async {
      var calls = 0;
      final out = await boundedFetch<int, int>(
        items: const [],
        fetch: (i) async => ++calls,
      );
      expect(out, isEmpty);
      expect(calls, 0);
    });
  });

  // ═══════════════════════ الفحص المسبق للرصيد ═══════════════════════
  group('BulkPreflight — الرصيد مقابل الكلفة حين تُعرف', () {
    test('رصيدٌ مجهول ⇒ لا حكم (لا قصر ولا تحذير)', () {
      final p = BulkPreflight.compute(balance: null, costs: [10000, 10000]);
      expect(p.insufficient, isFalse);
      expect(p.sufficient, isFalse);
      expect(p.fitCount, isNull);
    });

    test('يكفي يقيناً', () {
      final p = BulkPreflight.compute(balance: 30000, costs: [10000, 20000]);
      expect(p.sufficient, isTrue);
      expect(p.insufficient, isFalse);
      expect(p.fitCount, 2);
      expect(p.knownCost, 30000);
    });

    test('🚨 لا يكفي: يكفي أوّل اثنين من أربعة، والعجز صحيح', () {
      final p = BulkPreflight.compute(
          balance: 25000, costs: [10000, 10000, 10000, 10000]);
      expect(p.insufficient, isTrue);
      expect(p.fitCount, 2);
      expect(p.shortfall, 15000);
      expect(p.count, 4);
    });

    test('كلفةٌ مجهولة: المعروف حدٌّ أدنى — يتجاوز ⇒ لا يكفي، وإلّا لا حكم', () {
      final over =
          BulkPreflight.compute(balance: 15000, costs: [10000, null, 10000]);
      expect(over.insufficient, isTrue);
      expect(over.fitCount, 1, reason: 'العدّ يقف عند أوّل كلفةٍ مجهولة');

      final under = BulkPreflight.compute(balance: 50000, costs: [10000, null]);
      expect(under.insufficient, isFalse);
      expect(under.sufficient, isFalse, reason: 'كلفةٌ مجهولة ⇒ لا يقين');
      expect(under.costKnown, isFalse);
    });

    test('🚨 رصيدٌ صفر (مديرٌ بالكارت) ⇒ لا يكفي ولا واحداً', () {
      final p = BulkPreflight.compute(balance: 0, costs: [46000, 46000]);
      expect(p.insufficient, isTrue);
      expect(p.fitCount, 0);
    });

    test('bulkNumOrNull يقرأ «IQD 3,120,000.00» والرقم، وغيره null', () {
      expect(bulkNumOrNull('IQD 3,120,000.00'), 3120000);
      expect(bulkNumOrNull(46000), 46000);
      expect(bulkNumOrNull('46000'), 46000);
      expect(bulkNumOrNull(null), isNull);
      expect(bulkNumOrNull(true), isNull);
      expect(bulkNumOrNull('—'), isNull);
    });
  });

  // ═══════════════════════ الشبكة ═══════════════════════
  group('BulkActivateApi.capability — نداءٌ واحد وكاشٌ للجلسة', () {
    late _Fake fake;
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      fake = _Fake();
      ApiClient.dio.httpClientAdapter = fake;
      BulkActivateApi.reset();
    });
    tearDown(BulkActivateApi.reset);

    test('طلبان معاً ⇒ نداءٌ واحد، ثمّ من الكاش', () async {
      fake.reply = (_) => (200, _capBody(supported: false, code: 'CARD_ONLY', reason: 'كارت فقط'));
      fake.delay = const Duration(milliseconds: 5);
      final both = await Future.wait(
          [BulkActivateApi.capability(), BulkActivateApi.capability()]);
      expect(both[0].blocked, isTrue);
      expect(both[1].blocked, isTrue);
      expect(fake.requests.length, 1);
      expect(fake.requests.single.path, BulkActivateApi.path);
      final again = await BulkActivateApi.capability();
      expect(again.message, 'كارت فقط');
      expect(fake.requests.length, 1, reason: 'من الكاش');
      expect(BulkActivateApi.cached?.blocked, isTrue);
      await BulkActivateApi.capability(fresh: true);
      expect(fake.requests.length, 2);
    });

    test('🚨 المجهول (خادمٌ أقدم 404 / 5xx) لا يقفل ولا يُكاش', () async {
      fake.reply = (_) => (404, {'success': false});
      final a = await BulkActivateApi.capability();
      expect(a.known, isFalse);
      expect(a.blocked, isFalse);
      await BulkActivateApi.capability();
      expect(fake.requests.length, 2, reason: 'يُسأل ثانيةً');

      fake.reply = (_) => (503, 'down');
      final b = await BulkActivateApi.capability();
      expect(b.blocked, isFalse);
    });

    test('المجهول لا يزيح حكماً معروفاً', () async {
      fake.reply = (_) => (200, _capBody(supported: false, code: 'NO_CREDIT', reason: 'بلا رصيد'));
      await BulkActivateApi.capability();
      fake.reply = (_) => (500, {});
      await BulkActivateApi.capability(fresh: true);
      expect(BulkActivateApi.cached?.blocked, isTrue);
    });

    test('🚨 خروجٌ أثناء النداء: الردّ القديم لا يُطبَّق على الجلسة الجديدة', () async {
      fake.reply = (_) => (200, _capBody(supported: false, code: 'CARD_ONLY'));
      fake.delay = const Duration(milliseconds: 10);
      final f = BulkActivateApi.capability();
      BulkActivateApi.reset();
      final r = await f;
      expect(r.known, isFalse);
      expect(BulkActivateApi.cached, isNull);
    });

    test('🚨 الحكم المقفل يُعاد سؤاله بعد دقيقة، والمسموح بعد خمس', () async {
      fake.reply = (_) => (200, _capBody(supported: false, code: 'CARD_ONLY', reason: 'كارت فقط'));
      await BulkActivateApi.capability();
      expect(fake.requests.length, 1);
      BulkActivateApi.debugAge(const Duration(seconds: 50));
      await BulkActivateApi.capability();
      expect(fake.requests.length, 1, reason: 'أحدث من دقيقة ⇒ الكاش');
      BulkActivateApi.debugAge(const Duration(seconds: 15));
      // مُنحت الصلاحيّة في الساس: السؤال بعد الدقيقة يفتح الزرّ.
      fake.reply = (_) => (200, _capBody(supported: true));
      final c = await BulkActivateApi.capability();
      expect(fake.requests.length, 2);
      expect(c.blocked, isFalse);
      expect(BulkActivateApi.cached?.blocked, isFalse);
      // المسموح يبقى خمس دقائق.
      BulkActivateApi.debugAge(const Duration(minutes: 4));
      await BulkActivateApi.capability();
      expect(fake.requests.length, 2);
      BulkActivateApi.debugAge(const Duration(minutes: 2));
      await BulkActivateApi.capability();
      expect(fake.requests.length, 3);
    });

    test('recheckIfLocked: يعيد السؤال حين القفل من الخادم وحده', () async {
      BulkActivateApi.recheckIfLocked(); // لا حكم ⇒ لا شيء
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fake.requests, isEmpty);
      fake.reply = (_) => (200, _capBody(supported: true));
      await BulkActivateApi.capability();
      BulkActivateApi.recheckIfLocked(); // مسموح ⇒ لا شيء
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fake.requests.length, 1);
      fake.reply = (_) => (200, _capBody(supported: false, code: 'NO_CREDIT', reason: 'بلا رصيد'));
      await BulkActivateApi.capability(fresh: true);
      expect(fake.requests.length, 2);
      fake.reply = (_) => (200, _capBody(supported: true));
      BulkActivateApi.recheckIfLocked(); // مقفل ⇒ سؤالٌ طازج يفتحه
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.requests.length, 3);
      expect(BulkActivateApi.cached?.blocked, isFalse);
    });

    test('مسح الجلسة (SubscribersApi.clearAllCaches) يمسح الحكم', () async {
      fake.reply = (_) => (200, _capBody(supported: false, code: 'CARD_ONLY'));
      await BulkActivateApi.capability();
      expect(BulkActivateApi.cached, isNotNull);
      SubscribersApi.clearAllCaches();
      expect(BulkActivateApi.cached, isNull);
    });
  });

  group('SubscribersApi.activateDetailed — الجماعيّ يُعلَّم ويُقرأ رفضه', () {
    late _Fake fake;
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      fake = _Fake();
      ApiClient.dio.httpClientAdapter = fake;
    });

    Map<String, dynamic> body() =>
        Map<String, dynamic>.from(jsonDecode(fake.requests.last.data is String
            ? fake.requests.last.data as String
            : jsonEncode(fake.requests.last.data)) as Map);

    test('🚨 bulk:true للجماعيّ وحده — والمفرد كما كان حرفيّاً', () async {
      fake.reply = (_) => (200, {'success': true});
      await SubscribersApi.activateDetailed(
        idx: '7',
        paymentType: 'non-cash',
        activationData: const {'user_price': 1},
        bulk: true,
      );
      expect(body()['bulk'], isTrue);
      expect(body().containsKey('method'), isFalse, reason: 'رصيدٌ ضمناً');

      await SubscribersApi.activate(
        idx: '7',
        paymentType: 'non-cash',
        activationData: const {'user_price': 1},
      );
      expect(body().keys.toSet(), {'paymentType', 'activationData'});
    });

    test('حالة HTTP ورمز الساس يصلان مع الرفض', () async {
      fake.reply = (_) => (
            422,
            {
              'success': false,
              'code': 'INSUFFICIENT_BALANCE',
              'message': 'رصيد المدير غير كافٍ لإتمام العملية',
              'sas4_code': 'rsp_insufficient_balance',
            }
          );
      final o = await SubscribersApi.activateDetailed(
        idx: '7',
        paymentType: 'cash',
        activationData: const {'user_price': 1},
        bulk: true,
      );
      expect(o.result.ok, isFalse);
      expect(o.status, 422);
      expect(o.result.code, 'INSUFFICIENT_BALANCE');
      expect(o.sas4Code, 'rsp_insufficient_balance');
      expect(o.noReply, isFalse);
      expect(judgeBulkActivate(o).stop, BulkStopKind.balance);
    });

    test('حارس التكرار: last.uncertain يصل (ويُحكم غير مؤكّد)', () async {
      fake.reply = (_) => (
            409,
            {
              'success': false,
              'code': 'RECENT_DUPLICATE',
              'message': 'محاولةٌ سابقة لم يتأكّد إن نُفّذت',
              'last': {'at_sec_ago': 40, 'uncertain': true},
            }
          );
      var o = await SubscribersApi.activateDetailed(
        idx: '7',
        paymentType: 'cash',
        activationData: const {'user_price': 1},
        bulk: true,
      );
      expect(o.lastUncertain, isTrue);
      expect(judgeBulkActivate(o).status, BulkRowStatus.unclear);
      fake.reply = (_) => (
            409,
            {
              'success': false,
              'code': 'RECENT_DUPLICATE',
              'message': 'فُعِّل قبل 9 ثانية',
              'last': {'uncertain': false},
            }
          );
      o = await SubscribersApi.activateDetailed(
        idx: '7',
        paymentType: 'cash',
        activationData: const {'user_price': 1},
        bulk: true,
      );
      expect(o.lastUncertain, isFalse);
      expect(judgeBulkActivate(o).status, BulkRowStatus.skipped);
    });

    test('409 SAS_SESSION_EXPIRED (الجماعيّ) ⇒ يقف بالجلسة', () async {
      fake.reply = (_) => (
            409,
            {
              'success': false,
              'code': 'SAS_SESSION_EXPIRED',
              'message': 'انتهت جلسة الساس — لم يُفعَّل هذا المشترك.',
            }
          );
      final o = await SubscribersApi.activateDetailed(
        idx: '7',
        paymentType: 'cash',
        activationData: const {'user_price': 1},
        bulk: true,
      );
      expect(o.status, 409);
      expect(judgeBulkActivate(o).stop, BulkStopKind.session);
    });
  });
}
