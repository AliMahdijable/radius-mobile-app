import '../../core/util/arabic_text.dart';

/// «الأوامر الصوتيّة» (٦ نوفمبر — المالك: «المساعد الصوتي… وكيل يامره يفعل مشترك يطفي مشترك يفحص جهاز»).
///
/// هنا الفهم وحده: جملة الوكيل (مكتوبةً أو من الإملاء) ⇒ ما يريد ولمن. على الجهاز، بلا شبكة ولا نموذج ذكاء — والجملة لا
/// تُرسل لأحد. التطابق مع المشترك/الجهاز في [VoiceResolver]، والتنفيذ دائماً من شاشة العمليّة نفسها بضغطة الوكيل.
enum VoiceAction {
  /// تفعيل/تجديد/تمديد — شاشة التفعيل نفسها (السعر والدفع والمدّة يختارها هناك).
  activate,

  /// تطفية/إيقاف/تعطيل (والتعليق للوطنيّ — صفحة المشترك تعرف مفرداته).
  disable,

  /// تشغيل/إرجاع.
  enable,

  /// فتح صفحة المشترك.
  open,

  /// «شكد عليه دين؟».
  debt,

  /// فحص جهازٍ من «الأجهزة».
  checkDevice,

  /// الفحص الشامل لكلّ الأجهزة.
  checkAll,

  unknown,
}

class VoiceIntent {
  const VoiceIntent(this.action, {this.query = '', this.months, this.payment, this.deviceKind, this.raw = ''});

  final VoiceAction action;

  /// الاسم/اليوزر/الجهاز كما قيل — بعد حذف الفعل والحشو، مطبَّعاً.
  final String query;

  /// «شهرين»، «٣ اشهر» — يُعرض تذكيراً (المدّة نفسها تُختار بشاشة التفعيل).
  final int? months;

  /// «دين»/«نقد» مع التفعيل — تذكيرٌ كذلك.
  final VoicePayment? payment;

  /// نوع الجهاز إن قيل («افحص سكتر الشمال» ⇒ sector) — يقدّم أجهزة نوعه بالمطابقة.
  final String? deviceKind;

  final String raw;

  bool get needsTarget => action != VoiceAction.unknown && action != VoiceAction.checkAll;

  @override
  String toString() => 'VoiceIntent($action, "$query", months: $months, payment: $payment)';
}

enum VoicePayment { cash, debt }

class VoiceCommand {
  VoiceCommand._();

