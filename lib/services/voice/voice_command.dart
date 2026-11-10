import '../../core/util/arabic_text.dart';

/// «الأوامر الصوتيّة» (٦ نوفمبر — المالك: «المساعد الصوتي… وكيل يامره يفعل مشترك يطفي مشترك يفحص جهاز»؛ ٧ نوفمبر: «العمليات
/// المهمه كلها ضمنها» — تسديد الدين وإضافته، الرصيد، الخصم، التذكيرات، المعلومات، الوصل، رمز QR، الكشف، الحركات، الاتصال).
///
/// ١٠ نوفمبر (المالك: «تسديد دين تفعيل جزئي وباقي العمليات يحتاج نوسع النطاق ويحتاج نخلي يتعرف على اللغة انكليزي عربي»):
/// • التفعيل بدفعه كما قيل — «جزئي ١٠ الاف»، «دفع ١٠ والباقي دين»، «نقد»، «بالدين»، «بالكارت»، «شهرين» — يظهر مختاراً بشاشته.
/// • باقي عمليّات صفحة المشترك: تمديد، تغيير باقة، فصل، تعديل، استهلاك، موقع، جلسات، سعر ثابت، بيع مادّة، ملاحظة.
/// • أوامر بلا مشترك: «مشترك جديد»، «افتح التقارير»، «المشتركين المنتهين».
/// • الإنكليزيّة كاملةً ("activate Ali Hussein partial 10 thousand") والإنكليزيّ بحروفٍ عربيّة («اكتيفيت»، «ديسكونكت»).
///
/// هنا الفهم وحده: جملة الوكيل (مكتوبةً أو من الإملاء) ⇒ ما يريد ولمن وبكم. على الجهاز، بلا شبكة ولا نموذج ذكاء — والجملة لا
/// تُرسل لأحد. التطابق مع المشترك/الجهاز في [VoiceResolver]، والتنفيذ دائماً من شاشة العمليّة نفسها بضغطة الوكيل (ما فُهم يظهر
/// مختاراً بها، ويُصحَّح هناك).
enum VoiceAction {
  /// تفعيل/تجديد — شاشة التفعيل نفسها، والدفع والمدّة والطريقة كما قيلت مختارةً بها.
  activate,

  /// «مدّد فلان» — شاشة التمديد (ومن لا تمديد عنده ⇒ شاشة التفعيل).
  extend,

  /// «غيّر باقة فلان الى …» — شاشة التعديل (الباقة تُختار هناك؛ ما قيل تذكير).
  changePackage,

  /// تطفية/إيقاف/تعطيل (والتعليق للوطنيّ — صفحة المشترك تعرف مفرداته).
  disable,

  /// تشغيل/إرجاع.
  enable,

  /// «افصل فلان» — فصل جلسته الآن (بتأكيده).
  disconnect,

  /// فتح صفحة المشترك.
  open,

  /// «عدّل فلان» — شاشة التعديل.
  edit,

  /// «احذف فلان» — يُفهم، والحذف نفسه يبقى بيد الوكيل من صفحته (نهائيّ لا يُفتح بالصوت).
  delete,

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

  /// «سعر فلان» / «ثبّت سعر فلان» — نافذة السعر الثابت.
  price,

  /// «بيع لفلان» — «بيع مادّة» والمشترك مختار.
  sell,

  /// «ملاحظة على فلان» — ملاحظته الخاصّة.
  note,

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

  /// «جلسات فلان» — سجلّ جلساته.
  sessions,

  /// «استهلاك فلان» / «شكد صارف».
  usage,

  /// «موقع فلان» / «وين بيته».
  location,

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

  /// «ضيف مشترك جديد» — شاشة إضافة المشترك.
  addSubscriber,

  /// «افتح التقارير» / «روح للصرفيات» — قسمٌ من التطبيق ([VoiceIntent.section]).
  openSection,

  /// «المشتركين المنتهين» / «وريني المديونين» — قائمة المشتركين بفلترها ([VoiceIntent.filter]).
  listSubscribers,

  unknown,
}

/// عمليّاتٌ تحمل مبلغاً (يُقرأ من الجملة).
const voiceMoneyActions = {VoiceAction.payDebt, VoiceAction.addDebt, VoiceAction.addCredit, VoiceAction.discount};

/// أوامر بلا مشترك ولا جهاز.
const voiceGlobalActions = {
  VoiceAction.checkAll,
  VoiceAction.addSubscriber,
  VoiceAction.openSection,
  VoiceAction.listSubscribers,
};

/// الدفع بين المشترك والوكيل عند التفعيل.
enum VoicePayment { cash, debt, partial }

/// من أين يُدفع للشركة: رصيد الوكيل، كارت تعبئة، أو بطاقة مصرفيّة (ماستر/فيزا — الوطنيّ).
enum VoiceMethod { balance, card, bankCard }

/// فلتر قائمة المشتركين كما قيل.
enum VoiceListFilter { all, active, online, offline, disabled, expired, debtors, nearExpiry }

class VoiceIntent {
  const VoiceIntent(
    this.action, {
    this.query = '',
    this.months,
    this.payment,
    this.paid,
    this.method,
    this.package = '',
    this.deviceKind,
    this.amount,
    this.fullAmount = false,
    this.looseAmount,
    this.section,
    this.filter,
    this.lang,
    this.raw = '',
  });

  final VoiceAction action;

  /// الاسم/اليوزر/الجهاز كما قيل — بعد حذف الفعل والحشو والمبلغ، مطبَّعاً.
  final String query;

  /// «شهرين»، «٣ اشهر» — تُختار بشاشة التفعيل حين تعرضها الشركة (وإلّا تذكير).
  final int? months;

  /// «نقد»/«دين»/«جزئي» مع التفعيل — يظهر مختاراً بشاشة التفعيل.
  final VoicePayment? payment;

  /// المدفوع نقداً مع التفعيل الجزئيّ («دفع ١٠ الاف والباقي دين») — بخانة «المبلغ المدفوع» هناك. null مع الجزئيّ ⇒ يُسأل.
  final int? paid;

  /// «بالكارت»/«بالرصيد»/«بالبطاقة» مع التفعيل.
  final VoiceMethod? method;

  /// الباقة المطلوبة كما قيلت («غيّر باقة علي الى فايبر ٥٠» ⇒ «فايبر 50») — تذكيرٌ يُعرض؛ تُختار بشاشة التعديل.
  final String package;

  /// نوع الجهاز إن قيل («افحص سكتر الشمال» ⇒ sector) — يقدّم أجهزة نوعه بالمطابقة.
  final String? deviceKind;

  /// المبلغ بالدينار («٢٥ الف»، «خمسة وعشرين الف»، «نص مليون») — للعمليّات الماليّة، يظهر بخانة نافذتها.
  final int? amount;

  /// «سدّد دينه كله» ⇒ الدين كاملاً.
  final bool fullAmount;

  /// مبلغٌ قيل مع التفعيل بلا كلمة دفع («فعّل علي ٢٥ الف») — لا يُربط بشيء؛ يُذكر للوكيل وحده.
  final int? looseAmount;

  /// القسم المطلوب ([VoiceAction.openSection]): معرّفه في «قوائم أخرى» (reports، expenses…) أو tab:home / tab:devices /
  /// tab:more / settings.
  final String? section;

  /// فلتر القائمة ([VoiceAction.listSubscribers]).
  final VoiceListFilter? filter;

  /// لغة الجملة الغالبة: ar أو en (null = أرقامٌ وحدها).
  final String? lang;

  final String raw;

  bool get needsTarget => action != VoiceAction.unknown && !voiceGlobalActions.contains(action);

  /// تفعيلٌ جزئيّ بلا مبلغ — يُسأل الوكيل «كم دفع؟» (أو يكتبه بشاشة التفعيل).
  bool get needsPaid => action == VoiceAction.activate && payment == VoicePayment.partial && paid == null;

  /// عمليّةٌ ماليّة بلا مبلغها — جملةٌ تالية بالمبلغ وحده تكمّلها.
  bool get needsAmount =>
      needsPaid ||
      (amount == null &&
          !fullAmount &&
          (action == VoiceAction.payDebt || action == VoiceAction.addDebt || action == VoiceAction.addCredit));

  /// الجملة التالية أعطت المبلغ الناقص.
  VoiceIntent withAmount(int value) => needsPaid ? _copy(paid: value) : _copy(amount: value);

  VoiceIntent withAction(VoiceAction a) => _copy(action: a);

  VoiceIntent _copy({VoiceAction? action, int? paid, int? amount}) => VoiceIntent(
        action ?? this.action,
        query: query,
        months: months,
        payment: payment,
        paid: paid ?? this.paid,
        method: method,
        package: package,
        deviceKind: deviceKind,
        amount: amount ?? this.amount,
        fullAmount: fullAmount,
        looseAmount: looseAmount,
        section: section,
        filter: filter,
        lang: lang,
        raw: raw,
      );

  @override
  String toString() =>
      'VoiceIntent($action, "$query", months: $months, payment: $payment, paid: $paid, method: $method, package: "$package", '
      'amount: $amount, full: $fullAmount, section: $section, filter: $filter, lang: $lang)';
}

/// صنف الفعل قبل أن يحسمه سياقه.
enum _Verb {
  activate,
  charge,
  extend,
  change,
  disable,
  enable,
  disconnect,
  check,
  status,
  pay,
  add,
  discount,
  remind,
  send,
  print,
  call,
  open,
  go,
  edit,
  delete,
  sell,
}

class VoiceCommand {
  VoiceCommand._();

  // ── المفردات (بعد التطبيع: أ/إ/آ ⇒ ا، ى/ئ ⇒ ي، ة ⇒ ه) — اللهجة العراقيّة أوّلاً، ثمّ الإنكليزيّة والإنكليزيّ بحروفٍ عربيّة ──
  static const _activate = {
    // «فعلا»: هكذا يكتب محرّك الخادم «فعّل» قبل اسمٍ يبدأ بحرف مدّ («فعّل حسين» ⇒ «فعلاً حسين» — قياس ١١ نوفمبر)
    'فعل', 'فعلا', 'فعله', 'فعلها', 'فعلوه', 'فعلله', 'فعللها', 'فعللي', 'افعل', 'تفعل', 'تفعيل', 'جدد', 'جدده', 'جددها', 'جددله',
    'جددلها', 'جددلي', 'اجدد', 'تجدد', 'تجديد', 'رنيو', 'رينيو', 'اكتيفيت', 'اكتفيت', 'اكتيفت', 'اكتيف', 'renew', 'renewal', 'activate', 'activation', 'reactivate',
  };

