import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import '../api/subscribers_api.dart';
import '../core/util/bidi.dart';
import '../core/widgets/sheet_scaffold.dart';
import '../models/subscriber.dart';
import 'merged_mode.dart';

/// العمليّات التي تتبعها رسالةٌ للمشترك: تأكيد التسديد، إشعار التفعيل، إشعار التمديد.
enum OpWaKind {
  pay('pay'),
  activate('activate'),
  extend('extend');

  const OpWaKind(this.wire);

  /// اسمها في `op=` عند الخادم (GET …/op-wa).
  final String wire;
}

/// تحذيرٌ يتبع إشعار النجاح (الدين لم يُسجَّل، أشهرٌ غير المطلوبة…): يُعرض بعده وقبل نتيجة الرسالة، كلٌّ في دوره.
typedef OpFollowUp = ({String text, Duration duration});

/// ما يُقال للمدير عن رسالة العمليّة: [sent] أُرسلت، وإلّا [reason] نصّ السبب جاهزاً للعرض.
@immutable
class OpWaVerdict {
  const OpWaVerdict.sent()
      : sent = true,
        reason = null;
  const OpWaVerdict.failed(String this.reason) : sent = false;

  final bool sent;
  final String? reason;
}

/// «هل أُرسلت رسالة العمليّة؟» (١٧ نوفمبر — المالك: «اكيد لازم يظهرله ان انرسلت رساله حتى يعرف»).
///
/// العمليّة (تسديد/تفعيل/تمديد) تنجح وتردّ فوراً ولا تنتظر الإشعار، فنتيجة الرسالة تصل بإحدى طريقتين:
///   • في ردّ العمليّة (`wa`) حين انتهى الإشعار قبل الردّ ⇒ تُقال مع النجاح نفسه؛
///   • وإلّا تُسأل من الخادم بعد ثوانٍ ([SubscribersApi.opWa]) ⇒ إشعار النجاح يكتمل نصّه في مكانه إن كان ما زال ظاهراً،
///     وإلّا إشعارٌ صغير باسم المشترك.
///
/// ما يُقال: «أُرسلت» دائماً، و«لم تُرسل» بسببها حين يملك المدير أو الموظّف ما يفعله (الواتساب غير متصل، لا رقم،
/// لا صلاحيّة واتساب للموظّف، تعذّر الإرسال). وما اختاره المدير بنفسه — الإشعار مطفأ، القالب معطَّل، المشترك مستثنى —
/// لا يُقال (مطلب ١١ يونيو). كلّ الإشعارات على الطبقة الجذريّة فتبقى بعد إغلاق الورقة، ولا يغطّي أحدها الآخر.
class OpWaNotice {
  OpWaNotice._();

  /// موظّفٌ بلا صلاحيّة واتساب (الخادم يتخطّى إرسال رسالته — قرار المالك ١٧ نوفمبر: الإرسال بصلاحيّة الموظّف، يفعّلها المدير).
  /// يبدأ بـ`feature_off` لتسكت عنه النسخ الأقدم، وهنا يُقال: الموظّف يعرف أنّ المشترك لم تصله رسالة وممّن يطلبها.
  static const employeeNoPermission = 'feature_off:employee_no_wa_permission';

  /// متى يُسأل الخادم — المدّة بين سؤالٍ وما قبله (الأوّل بعد ردّ العمليّة). المجموع ≈ ٤٠ث ثمّ صمت.
  /// الإشعار ينتهي عادةً في ثانيةٍ أو اثنتين؛ «الواتساب غير متصل» في ٢–٥ث؛ والبقيّة لإرسالٍ بطيء.
  static const defaultPollGaps = <Duration>[
    Duration(milliseconds: 900),
    Duration(milliseconds: 1300),
    Duration(milliseconds: 1800),
    Duration(seconds: 3),
    Duration(seconds: 4),
    Duration(seconds: 6),
    Duration(seconds: 9),
    Duration(seconds: 14),
  ];

  @visibleForTesting
  static List<Duration> pollGaps = defaultPollGaps;

  static const _failDuration = Duration(seconds: 5);
  static final _arabic = RegExp(r'[\u0600-\u06FF]');

  /// نتيجة الإرسال كما تُقال — `null` = لا شيء يُقال (لا نتيجة، أو اختيارٌ مضبوط من المدير).
  static OpWaVerdict? verdictOf(WhatsAppSendInfo? wa) {
    if (wa == null) return null;
    if (wa.sent) return const OpWaVerdict.sent();
    final r = (wa.reason ?? '').trim();
    if (r.isEmpty) return null;
    if (r != employeeNoPermission &&
        (r == 'notifications_disabled' || r == 'no_template' || r.startsWith('feature_off'))) {
      return null;
    }
    return OpWaVerdict.failed(reasonText(r));
  }

  /// نصّ السبب للعرض: الأسباب المعروفة بجملتنا، ونصّ الخادم العربيّ كما هو، وما عداهما (رمزٌ تقنيّ) جملةٌ عامّة — لا
  /// يظهر للمدير رمزٌ داخليّ.
  static String reasonText(String reason) {
    final r = reason.trim();
    if (r == 'not_connected') return 'sheets.wa_reason_not_connected'.tr();
    if (r == 'no_phone') return 'sheets.wa_reason_no_phone'.tr();
    if (r == employeeNoPermission) return 'sheets.wa_reason_no_permission'.tr();
    if (r.startsWith('loopback_error')) return 'sheets.wa_reason_check_failed'.tr();
    if (_arabic.hasMatch(r)) return r;
    return 'sheets.wa_reason_send_failed'.tr();
  }