  // ── المفردات (بعد التطبيع: أ/إ/آ ⇒ ا، ى ⇒ ي، ة ⇒ ه) — اللهجة العراقيّة أوّلاً ──
  static const _activate = {
    'فعل', 'فعله', 'فعلها', 'فعلوه', 'فعلله', 'فعللها', 'تفعيل', 'جدد', 'جدده', 'جددها', 'جددله', 'جددلها', 'تجديد', 'مدد',
    'مدده', 'مددله', 'مددلها', 'تمديد', 'اشحن', 'اشحنه', 'اشحنله', 'اشحنلها', 'شحن', 'شحنله', 'رنيو', 'renew', 'activate',
  };
  static const _disable = {
    'طفي', 'اطفي', 'طفيه', 'طفيها', 'طفيله', 'طفيلها', 'اطفيه', 'اطفيله', 'وقف', 'اوقف', 'وقفه', 'وقفها', 'وقفله', 'اوقفه',
    'عطل', 'عطله', 'عطلها', 'تعطيل', 'اقطع', 'اقطعه', 'اقطعها', 'قطع', 'قطعه', 'قطعله', 'ايقاف', 'علق', 'علقه', 'علقها',
    'تعليق', 'سد', 'سده', 'بلوك', 'block', 'disable', 'suspend',
  };
  static const _enable = {
    'شغل', 'شغله', 'شغلها', 'شغلوه', 'تشغيل', 'رجع', 'رجعه', 'رجعها', 'رجعله', 'ارجع', 'ارجعه', 'فك', 'فكه', 'فكها', 'فكله',
    'enable', 'resume', 'unblock',
  };
  static const _open = {
    'افتح', 'افتحه', 'افتحلي', 'افتحها', 'اعرض', 'اعرضلي', 'وريني', 'شوف', 'شوفلي', 'ابحث', 'ابحثلي', 'دور', 'دورلي', 'فتش',
    'فتشلي', 'معلومات', 'تفاصيل', 'حاله', 'حالته', 'وين', 'open', 'show', 'find',
  };
  static const _check = {
    'افحص', 'افحصلي', 'افحصه', 'فحص', 'افحصها', 'شيك', 'شيكلي', 'اختبر', 'ping', 'check',
  };
  static const _debtWords = {'دين', 'ديون', 'دينه', 'دينها', 'الدين', 'مديون', 'مديونه', 'debt'};
  static const _howMuch = {'شكد', 'كم', 'قديش', 'شقد', 'اشكد'};
  static const _onHim = {'عليه', 'عليها', 'مطلوب', 'مطلوبه', 'باقي'};
  static const _deviceWords = {
    'جهاز', 'الجهاز', 'سكتر', 'السكتر', 'راوتر', 'الراوتر', 'مايكروتك', 'المايكروتك', 'اولت', 'الاولت', 'لنك', 'اللنك',
    'برج', 'البرج', 'سويج', 'السويج', 'سويتش', 'السويتش', 'نانو', 'النانو', 'اكسس', 'الاكسس', 'سيرفر', 'السيرفر',
    'ap', 'sector', 'router', 'olt', 'switch', 'link', 'device',
  };
  /// كلمة الجهاز ⇒ نوعه في «الأجهزة» (NetworkDevice.type).
  static const _deviceKinds = {
    'سكتر': 'sector', 'السكتر': 'sector', 'sector': 'sector', 'اكسس': 'sector', 'الاكسس': 'sector', 'ap': 'sector',
    'راوتر': 'router', 'الراوتر': 'router', 'مايكروتك': 'router', 'المايكروتك': 'router', 'router': 'router',
    'سيرفر': 'router', 'السيرفر': 'router',
    'اولت': 'olt', 'الاولت': 'olt', 'olt': 'olt',
    'لنك': 'link', 'اللنك': 'link', 'link': 'link',
    'سويج': 'switch', 'السويج': 'switch', 'سويتش': 'switch', 'السويتش': 'switch', 'switch': 'switch',
  };
  static const _allWords = {'كل', 'الكل', 'جميع', 'كلها', 'شامل', 'الشامل', 'all'};
  static const _devicesPlural = {'الاجهزه', 'اجهزه', 'اجهزتي', 'الشبكه', 'شبكتي', 'devices', 'network'};
  static const _cashWords = {'نقد', 'نقدي', 'نقدا', 'كاش', 'cash'};
  static const _debtPay = {'دين', 'بالدين', 'اجل', 'بالاجل', 'دينه', 'debt'};

  /// حشوٌ يُحذف من الاسم (بعد التطبيع). ⚠️ «على» حرف الجرّ يُحذف قبل التطبيع وحده — بعده يصير «علي» (اسمٌ شائع).
  static const _filler = {
    'لو', 'سمحت', 'رجاء', 'رجاءا', 'من', 'فضلك', 'اريد', 'اريدك', 'ابي', 'ابغي', 'بدي', 'خلي', 'سوي', 'سويلي', 'سويله',
    'سويلها', 'هسه', 'هسا', 'هسع', 'حالا', 'الان', 'بسرعه', 'يا', 'ممكن', 'تكدر', 'تقدر', 'اكدر', 'الي', 'الى', 'ع',
    'مال', 'مالت', 'اشتراك', 'الاشتراك', 'اشتراكه', 'اشتراكها', 'المشترك', 'مشترك', 'المشتركه', 'حساب', 'الحساب', 'حسابه',
    'يوزر', 'اليوزر', 'خط', 'الخط', 'خطه', 'عند', 'هذا', 'هاذا', 'هذي', 'هاي', 'الاخ', 'الاستاذ', 'please', 'the',
  };

  static const _numberWords = {
    'واحد': 1, 'اثنين': 2, 'ثنين': 2, 'ثلاث': 3, 'ثلاثه': 3, 'تلاث': 3, 'اربع': 4, 'اربعه': 4, 'خمس': 5, 'خمسه': 5,
    'ست': 6, 'سته': 6, 'سبع': 7, 'سبعه': 7, 'ثمان': 8, 'ثمانيه': 8, 'ثمن': 8, 'تسع': 9, 'تسعه': 9, 'عشر': 10, 'عشره': 10,
  };
  static const _monthWords = {'شهر', 'اشهر', 'شهور', 'months', 'month'};