  /// «اشحن فلان» تجديد، و«اشحن رصيد فلان» إضافة رصيد.
  static const _charge = {'اشحن', 'اشحنه', 'اشحنله', 'اشحنلها', 'شحن', 'شحنله', 'recharge', 'topup'};
  static const _extend = {
    'مدد', 'مدده', 'مددها', 'مددله', 'مددلها', 'مددلي', 'امدد', 'تمدد', 'تمديد', 'اكستند', 'اكستيند', 'extend', 'extension',
  };
  static const _disable = {
    'طفي', 'اطفي', 'طفيه', 'طفيها', 'طفيله', 'طفيلها', 'طفيلي', 'تطفي', 'اطفيه', 'اطفيله', 'وقف', 'توقف', 'اوقف', 'وقفه', 'وقفها', 'وقفله', 'اوقفه',
    'عطل', 'عطله', 'عطلها', 'تعطيل', 'اقطع', 'اقطعه', 'اقطعها', 'قطع', 'قطعه', 'قطعله', 'ايقاف', 'علق', 'علقه', 'علقها',
    'تعليق', 'سد', 'سده', 'بلوك', 'ديسيبل', 'دسيبل', 'ديسابل', 'ديزابل', 'block', 'disable', 'suspend', 'deactivate', 'stop',
  };
  static const _enable = {
    'شغل', 'شغله', 'شغلها', 'شغلوه', 'شغللي', 'اشغل', 'تشغل', 'تشغيل', 'رجع', 'رجعه', 'رجعها', 'رجعله', 'ارجع', 'ارجعه', 'فك', 'فكه', 'فكها', 'فكله',
    'انيبل', 'اينيبل', 'انبلوك', 'enable', 'resume', 'unblock', 'unsuspend', 'restore',
  };
  static const _disconnect = {
    'افصل', 'افصله', 'افصلها', 'افصللي', 'تفصل', 'فصل', 'فصله', 'فصلها', 'ديسكونكت', 'دسكونكت', 'ديسكنكت', 'disconnect', 'kick',
    'logout',
  };
  static const _open = {
    'افتح', 'افتحه', 'افتحلي', 'افتحها', 'تفتح', 'اعرض', 'اعرضلي', 'وريني', 'شوف', 'شوفلي', 'ابحث', 'ابحثلي', 'دور', 'دورلي', 'فتش',
    'فتشلي', 'معلومات', 'تفاصيل', 'وين', 'open', 'show', 'find', 'search', 'view', 'display', 'lookup', 'where',
  };

  /// «روح للتقارير» — انتقالٌ لقسم (ومع اسم مشترك ⇒ فتح صفحته).
  static const _go = {'روح', 'روحلي', 'انتقل', 'ودني', 'وديني', 'خذني', 'اذهب', 'go', 'goto', 'navigate', 'take'};
  static const _edit = {'عدل', 'عدله', 'عدلها', 'عدللي', 'اعدل', 'تعدل', 'تعديل', 'edit', 'modify', 'update'};
  static const _delete = {
    'احذف', 'احذفه', 'احذفها', 'حذف', 'امسح', 'امسحه', 'امسحها', 'مسح', 'delete', 'remove', 'erase',
  };
  static const _sell = {'بيع', 'بيعه', 'بيعله', 'بيعلها', 'بيعلي', 'ابيع', 'sell', 'sale'};

  /// «غيّر/بدّل» — مع «باقة» تغيير باقة، مع «سعر» السعر الثابت، وإلّا تعديل.
  static const _change = {
    'غير', 'غيره', 'غيرها', 'غيرله', 'غيرلها', 'بدل', 'بدله', 'بدلها', 'بدلله', 'بدللها', 'change',
  };

  /// أفعالٌ لا تعني تغيير الباقة إلّا مع كلمتها («حوّل علي على باقة ٥٠») — وحدها ليست فعلاً هنا.
  static const _changeWithPkg = {
    'حول', 'حوله', 'حولها', 'انقل', 'انقله', 'انقلها', 'نزل', 'نزله', 'ارفع', 'ارفعه', 'move', 'set',
  };

  /// ترقيةٌ/تنزيل — تغيير باقة بلا كلمتها.
  /// ⚠️ بلا «رقّي/رقّيه»: «رقيه» بعد التطبيع هي الاسم «رقيّة».
  static const _upgrade = {'ابكريد', 'ابغريد', 'upgrade', 'downgrade'};

  /// «حالة فلان» / «شلونه» ⇒ جواب حاله (فحص المشترك) لا فتح صفحته وحده.
  static const _status = {'حاله', 'حالته', 'حالتها', 'وضع', 'وضعه', 'وضعها', 'شلونه', 'شلونها', 'status', 'state'};

  /// «علي متصل؟» / "is Ali online" — سؤال حاله.
  static const _stateWords = {'متصل', 'متصله', 'اونلاين', 'اوفلاين', 'online', 'offline', 'connected'};

  /// كلمةٌ تقول إنّ المقصود مشتركٌ لا جهاز («افحص المشترك علي»).
  static const _subscriberWords = {
    'مشترك', 'المشترك', 'مشتركه', 'المشتركه', 'يوزر', 'اليوزر', 'زبون', 'الزبون', 'خط', 'الخط', 'حساب', 'الحساب', 'حسابه',
    'اشتراك', 'الاشتراك', 'اشتراكه', 'subscriber', 'user', 'customer', 'client',
  };
  /// «مشترك جديد» — المشترك نفسه لا «حساب/خط/اشتراك» (تلتبس).
  static const _newSubWords = {
    'مشترك', 'المشترك', 'مشتركه', 'يوزر', 'اليوزر', 'زبون', 'الزبون', 'subscriber', 'user', 'customer', 'client',
  };
  static const _check = {
    'افحص', 'افحصلي', 'افحصه', 'تفحص', 'فحص', 'افحصها', 'شيك', 'شيكلي', 'چيك', 'تشيك', 'جيك', 'اختبر', 'ping', 'check', 'test',
    'diagnose', 'inspect',
  };

  // العمليّات الماليّة والمراسلة (٧ نوفمبر)
  static const _pay = {
    'سدد', 'سدده', 'سددها', 'سددله', 'سددلها', 'سددلي', 'اسدد', 'تسدد', 'تسديد', 'سداد', 'ادفع', 'دفع', 'دفعت', 'دافع', 'استلم', 'استلمت',
    'استلمنا', 'قبضت', 'قبض', 'pay', 'paid', 'pays', 'settle', 'settled', 'collect', 'collected', 'receive', 'received',
    'payment', 'repay',
  };
  static const _add = {
    'ضيف', 'اضف', 'اضيف', 'تضيف', 'ضيفلي', 'ضيفله', 'ضيفلها', 'ضيفه', 'اضفله', 'زيد', 'زيده', 'زيدله', 'سجل', 'سجله', 'سجلله', 'سجللها',
    'سجلها', 'حط', 'حطله', 'حطلها', 'حطه', 'اكتب', 'اكتبله', 'قيد', 'قيده', 'قيدله', 'اضافه', 'add', 'record', 'put',
    'register',
  };
  static const _discount = {'خصم', 'خصمله', 'خصملها', 'اخصم', 'اخصمله', 'تخفيض', 'خفض', 'خفضله', 'discount'};
  static const _remind = {
    'ذكر', 'ذكره', 'ذكرها', 'ذكرله', 'ذكرلها', 'تذكير', 'نبه', 'نبهه', 'نبهها', 'نبهله', 'طالب', 'طالبه', 'remind',
    'reminder', 'warn', 'warning', 'notify', 'alert',
  };
  static const _send = {
    'ارسل', 'ارسله', 'ارسلله', 'ارسلها', 'ارسللها', 'ترسل', 'دز', 'ادز', 'تدز', 'دزله', 'دزلها', 'دزه', 'ابعث', 'ابعثله', 'ابعتله', 'ابعت', 'ارسال',
    'بلغ', 'بلغه', 'طرش', 'طرشله', 'send',
  };
  static const _print = {'اطبع', 'اطبعله', 'اطبعلي', 'اطبعها', 'تطبع', 'طباعه', 'طبع', 'print'};
  static const _call = {
    'اتصل', 'اتصله', 'اتصلبه', 'اتصلي', 'تتصل', 'رن', 'رنله', 'رنلي', 'كلم', 'كلمه', 'دك', 'دكله', 'call', 'dial', 'ring', 'phone',
  };

  // كلماتٌ تحدّد العمليّة مع الفعل أو وحدها (وتُحذف من الاسم)
  static const _credit = {'رصيد', 'الرصيد', 'رصيده', 'رصيدها', 'بالرصيد', 'للرصيد', 'credit', 'balance'};
  static const _info = {
    'معلومات', 'المعلومات', 'معلوماته', 'معلوماتها', 'بالمعلومات', 'بيانات', 'بياناته', 'تفاصيله', 'info', 'information',
    'details',
  };
  static const _qr = {
    'qr', 'كيوار', 'كيو', 'باركود', 'الباركود', 'رمز', 'الرمز', 'رمزه', 'كود', 'الكود', 'الدخول', 'دخول', 'code', 'barcode',
    'login',
  };
  static const _statement = {'كشف', 'الكشف', 'كشفه', 'statement'};
  static const _movements = {
    'حركات', 'الحركات', 'حركاته', 'حركاتها', 'movements', 'activity', 'activities', 'history', 'log', 'logs',
    'transactions',
  };
  static const _whatsapp = {
    'واتساب', 'الواتساب', 'واتس', 'وتساب', 'راسل', 'راسله', 'راسلها', 'whatsapp', 'message', 'msg', 'chat',
  };
  static const _expiry = {
    'انتهاء', 'الانتهاء', 'بالانتهاء', 'بانتهاء', 'ينتهي', 'تنتهي', 'خلصان', 'يخلص', 'نهايه', 'expiry', 'expire', 'expires',
    'expiration', 'ending',
  };
  static const _receipt = {'وصل', 'الوصل', 'وصله', 'فاتوره', 'receipt', 'invoice', 'bill'};
  static const _full = {'كله', 'كلها', 'بالكامل', 'الكامل', 'جميعه', 'كامله', 'full', 'fully', 'entire', 'whole', 'all'};
  static const _currency = {'دينار', 'دنانير', 'الدينار', 'iqd', 'dinar', 'dinars'};
  static const _usage = {
    'استهلاك', 'الاستهلاك', 'استهلاكه', 'استهلاكها', 'صارف', 'صارفه', 'مستهلك', 'استهلك', 'يوزج', 'usage', 'consumption',
    'traffic',
  };
  static const _location = {
    'موقع', 'الموقع', 'موقعه', 'موقعها', 'لوكيشن', 'اللوكيشن', 'عنوان', 'العنوان', 'عنوانه', 'عنوانها', 'خريطه', 'الخريطه',
    'بيته', 'بيتها', 'location', 'address', 'map', 'gps',
  };
  static const _sessions = {'جلسات', 'الجلسات', 'جلساته', 'جلساتها', 'sessions'};