  /// يعرض إشعار نجاح العمليّة [okText] ومعه نتيجة رسالتها، ثمّ [followUps] في دورها. يُستدعى فور النجاح والورقة ما زالت
  /// مركّبة (الطبقة الجذريّة تُلتقط الآن وتبقى بعدها). يكتمل حين يزول إشعار النجاح.
  ///
  /// [wa] ما حمله ردّ العمليّة (null = لم يحمل نتيجة). [manual] = «الإرسال اليدويّ»: المدير يرسل بيده من نافذة
  /// المعاينة، فلا رسالة تلقائيّة تُنتظر نتيجتها. [pressedAt] لحظة ضغط الزرّ — يُحسب منها `age_ms`.
  static Future<void> show(
    BuildContext context, {
    required Subscriber sub,
    required OpWaKind op,
    required String okText,
    required DateTime pressedAt,
    WhatsAppSendInfo? wa,
    bool manual = false,
    Duration okDuration = const Duration(seconds: 3),
    List<OpFollowUp> followUps = const [],
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future<void>.value();
    final name = iso(sub.fullName);
    final inReply = !manual && wa != null;
    final first = inReply ? verdictOf(wa) : null;
    final sentNow = first != null && first.sent;

    // إشعار النجاح بوسمٍ خاصّ بهذه العمليّة: «أُرسلت» التي تصل وهو ظاهر تُكمل نصّه في مكانه (الجديد يُزيل سابقه).
    final tag = Object();
    final gone = Completer<void>();
    var okVisible = true;
    var replaced = false;
    void okGone() {
      okVisible = false;
      if (!gone.isCompleted) gone.complete();
    }

    unawaited(showSheetSnackOn(
      overlay,
      sentNow ? 'sheets.wa_sent_merged'.tr(args: [okText]) : okText,
      duration: okDuration,
      tag: tag,
    ).then((_) {
      if (!replaced) okGone();
    }));

    // ما يتبع النجاح كلٌّ في دوره — تحذيرات العمليّة أوّلاً ثمّ نتيجة الرسالة، فلا يغطّي إشعارٌ آخر.
    var tail = gone.future;
    void then(String text, {required bool isError, Duration duration = const Duration(seconds: 3), bool explain = false}) {
      tail = tail.then((_) => showSheetSnackOn(overlay, text, isError: isError, duration: duration, autoExplain: explain));
    }

    // تحذيرات العمليّة كما كانت (ومعها «اشرحلي» إن طابقت رفضاً من الخادم)؛ نتيجة الرسالة بنصّنا فلا شرح لها.
    for (final f in followUps) {
      then(f.text, isError: true, duration: f.duration, explain: true);
    }

    void say(OpWaVerdict v) {
      if (!v.sent) {
        then(_failedText(op, name, v.reason ?? ''), isError: true, duration: _failDuration);
        return;
      }
      if (okVisible && !replaced) {
        replaced = true;
        unawaited(showSheetSnackOn(
          overlay,
          'sheets.wa_sent_merged'.tr(args: [okText]),
          duration: okDuration,
          tag: tag,
        ).then((_) => okGone()));
        return;
      }
      then(_sentText(op, name), isError: false);
    }

    if (inReply) {
      if (first != null && !first.sent) say(first);
    } else if (!manual) {
      unawaited(_ask(sub, op, pressedAt).then((v) {
        if (v != null && overlay.mounted) say(v);
      }));
    }
    return gone.future;
  }

  /// يسأل الخادم عن نتيجة الرسالة حتى تُحسم أو تنقضي المواعيد. `null` = لا شيء يُقال.
  static Future<OpWaVerdict?> _ask(Subscriber sub, OpWaKind op, DateTime pressedAt) async {
    final idx = sub.idx;
    if (idx == null || idx.isEmpty) return null;
    var nones = 0;
    var lost = 0;
    for (final gap in pollGaps) {
      await Future<void>.delayed(gap);
      final r = await MergedOps.run(
        sub,
        () => SubscribersApi.opWa(idx, op: op.wire, ageMs: DateTime.now().difference(pressedAt).inMilliseconds),
      );
      if (r == null) return null; // ردٌّ لا يُقرأ (رفض، خادمٌ بلا المسار) ⇒ لا سؤال ثانٍ
      final info = r.info;
      if (info != null) return verdictOf(info);
      // «لا إشعار لهذه العمليّة»: مرّتان تكفيان (الأولى قد تسبق كتابة سطر الحركة بلحظة)
      if (r.state == 'none' && ++nones >= 2) return null;
      // انقطعت الشبكة بعد العمليّة: محاولتان ثمّ صمت — لا طرق متواصل على شبكةٍ غائبة
      if (r.state == OpWaRead.unreachable.state && ++lost >= 2) return null;
      // pending / أوّل none / أوّل انقطاع ⇒ الموعد التالي
    }
    return null;
  }

  static String _sentText(OpWaKind op, String name) => switch (op) {
        OpWaKind.pay => 'sheets.wa_sent_pay'.tr(args: [name]),
        OpWaKind.activate => 'sheets.wa_sent_activate'.tr(args: [name]),
        OpWaKind.extend => 'sheets.wa_sent_extend'.tr(args: [name]),
      };

  static String _failedText(OpWaKind op, String name, String reason) => switch (op) {
        OpWaKind.pay => 'sheets.wa_failed_pay'.tr(args: [name, reason]),
        OpWaKind.activate => 'sheets.wa_failed_activate'.tr(args: [name, reason]),
        OpWaKind.extend => 'sheets.wa_failed_extend'.tr(args: [name, reason]),
      };
}