  /// جملة الوكيل ⇒ ما يريد. لا يرمي؛ ما لا يُفهم ⇒ [VoiceAction.unknown] بالنصّ كما هو.
  static VoiceIntent parse(String transcript) {
    final raw = transcript.trim();
    if (raw.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);
    // «على» (حرف جرّ بالألف المقصورة) يُحذف قبل التطبيع — بعده لا يُميَّز عن اسم «علي»
    final pre = latinDigits(raw).replaceAll(RegExp(r'(^|\s)على(?=\s|$)'), ' ');
    final norm = normalizeArabic(pre.toLowerCase())
        .replaceAll(RegExp(r'[.,!?؟،؛:"«»()\[\]{}_\-–—/\\|*+=~`^]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final tokens = norm.isEmpty ? <String>[] : norm.split(' ');
    if (tokens.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);

    VoiceAction? action;
    final used = <int>{};
    // ١) الفعل — أوّل ما يُعرف من الجملة (العراقيّ يبدأ به غالباً، ويُقبل بآخرها)
    for (var i = 0; i < tokens.length && action == null; i++) {
      final t = tokens[i];
      if (_activate.contains(t)) {
        action = VoiceAction.activate;
      } else if (_disable.contains(t)) {
        action = VoiceAction.disable;
      } else if (_enable.contains(t)) {
        action = VoiceAction.enable;
      } else if (_check.contains(t)) {
        action = VoiceAction.checkDevice;
      } else if (_open.contains(t)) {
        action = VoiceAction.open;
      }
      if (action != null) used.add(i);
    }
    // «شكد عليه» / «كم عليه دين» / «دين علي» بلا فعل
    final hasHowMuch = tokens.any(_howMuch.contains);
    final hasOnHim = tokens.any(_onHim.contains);
    final hasDebtWord = tokens.any(_debtWords.contains);
    if (action == null && (hasDebtWord || (hasHowMuch && hasOnHim))) action = VoiceAction.debt;
    if (action == VoiceAction.open && hasDebtWord) action = VoiceAction.debt;

    // ٢) المدّة والدفع (مع التفعيل) — وتُحذف من الاسم
    int? months;
    VoicePayment? payment;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t == 'شهرين') {
        months = 2;
        used.add(i);
      } else if (t == 'سنه' || t == 'سنة') {
        months = 12;
        used.add(i);
        if (i > 0 && (tokens[i - 1] == 'نص' || tokens[i - 1] == 'نصف')) {
          months = 6;
          used.add(i - 1);
        }
      } else if (_monthWords.contains(t)) {
        used.add(i);
        int? n;
        if (i > 0) {
          final p = tokens[i - 1];
          n = int.tryParse(p) ?? _numberWords[p];
          if (n != null) used.add(i - 1);
        }
        months = n ?? (t == 'شهر' || t == 'month' ? 1 : months);
      }
      if (action == VoiceAction.activate) {
        if (_cashWords.contains(t)) {
          payment = VoicePayment.cash;
          used.add(i);
        } else if (_debtPay.contains(t)) {
          payment = VoicePayment.debt;
          used.add(i);
        }
      }
    }
    if (months != null && (months < 1 || months > 24)) months = null;

    // ٣) الفحص: «كلّ الأجهزة»/«فحص شامل» ⇒ الشامل؛ وكلمة الجهاز تُحذف من الاسم
    if (action == VoiceAction.checkDevice) {
      final all = tokens.any(_allWords.contains);
      final plural = tokens.any(_devicesPlural.contains);
      final rest = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        if (used.contains(i)) continue;
        final t = tokens[i];
        if (_deviceWords.contains(t) || _allWords.contains(t) || _devicesPlural.contains(t) || _filler.contains(t)) continue;
        rest.add(t);
      }
      if ((all || plural || tokens.contains('شامل') || tokens.contains('الشامل')) && rest.isEmpty) {
        return VoiceIntent(VoiceAction.checkAll, raw: raw);
      }
      String? kind;
      for (final t in tokens) {
        if (_deviceKinds.containsKey(t)) {
          kind = _deviceKinds[t];
          break;
        }
      }
      if (rest.isEmpty && kind == null) return VoiceIntent(VoiceAction.checkAll, raw: raw);
      return VoiceIntent(VoiceAction.checkDevice, query: rest.join(' '), deviceKind: kind, raw: raw);
    }

    // ٤) الاسم: ما بقي بلا حشو ولا كلمات السؤال
    final rest = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      if (used.contains(i)) continue;
      final t = tokens[i];
      if (_filler.contains(t)) continue;
      if (action == VoiceAction.debt && (_debtWords.contains(t) || _howMuch.contains(t) || _onHim.contains(t))) continue;
      rest.add(t);
    }
    final query = rest.join(' ');
    if (action == null) {
      // اسمٌ وحده («علي حسين») ⇒ فتح صفحته؛ وإلّا لا فهم
      return query.isEmpty
          ? VoiceIntent(VoiceAction.unknown, raw: raw)
          : VoiceIntent(VoiceAction.open, query: query, raw: raw);
    }
    if (query.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);
    return VoiceIntent(action, query: query, months: action == VoiceAction.activate ? months : null,
        payment: action == VoiceAction.activate ? payment : null, raw: raw);
  }
}