  /// «اقطع الجلسة/الاتصال» ⇒ فصلٌ لا تطفية.
  static const _sessionOne = {
    'جلسه', 'الجلسه', 'جلسته', 'جلستها', 'اتصال', 'الاتصال', 'اتصاله', 'اتصالها', 'session', 'connection',
  };
  static const _priceWords = {'سعر', 'السعر', 'سعره', 'سعرها', 'تسعيره', 'price', 'pricing'};

  /// «ثبّت سعر علي» / «سعر ثابت لعلي» — تُحذف من الاسم مع السعر وحده («ثابت» اسمٌ شائع فلا تدلّ وحدها).
  static const _priceExtra = {'ثابت', 'الثابت', 'ثبت', 'ثبته', 'ثبتله', 'fixed'};
  static const _noteWords = {'ملاحظه', 'الملاحظه', 'ملاحظته', 'ملاحظتها', 'ملاحظات', 'note', 'notes'};
  static const _password = {
    'باسورد', 'الباسورد', 'باسوورد', 'الباسوورد', 'باسورده', 'باسوورده', 'باسوردها', 'password', 'pass', 'passcode',
  };
  static const _packageWords = {
    'باقه', 'الباقه', 'باقته', 'باقتها', 'لباقه', 'باكج', 'الباكج', 'بكج', 'البكج', 'باكيج', 'بروفايل', 'البروفايل', 'سرعه',
    'السرعه', 'سرعته', 'سرعتها', 'package', 'plan', 'profile', 'speed',
  };

  /// «غيّر اسم/رقم علي» — تعديلٌ، والحقل ليس من الاسم.
  static const _editFields = {
    'اسم', 'الاسم', 'اسمه', 'رقم', 'الرقم', 'رقمه', 'هاتف', 'الهاتف', 'هاتفه', 'تلفون', 'موبايل', 'name', 'phone', 'number',
    'mobile',
  };

  /// «استهلاك علي هذا الشهر» — الوقت ليس من الاسم (مع القراءات وحدها).
  static const _timeWords = {
    'الشهر', 'هالشهر', 'شهر', 'اليوم', 'هاليوم', 'الاسبوع', 'هالاسبوع', 'اسبوع', 'امس', 'البارحه', 'اليومي', 'الشهري', 'month',
    'monthly', 'today', 'week', 'daily', 'yesterday',
  };

  /// «بيع راوتر لعلي» — المادّة ليست من الاسم.
  static const _itemWords = {'كيبل', 'كابل', 'ماده', 'الماده', 'مواد', 'غرض', 'cable', 'item', 'product'};

  /// «دفع نص المبلغ» — جزءٌ من السعر لا مبلغٌ يُعرف هنا: جزئيٌّ يُسأل مبلغه.
  static const _priceRef = {'المبلغ', 'مبلغ', 'السعر', 'سعر', 'القيمه', 'قيمه', 'الاشتراك', 'price', 'amount', 'it'};

  /// «صفحة علي» — تُحذف مع الفتح.
  static const _pageWords = {'صفحه', 'صفحته', 'صفحتها', 'ملف', 'ملفه', 'ملفها', 'page', 'profile'};

  static const _debtWords = {
    'دين', 'ديون', 'دينه', 'دينها', 'الدين', 'بالدين', 'بدينه', 'بالديون', 'مديون', 'مديونه', 'debt', 'debts',
  };
  static const _howMuch = {'شكد', 'كم', 'قديش', 'شقد', 'اشكد', 'howmuch'};
  static const _onHim = {'عليه', 'عليها', 'مطلوب', 'مطلوبه', 'باقي', 'owe', 'owes', 'owed'};
  static const _deviceWords = {
    'جهاز', 'الجهاز', 'سكتر', 'السكتر', 'راوتر', 'الراوتر', 'مايكروتك', 'المايكروتك', 'اولت', 'الاولت', 'لنك', 'اللنك',
    'برج', 'البرج', 'سويج', 'السويج', 'سويتش', 'السويتش', 'نانو', 'النانو', 'اكسس', 'الاكسس', 'سيرفر', 'السيرفر',
    'ap', 'sector', 'router', 'olt', 'switch', 'link', 'device', 'tower', 'nano', 'server', 'mikrotik', 'antenna',
  };

  /// كلمة الجهاز ⇒ نوعه في «الأجهزة» (NetworkDevice.type).
  static const _deviceKinds = {
    'سكتر': 'sector', 'السكتر': 'sector', 'sector': 'sector', 'اكسس': 'sector', 'الاكسس': 'sector', 'ap': 'sector',
    'راوتر': 'router', 'الراوتر': 'router', 'مايكروتك': 'router', 'المايكروتك': 'router', 'router': 'router',
    'سيرفر': 'router', 'السيرفر': 'router', 'server': 'router', 'mikrotik': 'router',
    'اولت': 'olt', 'الاولت': 'olt', 'olt': 'olt',
    'لنك': 'link', 'اللنك': 'link', 'link': 'link',
    'سويج': 'switch', 'السويج': 'switch', 'سويتش': 'switch', 'السويتش': 'switch', 'switch': 'switch',
  };
  static const _allWords = {'كل', 'الكل', 'جميع', 'كلها', 'شامل', 'الشامل', 'all', 'full', 'everything', 'whole'};
  static const _devicesPlural = {'الاجهزه', 'اجهزه', 'اجهزتي', 'الشبكه', 'شبكتي', 'devices', 'network'};

  // ── الدفع مع التفعيل ──
  static const _cashWords = {'نقد', 'نقدي', 'نقدا', 'نقديه', 'كاش', 'cash'};
  static const _debtPay = {
    'دين', 'بالدين', 'الدين', 'عالدين', 'اجل', 'بالاجل', 'موجل', 'دينه', 'debt', 'deferred', 'later', 'unpaid',
  };
  static const _partialWords = {'جزيي', 'جزييا', 'بالجزيي', 'الجزيي', 'جزء', 'جزييه', 'بارشل', 'partial', 'partially', 'part'};

  /// «دفع ١٠ الاف» — المبلغ بعدها مدفوعٌ نقداً؛ وحدها («فعّله دافع») نقداً كاملاً.
  static const _paidCue = {
    'دفع', 'دافع', 'دفعت', 'دفعلي', 'يدفع', 'واصل', 'واصله', 'واصلني', 'مدفوع', 'paid', 'pay', 'pays', 'paying',
  };

  /// «مقدّم ١٠ الاف» — جزئيّ دائماً (ولو بلا مبلغ ⇒ يُسأل).
  static const _advanceCue = {'مقدم', 'مقدمه', 'عربون', 'deposit', 'upfront', 'advance', 'down'};

  /// النفي قبل كلمة الدفع يقلبها: «ما دافع» / «بدون دفع» / "not paid" ⇒ بالدين لا نقداً؛ و«مو دين» / «بدون دين» ⇒ نقداً. وقبل
  /// الفعل نفسه («لا تفعّل علي» / "don't activate") ⇒ ليس أمراً.
  static const _negations = {
    'ما', 'مو', 'مش', 'لم', 'لا', 'بلا', 'بدون', 'غير', 'ماكو', 'not', 'no', 'never', 'without', 'don', 'dont', 'didn',
    'didnt', 'hasn', 'hasnt', 'doesn', 'doesnt', 'isn', 'isnt', 'wasn',
  };

  /// «والباقي دين».
  static const _restWords = {'الباقي', 'باقي', 'الباقيه', 'المتبقي', 'rest', 'remaining', 'remainder'};
  static const _cardWords = {
    'كارت', 'بالكارت', 'بكارت', 'الكارت', 'كارتات', 'الكارتات', 'بالكارتات', 'كارد', 'card', 'voucher', 'prepaid',
  };
  static const _bankCardWords = {
    'بطاقه', 'بالبطاقه', 'البطاقه', 'ماستر', 'ماستركارد', 'فيزا', 'mastercard', 'visa',
  };
  static const _walletWords = {'محفظتي', 'المحفظه', 'بالمحفظه', 'محفظه', 'wallet'};

  /// حشوٌ يُحذف من الاسم (بعد التطبيع). ⚠️ «على» حرف الجرّ يُحذف قبل التطبيع وحده — بعده يصير «علي» (اسمٌ شائع).
  static const _filler = {
    'لو', 'سمحت', 'رجاءا', 'من', 'فضلك', 'اريد', 'اريدك', 'ابي', 'ابغي', 'بدي', 'خلي', 'سوي', 'سويلي', 'سويله',
    'سويلها', 'هسه', 'هسا', 'هسع', 'حالا', 'الان', 'بسرعه', 'يا', 'ممكن', 'تكدر', 'تقدر', 'اكدر', 'الي', 'الى', 'ع',
    'مال', 'مالت', 'اشتراك', 'الاشتراك', 'اشتراكه', 'اشتراكها', 'المشترك', 'مشترك', 'المشتركه', 'حساب', 'الحساب', 'حسابه',
    'يوزر', 'اليوزر', 'خط', 'الخط', 'خطه', 'عند', 'هذا', 'هاذا', 'هذي', 'هاي', 'الاخ', 'الاستاذ', 'please', 'the',
    'له', 'لها', 'الها', 'اله', 'بيه', 'بيها', 'ب', 'ل', 'و', 'جديد', 'جديده', 'مبلغ', 'المبلغ', 'بمبلغ',
    // أدوات السؤال («شنو حالة علي») — ليست من الاسم
    'شنو', 'شو', 'ايش', 'شلون', 'اشلون', 'كيف', 'هل',
    // «اقطع النت عن علي»
    'عن', 'النت', 'نت', 'الانترنت', 'انترنت', 'اسمه', 'اسمها', 'تبع', 'بعده', 'بعدها', 'لسه', 'شي', 'لي', 'ريت', 'ياريت',
    'وخلي', 'وخليه', 'خليه', 'خليها', 'لا', 'او', 'راح', 'رح', 'البلوك', 'الحظر',
    // الإنكليزيّة
    'a', 'an', 'for', 'to', 'of', 'on', 'in', 'at', 'by', 'with', 'from', 'into', 'his', 'her', 'their', 'him', 'he',
    'she', 'me', 'my', 'i', 'want', 'need', 'would', 'like', 'can', 'could', 'you', 'this', 'that', 'mr', 'mrs', 'is',
    'are', 'does', 'do', 'did', 'and', 'now', 'subscriber', 'user', 'account', 'subscription', 'customer', 'client',
    'line', 'named', 'called', 'what', 'whats', 'how', 'amount', 'about', 'new', 'it',
  };

