import 'package:flutter/foundation.dart';

import 'fiber_band.dart';
import 'fiber_onu.dart';

/// ما يلزم التشخيصَ من حساب المشترك بالساس (يبنيه المستدعي من `Subscriber` — المنطق هنا بلا واجهة ولا شبكة).
@immutable
class FiberSubscriberFacts {
  const FiberSubscriberFacts({
    required this.expired,
    required this.disabled,
    required this.sessionOnline,
    this.expiresAt,
    this.remainingDays,
    this.debt = 0,
  });

  final bool expired, disabled, sessionOnline;
  final DateTime? expiresAt;
  final int? remainingDays;

  /// الدين بالدينار (موجب = عليه).
  final double debt;
}

enum FiberVerdictKind {
  /// الجهاز مفصول لانطفاء الكهرباء عنده.
  power,

  /// الجهاز مفصول لفقدان الضوء — وحده (سلك البيت/الوصلة).
  fiberHome,

  /// الجهاز مفصول ضمن عطلٍ جماعيّ على صندوقه/منفذه.
  outage,

  /// الجهاز مفصول ولا يقول الأولت لماذا.
  onuDown,

  /// الاشتراك منتهٍ أو معطَّل — الساس يرفضه.
  subscription,

  /// الضوء ضعيف (قد يفصل ويرجع).
  weakLight,

  /// الضوء والجهاز والاشتراك سليمة ولا جلسة — الراوتر/كلمة سرّ الاتصال.
  router,

  /// كلّ شيءٍ سليم والاتصال قائم.
  allGood,

  /// لا جهاز ألياف مربوط بالمشترك — الحكم من الساس وحده.
  noOnu,

  /// الجهاز والضوء سليمان، وحساب المشترك غير معروف (غير مربوط أو لم يُقرأ) — لا حكم على الاشتراك والجلسة.
  onuOnly,
}

enum FiberStepState { ok, bad, warn, skip }

@immutable
class FiberDiagStep {
  const FiberDiagStep(this.title, this.state, this.detail);
  final String title;
  final FiberStepState state;
  final String detail;
}

@immutable
class FiberDiagnosis {
  const FiberDiagnosis({required this.kind, required this.title, required this.body, required this.steps});
  final FiberVerdictKind kind;
  final String title, body;
  final List<FiberDiagStep> steps;
}

class FiberDiagnose {
  FiberDiagnose._();

