// «الأمر الصوتي ٢» (١٠ نوفمبر — المالك: «تسديد دين تفعيل جزئي وباقي العمليات يحتاج نوسع النطاق ويحتاج نخلي يتعرف على اللغة
// انكليزي عربي من النطق»): الفهم على الجهاز — التفعيل بدفعه كما قيل، باقي عمليّات صفحة المشترك، أوامر بلا مشترك، والإنكليزيّة
// كاملةً والإنكليزيّ بحروفٍ عربيّة. لا شبكة هنا.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/voice/voice_command.dart';

void main() {
  VoiceIntent p(String s) => VoiceCommand.parse(s);

  group('التفعيل بدفعه كما قيل', () {
    test('«تفعيل جزئي»: كلمة «جزئي» أو «دفع/دافع/واصل/مقدّم» تربط المبلغ مدفوعاً، و«والباقي دين» تؤكّده', () {
      var a = p('تفعيل جزئي علي حسين عشرة الاف');
      expect([a.action, a.query, a.payment, a.paid], [VoiceAction.activate, 'علي حسين', VoicePayment.partial, 10000]);
      a = p('فعّل علي حسين جزئي ١٠ الاف');
      expect([a.query, a.payment, a.paid], ['علي حسين', VoicePayment.partial, 10000]);
      a = p('فعّل علي حسين ودفع ١٥ الف والباقي دين');
      expect([a.query, a.payment, a.paid], ['علي حسين', VoicePayment.partial, 15000]);
      a = p('فعل محمد كاظم دافع عشرين');
      expect([a.query, a.payment, a.paid], ['محمد كاظم', VoicePayment.partial, 20000], reason: 'ما دون الألف بالآلاف');
      a = p('جدد زينب علي واصل ٥ الاف');
      expect([a.query, a.payment, a.paid], ['زينب علي', VoicePayment.partial, 5000]);
      a = p('فعل احمد مقدم ١٠ الاف');
      expect([a.payment, a.paid], [VoicePayment.partial, 10000]);
      a = p('فعل احمد نقد ١٠ الاف والباقي بالدين');
      expect([a.query, a.payment, a.paid], ['احمد', VoicePayment.partial, 10000], reason: 'نقدٌ بمبلغ = مدفوعٌ جزئيّ');
    });

    test('جزئيّ بلا مبلغ ⇒ يُسأل «كم دفع؟»، والجملة التالية بالمبلغ وحده تكمّله', () {
      final a = p('فعّل علي حسين جزئي');
      expect([a.action, a.query, a.payment, a.paid, a.needsPaid], [VoiceAction.activate, 'علي حسين', VoicePayment.partial, null, true]);
      expect(a.needsAmount, isTrue);
      expect(VoiceCommand.parseBareAmount('عشرة آلاف'), 10000);
      expect(VoiceCommand.parseBareAmount('دفع ١٥ الف دينار'), 15000);
      expect(VoiceCommand.parseBareAmount('ten thousand'), 10000);
      expect(VoiceCommand.parseBareAmount('25'), 25000);
      expect(VoiceCommand.parseBareAmount('فعل علي ١٠ الاف'), isNull, reason: 'أمرٌ جديد لا مبلغٌ وحده');
      expect(VoiceCommand.parseBareAmount('علي'), isNull);
      final b = a.withAmount(10000);
      expect([b.paid, b.payment, b.query, b.needsPaid], [10000, VoicePayment.partial, 'علي حسين', false]);
      // والتسديد بلا مبلغ يكمَّل كذلك
      final c = p('سدد دين علي حسين');
      expect(c.needsAmount, isTrue);
      expect(c.withAmount(25000).amount, 25000);
      expect(p('سدد دين علي كله').needsAmount, isFalse);
    });

    test('نقد/دين وحدها، و«دافع» وحدها نقدٌ كامل، و«وسدّد دينه» لا تجعل التفعيل بالدين', () {
      expect(p('فعل علي حسين نقد').payment, VoicePayment.cash);
      expect(p('فعل علي حسين كاش').payment, VoicePayment.cash);
      expect(p('فعل علي حسين بالدين').payment, VoicePayment.debt);
      expect(p('فعل علي حسين اجل').payment, VoicePayment.debt);
      final a = p('فعل علي حسين دافع');
      expect([a.payment, a.paid, a.query], [VoicePayment.cash, null, 'علي حسين']);
      final b = p('فعل علي حسين وسدد دينه');
      expect([b.action, b.payment, b.query], [VoiceAction.activate, null, 'علي حسين']);
      expect(p('فعل علي حسين').payment, isNull, reason: 'لم يُقل ⇒ اختيار الشاشة كما هو');
    });

    test('النفي يقلب الدفع («ما دافع» دينٌ لا نقد، «مو دين» نقد)، والنهي ليس أمراً («لا تفعّل»)', () {
      var a = p('فعّل علي حسين ما دافع');
      expect([a.action, a.query, a.payment, a.paid], [VoiceAction.activate, 'علي حسين', VoicePayment.debt, null]);
      a = p('فعّل علي حسين بعده ما دفع شي');
      expect([a.query, a.payment], ['علي حسين', VoicePayment.debt]);
      a = p('فعّل علي حسين بدون مقدم');
      expect([a.query, a.payment, a.needsPaid], ['علي حسين', VoicePayment.debt, false]);
      a = p('فعّل علي حسين مو نقد');
      expect([a.query, a.payment], ['علي حسين', VoicePayment.debt]);
      a = p('فعّل علي حسين مو دين');
      expect([a.query, a.payment], ['علي حسين', VoicePayment.cash]);
      a = p('فعّل علي حسين بدون دين');
      expect([a.query, a.payment], ['علي حسين', VoicePayment.cash]);
      a = p("activate Ali Hussein, he hasn't paid");
      expect([a.query, a.payment], ['ali hussein', VoicePayment.debt]);
      a = p('activate Ali Hussein not paid');
      expect([a.query, a.payment], ['ali hussein', VoicePayment.debt]);
      a = p('فعّل علي حسين دفع كله');
      expect([a.query, a.payment, a.paid], ['علي حسين', VoicePayment.cash, null]);
      a = p('فعّل علي حسين دفع ١٠ الاف والباقي ٢٥ الف دين');
      expect([a.query, a.payment, a.paid], ['علي حسين', VoicePayment.partial, 10000], reason: 'المدفوع ما بعد «دفع»؛ الباقي ليس اسماً');
      // النهي: لا كرت تنفيذ
      expect(p('لا تفعل علي حسين').action, isNot(VoiceAction.activate));
      expect(p('ما تطفي علي حسين').action, isNot(VoiceAction.disable));
      expect(p("don't activate Ali Hussein").action, VoiceAction.unknown);
      expect(p('do not disable Ali Hussein').action, VoiceAction.unknown);
      expect(p('لا تسدد دين علي').action, isNot(VoiceAction.payDebt));
    });

    test('صيغ الكلام اليوميّ: «فعّللي»، «اريد افعّل»، «تكدر تفعّل»، «جزئي خمسة»، «والباقي عليها»، «نص المبلغ»', () {
      for (final s in ['فعللي علي حسين', 'فعّل لي اشتراك علي حسين', 'اريد افعل علي حسين', 'يا ريت تفعل علي حسين', 'تكدر تجدد علي حسين']) {
        final a = p(s);
        expect([a.action, a.query], [VoiceAction.activate, 'علي حسين'], reason: s);
      }
      var a = p('فعل ابو علي جزئي خمسة');
      expect([a.query, a.payment, a.paid], ['ابو علي', VoicePayment.partial, 5000], reason: 'العدد الصغير بعد كلمة الدفع مبلغ');
      a = p('فعل ست زينب دافع');
      expect([a.query, a.payment, a.paid], ['ست زينب', VoicePayment.cash, null], reason: '«ست» قبل كلمة الدفع من الاسم');
      a = p('فعل ام حسين دفعت عشرة والباقي عليها');
      expect([a.query, a.payment, a.paid], ['ام حسين', VoicePayment.partial, 10000]);
      a = p('فعل علي حسين وخلي دين');
      expect([a.query, a.payment], ['علي حسين', VoicePayment.debt]);
      a = p('فعل علي حسين ودفع نص المبلغ');
      expect([a.query, a.payment, a.paid, a.needsPaid], ['علي حسين', VoicePayment.partial, null, true], reason: 'جزءٌ من السعر يُسأل مبلغه');
      a = p('علي حسين متصل لو لا');
      expect([a.action, a.query], [VoiceAction.checkSubscriber, 'علي حسين']);
      a = p('استهلاك علي حسين هذا الشهر');
      expect([a.action, a.query], [VoiceAction.usage, 'علي حسين']);
      a = p('بيع راوتر لعلي حسين');
      expect([a.action, a.query], [VoiceAction.sell, 'لعلي حسين']);
      expect([p('التقارير المالية').action, p('التقارير المالية').section], [VoiceAction.openSection, 'reports']);
      expect([p('شكد عدد المتصلين').action, p('شكد عدد المتصلين').filter], [VoiceAction.listSubscribers, VoiceListFilter.online]);
    });

    test('جملٌ تُفهم على وجهها: «سنة كاملة»، «نص الدين» يُسأل، «كل ديونه» كاملاً، «امسح دينه» ليس حذفاً، «ضيف صرفية» قسمها', () {
      var a = p('جدد لعلي حسين سنة كاملة');
      expect([a.action, a.query, a.months], [VoiceAction.activate, 'لعلي حسين', 12]);
      a = p('سدد دين علي حسين نص الدين');
      expect([a.action, a.query, a.amount, a.fullAmount, a.needsAmount], [VoiceAction.payDebt, 'علي حسين', null, false, true]);
      a = p('سدد كل ديون علي حسين');
      expect([a.action, a.query, a.fullAmount], [VoiceAction.payDebt, 'علي حسين', true]);
      a = p('علي حسين سدد كلشي');
      expect([a.action, a.query, a.fullAmount], [VoiceAction.payDebt, 'علي حسين', true]);
      a = p('امسح دين علي حسين');
      expect([a.action, a.query], [VoiceAction.debt, 'علي حسين'], reason: 'ليس حذف المشترك');
      expect([p('ضيف صرفية').action, p('ضيف صرفية').section], [VoiceAction.openSection, 'expenses']);
      expect([p('اضافة صرفية جديدة').action, p('اضافة صرفية جديدة').section], [VoiceAction.openSection, 'expenses']);
      a = p('فك البلوك عن علي حسين');
      expect([a.action, a.query], [VoiceAction.enable, 'علي حسين']);
      a = p('شنو حالة سكتر الشمال');
      expect([a.action, a.query, a.deviceKind], [VoiceAction.checkDevice, 'الشمال', 'sector']);
      a = p('نبه علي حسين اشتراكه راح ينتهي');
      expect([a.action, a.query], [VoiceAction.expiryWarning, 'علي حسين']);
      a = p('دز رمز الدخول لعلي حسين');
      expect([a.action, a.query], [VoiceAction.qr, 'لعلي حسين']);
      a = p('activate ali hussein half paid');
      expect([a.query, a.payment, a.paid], ['ali hussein', VoicePayment.partial, null]);
      a = p('فعل علي حسين دفع نص مليون');
      expect([a.query, a.payment, a.paid], ['علي حسين', VoicePayment.partial, 500000], reason: '«نص مليون» مبلغ لا «نص المبلغ»');
      a = p('what does ali hussein owe');
      expect([a.action, a.query], [VoiceAction.debt, 'ali hussein']);
      a = p('how is ali hussein');
      expect([a.action, a.query], [VoiceAction.checkSubscriber, 'ali hussein']);
    });

    test('المبلغ بلا كلمة دفع لا يُربط (يُذكر وحده)، وأرقام اليوزر تبقى له', () {
      var a = p('فعل علي حسين ٢٥ الف');
      expect([a.query, a.payment, a.paid, a.looseAmount], ['علي حسين', null, null, 25000]);
      a = p('فعل علي 77');
      expect([a.query, a.looseAmount], ['علي 77', null], reason: '77 من اليوزر لا مبلغ');
      a = p('فعل علي 77 دفع 10');
      expect([a.query, a.payment, a.paid], ['علي 77', VoicePayment.partial, 10000], reason: 'المبلغ ما بعد كلمة الدفع');
      a = p('سدد دين علي 77 ٢٥ الف');
      expect([a.action, a.query, a.amount], [VoiceAction.payDebt, 'علي 77', 25000], reason: 'رقمان متجاوران ليسا عدداً واحداً');
    });

    test('الطريقة والمدّة: «بالكارت»، «بالرصيد» (تفعيلٌ لا إضافة رصيد)، «بالبطاقة»، «شهرين»، «سنة»', () {
      var a = p('فعل علي حسين بالكارت');
      expect([a.action, a.query, a.method], [VoiceAction.activate, 'علي حسين', VoiceMethod.card]);
      a = p('فعل علي حسين بالرصيد');
      expect([a.action, a.query, a.method], [VoiceAction.activate, 'علي حسين', VoiceMethod.balance]);
      expect(p('اشحن رصيد علي ٥٠ الف').action, VoiceAction.addCredit, reason: '«اشحن رصيد» إضافة رصيد كما كانت');
      a = p('فعل علي حسين بالبطاقة');
      expect(a.method, VoiceMethod.bankCard);
      a = p('فعل علي حسين شهرين جزئي ٢٠ الف');
      expect([a.query, a.months, a.payment, a.paid], ['علي حسين', 2, VoicePayment.partial, 20000]);
      a = p('فعل علي حسين ٣ اشهر دفع ٥٠ الف');
      expect([a.months, a.paid], [3, 50000]);
      expect(p('فعل علي حسين سنه').months, 12);
      expect(p('فعل علي حسين سنتين').months, 24);
    });
  });

  group('باقي عمليّات صفحة المشترك', () {
    test('التمديد غير التفعيل', () {
      for (final s in ['مدد علي حسين', 'مدّدله لعلي حسين', 'تمديد اشتراك علي حسين']) {
        final a = p(s);
        expect(a.action, VoiceAction.extend, reason: s);
        expect(a.query.endsWith('علي حسين'), isTrue, reason: '$s ⇒ ${a.query}');
      }
      expect(p('جدد علي حسين').action, VoiceAction.activate);
    });

    test('تغيير الباقة: الاسم والباقة بفاصلهما', () {
      var a = p('غيّر باقة علي حسين الى فايبر ٣٥');
      expect([a.action, a.query, a.package], [VoiceAction.changePackage, 'علي حسين', 'فايبر 35']);
      a = p('بدّل باقة علي حسين لفايبر ٥٠');
      expect([a.action, a.query, a.package], [VoiceAction.changePackage, 'علي حسين', 'فايبر 50']);
      a = p('حوّل علي حسين على باقة ٥٠ ميكا');
      expect([a.action, a.query, a.package], [VoiceAction.changePackage, 'علي حسين', '50 ميكا']);
      a = p('غير باقة علي حسين');
      expect([a.action, a.query, a.package], [VoiceAction.changePackage, 'علي حسين', '']);
      a = p('upgrade Ali Hussein to 100 mega');
      expect([a.action, a.query, a.package], [VoiceAction.changePackage, 'ali hussein', '100 mega']);
      expect(p('حول علي حسين').action, VoiceAction.open, reason: '«حوّل» بلا «باقة» ليست أمراً');
    });

    test('فصل، تعديل، استهلاك، موقع، جلسات، سعر، بيع، ملاحظة، حذف', () {
      expect([p('افصل علي حسين').action, p('افصل علي حسين').query], [VoiceAction.disconnect, 'علي حسين']);
      expect([p('اقطع الاتصال عن علي').action, p('اقطع الاتصال عن علي').query], [VoiceAction.disconnect, 'علي']);
      expect(p('اقطعه لحسين').action, VoiceAction.disable, reason: '«اقطع» وحدها تطفية كما كانت');
      expect([p('عدل علي حسين').action, p('عدل علي حسين').query], [VoiceAction.edit, 'علي حسين']);
      expect([p('غير باسورد علي حسين').action, p('غير باسورد علي حسين').query], [VoiceAction.edit, 'علي حسين']);
      expect([p('غير اسم علي حسين').action, p('غير اسم علي حسين').query], [VoiceAction.edit, 'علي حسين']);
      expect([p('استهلاك علي حسين').action, p('استهلاك علي حسين').query], [VoiceAction.usage, 'علي حسين']);
      expect([p('شكد صارف علي حسين').action, p('شكد صارف علي حسين').query], [VoiceAction.usage, 'علي حسين']);
      expect([p('موقع علي حسين').action, p('موقع علي حسين').query], [VoiceAction.location, 'علي حسين']);
      expect(p('وريني لوكيشن زينب').action, VoiceAction.location);
      expect([p('جلسات علي حسين').action, p('جلسات علي حسين').query], [VoiceAction.sessions, 'علي حسين']);
      expect(p('سجل جلسات علي').action, VoiceAction.sessions);
      expect([p('سعر علي حسين').action, p('سعر علي حسين').query], [VoiceAction.price, 'علي حسين']);
      final fixed = p('ثبت سعر علي حسين ٣٠ الف');
      expect([fixed.action, fixed.query, fixed.amount], [VoiceAction.price, 'علي حسين', 30000]);
      expect(p('بيع لعلي حسين').action, VoiceAction.sell);
      expect([p('ملاحظة على علي حسين').action, p('ملاحظة على علي حسين').query], [VoiceAction.note, 'علي حسين']);
      expect(p('اكتب ملاحظة لعلي').action, VoiceAction.note);
      expect(p('اكتب على علي ١٠ الاف').action, VoiceAction.addDebt, reason: '«اكتب عليه» دينٌ كما كان');
      expect([p('احذف علي حسين').action, p('احذف علي حسين').query], [VoiceAction.delete, 'علي حسين']);
      expect([p('باسورد علي حسين').action, p('باسورد علي حسين').query], [VoiceAction.open, 'علي حسين']);
      expect([p('كلمة السر مال علي').action, p('كلمة السر مال علي').query], [VoiceAction.open, 'علي']);
      expect(p('علي حسين متصل').action, VoiceAction.checkSubscriber, reason: 'سؤال حاله');
      expect(p('علي حسين متصل').query, 'علي حسين');
    });
  });

  group('أسماءٌ تشبه كلمات الأوامر تبقى أسماء', () {
    test('«علاء الدين»، «عبد الباقي»، «رقيّة»، «دينا»، «باسم»، «ثابت»، «واصل»، «زيد»، «طالب»، «رجاء»، «ابو كامل»', () {
      var a = p('فعّل علاء الدين حسين');
      expect([a.action, a.query, a.payment], [VoiceAction.activate, 'علاء الدين حسين', null]);
      a = p('طفي نور الدين علي');
      expect([a.action, a.query], [VoiceAction.disable, 'نور الدين علي']);
      a = p('سدد دين صلاح الدين ٢٥ الف');
      expect([a.action, a.query, a.amount], [VoiceAction.payDebt, 'صلاح الدين', 25000]);
      a = p('فعّل عبد الباقي حسين');
      expect([a.action, a.query, a.payment], [VoiceAction.activate, 'عبد الباقي حسين', null]);
      a = p('فعّل عبد الواحد جزئي ١٠ الاف');
      expect([a.query, a.payment, a.paid], ['عبد الواحد', VoicePayment.partial, 10000]);
      a = p('رقية حسين');
      expect([a.action, a.query], [VoiceAction.open, 'رقيه حسين']);
      a = p('فعّل دينا علي');
      expect([a.action, a.query, a.payment], [VoiceAction.activate, 'دينا علي', null]);
      a = p('فعّل باسم محمد');
      expect([a.action, a.query], [VoiceAction.activate, 'باسم محمد']);
      a = p('طفي ثابت علي');
      expect([a.action, a.query], [VoiceAction.disable, 'ثابت علي']);
      a = p('ثابت علي');
      expect([a.action, a.query], [VoiceAction.open, 'ثابت علي']);
      a = p('فعّل واصل علي');
      expect([a.action, a.query, a.payment], [VoiceAction.activate, 'واصل علي', null]);
      a = p('فعّل علي حسين واصل');
      expect([a.query, a.payment], ['علي حسين', VoicePayment.cash]);
      a = p('زيد علي');
      expect([a.action, a.query], [VoiceAction.open, 'زيد علي']);
      a = p('زيد على علي ١٠ الاف');
      expect([a.action, a.query, a.amount], [VoiceAction.addDebt, 'علي', 10000]);
      a = p('طالب حسين');
      expect([a.action, a.query], [VoiceAction.open, 'طالب حسين']);
      a = p('طالب علي بالدين');
      expect([a.action, a.query], [VoiceAction.debtReminder, 'علي']);
      a = p('فعّل رجاء حسين');
      expect([a.action, a.query], [VoiceAction.activate, 'رجاء حسين']);
      a = p('رجاءً فعّل علي حسين');
      expect([a.action, a.query], [VoiceAction.activate, 'علي حسين']);
      a = p('سدد دين ابو كامل');
      expect([a.action, a.query, a.fullAmount], [VoiceAction.payDebt, 'ابو كامل', false]);
      a = p('فعّل حجي واصل نقد');
      expect([a.query, a.payment], ['حجي واصل', VoicePayment.cash]);
    });
  });

  group('أوامر بلا مشترك', () {
    test('«مشترك جديد» بصيغه — ولا يلتبس بإضافة دين', () {
      for (final s in ['ضيف مشترك جديد', 'مشترك جديد', 'اضافة مشترك', 'اريد اضيف مشترك', 'add subscriber', 'add a new user']) {
        expect(p(s).action, VoiceAction.addSubscriber, reason: s);
        expect(p(s).needsTarget, isFalse);
      }
      expect(p('ضيف على المشترك علي ١٠ الاف').action, VoiceAction.addDebt);
      expect(p('ضيف دين على زينب ١٠ آلاف').action, VoiceAction.addDebt);
    });

    test('القسم باسمه', () {
      const want = {
        'افتح التقارير': 'reports',
        'التقارير': 'reports',
        'روح للصرفيات': 'expenses',
        'افتح قسم المبيعات': 'sales',
        'التسويات': 'settlements',
        'الكارتات': 'cards',
        'الباقات': 'packages',
        'الموظفين': 'employees',
        'المدراء': 'managers',
        'سجل الرسائل': 'message_logs',
        'طلبات التجديد': 'renew_requests',
        'بوابة المشترك': 'portal',
        'شحن الرصيد': 'topup',
        'اشحن رصيدي': 'topup',
        'الاعدادات': 'settings',
        'الأجهزة': 'tab:devices',
        'الرئيسية': 'tab:home',
        'قوائم أخرى': 'tab:more',
        'open reports': 'reports',
        'go to expenses': 'expenses',
        'settings': 'settings',
      };
      want.forEach((s, id) {
        final a = p(s);
        expect([a.action, a.section], [VoiceAction.openSection, id], reason: s);
      });
      // ما كان يعمل يبقى
      expect(p('افحص الاجهزه').action, VoiceAction.checkAll);
      expect(p('اشحن رصيد علي ٥٠ الف').action, VoiceAction.addCredit);
      expect(p('سجل حركات زينب').action, VoiceAction.movements);
      expect(p('واتساب احمد').action, VoiceAction.whatsapp);
    });

    test('قوائم المشتركين بفلترها — جملةٌ فيها اسمٌ ليست قائمة', () {
      const want = {
        'المشتركين': VoiceListFilter.all,
        'افتح المشتركين': VoiceListFilter.all,
        'المشتركين المنتهين': VoiceListFilter.expired,
        'وريني المنتهين': VoiceListFilter.expired,
        'المديونين': VoiceListFilter.debtors,
        'وريني الديون': VoiceListFilter.debtors,
        'المتصلين': VoiceListFilter.online,
        'شكد المتصلين': VoiceListFilter.online,
        'غير المتصلين': VoiceListFilter.offline,
        'المشتركين المعطلين': VoiceListFilter.disabled,
        'المشتركين الفعالين': VoiceListFilter.active,
        'قريب الانتهاء': VoiceListFilter.nearExpiry,
        'المشتركين اللي راح ينتهون': VoiceListFilter.nearExpiry,
        'expired subscribers': VoiceListFilter.expired,
        'show debtors': VoiceListFilter.debtors,
        'online users': VoiceListFilter.online,
      };
      want.forEach((s, f) {
        final a = p(s);
        expect([a.action, a.filter], [VoiceAction.listSubscribers, f], reason: s);
      });
      expect(p('شكد على علي دين').action, VoiceAction.debt);
      expect(p('ديون علي حسين').action, VoiceAction.debt);
      expect(p('نبهه بالانتهاء احمد').action, VoiceAction.expiryWarning);
    });
  });

  group('الإنكليزيّة', () {
    test('الجملة الإنكليزيّة كاملةً — الفعل والاسم والدفع والمبلغ', () {
      var a = p('Activate Ali Hussein');
      expect([a.action, a.query, a.lang], [VoiceAction.activate, 'ali hussein', 'en']);
      a = p('Renew Ali Hussein for two months, cash.');
      expect([a.action, a.query, a.months, a.payment], [VoiceAction.activate, 'ali hussein', 2, VoicePayment.cash]);
      a = p('activate Ali Hussein partial 10 thousand');
      expect([a.query, a.payment, a.paid], ['ali hussein', VoicePayment.partial, 10000]);
      a = p('Activate Ali Hussein, he paid ten thousand, the rest on debt');
      expect([a.query, a.payment, a.paid], ['ali hussein', VoicePayment.partial, 10000]);
      a = p('activate Ali Hussein on credit');
      expect([a.query, a.payment], ['ali hussein', VoicePayment.debt]);
      a = p('activate Ali Hussein by card');
      expect([a.query, a.method], ['ali hussein', VoiceMethod.card]);
      a = p('extend Ali Hussein');
      expect([a.action, a.query], [VoiceAction.extend, 'ali hussein']);
      a = p('turn off Mohammed Kadhim');
      expect([a.action, a.query], [VoiceAction.disable, 'mohammed kadhim']);
      a = p('turn on Mohammed Kadhim');
      expect(a.action, VoiceAction.enable);
      a = p('disconnect Ali');
      expect([a.action, a.query], [VoiceAction.disconnect, 'ali']);
    });

    test('المال والمراسلة والفحص بالإنكليزيّة', () {
      var a = p("Pay Ali Hussein's debt 25,000");
      expect([a.action, a.query, a.amount], [VoiceAction.payDebt, 'ali hussein', 25000]);
      a = p('Ali Hussein paid twenty five thousand');
      expect([a.action, a.query, a.amount], [VoiceAction.payDebt, 'ali hussein', 25000]);
      a = p('pay debt of Ali in full');
      expect([a.action, a.query, a.fullAmount], [VoiceAction.payDebt, 'ali', true]);
      a = p('add debt to Zainab 10k');
      expect([a.action, a.query, a.amount], [VoiceAction.addDebt, 'zainab', 10000]);
      a = p('add credit to Zainab half a million');
      expect([a.action, a.query, a.amount], [VoiceAction.addCredit, 'zainab', 500000]);
      a = p('how much does Ali owe');
      expect([a.action, a.query], [VoiceAction.debt, 'ali']);
      a = p('remind Ali of his debt');
      expect([a.action, a.query], [VoiceAction.debtReminder, 'ali']);
      a = p('send expiry warning to Ahmed');
      expect([a.action, a.query], [VoiceAction.expiryWarning, 'ahmed']);
      a = p('send info to Hussein');
      expect([a.action, a.query], [VoiceAction.sendInfo, 'hussein']);
      a = p('print receipt for Hussein');
      expect([a.action, a.query], [VoiceAction.printReceipt, 'hussein']);
      a = p("show me Ali's statement");
      expect([a.action, a.query], [VoiceAction.statement, 'ali']);
      a = p('call Ali');
      expect([a.action, a.query], [VoiceAction.call, 'ali']);
      a = p('whatsapp Ahmed');
      expect([a.action, a.query], [VoiceAction.whatsapp, 'ahmed']);
      a = p('check subscriber Ali Hussein');
      expect([a.action, a.query], [VoiceAction.checkSubscriber, 'ali hussein']);
      a = p('what is the status of Ali');
      expect([a.action, a.query], [VoiceAction.checkSubscriber, 'ali']);
      a = p('is Ali online');
      expect([a.action, a.query], [VoiceAction.checkSubscriber, 'ali']);
      a = p('check sector north');
      expect([a.action, a.query, a.deviceKind], [VoiceAction.checkDevice, 'north', 'sector']);
      expect(p('check all devices').action, VoiceAction.checkAll);
      expect(p('full check').action, VoiceAction.checkAll);
      a = p('change package of Ali Hussein to Fiber 50');
      expect([a.action, a.query, a.package], [VoiceAction.changePackage, 'ali hussein', 'fiber 50']);
      a = p('change package to Fiber 50 for Ali Hussein');
      expect([a.action, a.query, a.package], [VoiceAction.changePackage, 'ali hussein', 'fiber 50']);
      a = p('usage of Ali');
      expect([a.action, a.query], [VoiceAction.usage, 'ali']);
      a = p('open Ali Hussein');
      expect([a.action, a.query], [VoiceAction.open, 'ali hussein']);
    });

    test('الأرقام الإنكليزيّة المنطوقة', () {
      int? amt(String s) => VoiceCommand.parseAmount(VoiceCommand.tokenize(s))?.$1;
      expect(amt('twenty five thousand'), 25000);
      expect(amt('one hundred and fifty thousand'), 150000);
      expect(amt('half a million'), 500000);
      expect(amt('a quarter of a million'), 250000);
      expect(amt('two thousand five hundred'), 2500);
      expect(amt('25k'), 25000);
      expect(amt('ten'), 10000, reason: 'ما دون الألف بالآلاف');
      expect(amt('five'), 5000);
      expect(amt('one'), isNull, reason: '"one" وحدها ليست مبلغاً');
      expect(amt('1.5 million'), 1500000, reason: 'الكسر العشريّ رقمٌ واحد — لا «5 مليون»');
      expect(amt('٢.٥ مليون'), 2500000);
      expect(amt('25.000'), 25000, reason: 'فاصلة الآلاف كما كانت');
    });

    test('الإنكليزيّ بحروفٍ عربيّة (المحرّك العربيّ يسمع كلمةً إنكليزيّة)، واللغة الغالبة', () {
      expect([p('اكتيفيت علي حسين').action, p('اكتيفيت علي حسين').query], [VoiceAction.activate, 'علي حسين']);
      expect(p('رينيو علي حسين').action, VoiceAction.activate);
      expect(p('ديسيبل علي حسين').action, VoiceAction.disable);
      expect(p('انيبل علي حسين').action, VoiceAction.enable);
      expect(p('ديسكونكت علي حسين').action, VoiceAction.disconnect);
      expect(p('اكستند علي حسين').action, VoiceAction.extend);
      expect(p('چيك سكتر الشمال').action, VoiceAction.checkDevice);
      expect(p('فعّل علي حسين').lang, 'ar');
      expect(p('فعّل ali77').lang, 'ar', reason: 'يوزرٌ لاتينيّ بجملةٍ عربيّة');
      expect(p('activate علي حسين').lang, 'ar');
      expect(p('activate ali hussein').lang, 'en');
      expect(p('07701234567').lang, isNull);
    });
  });
  test('١١ نوفمبر (قياس محرّك الخادم على ٦٨ أمراً): المبلغ برمز العملة مبلغ، و«فعلاً حسين علي بالدين» تفعيلٌ بالدين', () {
    final a = VoiceCommand.parse(r'Add debt to Zainab, $10,000');
    expect([a.action, a.amount, a.query], [VoiceAction.addDebt, 10000, 'zainab']);
    final b = VoiceCommand.parse('فعلاً حسين علي بالدين');
    expect([b.action, b.payment, b.query], [VoiceAction.activate, VoicePayment.debt, 'حسين علي']);
    expect(VoiceCommand.parse('فعلا علي حسين').action, VoiceAction.activate);
    // والفعل الأوّل بالجملة يبقى الحاكم
    expect(VoiceCommand.parse('سدد دين علي فعلا').action, VoiceAction.payDebt);
  });
}