  /// عددٌ قبل «اشهر/months».
  static const _numberWords = {
    'واحد': 1, 'اثنين': 2, 'ثنين': 2, 'ثلاث': 3, 'ثلاثه': 3, 'تلاث': 3, 'اربع': 4, 'اربعه': 4, 'خمس': 5, 'خمسه': 5,
    'ست': 6, 'سته': 6, 'سبع': 7, 'سبعه': 7, 'ثمان': 8, 'ثمانيه': 8, 'ثمن': 8, 'تسع': 9, 'تسعه': 9, 'عشر': 10, 'عشره': 10,
    'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
    'ten': 10, 'eleven': 11, 'twelve': 12,
  };
  static const _monthWords = {'شهر', 'اشهر', 'شهور', 'months', 'month'};
  static const _yearWords = {'سنه', 'year', 'years'};
  static const _halfWords = {'نص', 'نصف', 'half'};

  // ── الأرقام المنطوقة (للمبالغ) ──
  static const _units = {
    'واحد': 1, 'وحده': 1, 'اثنين': 2, 'ثنين': 2, 'اثنان': 2, 'تنين': 2, 'ثلاث': 3, 'ثلاثه': 3, 'تلاث': 3, 'تلاثه': 3,
    'اربع': 4, 'اربعه': 4, 'خمس': 5, 'خمسه': 5, 'ست': 6, 'سته': 6, 'سبع': 7, 'سبعه': 7, 'ثمان': 8, 'ثمانيه': 8, 'ثمن': 8,
    'ثمنيه': 8, 'تمن': 8, 'تمنيه': 8, 'تسع': 9, 'تسعه': 9, 'one': 1,
  };