  static String _clock(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _rx(double v) => '${v.toStringAsFixed(1)} dBm';

  /// داخل جملةٍ عربيّة: معزولةً (FSI…PDI)، وإلّا تنقلب «‎-28.1 dBm» إلى «dBm 28.1-».
  static String _rxIn(double v) => '\u2068${_rx(v)}\u2069';

  /// [inOutage] = جهازه ضمن عطلٍ جماعيّ مكتشَف الآن. [boxOnline]/[boxTotal] = جيرانه على الصندوق نفسه (بلا جهازه).
  ///
  /// [sub] = `null` حين لا نعرف حسابه (الجهاز غير مربوط، أو الساس لم يُجب): الاشتراك والجلسة «غير معروف» بسبب
  /// [subUnknown] — لا «فعّال» ولا «ماكو جلسة» بلا دليل.
  static FiberDiagnosis of({
    required FiberSubscriberFacts? sub,
    FiberOnuLive? onu,
    bool inOutage = false,
    int? boxOnline,
    int? boxTotal,
    DateTime? now,
    String subUnknown = 'غير مربوط بمشترك',
  }) {
    final t = now ?? DateTime.now();
    // ١. الاشتراك
    final FiberDiagStep subStep;
    if (sub == null) {
      subStep = FiberDiagStep('الاشتراك بالساس', FiberStepState.skip, subUnknown);
    } else if (sub.disabled) {
      subStep = const FiberDiagStep('الاشتراك بالساس', FiberStepState.bad, 'الحساب معطَّل');
    } else if (sub.expired) {
      final when = sub.expiresAt == null ? '' : ' من ${_dayWord(sub.expiresAt!, t)} ${_clock(sub.expiresAt!)}';
      subStep = FiberDiagStep('الاشتراك بالساس', FiberStepState.bad, 'منتهي$when');
    } else {
      final left = sub.remainingDays;
      final parts = <String>['فعّال', if (left != null && left >= 0) 'باقي ${_days(left)}'];
      parts.add(sub.debt > 0 ? 'عليه دين' : 'بلا دين');
      subStep = FiberDiagStep('الاشتراك بالساس', sub.debt > 0 ? FiberStepState.warn : FiberStepState.ok, parts.join(' · '));
    }

    // ٢. الـONU و٣. الضوء
    final FiberDiagStep onuStep;
    final FiberDiagStep lightStep;
    if (onu == null) {
      onuStep = const FiberDiagStep('جهاز الألياف', FiberStepState.skip, 'غير مربوط بجهازٍ على الأولت');
      lightStep = const FiberDiagStep('الضوء', FiberStepState.skip, 'يحتاج ربط جهازه أوّلاً');
    } else if (!onu.online) {
      final since = onu.changedAt == null ? '' : ' من ${_clock(onu.changedAt!)}';
      final why = onu.reason == null ? '' : ' · ${fiberReasonLabel(onu.reason!)}';
      onuStep = FiberDiagStep('جهاز الألياف', onu.reason == FiberDropReason.power ? FiberStepState.warn : FiberStepState.bad,
          'مفصول$since$why');
      lightStep = const FiberDiagStep('الضوء', FiberStepState.skip, 'لا قراءة والجهاز مفصول');
    } else {
      final since = onu.changedAt == null ? 'متّصل' : 'متّصل من ${_since(onu.changedAt!, t)}';
      onuStep = FiberDiagStep('جهاز الألياف', FiberStepState.ok, since);
      final rx = onu.rx;
      if (rx == null) {
        lightStep = const FiberDiagStep('الضوء', FiberStepState.skip, 'الأولت لا يعطي قراءة الضوء');
      } else {
        final band = FiberBands.of(rx)!;
        lightStep = FiberDiagStep(
          'الضوء',
          switch (band) {
            FiberBand.good => FiberStepState.ok,
            FiberBand.marginal || FiberBand.strong => FiberStepState.warn,
            FiberBand.weak => FiberStepState.bad,
          },
          '${_rx(rx)} · ${FiberBands.label(band)}',
        );
      }
    }

    // ٤. الراوتر والجلسة
    final FiberDiagStep routerStep;
    if (onu != null && !onu.online) {
      routerStep = const FiberDiagStep('الراوتر والاتصال', FiberStepState.skip, 'ما يوصل له شي والجهاز مفصول');
    } else if (sub == null) {
      routerStep = const FiberDiagStep('الراوتر والاتصال', FiberStepState.skip, 'تُعرف من جلسة المشترك بالساس');
    } else if (sub.sessionOnline) {
      routerStep = const FiberDiagStep('الراوتر والاتصال', FiberStepState.ok, 'متّصل بالساس الآن');
    } else if (sub.expired || sub.disabled) {
      routerStep = const FiberDiagStep('الراوتر والاتصال', FiberStepState.warn, 'الراوتر يحاول والساس يرفضه');
    } else {
      routerStep = const FiberDiagStep('الراوتر والاتصال', FiberStepState.bad, 'ماكو جلسة بالساس');
    }
    final steps = List<FiberDiagStep>.unmodifiable([subStep, onuStep, lightStep, routerStep]);

    // الحكم: المادّيّ أوّلاً (التجديد لا يُرجع نتّاً لجهازٍ مفصول)، ثمّ الاشتراك، ثمّ الضوء، ثمّ الراوتر.
    if (onu != null && !onu.online) {
      final since = onu.changedAt == null ? '' : ' الساعة ${_clock(onu.changedAt!)}';
      if (inOutage) {
        return FiberDiagnosis(
          kind: FiberVerdictKind.outage,
          title: 'عطلٌ بالمنطقة، مو عنده وحده',
          body: 'جهازه انقطع$since ضمن عطلٍ جماعيّ على نفس الخطّ. افتح العطل لتعرف مكانه وتبلّغ المتأثرين.',
          steps: steps,
        );
      }
      switch (onu.reason) {
        case FiberDropReason.power:
          return FiberDiagnosis(
            kind: FiberVerdictKind.power,
            title: 'الكهرباء طافية عنده',
            body: 'الجهاز بعث إشارة انطفاء$since، يعني طفى وماكو عطل بالشبكة. يرجع وحده لمّا ترجع الكهرباء.',
            steps: steps,
          );
        case FiberDropReason.fiber:
          final neighbours = boxTotal != null && boxTotal > 0 && boxOnline != null
              ? (boxOnline == boxTotal ? 'وجيرانه على الصندوق شغّالين، ' : '')
              : '';
          return FiberDiagnosis(
            kind: FiberVerdictKind.fiberHome,
            title: 'انقطع الضوء عن بيته',
            body: 'الجهاز انقطع$since بسبب «فقدان ضوء»، $neighbours'
                'يعني الخلل بسلك البيت أو وصلته بالصندوق.',
            steps: steps,
          );
        case FiberDropReason.other:
        case FiberDropReason.unknown:
        case null:
          return FiberDiagnosis(
            kind: FiberVerdictKind.onuDown,
            title: 'جهاز الألياف مفصول',
            body: 'الجهاز انقطع$since والأولت ما يقول السبب. إذا الكهرباء عنده شغّالة فالخلل بالليف أو الوصلة.',
            steps: steps,
          );
      }
    }
    if (sub == null) {
      final rx = onu?.rx;
      if (rx != null && FiberBands.of(rx) == FiberBand.weak) {
        return FiberDiagnosis(
          kind: FiberVerdictKind.weakLight,
          title: 'الضوء ضعيف عنده',
          body: 'الضوء ${_rxIn(rx)}، تحت حدّ الجهاز (−27)، فيفصل ويرجع أو يبطأ. نظّف الوصلة أو افحص السلك.',
          steps: steps,
        );
      }
      return FiberDiagnosis(
        kind: onu == null ? FiberVerdictKind.noOnu : FiberVerdictKind.onuOnly,
        title: onu == null ? 'ما عندنا شي نفحصه' : 'جهاز الألياف يشتغل',
        body: onu == null
            ? 'لا جهاز ولا مشترك معروف — اختر الجهاز أو اربطه بمشترك.'
            : 'الجهاز متّصل${rx == null ? '' : ' وضوءه ${_rxIn(rx)}'}. $subUnknown، فالاشتراك والجلسة ما نقدر نفحصهم من هنا.',
        steps: steps,
      );
    }
    if (sub.disabled || sub.expired) {
      return FiberDiagnosis(
        kind: FiberVerdictKind.subscription,
        title: sub.disabled ? 'حسابه معطَّل' : 'اشتراكه منتهي',
        body: onu == null
            ? 'الساس رافض الاتصال لحين ${sub.disabled ? 'تفعيل الحساب' : 'التجديد'}.'
            : 'الضوء والجهاز سليمين، بس الساس رافض الاتصال لحين ${sub.disabled ? 'تفعيل الحساب' : 'التجديد'}.',
        steps: steps,
      );
    }
    final rx = onu?.rx;
    if (rx != null && FiberBands.of(rx) == FiberBand.weak) {
      return FiberDiagnosis(
        kind: FiberVerdictKind.weakLight,
        title: 'الضوء ضعيف عنده',
        body: 'الضوء ${_rxIn(rx)}، تحت حدّ الجهاز (−27)، فيفصل ويرجع أو يبطأ. نظّف الوصلة أو افحص السلك.',
        steps: steps,
      );
    }
    if (!sub.sessionOnline) {
      return FiberDiagnosis(
        kind: onu == null ? FiberVerdictKind.noOnu : FiberVerdictKind.router,
        title: onu == null ? 'ماكو اتّصال من عنده' : 'المشكلة بالراوتر عند المشترك',
        body: onu == null
            ? 'اشتراكه فعّال بس ماكو جلسة. اربط جهاز أليافه حتى نعرف إذا الخلل بالضوء أو بالراوتر.'
            : 'الضوء والجهاز سليمين واشتراكه فعّال، بس الراوتر ما اتّصل. طفّي الراوتر وشغّله، وتأكّد من كلمة سرّ الاتصال.',
        steps: steps,
      );
    }
    return FiberDiagnosis(
      kind: onu == null ? FiberVerdictKind.noOnu : FiberVerdictKind.allGood,
      title: 'كلّ شي سليم',
      body: onu == null ? 'اشتراكه فعّال وهو متّصل الآن.' : 'الضوء والجهاز والاشتراك سليمة، وهو متّصل الآن.',
      steps: steps,
    );
  }

  static String _days(int n) => n == 1
      ? 'يوم'
      : n == 2
          ? 'يومين'
          : n >= 3 && n <= 10
              ? '$n أيّام'
              : '$n يوماً';

  static String _since(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'لحظات';
    if (d.inHours < 1) return '${d.inMinutes} دقيقة';
    if (d.inDays < 1) {
      final h = d.inHours;
      return h == 1 ? 'ساعة' : (h == 2 ? 'ساعتين' : (h <= 10 ? '$h ساعات' : '$h ساعة'));
    }
    return _days(d.inDays);
  }

  static String _dayWord(DateTime t, DateTime now) {
    final a = DateTime(now.year, now.month, now.day);
    final l = t.toLocal();
    final b = DateTime(l.year, l.month, l.day);
    final diff = a.difference(b).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return '${l.year}/${l.month}/${l.day}';
  }
}
