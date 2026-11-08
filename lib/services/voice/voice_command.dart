import '../../core/util/arabic_text.dart';

/// «الأوامر الصوتيّة» (٦ نوفمبر — المالك: «المساعد الصوتي… وكيل يامره يفعل مشترك يطفي مشترك يفحص جهاز»؛ ٧ نوفمبر: «العمليات
/// المهمه كلها ضمنها» — تسديد الدين وإضافته، الرصيد، الخصم، التذكيرات، المعلومات، الوصل، رمز QR، الكشف، الحركات، الاتصال).
///
/// هنا الفهم وحده: جملة الوكيل (مكتوبةً أو من الإملاء) ⇒ ما يريد ولمن وبكم. على الجهاز، بلا شبكة ولا نموذج ذكاء — والجملة لا
/// تُرسل لأحد. التطابق مع المشترك/الجهاز في [VoiceResolver]، والتنفيذ دائماً من شاشة العمليّة نفسها بضغطة الوكيل (المبلغ يظهر
/// بخانتها كما فُهم، ويُصحَّح هناك).
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

  /// «سدّد دين فلان ٢٥ الف» / «فلان دفع ٢٥ الف» — نافذة التسديد بالمبلغ (أو «كله» = الدين كاملاً).
  payDebt,

  /// «ضيف دين على فلان ١٠ الاف» / «سجّل عليه» — نافذة إضافة الدين بالمبلغ.
  addDebt,

  /// «ضيف رصيد لفلان ٥٠ الف» / «اشحن رصيد» — نافذة إضافة الرصيد بالمبلغ.
  addCredit,

  /// «سوي خصم لفلان» — نافذة الخصم السريع.
  discount,

  /// «ذكّره بالدين» / «ارسل تذكير دين لفلان» — رسالة التذكير بمعاينتها.
  debtReminder,

  /// «نبّهه بالانتهاء» — رسالة قرب الانتهاء بمعاينتها.
  expiryWarning,

  /// «ارسل معلومات فلان» / «دزله المعلومات» — رسالة المعلومات بمعاينتها.
  sendInfo,

  /// «اطبع وصل فلان».
  printReceipt,

  /// «رمز QR لفلان» — رمز دخول تطبيق المشترك.
  qr,

  /// «كشف حساب فلان».
  statement,

  /// «حركات فلان» / «سجل حركات».
  movements,

  /// «اتصل بفلان».
  call,

  /// «واتساب فلان» / «راسله».
  whatsapp,

  /// فحص جهازٍ من «الأجهزة» — «افحص سكتر الشمال»: كرت الجهاز بنتيجة فحصه (٨ نوفمبر).
  checkDevice,

  /// «افحص المشترك فلان» / «شنو حالة فلان» (٨ نوفمبر — المالك: «الكارت مباشره يجاوبه قبل يا اما مخلص متصل ومخلص طافي اذا متصل
  /// وفعال شنو حاله السي سي كيو، حاله الاشاره اذا كان موجود مانجمنت»): الجواب أوّلاً ثمّ صفحته.
  checkSubscriber,

  /// «افحص فلان» بلا «مشترك» ولا «جهاز» — يُبحث بالأجهزة والمشتركين معاً، والأوضح يُفحص.
  check,

  /// الفحص الشامل لكلّ الأجهزة.
  checkAll,

  unknown,
}

/// عمليّاتٌ تحمل مبلغاً (يُقرأ من الجملة).
const voiceMoneyActions = {VoiceAction.payDebt, VoiceAction.addDebt, VoiceAction.addCredit, VoiceAction.discount};

class VoiceIntent {
  const VoiceIntent(this.action,
      {this.query = '', this.months, this.payment, this.deviceKind, this.amount, this.fullAmount = false, this.raw = ''});

  final VoiceAction action;

  /// الاسم/اليوزر/الجهاز كما قيل — بعد حذف الفعل والحشو والمبلغ، مطبَّعاً.
  final String query;

  /// «شهرين»، «٣ اشهر» — يُعرض تذكيراً (المدّة نفسها تُختار بشاشة التفعيل).
  final int? months;