  /// آحادٌ إنكليزيّة — لا تلتبس باسم («ست زينب» بالعربيّة تلتبس)، فتكفي وحدها مبلغاً.
  static const _unitsEn = {'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9};
  static const _teens = {
    'عشر': 10, 'عشره': 10, 'احدعش': 11, 'احدعشر': 11, 'حدعش': 11, 'اداعش': 11, 'اثنعش': 12, 'اثناعش': 12, 'اثنعشر': 12,
    'اطنعش': 12, 'ثلطعش': 13, 'تلطعش': 13, 'ثلاثطعش': 13, 'اربعطعش': 14, 'خمسطعش': 15, 'خمستعش': 15, 'ستطعش': 16,
    'سبعطعش': 17, 'ثمنطعش': 18, 'تمنطعش': 18, 'تسعطعش': 19,
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
    'eighteen': 18, 'nineteen': 19,
  };
  static const _tens = {
    'عشرين': 20, 'ثلاثين': 30, 'تلاثين': 30, 'اربعين': 40, 'خمسين': 50, 'ستين': 60, 'سبعين': 70, 'ثمانين': 80, 'ثمنين': 80,
    'تمانين': 80, 'تسعين': 90,
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80,
    'ninety': 90,
  };
  static const _hundreds = {
    'ميه': 100, 'مايه': 100, 'ميتين': 200, 'مايتين': 200, 'ثلاثميه': 300, 'تلثميه': 300, 'تلاثميه': 300, 'ثلثميه': 300,
    'اربعميه': 400, 'خمسميه': 500, 'ستميه': 600, 'سبعميه': 700, 'ثمنميه': 800, 'ثمانميه': 800, 'تمنميه': 800, 'تسعميه': 900,
    'hundred': 100, 'hundreds': 100,
  };
  static const _thousandsWords = {
    'الف': 1000, 'الاف': 1000, 'الوف': 1000, 'الفين': 2000, 'الفان': 2000, 'ثلاثتلاف': 3000, 'تلاثتلاف': 3000, 'تلتلاف': 3000,
    'اربعتلاف': 4000, 'خمستلاف': 5000, 'خمستالاف': 5000, 'ستتلاف': 6000, 'سبعتلاف': 7000, 'ثمنتلاف': 8000, 'تمنتلاف': 8000,
    'تسعتلاف': 9000, 'عشرتلاف': 10000, 'عشرتالاف': 10000,
    'thousand': 1000, 'thousands': 1000, 'k': 1000, 'grand': 1000,
  };
  static const _millionsWords = {
    'مليون': 1000000, 'ملايين': 1000000, 'مليونين': 2000000, 'million': 1000000, 'millions': 1000000,
  };
  static const _fractions = {'نص': 0.5, 'نصف': 0.5, 'ربع': 0.25, 'half': 0.5, 'quarter': 0.25};

  /// روابط داخل العدد: «مية وخمسين»، "half a million"، "one hundred and fifty".
  static const _numJoin = {'و', 'and', 'a', 'an', 'of'};

  // ── قوائم المشتركين ──
  static const _listWords = {
    'المشتركين', 'مشتركين', 'المشتركون', 'مشتركون', 'مشتركيني', 'الزباين', 'زباين', 'اليوزرات', 'يوزرات', 'subscribers',
    'users', 'customers', 'clients',
  };
  static const _filters = <String, VoiceListFilter>{
    'المنتهين': VoiceListFilter.expired, 'منتهين': VoiceListFilter.expired, 'المنتهيه': VoiceListFilter.expired,
    'المنتهيين': VoiceListFilter.expired, 'منتهيين': VoiceListFilter.expired, 'الخلصانين': VoiceListFilter.expired,
    'خلصانين': VoiceListFilter.expired, 'expired': VoiceListFilter.expired,
    'المديونين': VoiceListFilter.debtors, 'مديونين': VoiceListFilter.debtors, 'المدينين': VoiceListFilter.debtors,
    'مدينين': VoiceListFilter.debtors, 'المطلوبين': VoiceListFilter.debtors, 'مطلوبين': VoiceListFilter.debtors,
    'الديون': VoiceListFilter.debtors, 'ديون': VoiceListFilter.debtors, 'debtors': VoiceListFilter.debtors,
    'debts': VoiceListFilter.debtors, 'indebted': VoiceListFilter.debtors,
    'المتصلين': VoiceListFilter.online, 'متصلين': VoiceListFilter.online, 'الاونلاين': VoiceListFilter.online,
    'اونلاين': VoiceListFilter.online, 'online': VoiceListFilter.online, 'connected': VoiceListFilter.online,
    'الاوفلاين': VoiceListFilter.offline, 'اوفلاين': VoiceListFilter.offline, 'المفصولين': VoiceListFilter.offline,
    'مفصولين': VoiceListFilter.offline, 'الطافين': VoiceListFilter.offline, 'طافين': VoiceListFilter.offline,
    'offline': VoiceListFilter.offline, 'disconnected': VoiceListFilter.offline,
    'المعطلين': VoiceListFilter.disabled, 'معطلين': VoiceListFilter.disabled, 'المطفيين': VoiceListFilter.disabled,
    'مطفيين': VoiceListFilter.disabled, 'الموقوفين': VoiceListFilter.disabled, 'موقوفين': VoiceListFilter.disabled,
    'المعلقين': VoiceListFilter.disabled, 'disabled': VoiceListFilter.disabled, 'suspended': VoiceListFilter.disabled,
    'الفعالين': VoiceListFilter.active, 'فعالين': VoiceListFilter.active, 'الشغالين': VoiceListFilter.active,
    'شغالين': VoiceListFilter.active, 'active': VoiceListFilter.active,
    'القريبين': VoiceListFilter.nearExpiry, 'قريبين': VoiceListFilter.nearExpiry, 'expiring': VoiceListFilter.nearExpiry,
  };

  /// «قريب الانتهاء» بكلمتين.
  static const _nearWords = {'قريب', 'قريبه', 'قرب', 'راح', 'soon'};

  /// حشو أوامر القوائم والأقسام.
  static const _navFiller = {
    'قسم', 'صفحه', 'قايمه', 'شاشه', 'تبويب', 'لي', 'كل', 'جميع', 'اللي', 'هم', 'عدد', 'count', 'number', 'section', 'page', 'screen', 'tab', 'menu',
    'list', 'all', 'who', 'the', 'to', 'of', 'me', 'my', 'are', 'is', 'please', 'عندي', 'مالتي', 'مالي',
  };

  /// اسم القسم (مطبَّعاً بلا «ال») ⇒ معرّفه.
  static const _sections = <String, String>{
    'تقارير': 'reports', 'تقرير': 'reports', 'تقارير ماليه': 'reports', 'تقرير مالي': 'reports', 'ماليه': 'reports',
    'reports': 'reports', 'report': 'reports',
    'صرفيات': 'expenses', 'مصاريف': 'expenses', 'مصروفات': 'expenses', 'expenses': 'expenses',
    'تسويه': 'settlements', 'تسويات': 'settlements', 'تسويه حساب': 'settlements', 'settlements': 'settlements',
    'settlement': 'settlements',
    'مبيعات': 'sales', 'sales': 'sales',
    'شحن رصيد': 'topup', 'شحن رصيد صفحه': 'topup', 'شحن صفحه': 'topup', 'شحن رصيدي': 'topup', 'اشحن رصيدي': 'topup',
    'اشحن رصيد صفحه': 'topup', 'اشحن صفحه': 'topup', 'اشحن صفحتي': 'topup', 'topup': 'topup',
    'كارتات': 'cards', 'cards': 'cards', 'vouchers': 'cards',
    'تلغرام': 'telegram', 'تليغرام': 'telegram', 'تلكرام': 'telegram', 'تليكرام': 'telegram', 'telegram': 'telegram',
    'تبليغات': 'broadcast', 'تبليغ': 'broadcast', 'بث': 'broadcast', 'broadcast': 'broadcast',
    'سجل رسايل': 'message_logs', 'رسايل': 'message_logs', 'messages': 'message_logs',
    'تذاكر': 'tickets', 'tickets': 'tickets',
    'طلبات تجديد': 'renew_requests', 'طلبات تفعيل': 'renew_requests', 'renew requests': 'renew_requests',
    'مدراء': 'managers', 'مدراء فرعيين': 'managers', 'وكلاء': 'managers', 'managers': 'managers', 'agents': 'managers',
    'باقات': 'packages', 'packages': 'packages', 'plans': 'packages',
    'خصومات': 'discounts', 'discounts': 'discounts',
    'اسعار مشتركين': 'subscriber_prices', 'اسعار': 'subscriber_prices', 'prices': 'subscriber_prices',
    'موظفين': 'employees', 'موظفيني': 'employees', 'employees': 'employees', 'staff': 'employees',
    'بوابه مشترك': 'portal', 'بوابه': 'portal', 'portal': 'portal',
    'اجهزه': 'tab:devices', 'devices': 'tab:devices', 'network': 'tab:devices',
    'رييسيه': 'tab:home', 'داشبورد': 'tab:home', 'لوحه': 'tab:home', 'dashboard': 'tab:home', 'home': 'tab:home',
    'قوايم اخري': 'tab:more', 'قوايم': 'tab:more', 'more': 'tab:more',
    'اعدادات': 'settings', 'ضبط': 'settings', 'settings': 'settings',
  };

  /// ما بعدها اسمٌ دائماً («عبد الباقي»، «ابو كامل»، «حجي واصل») — لا يُقرأ كلمة أمر ولو طابقها.
  static const _nameHeads = {
    'عبد', 'ابو', 'ام', 'ابن', 'بن', 'بنت', 'حجي', 'الحجي', 'حاج', 'الحاج', 'حجيه', 'الحجيه', 'سيد', 'السيد', 'شيخ', 'الشيخ',
    'استاذ', 'الاستاذ', 'دكتور', 'الدكتور', 'مهندس', 'المهندس', 'ملا', 'abu', 'abo', 'um', 'umm', 'ibn', 'bin', 'abd',
    'abdul', 'hajji', 'haji', 'sayed', 'sayyid', 'sheikh', 'dr',
  };

  /// «علاء الدين»، «نور الدين»… — «الدين» هنا من الاسم لا الدَّين.
  static const _dinHeads = {
    'علاء', 'نور', 'صلاح', 'سيف', 'عز', 'محي', 'محيي', 'شمس', 'بهاء', 'جمال', 'كمال', 'نجم', 'حسام', 'ضياء', 'عماد', 'زين',
    'تقي', 'فخر', 'نصر', 'ناصر', 'سعد', 'مجد', 'تاج', 'بدر', 'شهاب', 'جلال', 'برهان', 'صفاء', 'صدر', 'قطب', 'شرف', 'نظام',
    'رضي', 'ولي', 'خير', 'امين', 'معز', 'محب', 'قمر', 'عصام', 'علا', 'ala', 'alaa', 'noor', 'nour', 'nur', 'salah', 'saif',
    'izz', 'ezz',
  };

  /// علامةٌ تُلصق بكلمة الاسم المقفلة فلا تطابق أيّ مفردة — وتُنزع من الاسم الناتج.
  static const _keep = '\u00B7';

  /// كلمةٌ هي اسمٌ شائع أيضاً — لا تُقرأ فعلاً إلّا بقرينتها («زيد علي» مشترك؛ «زيد على علي ١٠ الاف» دين).
  static const _nameLikeAdd = {'زيد'};
  static const _nameLikeRemind = {'طالب'};

  /// «واصل» دفعٌ بعد اسم («فعّل علي واصل»)، واسمٌ قبله («فعّل واصل علي»).
  static const _nameLikeCue = {'واصل', 'واصله'};

  /// كلمتان تُقرآن واحدة.
  static const _bigrams = <String, String>{
    'turn off': 'disable', 'switch off': 'disable', 'shut off': 'disable', 'cut off': 'disable',
    'turn on': 'enable', 'switch on': 'enable',
    'top up': 'topup', 'log out': 'logout', 'kick out': 'kick', 'sign out': 'logout', 'pay off': 'pay',
    'how much': 'howmuch', 'how many': 'howmuch', 'how is': 'status', 'look up': 'lookup', 'go to': 'goto', 'master card': 'mastercard',
    'كلمه السر': 'باسورد', 'كلمه المرور': 'باسورد', 'كلمه سر': 'باسورد', 'ماستر كارد': 'ماستركارد',
    'اون لاين': 'اونلاين', 'اوف لاين': 'اوفلاين',
    'غير المتصلين': 'الاوفلاين', 'غير متصلين': 'الاوفلاين', 'مو متصلين': 'الاوفلاين', 'الغير متصلين': 'الاوفلاين',
    'not connected': 'offline', 'not online': 'offline',
  };

  /// كلّ مفردات الأوامر — «ودفع» ⇒ «دفع» حين يكون الباقي منها (و«وليد» يبقى).
  static final Set<String> _vocab = {
    ..._activate, ..._charge, ..._extend, ..._disable, ..._enable, ..._disconnect, ..._open, ..._go, ..._edit, ..._delete,
    ..._sell, ..._change, ..._changeWithPkg, ..._upgrade, ..._status, ..._check, ..._pay, ..._add, ..._discount, ..._remind,
    ..._send, ..._print, ..._call, ..._credit, ..._info, ..._qr, ..._statement, ..._movements, ..._whatsapp, ..._expiry,
    ..._receipt, ..._full, ..._usage, ..._location, ..._sessions, ..._sessionOne, ..._priceWords, ..._noteWords, ..._password,
    ..._packageWords, ..._debtWords, ..._cashWords, ..._debtPay, ..._partialWords, ..._paidCue, ..._advanceCue, ..._restWords,
    ..._cardWords, ..._bankCardWords, ..._walletWords, ..._monthWords, 'شهرين', 'سنه', 'سنتين',
  };

  static _Verb? _verbOf(String t) {
    if (_activate.contains(t)) return _Verb.activate;
    if (_charge.contains(t)) return _Verb.charge;
    if (_extend.contains(t)) return _Verb.extend;
    if (_disable.contains(t)) return _Verb.disable;
    if (_enable.contains(t)) return _Verb.enable;
    if (_disconnect.contains(t)) return _Verb.disconnect;
    if (_check.contains(t)) return _Verb.check;
    if (_status.contains(t)) return _Verb.status;
    if (_pay.contains(t)) return _Verb.pay;
    if (_add.contains(t)) return _Verb.add;
    if (_discount.contains(t)) return _Verb.discount;
    if (_remind.contains(t)) return _Verb.remind;
    if (_send.contains(t)) return _Verb.send;
    if (_print.contains(t)) return _Verb.print;
    if (_call.contains(t)) return _Verb.call;
    if (_edit.contains(t)) return _Verb.edit;
    if (_delete.contains(t)) return _Verb.delete;
    if (_sell.contains(t)) return _Verb.sell;
    if (_change.contains(t) || _upgrade.contains(t)) return _Verb.change;
    if (_go.contains(t)) return _Verb.go;
    if (_open.contains(t) && !_info.contains(t)) return _Verb.open;
    return null;
  }

  /// كلمة عددٍ (بلا «و» أوّلها) ⇒ صنفها، وإلّا null.
  static String? _numKind(String t) {
    if (RegExp(r'^\d+$').hasMatch(t)) return 'digits';
    if (RegExp(r'^\d+\.\d{1,2}$').hasMatch(t)) return 'decimal';
    if (_units.containsKey(t)) return 'unit';
    if (_unitsEn.containsKey(t)) return 'sunit';
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
  /// ٢٥٬٠٠٠ — لا مبلغ دين بخمسةٍ وعشرين ديناراً). رقمان متجاوران ليسا عدداً واحداً («علي 77 ٢٥ الف» ⇒ ٢٥ الف، و77 لليوزر).
  /// [near]: موضع كلمة الدفع — يُؤخذ أوّل مبلغٍ بعدها (وإلّا آخر ما قبلها) لا الأطول. ⇒ (المبلغ، مواضع كلماته) أو null.
  static (int, Set<int>)? parseAmount(List<String> tokens, {Set<int> skip = const {}, int? near, int? weakAfter}) {
    final chains = <(int, Set<int>)>[];
    var i = 0;
    while (i < tokens.length) {
      if (skip.contains(i) || _numKind(_stripWaw(tokens[i])) == null) {
        i++;
        continue;
      }
      // سلسلةٌ تبدأ هنا
      final idx = <int>{};
      var j = i;
      String? prevKind;
      while (j < tokens.length && !skip.contains(j)) {
        final t = tokens[j];
        if (_numJoin.contains(t)) {
          // رابطٌ يتبعه عدد («و»، and، "half a million")
          var k = j + 1;
          while (k < tokens.length && k <= j + 2 && _numJoin.contains(tokens[k])) {
            k++;
          }
          if (k < tokens.length && !skip.contains(k) && _numKind(_stripWaw(tokens[k])) != null) {
            for (var x = j; x < k; x++) {
              idx.add(x);
            }
            j = k;
            continue;
          }
          break;
        }
        final kind = _numKind(_stripWaw(t));
        if (kind == null && !_currency.contains(t)) break;
        final numeral = kind == 'digits' || kind == 'decimal';
        if (numeral && (prevKind == 'digits' || prevKind == 'decimal')) break;
        idx.add(j);
        if (kind != null) prevKind = kind;
        j++;
      }
      // [weakAfter]: سلسلةٌ تبدأ بعد هذا الموضع تُقبل ولو بلا كلمةٍ «قويّة» (آحادٌ وحدها بعد كلمة الدفع)
      final v = _valueOf([for (final k in idx.toList()..sort()) _stripWaw(tokens[k])], weakOk: weakAfter != null && i > weakAfter);
      if (v != null) chains.add((v, idx));
      i = j > i ? j : i + 1;
    }
    if (chains.isEmpty) return null;
    if (near != null) {
      (int, Set<int>)? after;
      (int, Set<int>)? before;
      for (final c in chains) {
        final first = c.$2.reduce((a, b) => a < b ? a : b);
        if (first > near) {
          after ??= c;
        } else {
          before = c;
        }
      }
      return after ?? before;
    }
    var best = chains.first;
    for (final c in chains.skip(1)) {
      if (c.$2.length > best.$2.length) best = c;
    }
    return best;
  }

  static int? _valueOf(List<String> words, {bool weakOk = false}) {
    var total = 0.0;
    var group = 0.0;
    var strong = weakOk;
    var multiplied = false;
    var lastMult = 0.0;
    for (var k = 0; k < words.length; k++) {
      final w = words[k];
      if (_numJoin.contains(w) || _currency.contains(w)) continue;
      switch (_numKind(w)) {
        case 'digits' || 'decimal':
          group += double.parse(w);
          strong = true;
        case 'unit':
          group += _units[w]!.toDouble();
        case 'sunit':
          group += _unitsEn[w]!.toDouble();
          strong = true;
        case 'teen':
          group += _teens[w]!.toDouble();
          strong = true;
        case 'ten':
          group += _tens[w]!.toDouble();
          strong = true;
        case 'hundred':
          // «خمسه ميه» = ٥٠٠ (نادر)، "five hundred" — وإلّا تُضاف
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

  /// سلسلةٌ هي مالٌ بلا لبس: فيها «الف/مليون» أو عملة أو رقمٌ من ألفٍ فأكثر (لا «77» من يوزر).
  static bool _isMoney(List<String> tokens, Set<int> idx) {
    for (final i in idx) {
      final t = _stripWaw(tokens[i]);
      final k = _numKind(t);
      if (k == 'thousand' || k == 'million' || _currency.contains(t)) return true;
      if (k == 'digits' && (int.tryParse(t) ?? 0) >= 1000) return true;
    }
    return false;
  }

  /// الجملة ⇒ كلماتها مطبَّعةً: الأرقام لاتينيّة، «25,000» رقمٌ واحد، الترقيم يُهمل، الكلمتان المعروفتان واحدة، و«ودفع» ⇒ «دفع».
  static List<String> tokenize(String transcript) {
    // «على» (حرف جرّ بالألف المقصورة) يُحذف قبل التطبيع — بعده لا يُميَّز عن اسم «علي»
    var pre = latinDigits(transcript).replaceAll(RegExp(r'(^|\s)على(?=\s|$)'), ' ');
    // «25,000» / «٢٥٬٠٠٠» رقمٌ واحد قبل حذف الترقيم
    for (var k = 0; k < 3; k++) {
      pre = pre.replaceAllMapped(RegExp(r'(\d)[,٬،.](\d{3})(?!\d)'), (m) => '${m[1]}${m[2]}');
    }
    // «1.5 مليون» كسرٌ عشريّ يبقى رقماً واحداً (لا عنوان IP ولا «25.000» التي ضُمّت أعلاه)
    pre = pre.replaceAllMapped(RegExp(r'(?<![\d.])(\d+)\.(\d{1,2})(?![\d.])'), (m) => '${m[1]}§${m[2]}');
    pre = pre
        .toLowerCase()
        // Ali's ⇒ ali
        .replaceAllMapped(RegExp(r"([a-z0-9])['’`]s\b"), (m) => m[1]!)
        // 25k ⇒ 25 thousand (رقمٌ قائمٌ بنفسه — لا «ali5k»)
        .replaceAllMapped(RegExp(r'(^|\s)(\d+)\s*k\b'), (m) => '${m[1]}${m[2]} thousand');
    final norm = normalizeArabic(pre)
        // (ورمز العملة: محرّك الخادم يكتب "$10,000" لـ«ten thousand» — قياس ١١ نوفمبر)
        .replaceAll(RegExp(r'''[.,!?؟،؛:"'’‘«»()\[\]{}_\-–—/\\|*+=~`^$€£]'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('§', '.')
        .trim();
    if (norm.isEmpty) return <String>[];
    final words = norm.split(' ');
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final two = i + 1 < words.length ? _bigrams['${words[i]} ${words[i + 1]}'] : null;
      if (two != null) {
        out.add(two);
        i++;
        continue;
      }
      final w = words[i];
      out.add(w.length > 3 && w.startsWith('و') && !_vocab.contains(w) && _vocab.contains(w.substring(1)) ? w.substring(1) : w);
    }
    // كلمة الاسم بعد «عبد/ابو/حجي…» و«الدين» بعد «علاء/نور…» تُقفل اسماً
    for (var i = 1; i < out.length; i++) {
      var prev = out[i - 1].replaceAll(_keep, '');
      // «لابو»، «بعبد»
      if (prev.length > 3 && (prev.startsWith('ل') || prev.startsWith('ب'))) {
        final bare = prev.substring(1);
        if (_nameHeads.contains(bare) || _dinHeads.contains(bare)) prev = bare;
      }
      if (_nameHeads.contains(prev) || (out[i] == 'الدين' && _dinHeads.contains(prev))) out[i] = '${out[i]}$_keep';
    }
    return out;
  }

  static final _arabicLetter = RegExp('[ء-يپچڤگ]');
  static final _latinLetter = RegExp('[a-z]');

  static String? _langOf(List<String> tokens) {
    var ar = 0;
    var en = 0;
    for (final t in tokens) {
      if (_arabicLetter.hasMatch(t)) {
        ar++;
      } else if (_latinLetter.hasMatch(t)) {
        en++;
      }
    }
    if (ar == 0 && en == 0) return null;
    return en > ar ? 'en' : 'ar';
  }

  static String _bare(String w) => w.length > 3 && w.startsWith('ال') ? w.substring(2) : w;

  /// موضع كلمة النفي قبل [at] مباشرةً ("hasn't paid" تُقطَّع hasn + t) — أو null.
  static int? _negationBefore(List<String> tokens, int at) {
    var k = at - 1;
    if (k >= 0 && tokens[k] == 't') k--;
    return k >= 0 && _negations.contains(tokens[k]) ? k : null;
  }

  static bool _negated(List<String> tokens, int at) => _negationBefore(tokens, at) != null;

  /// جملةٌ هي مبلغٌ وحده («عشرة آلاف»، «دفع ١٠ الاف»، "ten thousand") ⇒ المبلغ — جواب «كم دفع؟». وإلّا null.
  static int? parseBareAmount(String transcript) {
    final tokens = tokenize(transcript);
    if (tokens.isEmpty) return null;
    final a = parseAmount(tokens);
    if (a == null) return null;
    for (var i = 0; i < tokens.length; i++) {
      if (a.$2.contains(i)) continue;
      final t = tokens[i];
      if (_filler.contains(t) || _currency.contains(t) || _paidCue.contains(t) || _advanceCue.contains(t)) continue;
      return null;
    }
    return a.$1;
  }

  /// جملة الوكيل ⇒ ما يريد. لا يرمي؛ ما لا يُفهم ⇒ [VoiceAction.unknown] بالنصّ كما هو.
  static VoiceIntent parse(String transcript) {
    final raw = transcript.trim();
    if (raw.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);
    final tokens = tokenize(raw);
    if (tokens.isEmpty) return VoiceIntent(VoiceAction.unknown, raw: raw);
    final lang = _langOf(tokens);
    VoiceIntent make(
      VoiceAction a, {
      String query = '',
      int? months,
      VoicePayment? payment,
      int? paid,
      VoiceMethod? method,
      String package = '',
      String? deviceKind,
      int? amount,
      bool full = false,
      int? loose,
      String? section,
      VoiceListFilter? filter,
    }) =>
        VoiceIntent(a,
            query: query.replaceAll(_keep, ''),
            months: months,
            payment: payment,
            paid: paid,
            method: method,
            package: package.replaceAll(_keep, ''),
            deviceKind: deviceKind,
            amount: amount,
            fullAmount: full,
            looseAmount: loose,
            section: section,
            filter: filter,
            lang: lang,
            raw: raw);

    bool has(Set<String> set) => tokens.any(set.contains);

    // ٠) أوامر بلا مشترك: «مشترك جديد»، قسمٌ باسمه، قائمةٌ بفلترها — جملةٌ كلّها من مفرداتها، فلا تلتبس باسم
    final global = _global(tokens);
    if (global != null) {
      return make(global.$1, section: global.$2, filter: global.$3);
    }

    final hasCredit = has(_credit);
    final hasInfo = has(_info);
    final hasQr = has(_qr);
    final hasStatement = has(_statement);
    final hasMovements = has(_movements);
    final hasSessions = has(_sessions);
    final hasUsage = has(_usage);
    final hasLocation = has(_location);
    final hasWhatsapp = has(_whatsapp);
    final hasExpiry = has(_expiry);
    final hasRemind = has(_remind);
    final hasDebtWord = has(_debtWords);
    final hasPackage = has(_packageWords);
    final hasPrice = has(_priceWords);
    final hasNote = has(_noteWords);
    final hasPassword = has(_password);

    final anyAmount = parseAmount(tokens);
    final moneySaid = anyAmount != null && _isMoney(tokens, anyAmount.$2);

    VoiceAction? action;
    final used = <int>{};
    int? verbAt;
    // ١) الفعل — أوّل ما يُعرف من الجملة (العراقيّ يبدأ به غالباً، ويُقبل بآخرها)
    for (var i = 0; i < tokens.length && action == null; i++) {
      final t = tokens[i];
      var v = _verbOf(t);
      // «حوّل/انقل/نزّل» فعلُ تغيير باقةٍ مع كلمتها وحدها
      if (v == null && _changeWithPkg.contains(t) && hasPackage) v = _Verb.change;
      // «زيد علي» / «طالب حسين» مشتركان — فعلان بمالٍ أو كلمة دين وحدهما
      if (v == _Verb.add && _nameLikeAdd.contains(t) && !(hasDebtWord || hasCredit || moneySaid)) v = null;
      if (v == _Verb.remind && _nameLikeRemind.contains(t) && !hasDebtWord) v = null;
      if (v == null) continue;
      action = switch (v) {
        _Verb.activate => VoiceAction.activate,
        // «اشحن رصيد» إضافة رصيد لا تفعيل
        _Verb.charge => hasCredit ? VoiceAction.addCredit : VoiceAction.activate,
        _Verb.extend => VoiceAction.extend,
        // «اقطع الجلسة/الاتصال» فصلٌ لا تطفية
        _Verb.disable => has(_sessionOne) ? VoiceAction.disconnect : VoiceAction.disable,
        _Verb.enable => VoiceAction.enable,
        _Verb.disconnect => VoiceAction.disconnect,
        _Verb.check => VoiceAction.checkDevice,
        _Verb.status => VoiceAction.checkSubscriber,
        _Verb.pay => VoiceAction.payDebt,
        _Verb.add => hasCredit
            ? VoiceAction.addCredit
            : hasMovements
                ? VoiceAction.movements
                : hasSessions
                    ? VoiceAction.sessions
                    : hasNote
                        ? VoiceAction.note
                        : VoiceAction.addDebt,
        _Verb.discount => VoiceAction.discount,
        _Verb.remind => hasExpiry ? VoiceAction.expiryWarning : VoiceAction.debtReminder,
        _Verb.send => hasExpiry
            ? VoiceAction.expiryWarning
            : (hasRemind || hasDebtWord)
                ? VoiceAction.debtReminder
                : hasQr
                    ? VoiceAction.qr
                    : hasLocation
                        ? VoiceAction.location
                        : VoiceAction.sendInfo,
        _Verb.print => VoiceAction.printReceipt,
        _Verb.call => VoiceAction.call,
        _Verb.edit => VoiceAction.edit,
        // «امسح دين علي» ليس حذف المشترك — دينه يُعرض، وتسديده بيد الوكيل
        _Verb.delete => hasDebtWord ? VoiceAction.debt : VoiceAction.delete,
        _Verb.sell => VoiceAction.sell,
        _Verb.change => (hasPackage || _upgrade.contains(t))
            ? VoiceAction.changePackage
            : hasPrice
                ? VoiceAction.price
                : VoiceAction.edit,
        _Verb.open || _Verb.go => VoiceAction.open,
      };
      used.add(i);
      verbAt = i;
    }
    // «لا تفعّل علي» / "don't activate Ali" — نهيٌ لا أمر: لا كرت تنفيذ له
    if (verbAt != null && _negated(tokens, verbAt)) return make(VoiceAction.unknown);
    // «افتح/وريني» + ما يُفتح: الكشف، الحركات، الرمز، الواتساب، الدين — و«شوف حالة فلان» جواب حاله
    if (action == VoiceAction.open) {
      if (has(_status) || has(_stateWords)) {
        action = VoiceAction.checkSubscriber;
      } else if (hasStatement) {
        action = VoiceAction.statement;
      } else if (hasMovements) {
        action = VoiceAction.movements;
      } else if (hasSessions) {
        action = VoiceAction.sessions;
      } else if (hasUsage) {
        action = VoiceAction.usage;
      } else if (hasLocation) {
        action = VoiceAction.location;
      } else if (hasQr) {
        action = VoiceAction.qr;
      } else if (hasWhatsapp) {
        action = VoiceAction.whatsapp;
      } else if (hasNote) {
        action = VoiceAction.note;
      } else if (hasPrice) {
        action = VoiceAction.price;
      } else if (hasDebtWord) {
        action = VoiceAction.debt;
      }
    }
    // بلا فعل: الاسم وحده مع كلمة العمليّة
    final hasHowMuch = has(_howMuch);
    final hasOnHim = has(_onHim);
    if (action == null) {
      if (has(_status) || has(_stateWords)) {
        action = VoiceAction.checkSubscriber;
      } else if (hasStatement) {
        action = VoiceAction.statement;
      } else if (hasMovements) {
        action = VoiceAction.movements;
      } else if (hasSessions) {
        action = VoiceAction.sessions;
      } else if (hasUsage) {
        action = VoiceAction.usage;
      } else if (hasLocation) {
        action = VoiceAction.location;
      } else if (hasQr) {
        action = VoiceAction.qr;
      } else if (hasWhatsapp) {
        action = VoiceAction.whatsapp;
      } else if (has(_receipt)) {
        action = VoiceAction.printReceipt;
      } else if (hasNote) {
        action = VoiceAction.note;
      } else if (hasPrice) {
        action = VoiceAction.price;
      } else if (hasInfo || hasPassword) {
        action = VoiceAction.open;
      } else if (hasCredit && parseAmount(tokens) != null) {
        action = VoiceAction.addCredit;
      } else if (hasOnHim && !hasHowMuch && parseAmount(tokens) != null) {
        // «علي عليه ٢٥ الف» ⇒ دين يُضاف (السؤال «شكد عليه» لا)
        action = VoiceAction.addDebt;
      } else if (hasDebtWord || (hasHowMuch && hasOnHim) || tokens.any(const {'owe', 'owes', 'owed'}.contains)) {
        action = VoiceAction.debt;
      }
    }

    // تغيير الباقة: الاسم والباقة يُفصلان بـ«الى»/to أو بكلمة «باقة» بينهما
    if (action == VoiceAction.changePackage) {
      final split = _splitPackage(tokens, verbAt ?? -1);
      if (split.$1.isEmpty) return make(VoiceAction.unknown);
      return make(VoiceAction.changePackage, query: split.$1, package: split.$2);
    }

    // ٢) المدّة (مع التفعيل والتمديد) — وتُحذف من الاسم
    int? months;
    if (action == VoiceAction.activate || action == VoiceAction.extend || action == null) {
      for (var i = 0; i < tokens.length; i++) {
        if (used.contains(i)) continue;
        final t = tokens[i];
        int? n;
        if (i > 0 && !used.contains(i - 1)) n = int.tryParse(tokens[i - 1]) ?? _numberWords[tokens[i - 1]];
        if (t == 'شهرين') {
          months = 2;
          used.add(i);
        } else if (t == 'سنتين') {
          months = 24;
          used.add(i);
        } else if (_yearWords.contains(t)) {
          used.add(i);
          if (i > 0 && _halfWords.contains(tokens[i - 1])) {
            months = 6;
            used.add(i - 1);
          } else if (i > 1 && _halfWords.contains(tokens[i - 2]) && (tokens[i - 1] == 'a' || tokens[i - 1] == 'an')) {
            months = 6;
            used
              ..add(i - 1)
              ..add(i - 2);
          } else if (n != null) {
            months = n * 12;
            used.add(i - 1);
          } else {
            months = 12;
          }
        } else if (_monthWords.contains(t)) {
          used.add(i);
          if (n != null) used.add(i - 1);
          months = n ?? (t == 'شهر' || t == 'month' ? 1 : months);
        }
        // «سنة كاملة» / «شهر كامل» — ليست من الاسم
        if (used.contains(i) && i + 1 < tokens.length && const {'كامله', 'كامل', 'كاملين', 'full'}.contains(tokens[i + 1])) {
          used.add(i + 1);
        }
      }
    }
    if (months != null && (months < 1 || months > 24)) months = null;

    // ٣) الدفع والطريقة مع التفعيل: «جزئي ١٠ الاف»، «دفع ١٠ والباقي دين»، «نقد»، «بالدين»، «بالكارت»
    VoicePayment? payment;
    VoiceMethod? method;
    int? paid;
    int? loose;
    if (action == VoiceAction.activate) {
      var cash = false;
      var debt = false;
      var partial = false;
      var paidCue = false;
      var rest = false;
      int? cueAt;
      // «والباقي دين» — «الباقي» وحدها قد تكون من اسم
      bool restAt(int i) {
        var words = 0;
        for (var k = i + 1; k < tokens.length && k <= i + 6 && words < 2; k++) {
          final x = tokens[k];
          if (_debtPay.contains(x) || _debtWords.contains(x) || _onHim.contains(x) || x == 'credit') return true;
          // «والباقي ٢٥ الف دين» — المبلغ بينهما لا يقطع
          if (_numKind(_stripWaw(x)) != null || _currency.contains(x) || _numJoin.contains(x)) continue;
          words++;
        }
        return false;
      }

      // اسمٌ قبل الكلمة؟ («فعّل علي واصل» دفع؛ «فعّل واصل علي» اسم)
      bool nameBefore(int i) {
        for (var k = 0; k < i; k++) {
          if (!used.contains(k) && !_vocab.contains(tokens[k]) && !_filler.contains(tokens[k])) return true;
        }
        return false;
      }

      for (var i = 0; i < tokens.length; i++) {
        if (used.contains(i)) continue;
        final t = tokens[i];
        if (_nameLikeCue.contains(t) && !nameBefore(i)) continue;
        if (_restWords.contains(t) && !restAt(i)) continue;
        final no = _negationBefore(tokens, i);
        final payWord = _partialWords.contains(t) || _advanceCue.contains(t) || _paidCue.contains(t) || _cashWords.contains(t);
        if (no != null && payWord) {
          // «ما دافع» / «بدون مقدّم» / "not paid" ⇒ لم يدفع: بالدين
          debt = true;
          used
            ..add(no)
            ..add(i);
          if (no < i - 1) used.add(i - 1);
          continue;
        }
        final nextT = i + 1 < tokens.length ? tokens[i + 1] : '';
        final nextKind = _numKind(_stripWaw(nextT));
        if (_fractions.containsKey(t) &&
            nextKind != 'thousand' &&
            nextKind != 'million' &&
            (_priceRef.contains(nextT) || _paidCue.contains(nextT) || (i > 0 && _paidCue.contains(tokens[i - 1])))) {
          // «دفع نص المبلغ» / «دفع نص» / "half paid" — جزءٌ من السعر لا مبلغٌ يُعرف هنا (السعر بشاشة التفعيل): جزئيٌّ يُسأل مبلغه
          partial = true;
          if (_priceRef.contains(nextT)) used.add(i + 1);
        } else if (_partialWords.contains(t) || _advanceCue.contains(t)) {
          partial = true;
          cueAt ??= i;
        } else if (_paidCue.contains(t)) {
          paidCue = true;
          cueAt ??= i;
        } else if (_cashWords.contains(t)) {
          cash = true;
          cueAt ??= i;
        } else if (_restWords.contains(t)) {
          rest = true;
        } else if (rest && _onHim.contains(t)) {
          // «والباقي عليه» — ليست من الاسم
        } else if (t == 'credit' && i > 0 && tokens[i - 1] == 'on') {
          debt = true; // "on credit" = بالدين
        } else if (_debtPay.contains(t) || _debtWords.contains(t)) {
          if (no != null) {
            // «مو دين» / «بدون دين» ⇒ نقداً
            cash = true;
            used.add(no);
          } else if (!(i > 0 && _pay.contains(tokens[i - 1]) && !_paidCue.contains(tokens[i - 1]))) {
            // («وسدّد دينه» أمرٌ آخر لا دفع هذا التفعيل)
            debt = true;
          }
        } else if (_full.contains(t) && t != 'كامل' && t != 'كامله') {
          // «دفع كله» — ليست من الاسم
        } else if (_cardWords.contains(t)) {
          method = VoiceMethod.card;
        } else if (_bankCardWords.contains(t)) {
          method = VoiceMethod.bankCard;
        } else if (_credit.contains(t) || _walletWords.contains(t)) {
          method ??= VoiceMethod.balance;
        } else if (!_pay.contains(t) && !_currency.contains(t)) {
          continue;
        }
        used.add(i);
      }
      if (partial || paidCue || cash || rest) {
        // بعد كلمة الدفع يكفي العدد الصغير وحده («جزئي خمسة» = ٥ الاف) — قبلها لا («ست زينب»)
        final a = parseAmount(tokens, skip: used, near: cueAt, weakAfter: cueAt);
        if (a != null) {
          paid = a.$1;
          used.addAll(a.$2);
          // مبلغٌ آخر بالجملة («والباقي ٢٥ الف دين») مالٌ لا اسم — يُحذف ولا يُربط
          for (var more = parseAmount(tokens, skip: used); more != null && _isMoney(tokens, more.$2); more = parseAmount(tokens, skip: used)) {
            used.addAll(more.$2);
          }
        }
      } else {
        // مبلغٌ بلا كلمة دفع («فعّل علي ٢٥ الف») — لا يُربط؛ يُحذف من الاسم إن كان مالاً بلا لبس ويُذكر
        final a = parseAmount(tokens, skip: used);
        if (a != null && _isMoney(tokens, a.$2)) {
          loose = a.$1;
          used.addAll(a.$2);
        }
      }
      if (paid != null || partial || rest) {
        payment = VoicePayment.partial;
      } else if (cash) {
        payment = VoicePayment.cash;
      } else if (debt) {
        payment = VoicePayment.debt;
      } else if (paidCue) {
        payment = VoicePayment.cash;
      }
    }

    // ٤) المبلغ (العمليّات الماليّة) و«كله»
    int? amount;
    var full = false;
    int? fullAt;
    if (voiceMoneyActions.contains(action) || action == VoiceAction.price) {
      final a = parseAmount(tokens, skip: used);
      if (a != null) {
        amount = a.$1;
        used.addAll(a.$2);
      }
      if (action == VoiceAction.payDebt && amount == null) {
        for (var i = 0; i < tokens.length; i++) {
          if (used.contains(i)) continue;
          // «سدد نص دينه» — جزءٌ من الدين لا مبلغٌ يُعرف هنا: يُحذف من الاسم والمبلغ يُسأل
          if (_fractions.containsKey(tokens[i])) {
            used.add(i);
            continue;
          }
          // «سدد كل ديونه» / «سدد كلشي»
          final all = tokens[i] == 'كلشي' || tokens[i] == 'كلش' || (tokens[i] == 'كل' && i + 1 < tokens.length && _debtWords.contains(tokens[i + 1]));
          if (all) {
            full = true;
            used.add(i);
            continue;
          }
          // «كامل» آخر الجملة وحدها (قد يكون اسماً: «سدد دين كامل حسن»)
          final nameLike = tokens[i] == 'كامل' || tokens[i] == 'كامله';
          if ((_full.contains(tokens[i]) && !nameLike) || (nameLike && i == tokens.length - 1)) {
            full = true;
            used.add(i);
            if (nameLike) fullAt = i;
          }
        }
      }
    }

    // «شنو حالة سكتر الشمال» — حال جهازٍ لا مشترك
    if (action == VoiceAction.checkSubscriber && tokens.any(_deviceWords.contains) && !has(_subscriberWords)) {
      action = VoiceAction.checkDevice;
    }
    // ٥) الفحص: «كلّ الأجهزة»/«فحص شامل» ⇒ الشامل؛ «افحص المشترك فلان» ⇒ المشترك؛ وكلمة الجهاز تُحذف من الاسم
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
            _status.contains(t) ||
            _stateWords.contains(t) ||
            _open.contains(t)) {
          continue;
        }
        rest.add(t);
      }
      if (action == VoiceAction.checkSubscriber || has(_subscriberWords)) {
        return rest.isEmpty
            ? make(VoiceAction.unknown)
            : make(VoiceAction.checkSubscriber, query: rest.join(' '));
      }
      if ((all || plural || tokens.contains('شامل') || tokens.contains('الشامل')) && rest.isEmpty) {
        return make(VoiceAction.checkAll);
      }
      String? kind;
      for (final t in tokens) {
        if (_deviceKinds.containsKey(t)) {
          kind = _deviceKinds[t];
          break;
        }
      }
      if (rest.isEmpty && kind == null) return make(VoiceAction.checkAll);
      // «افحص علي حسين» بلا «جهاز/سكتر» ولا «مشترك» ⇒ يُبحث بالاثنين
      if (!tokens.any(_deviceWords.contains)) return make(VoiceAction.check, query: rest.join(' '));
      return make(VoiceAction.checkDevice, query: rest.join(' '), deviceKind: kind);
    }

    // ٦) الاسم: ما بقي بلا حشو ولا كلمات العمليّة
    final plain = action == VoiceAction.open || action == VoiceAction.activate || action == VoiceAction.extend || action == null;
    final drop = <String>{
      ..._filler,
      if (!plain) ...{
        ..._debtWords, ..._howMuch, ..._onHim, ..._credit, ..._info, ..._qr, ..._statement, ..._movements, ..._whatsapp,
        ..._expiry, ..._remind, ..._receipt, ..._currency, ..._full, ..._usage, ..._location, ..._sessions, ..._sessionOne,
        ..._priceWords, ..._noteWords, ..._password, ..._packageWords, ..._open, ..._go,
      },
      if (action == VoiceAction.edit) ..._editFields,
      if (action == VoiceAction.usage ||
          action == VoiceAction.sessions ||
          action == VoiceAction.movements ||
          action == VoiceAction.statement)
        ..._timeWords,
      if (action == VoiceAction.sell) ...{..._deviceWords, ..._itemWords},
      if (action == VoiceAction.price) ..._priceExtra,
      if (action == VoiceAction.debt) ...{..._debtWords, ..._howMuch, ..._onHim},
      if (action == VoiceAction.open) ...{..._info, ..._password, ..._pageWords},
    };
    List<String> restOf() => [
          for (var i = 0; i < tokens.length; i++)
            // «رجاءً فعّل علي» حشو أوّل الجملة — وبعد الفعل اسم «رجاء»
            if (!used.contains(i) && !drop.contains(tokens[i]) && !(i == 0 && tokens[i] == 'رجاء')) tokens[i],
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
      return query.isEmpty ? make(VoiceAction.unknown) : make(VoiceAction.open, query: query);
    }
    if (query.isEmpty) return make(VoiceAction.unknown);
    final act = action == VoiceAction.activate;
    return make(action,
        query: query,
        months: act || action == VoiceAction.extend ? months : null,
        payment: act ? payment : null,
        paid: act ? paid : null,
        method: act ? method : null,
        amount: amount,
        full: full,
        loose: act ? loose : null);
  }

  /// أوامر بلا مشترك — تُقبل حين تكون الجملة كلّها من مفرداتها (لا اسم فيها): ⇒ (العمليّة، القسم، الفلتر) أو null.
  static (VoiceAction, String?, VoiceListFilter?)? _global(List<String> tokens) {
    bool nav(String t) => _open.contains(t) || _go.contains(t) || _navFiller.contains(t) || _filler.contains(t);

    // «ضيف مشترك جديد» / "add a new subscriber"
    const fresh = {'جديد', 'جديده', 'new'};
    const create = {'انشي', 'انشاء', 'سجل', 'create'};
    final hasSub = tokens.any(_newSubWords.contains);
    final hasNew = tokens.any(fresh.contains);
    final hasAdd = tokens.any((t) => _add.contains(t) || create.contains(t));
    if (hasSub && (hasNew || hasAdd)) {
      final extra = tokens.where((t) =>
          !_newSubWords.contains(t) && !fresh.contains(t) && !_add.contains(t) && !create.contains(t) && !_filler.contains(t));
      if (extra.isEmpty) return (VoiceAction.addSubscriber, null, null);
    }

    // «ضيف صرفية» / «صرفية جديدة» — الصرفيّة تُضاف من قسمها (لا دين باسم «صرفية»)
    const expense = {'صرفيه', 'الصرفيه', 'مصروف', 'المصروف', 'expense'};
    if (tokens.any(expense.contains)) {
      final extra = tokens.where((t) =>
          !expense.contains(t) && !fresh.contains(t) && !_add.contains(t) && !create.contains(t) && !_filler.contains(t) && !nav(t));
      if (extra.isEmpty) return (VoiceAction.openSection, 'expenses', null);
    }

    // قسمٌ باسمه: «افتح التقارير»، «روح للصرفيات»، "open reports"
    final core = [
      for (final t in tokens)
        if (!_open.contains(t) && !_go.contains(t) && !_navFiller.contains(t)) t,
    ];
    if (core.isNotEmpty && core.length <= 3) {
      String strip(String w) {
        // «للتقارير» ⇒ «تقارير»
        final x = w.length > 4 && w.startsWith('لل') ? w.substring(2) : w;
        return _bare(x);
      }

      final section = _sections[core.map(strip).join(' ')];
      if (section != null) return (VoiceAction.openSection, section, null);
    }

    // قائمةٌ بفلترها: «المشتركين المنتهين»، «وريني المديونين»، "expired subscribers"
    VoiceListFilter? filter;
    var list = false;
    var near = false;
    var expiryWord = false;
    for (final t in tokens) {
      if (_listWords.contains(t)) {
        list = true;
      } else if (_filters.containsKey(t)) {
        filter ??= _filters[t];
      } else if (_nearWords.contains(t)) {
        near = true;
      } else if (_expiry.contains(t) || t == 'ينتهون' || t == 'expire') {
        expiryWord = true;
      } else if (_howMuch.contains(t) || nav(t)) {
        continue;
      } else {
        return null; // كلمةٌ ليست من مفردات القوائم ⇒ ليس أمر قائمة
      }
    }
    if (near && expiryWord) filter = VoiceListFilter.nearExpiry;
    if (filter == null && !list) return null;
    if (filter == null && (near || expiryWord)) return null;
    return (VoiceAction.listSubscribers, null, filter ?? VoiceListFilter.all);
  }

  /// كلماتٌ تدلّ أنّ ما بعد «لـ» الملصوقة باقةٌ لا اسم («لفايبر ٥٠»).
  static const _packageHints = {
    'فايبر', 'ميكا', 'ميغا', 'مكا', 'ميجا', 'ميگا', 'كيكا', 'جيجا', 'برو', 'بلس', 'لايت', 'ذهبي', 'ذهبيه', 'فضي', 'فضيه', 'ماسي',
    'ماسيه', 'سوبر', 'تربو', 'اقتصادي', 'اقتصاديه', 'مفتوح', 'مفتوحه', 'انلمتد', 'fiber', 'mega', 'giga', 'pro', 'plus', 'lite',
  };

  /// «غيّر باقة علي حسين الى فايبر ٥٠» ⇒ (الاسم، الباقة كما قيلت). الباقة قد تفرغ («غيّر باقة علي») — تُختار بشاشتها.
  static (String, String) _splitPackage(List<String> tokens, int verbAt) {
    const delims = {'الي', 'الى', 'ل', 'to', 'into', 'ع'};
    const forWords = {'for', 'مال', 'مالت', 'للمشترك', 'للزبون'};
    bool pkgWord(String t) => _packageWords.contains(t);
    String join(Iterable<String> ws, {bool name = false}) =>
        ws.where((w) => !pkgWord(w) && !_change.contains(w) && (!name || !_filler.contains(w))).join(' ');

    final body = <int>[for (var i = 0; i < tokens.length; i++) if (i != verbAt) i];
    int? d;
    for (final i in body) {
      if (i > verbAt && delims.contains(tokens[i]) && i + 1 < tokens.length) d = i;
    }
    if (d != null) {
      final before = [for (final i in body) if (i < d) tokens[i]];
      final after = [for (final i in body) if (i > d) tokens[i]];
      final name = join(before, name: true);
      if (name.isNotEmpty) return (name, join(after));
      // "change package to fiber 50 for Ali"
      final f = after.indexWhere(forWords.contains);
      if (f > 0 && f + 1 < after.length) return (join(after.sublist(f + 1), name: true), join(after.sublist(0, f)));
      return (join(after, name: true), '');
    }
    // بلا فاصل: كلمة «باقة» بين الاسم والباقة («حوّل علي حسين باقة ٥٠ ميگا»)
    final p = body.where((i) => pkgWord(tokens[i])).toList();
    if (p.isNotEmpty) {
      final before = [for (final i in body) if (i < p.last) tokens[i]];
      final after = [for (final i in body) if (i > p.last) tokens[i]];
      final name = join(before, name: true);
      if (name.isNotEmpty && after.isNotEmpty) return (name, join(after));
    }
    // «بدّل باقة علي لفايبر ٥٠» — «لـ» ملصوقةٌ بباقةٍ تُعرف بكلمتها أو برقمها
    final rest = [for (final i in body) if (!pkgWord(tokens[i]) && !_filler.contains(tokens[i])) tokens[i]];
    for (var k = rest.length - 1; k >= 1; k--) {
      final w = rest[k];
      if (w.length > 3 && w.startsWith('ل')) {
        final head = w.substring(1);
        final numeric = RegExp(r'\d').hasMatch(head) || (k + 1 < rest.length && RegExp(r'^\d').hasMatch(rest[k + 1]));
        if (_packageHints.contains(head) || numeric) {
          return (rest.sublist(0, k).join(' '), [head, ...rest.sublist(k + 1)].join(' '));
        }
      }
    }
    return (rest.join(' '), '');
  }
}