  /// «دين»/«نقد» مع التفعيل — تذكيرٌ كذلك.
  final VoicePayment? payment;

  /// نوع الجهاز إن قيل («افحص سكتر الشمال» ⇒ sector) — يقدّم أجهزة نوعه بالمطابقة.
  final String? deviceKind;

  /// المبلغ بالدينار («٢٥ الف»، «خمسة وعشرين الف»، «نص مليون») — للعمليّات الماليّة، يظهر بخانة نافذتها.
  final int? amount;

  /// «سدّد دينه كله» ⇒ الدين كاملاً.
  final bool fullAmount;

  final String raw;

  bool get needsTarget => action != VoiceAction.unknown && action != VoiceAction.checkAll;

  @override
  String toString() => 'VoiceIntent($action, "$query", months: $months, payment: $payment, amount: $amount, full: $fullAmount)';
}

enum VoicePayment { cash, debt }

class VoiceCommand {
  VoiceCommand._();

  // ── المفردات (بعد التطبيع: أ/إ/آ ⇒ ا، ى/ئ ⇒ ي، ة ⇒ ه) — اللهجة العراقيّة أوّلاً ──
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
    'فتشلي', 'معلومات', 'تفاصيل', 'وين', 'open', 'show', 'find',
  };

  /// «حالة فلان» / «شلونه» ⇒ جواب حاله (فحص المشترك) لا فتح صفحته وحده.
  static const _status = {'حاله', 'حالته', 'حالتها', 'وضع', 'وضعه', 'وضعها', 'شلونه', 'شلونها', 'status'};

  /// كلمةٌ تقول إنّ المقصود مشتركٌ لا جهاز («افحص المشترك علي»).
  static const _subscriberWords = {
    'مشترك', 'المشترك', 'مشتركه', 'المشتركه', 'يوزر', 'اليوزر', 'زبون', 'الزبون', 'خط', 'الخط', 'حساب', 'الحساب', 'حسابه',
    'اشتراك', 'الاشتراك', 'اشتراكه', 'subscriber', 'user',
  };
  static const _check = {
    'افحص', 'افحصلي', 'افحصه', 'فحص', 'افحصها', 'شيك', 'شيكلي', 'اختبر', 'ping', 'check',
  };

  // العمليّات الماليّة والمراسلة (٧ نوفمبر)
  static const _pay = {
    'سدد', 'سدده', 'سددها', 'سددله', 'سددلها', 'سددلي', 'تسديد', 'سداد', 'ادفع', 'دفع', 'دفعت', 'دافع', 'استلم', 'استلمت',
    'استلمنا', 'قبضت', 'قبض', 'pay',
  };
  static const _add = {
    'ضيف', 'اضف', 'اضيف', 'ضيفله', 'ضيفلها', 'ضيفه', 'اضفله', 'زيد', 'زيده', 'زيدله', 'سجل', 'سجله', 'سجلله', 'سجللها',
    'سجلها', 'حط', 'حطله', 'حطلها', 'حطه', 'اكتب', 'اكتبله', 'قيد', 'قيده', 'قيدله', 'اضافه', 'add',
  };
  static const _discount = {'خصم', 'خصمله', 'خصملها', 'اخصم', 'اخصمله', 'تخفيض', 'خفض', 'خفضله', 'discount'};
  static const _remind = {'ذكر', 'ذكره', 'ذكرها', 'ذكرله', 'ذكرلها', 'تذكير', 'نبه', 'نبهه', 'نبهها', 'نبهله', 'طالب', 'طالبه', 'remind'};
  static const _send = {
    'ارسل', 'ارسله', 'ارسلله', 'ارسلها', 'ارسللها', 'دز', 'دزله', 'دزلها', 'دزه', 'ابعث', 'ابعثله', 'ابعتله', 'ابعت', 'ارسال',
    'بلغ', 'بلغه', 'طرش', 'طرشله', 'send',
  };
  static const _print = {'اطبع', 'اطبعله', 'اطبعلي', 'اطبعها', 'طباعه', 'طبع', 'print'};
  static const _call = {'اتصل', 'اتصله', 'اتصلبه', 'اتصلي', 'رن', 'رنله', 'رنلي', 'كلم', 'كلمه', 'دك', 'دكله', 'call'};

  // كلماتٌ تحدّد العمليّة مع الفعل أو وحدها (وتُحذف من الاسم)
  static const _credit = {'رصيد', 'الرصيد', 'رصيده', 'رصيدها', 'بالرصيد', 'للرصيد', 'credit', 'balance'};
  static const _info = {'معلومات', 'المعلومات', 'معلوماته', 'معلوماتها', 'بالمعلومات', 'بيانات', 'بياناته', 'تفاصيله', 'info'};
  static const _qr = {'qr', 'كيوار', 'كيو', 'باركود', 'الباركود', 'رمز', 'الرمز', 'رمزه', 'كود', 'الكود'};
  static const _statement = {'كشف', 'الكشف', 'كشفه', 'statement'};
  static const _movements = {'حركات', 'الحركات', 'حركاته', 'حركاتها', 'movements'};
  static const _whatsapp = {'واتساب', 'الواتساب', 'واتس', 'وتساب', 'راسل', 'راسله', 'راسلها', 'whatsapp'};
  static const _expiry = {'انتهاء', 'الانتهاء', 'بالانتهاء', 'بانتهاء', 'ينتهي', 'تنتهي', 'خلصان', 'يخلص', 'نهايه', 'expiry'};
  static const _receipt = {'وصل', 'الوصل', 'وصله', 'فاتوره', 'receipt'};
  static const _full = {'كله', 'كلها', 'بالكامل', 'الكامل', 'جميعه', 'كامله'};
  static const _currency = {'دينار', 'دنانير', 'الدينار', 'iqd'};

  static const _debtWords = {'دين', 'ديون', 'دينه', 'دينها', 'الدين', 'بالدين', 'بدينه', 'بالديون', 'مديون', 'مديونه', 'debt'};
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
    'له', 'لها', 'الها', 'اله', 'بيه', 'بيها', 'ب', 'ل', 'و', 'جديد', 'جديده', 'مبلغ', 'المبلغ', 'بمبلغ',
    // أدوات السؤال («شنو حالة علي») — ليست من الاسم
    'شنو', 'شو', 'ايش', 'شلون', 'اشلون', 'كيف',
  };

  static const _numberWords = {
    'واحد': 1, 'اثنين': 2, 'ثنين': 2, 'ثلاث': 3, 'ثلاثه': 3, 'تلاث': 3, 'اربع': 4, 'اربعه': 4, 'خمس': 5, 'خمسه': 5,
    'ست': 6, 'سته': 6, 'سبع': 7, 'سبعه': 7, 'ثمان': 8, 'ثمانيه': 8, 'ثمن': 8, 'تسع': 9, 'تسعه': 9, 'عشر': 10, 'عشره': 10,
  };
  static const _monthWords = {'شهر', 'اشهر', 'شهور', 'months', 'month'};

  // ── الأرقام المنطوقة (للمبالغ) ──
  static const _units = {
    'واحد': 1, 'وحده': 1, 'اثنين': 2, 'ثنين': 2, 'اثنان': 2, 'تنين': 2, 'ثلاث': 3, 'ثلاثه': 3, 'تلاث': 3, 'تلاثه': 3,
    'اربع': 4, 'اربعه': 4, 'خمس': 5, 'خمسه': 5, 'ست': 6, 'سته': 6, 'سبع': 7, 'سبعه': 7, 'ثمان': 8, 'ثمانيه': 8, 'ثمن': 8,
    'ثمنيه': 8, 'تمن': 8, 'تمنيه': 8, 'تسع': 9, 'تسعه': 9,
  };
  static const _teens = {
    'عشر': 10, 'عشره': 10, 'احدعش': 11, 'احدعشر': 11, 'حدعش': 11, 'اداعش': 11, 'اثنعش': 12, 'اثناعش': 12, 'اثنعشر': 12,
    'اطنعش': 12, 'ثلطعش': 13, 'تلطعش': 13, 'ثلاثطعش': 13, 'اربعطعش': 14, 'خمسطعش': 15, 'خمستعش': 15, 'ستطعش': 16,
    'سبعطعش': 17, 'ثمنطعش': 18, 'تمنطعش': 18, 'تسعطعش': 19,
  };
  static const _tens = {
    'عشرين': 20, 'ثلاثين': 30, 'تلاثين': 30, 'اربعين': 40, 'خمسين': 50, 'ستين': 60, 'سبعين': 70, 'ثمانين': 80, 'ثمنين': 80,
    'تمانين': 80, 'تسعين': 90,
  };
  static const _hundreds = {
    'ميه': 100, 'مايه': 100, 'ميتين': 200, 'مايتين': 200, 'ثلاثميه': 300, 'تلثميه': 300, 'تلاثميه': 300, 'ثلثميه': 300,
    'اربعميه': 400, 'خمسميه': 500, 'ستميه': 600, 'سبعميه': 700, 'ثمنميه': 800, 'ثمانميه': 800, 'تمنميه': 800, 'تسعميه': 900,
  };
  static const _thousandsWords = {
    'الف': 1000, 'الاف': 1000, 'الوف': 1000, 'الفين': 2000, 'الفان': 2000, 'ثلاثتلاف': 3000, 'تلاثتلاف': 3000, 'تلتلاف': 3000,
    'اربعتلاف': 4000, 'خمستلاف': 5000, 'خمستالاف': 5000, 'ستتلاف': 6000, 'سبعتلاف': 7000, 'ثمنتلاف': 8000, 'تمنتلاف': 8000,
    'تسعتلاف': 9000, 'عشرتلاف': 10000, 'عشرتالاف': 10000,
  };
  static const _millionsWords = {'مليون': 1000000, 'ملايين': 1000000, 'مليونين': 2000000};
  static const _fractions = {'نص': 0.5, 'نصف': 0.5, 'ربع': 0.25};

  /// كلمة عددٍ (بلا «و» أوّلها) ⇒ صنفها، وإلّا null.
  static String? _numKind(String t) {
    if (RegExp(r'^\d+$').hasMatch(t)) return 'digits';
    if (_units.containsKey(t)) return 'unit';
    if (_teens.containsKey(t)) return 'teen';
    if (_tens.containsKey(t)) return 'ten';
    if (_hundreds.containsKey(t)) return 'hundred';
    if (_thousandsWords.containsKey(t)) return 'thousand';
    if (_millionsWords.containsKey(t)) return 'million';
    if (_fractions.containsKey(t)) return 'fraction';
    return null;
  }

  /// «وعشرين» ⇒ «عشرين» (حرف العطف ملصوقاً) — إن كان الباقي عدداً.
  static String _stripWaw(String t) => t.length > 2 && t.startsWith('و') && _numKind(t.substring(1)) != null ? t.substring(1) : t;

  /// المبلغ من الجملة: أطول سلسلةٍ عدديّة متّصلة (أرقام، كلمات عدد، «الف/مليون»، «و»، «نص/ربع») فيها كلمةٌ «قويّة» (رقم، عشرات، مئات،
  /// آلاف، ملايين — لا «ست»/«خمس» وحدها: قد تكون اسماً). أقلّ من ألف بلا «الف/مليون» ⇒ بالآلاف (العراقيّ: «دفع خمسة وعشرين» =
  /// ٢٥٬٠٠٠ — لا مبلغ دين بخمسةٍ وعشرين ديناراً). ⇒ (المبلغ، مواضع كلماته) أو null.
  static (int, Set<int>)? parseAmount(List<String> tokens, {Set<int> skip = const {}}) {
    (int, Set<int>)? best;
    var i = 0;
    while (i < tokens.length) {
      if (skip.contains(i) || _numKind(_stripWaw(tokens[i])) == null) {
        i++;
        continue;
      }
      // سلسلةٌ تبدأ هنا
      final idx = <int>{};
      var j = i;
      while (j < tokens.length && !skip.contains(j)) {
        final t = tokens[j];
        if (t == 'و' && j + 1 < tokens.length && _numKind(_stripWaw(tokens[j + 1])) != null) {
          idx.add(j);
          j++;
          continue;
        }
        if (_numKind(_stripWaw(t)) == null && !_currency.contains(t)) break;
        idx.add(j);
        j++;
      }
      final v = _valueOf([for (final k in idx.toList()..sort()) _stripWaw(tokens[k])]);
      if (v != null && (best == null || idx.length > best.$2.length)) best = (v, idx);
      i = j;
    }
    return best;
  }

  static int? _valueOf(List<String> words) {
    var total = 0.0;
    var group = 0.0;
    var strong = false;
    var multiplied = false;
    var lastMult = 0.0;
    for (var k = 0; k < words.length; k++) {
      final w = words[k];
      if (w == 'و' || _currency.contains(w)) continue;
      switch (_numKind(w)) {
        case 'digits':
          group += double.parse(w);
          strong = true;
        case 'unit':
          group += _units[w]!.toDouble();
        case 'teen':
          group += _teens[w]!.toDouble();
          strong = true;
        case 'ten':
          group += _tens[w]!.toDouble();
          strong = true;
        case 'hundred':
          // «خمسه ميه» = ٥٠٠ (نادر) — وإلّا تُضاف
          group = group > 0 && group < 10 ? group * 100 : group + _hundreds[w]!;
          strong = true;
        case 'thousand':
          final m = _thousandsWords[w]!.toDouble();
          if (m == 1000) {
            total += (group == 0 ? 1 : group) * 1000;
          } else {
            total += group * 1000 + m;
          }
          group = 0;
          strong = true;
          multiplied = true;
          lastMult = 1000;
        case 'million':
          final m = _millionsWords[w]!.toDouble();
          if (m == 1000000) {
            total += (group == 0 ? 1 : group) * 1000000;
          } else {
            total += m;
          }
          group = 0;
          strong = true;
          multiplied = true;
          lastMult = 1000000;
        case 'fraction':
          final f = _fractions[w]!;
          // «مليون ونص» = ١٫٥ مليون؛ «نص مليون» = ٥٠٠ الف
          if (lastMult > 0 && group == 0) {
            total += f * lastMult;
          } else {
            group += f;
          }
        default:
          break;
      }
    }
    if (!strong) return null;
    var v = total + group;
    if (!multiplied && v > 0 && v < 1000) v *= 1000;
    final n = v.round();
    return n >= 250 && n <= 100000000 ? n : null;
  }

  /// جملة الوكيل ⇒ ما يريد. لا يرمي؛ ما لا يُفهم ⇒ [VoiceAction.unknown] بالنصّ كما هو.
  static VoiceIntent parse(String transcript) {
    final raw = transcript.trim();
    if (raw.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);
    // «على» (حرف جرّ بالألف المقصورة) يُحذف قبل التطبيع — بعده لا يُميَّز عن اسم «علي»
    var pre = latinDigits(raw).replaceAll(RegExp(r'(^|\s)على(?=\s|$)'), ' ');
    // «25,000» / «٢٥٬٠٠٠» رقمٌ واحد قبل حذف الترقيم
    for (var k = 0; k < 3; k++) {
      pre = pre.replaceAllMapped(RegExp(r'(\d)[,٬،.](\d{3})(?!\d)'), (m) => '${m[1]}${m[2]}');
    }
    final norm = normalizeArabic(pre.toLowerCase())
        .replaceAll(RegExp(r'[.,!?؟،؛:"«»()\[\]{}_\-–—/\\|*+=~`^]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final tokens = norm.isEmpty ? <String>[] : norm.split(' ');
    if (tokens.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);

    bool has(Set<String> set) => tokens.any(set.contains);
    final hasCredit = has(_credit);
    final hasInfo = has(_info);
    final hasQr = has(_qr);
    final hasStatement = has(_statement);
    final hasMovements = has(_movements);
    final hasWhatsapp = has(_whatsapp);
    final hasExpiry = has(_expiry);
    final hasRemind = has(_remind);
    final hasDebtWord = has(_debtWords);

    VoiceAction? action;
    final used = <int>{};
    // ١) الفعل — أوّل ما يُعرف من الجملة (العراقيّ يبدأ به غالباً، ويُقبل بآخرها)
    for (var i = 0; i < tokens.length && action == null; i++) {
      final t = tokens[i];
      if (_activate.contains(t)) {
        // «اشحن رصيد» إضافة رصيد لا تفعيل
        action = hasCredit ? VoiceAction.addCredit : VoiceAction.activate;
      } else if (_disable.contains(t)) {
        action = VoiceAction.disable;
      } else if (_enable.contains(t)) {
        action = VoiceAction.enable;
      } else if (_check.contains(t)) {
        action = VoiceAction.checkDevice;
      } else if (_status.contains(t)) {
        action = VoiceAction.checkSubscriber;
      } else if (_pay.contains(t)) {
        action = VoiceAction.payDebt;
      } else if (_add.contains(t)) {
        action = hasCredit ? VoiceAction.addCredit : (hasMovements ? VoiceAction.movements : VoiceAction.addDebt);
      } else if (_discount.contains(t)) {
        action = VoiceAction.discount;
      } else if (_remind.contains(t)) {
        action = hasExpiry ? VoiceAction.expiryWarning : VoiceAction.debtReminder;
      } else if (_send.contains(t)) {
        action = hasExpiry
            ? VoiceAction.expiryWarning
            : (hasRemind || hasDebtWord)
                ? VoiceAction.debtReminder
                : hasQr
                    ? VoiceAction.qr
                    : VoiceAction.sendInfo;
      } else if (_print.contains(t)) {
        action = VoiceAction.printReceipt;
      } else if (_call.contains(t)) {
        action = VoiceAction.call;
      } else if (_open.contains(t) && !_info.contains(t)) {
        action = VoiceAction.open;
      }
      if (action != null) used.add(i);
    }
    // «افتح/وريني» + ما يُفتح: الكشف، الحركات، الرمز، الواتساب، الدين — و«شوف حالة فلان» جواب حاله
    if (action == VoiceAction.open) {
      if (has(_status)) {
        action = VoiceAction.checkSubscriber;
      } else if (hasStatement) {
        action = VoiceAction.statement;
      } else if (hasMovements) {
        action = VoiceAction.movements;
      } else if (hasQr) {
        action = VoiceAction.qr;
      } else if (hasWhatsapp) {
        action = VoiceAction.whatsapp;
      } else if (hasDebtWord) {
        action = VoiceAction.debt;
      }
    }
    // بلا فعل: الاسم وحده مع كلمة العمليّة
    final hasHowMuch = has(_howMuch);
    final hasOnHim = has(_onHim);
    if (action == null) {
      if (has(_status)) {
        action = VoiceAction.checkSubscriber;
      } else if (hasStatement) {
        action = VoiceAction.statement;
      } else if (hasMovements) {
        action = VoiceAction.movements;
      } else if (hasQr) {
        action = VoiceAction.qr;
      } else if (hasWhatsapp) {
        action = VoiceAction.whatsapp;
      } else if (has(_receipt)) {
        action = VoiceAction.printReceipt;
      } else if (hasInfo) {
        action = VoiceAction.open;
      } else if (hasCredit && parseAmount(tokens) != null) {
        action = VoiceAction.addCredit;
      } else if (hasOnHim && !hasHowMuch && parseAmount(tokens) != null) {
        // «علي عليه ٢٥ الف» ⇒ دين يُضاف (السؤال «شكد عليه» لا)
        action = VoiceAction.addDebt;
      } else if (hasDebtWord || (hasHowMuch && hasOnHim)) {
        action = VoiceAction.debt;
      }
    }

    // ٢) المدّة والدفع (مع التفعيل) — وتُحذف من الاسم
    int? months;
    VoicePayment? payment;
    if (action == VoiceAction.activate || action == null) {
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
    }
    if (months != null && (months < 1 || months > 24)) months = null;

    // ٣) المبلغ (العمليّات الماليّة) و«كله»
    int? amount;
    var full = false;
    int? fullAt;
    if (voiceMoneyActions.contains(action)) {
      final a = parseAmount(tokens, skip: used);
      if (a != null) {
        amount = a.$1;
        used.addAll(a.$2);
      }
      if (action == VoiceAction.payDebt && amount == null) {
        for (var i = 0; i < tokens.length; i++) {
          // «كامل» آخر الجملة وحدها (قد يكون اسماً: «سدد دين كامل حسن»)
          if (_full.contains(tokens[i]) || (tokens[i] == 'كامل' && i == tokens.length - 1)) {
            full = true;
            used.add(i);
            if (tokens[i] == 'كامل') fullAt = i;
          }
        }
      }
    }

    // ٤) الفحص: «كلّ الأجهزة»/«فحص شامل» ⇒ الشامل؛ «افحص المشترك فلان» ⇒ المشترك؛ وكلمة الجهاز تُحذف من الاسم
    if (action == VoiceAction.checkDevice || action == VoiceAction.checkSubscriber) {
      final all = has(_allWords);
      final plural = has(_devicesPlural);
      final rest = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        if (used.contains(i)) continue;
        final t = tokens[i];
        if (_deviceWords.contains(t) ||
            _allWords.contains(t) ||
            _devicesPlural.contains(t) ||
            _filler.contains(t) ||
            _subscriberWords.contains(t) ||
            _status.contains(t)) {
          continue;
        }
        rest.add(t);
      }
      if (action == VoiceAction.checkSubscriber || has(_subscriberWords)) {
        return rest.isEmpty
            ? VoiceIntent(VoiceAction.unknown, raw: raw)
            : VoiceIntent(VoiceAction.checkSubscriber, query: rest.join(' '), raw: raw);
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
      // «افحص علي حسين» بلا «جهاز/سكتر» ولا «مشترك» ⇒ يُبحث بالاثنين
      if (!tokens.any(_deviceWords.contains)) return VoiceIntent(VoiceAction.check, query: rest.join(' '), raw: raw);
      return VoiceIntent(VoiceAction.checkDevice, query: rest.join(' '), deviceKind: kind, raw: raw);
    }

    // ٥) الاسم: ما بقي بلا حشو ولا كلمات العمليّة
    final drop = <String>{
      ..._filler,
      if (action != VoiceAction.open && action != VoiceAction.activate && action != null) ...{
        ..._debtWords, ..._howMuch, ..._onHim, ..._credit, ..._info, ..._qr, ..._statement, ..._movements, ..._whatsapp,
        ..._expiry, ..._remind, ..._receipt, ..._currency, ..._full,
      },
      if (action == VoiceAction.debt) ...{..._debtWords, ..._howMuch, ..._onHim},
      if (action == VoiceAction.open) ..._info,
    };
    List<String> restOf() => [
          for (var i = 0; i < tokens.length; i++)
            if (!used.contains(i) && !drop.contains(tokens[i])) tokens[i],
        ];
    var rest = restOf();
    // «سدد دين كامل» — «كامل» هنا الاسم لا «الدين كلّه»
    if (rest.isEmpty && fullAt != null) {
      used.remove(fullAt);
      full = false;
      rest = restOf();
    }
    final query = rest.join(' ');
    if (action == null) {
      // اسمٌ وحده («علي حسين») ⇒ فتح صفحته؛ وإلّا لا فهم
      return query.isEmpty
          ? VoiceIntent(VoiceAction.unknown, raw: raw)
          : VoiceIntent(VoiceAction.open, query: query, raw: raw);
    }
    if (query.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);
    return VoiceIntent(action,
        query: query,
        months: action == VoiceAction.activate ? months : null,
        payment: action == VoiceAction.activate ? payment : null,
        amount: amount,
        fullAmount: full,
        raw: raw);
  }
}
