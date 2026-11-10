// «الأوامر الصوتيّة» (٦–٧ نوفمبر — المالك: «وكيل يامره يفعل مشترك يطفي مشترك يفحص جهاز»): الفهم على الجهاز بجملٍ عراقيّة
// كما يُملي محرّك الصوت، والمطابقة بأسماء المشتركين/يوزراتهم وأسماء الأجهزة. لا شبكة هنا.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/voice/voice_command.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';

Subscriber _s(String idx, String user, String first, String last, {String? phone}) => Subscriber.fromJson({
      'idx': idx,
      'username': user,
      'firstname': first,
      'lastname': last,
      if (phone != null) 'phone': phone,
    });

NetworkDevice _d(int id, String name, String type, {String ip = '10.0.0.1'}) => NetworkDevice(
      id: id,
      adminId: '2',
      name: name,
      type: type,
      brand: 'mikrotik',
      ip: ip,
      port: 8728,
      protocol: 'api',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

void main() {
  group('الفهم', () {
    VoiceIntent p(String s) => VoiceCommand.parse(s);

    test('التفعيل بصيغه + المدّة والدفع + الاسم بلا حشو', () {
      final a = p('فعّل علي حسين شهرين بالدين');
      expect(a.action, VoiceAction.activate);
      expect(a.query, 'علي حسين');
      expect(a.months, 2);
      expect(a.payment, VoicePayment.debt);
      for (final s in ['جدد اشتراك محمد كاظم', 'جدّدله لمحمد كاظم', 'اشحن محمد كاظم']) {
        final x = p(s);
        expect(x.action, VoiceAction.activate, reason: s);
        expect(x.query.endsWith('محمد كاظم'), isTrue, reason: '$s ⇒ ${x.query}');
      }
      // ١٠ نوفمبر: «مدّد» صار عمليّة «تمديد» نفسها (زرّها بصفحة المشترك) لا التفعيل
      final ext = p('مدد اشتراك المشترك محمد كاظم');
      expect([ext.action, ext.query], [VoiceAction.extend, 'محمد كاظم']);
      expect(p('فعل احمد ٣ اشهر نقد').months, 3);
      expect(p('فعل احمد ٣ اشهر نقد').payment, VoicePayment.cash);
      expect(p('فعل احمد ثلاث اشهر').months, 3);
      expect(p('فعل احمد شهر').months, 1);
      expect(p('فعل احمد نص سنه').months, 6);
    });

    test('«على» حرف الجرّ يُحذف و«علي» الاسم يبقى', () {
      final a = p('شكد على علي دين');
      expect(a.action, VoiceAction.debt);
      expect(a.query, 'علي');
      expect(p('طفي اشتراك علي').query, 'علي');
    });

    test('التطفية والتشغيل والفتح والدين بمفرداتها', () {
      expect(p('طفي محمد').action, VoiceAction.disable);
      expect(p('وقف اشتراك حسين علي').action, VoiceAction.disable);
      expect(p('اقطعه لحسين').action, VoiceAction.disable);
      expect(p('عطل حسين').action, VoiceAction.disable);
      expect(p('شغل حسين').action, VoiceAction.enable);
      expect(p('رجعه لابو زهراء').action, VoiceAction.enable);
      expect(p('افتح اشتراك زينب').action, VoiceAction.open);
      expect(p('وريني حال زينب').action, VoiceAction.open);
      expect(p('شكد عليه دين احمد').action, VoiceAction.debt);
      expect(p('كم مطلوب حسن').action, VoiceAction.debt);
      expect(p('شكد عليه دين احمد').query, 'احمد');
      // اسمٌ وحده ⇒ فتح صفحته
      final o = p('ابو حيدر الحلي');
      expect([o.action, o.query], [VoiceAction.open, 'ابو حيدر الحلي']);
    });

    test('فحص الأجهزة: باسمه ونوعه، و«كل الأجهزة»/«فحص شامل» ⇒ الشامل', () {
      final a = p('افحص سكتر الشمال');
      expect([a.action, a.query, a.deviceKind], [VoiceAction.checkDevice, 'الشمال', 'sector']);
      expect(p('افحص الراوتر').action, VoiceAction.checkDevice);
      expect(p('افحص الراوتر').deviceKind, 'router');
      expect(p('افحص كل الاجهزه').action, VoiceAction.checkAll);
      expect(p('فحص شامل').action, VoiceAction.checkAll);
      expect(p('افحص الشبكة').action, VoiceAction.checkAll);
      expect(p('افحص').action, VoiceAction.checkAll);
    });

    test('٧ نوفمبر «العمليات المهمه كلها»: الدين تسديداً وإضافةً، الرصيد، الخصم — بالمبلغ كما يُنطق', () {
      var a = p('سدد دين احمد ٢٥ الف');
      expect([a.action, a.query, a.amount], [VoiceAction.payDebt, 'احمد', 25000]);
      a = p('علي حسين دفع خمسة وعشرين الف');
      expect([a.action, a.query, a.amount], [VoiceAction.payDebt, 'علي حسين', 25000]);
      a = p('سدد دين علي كله');
      expect([a.action, a.query, a.fullAmount, a.amount], [VoiceAction.payDebt, 'علي', true, null]);
      a = p('سدد دين كامل');
      expect([a.query, a.fullAmount], ['كامل', false], reason: '«كامل» وحدها اسم');
      a = p('ضيف دين على زينب ١٠ آلاف');
      expect([a.action, a.query, a.amount], [VoiceAction.addDebt, 'زينب', 10000]);
      a = p('حط على محمد كاظم 15,000');
      expect([a.action, a.query, a.amount], [VoiceAction.addDebt, 'محمد كاظم', 15000]);
      a = p('محمد عليه ٣٥ الف');
      expect([a.action, a.amount], [VoiceAction.addDebt, 35000]);
      expect(p('شكد عليه دين احمد').action, VoiceAction.debt, reason: 'السؤال يبقى سؤالاً');
      a = p('اضف رصيد لزينب ٥٠ الف');
      expect([a.action, a.query, a.amount], [VoiceAction.addCredit, 'لزينب', 50000]);
      a = p('اشحن رصيد علي نص مليون');
      expect([a.action, a.amount], [VoiceAction.addCredit, 500000]);
      expect(p('اشحن محمد كاظم').action, VoiceAction.activate, reason: 'بلا «رصيد» تجديد كما كان');
      a = p('سوي خصم لعلي ٥ الاف');
      expect([a.action, a.amount], [VoiceAction.discount, 5000]);
    });

    test('المبالغ المنطوقة: الأرقام والكلمات والآلاف والملايين و«نص»؛ ما دون الألف بلا «الف» بالآلاف؛ العدد وحده ليس مبلغاً', () {
      int? amt(String s) => VoiceCommand.parseAmount(s.split(' '))?.$1;
      expect(amt('مية وخمسين الف'.replaceAll('ة', 'ه')), 150000);
      expect(amt('مليون ونص'), 1500000);
      expect(amt('نص مليون'), 500000);
      expect(amt('ربع مليون'), 250000);
      expect(amt('الفين'), 2000);
      expect(amt('عشرتلاف'), 10000);
      expect(amt('خمسه وعشرين'), 25000, reason: 'العراقيّ: «دفع خمسة وعشرين» = ٢٥ الف');
      expect(amt('250 الف'), 250000);
      expect(amt('الف وخمسميه'), 1500);
      expect(amt('ست'), isNull, reason: '«ست» وحدها قد تكون «ست زينب»');
      expect(p('سدد دين علي ٢٥٬٠٠٠').amount, 25000);
      expect(p('سدد دين علي 25.000').amount, 25000);
    });

    test('المراسلة والوصل والرمز والكشف والحركات والاتّصال', () {
      expect(p('ذكر علي بالدين').action, VoiceAction.debtReminder);
      expect(p('ذكر علي بالدين').query, 'علي');
      expect(p('ارسل تذكير دين لعلي').action, VoiceAction.debtReminder);
      expect(p('نبهه بالانتهاء احمد').action, VoiceAction.expiryWarning);
      expect(p('دز معلومات حسين').action, VoiceAction.sendInfo);
      expect(p('دز معلومات حسين').query, 'حسين');
      expect(p('ارسل المعلومات لحسين').action, VoiceAction.sendInfo);
      expect([p('اطبع وصل حسين').action, p('اطبع وصل حسين').query], [VoiceAction.printReceipt, 'حسين']);
      expect(p('رمز qr علي').action, VoiceAction.qr);
      expect(p('ارسل رمز علي').action, VoiceAction.qr);
      expect([p('كشف حساب علي').action, p('كشف حساب علي').query], [VoiceAction.statement, 'علي']);
      expect(p('حركات زينب').action, VoiceAction.movements);
      expect(p('سجل حركات زينب').action, VoiceAction.movements);
      expect([p('اتصل بعلي').action, p('اتصل بعلي').query], [VoiceAction.call, 'بعلي']);
      expect(p('واتساب احمد').action, VoiceAction.whatsapp);
      expect(p('افتح واتساب احمد').action, VoiceAction.whatsapp);
      // ما كان يعمل يبقى
      expect(p('معلومات زينب').action, VoiceAction.open);
      expect(p('افتح اشتراك زينب').action, VoiceAction.open);
    });

    test('ما لا يُفهم ⇒ unknown بلا رمي، والأرقام العربيّة لاتينيّة، والترقيم يُهمل', () {
      expect(p('').action, VoiceAction.unknown);
      expect(p('   ').action, VoiceAction.unknown);
      expect(p('فعل').action, VoiceAction.unknown, reason: 'فعلٌ بلا اسم');
      expect(p('فعّل علي٧٧.').query, 'علي77');
      expect(p('طفي «ali.home»؟').query, 'ali home');
    });
  });

  group('المطابقة', () {
    final subs = [
      _s('1', 'ali.hussein', 'علي', 'حسين'),
      _s('2', 'ali77', 'علي', 'كاظم'),
      _s('3', 'mohammed.k', 'محمد', 'كاظم جبار', phone: '07701234567'),
      _s('4', 'zainab', 'زينب', 'علي'),
      _s('5', 'abu.haider', 'ابو حيدر', 'الحلي'),
    ];
    List<String> top(String q) => VoiceResolver.rank(subs, q).map((m) => m.item.username).toList();

    test('الاسم الكامل أوّلاً، وكلمة واحدة مشتركة ⇒ عدّة مرشّحين بلا جزم', () {
      expect(top('علي حسين').first, 'ali.hussein');
      final m = VoiceMatches(VoiceResolver.rank(subs, 'علي حسين'));
      expect(m.sure, isTrue);
      final many = VoiceMatches(VoiceResolver.rank(subs, 'علي'));
      expect(many.items.length, greaterThanOrEqualTo(2));
      expect(many.sure, isFalse, reason: 'ثلاثة «علي» ⇒ يختار الوكيل');
      expect(top('محمد كاظم').first, 'mohammed.k');
      expect(top('ابو حيدر').first, 'abu.haider');
      expect(top('أبو حيدر الحلّي').first, 'abu.haider', reason: 'الهمزة والشدّة تُطبَّعان');
    });

    test('الأرقام تحسم اليوزر، واليوزر بالحروف، والهاتف', () {
      expect(top('علي 77').first, 'ali77');
      expect(VoiceMatches(VoiceResolver.rank(subs, 'علي 77')).sure, isTrue);
      expect(top('zainab').first, 'zainab');
      expect(top('07701234567').first, 'mohammed.k');
      expect(top('7701234567').first, 'mohammed.k');
    });

    test('المنطوق العربيّ ليوزرٍ لاتينيّ بلا اسم: بالهيكل الصوتيّ', () {
      final s = [_s('9', 'hassan.kadhim', '', '')];
      expect(VoiceResolver.rank(s, 'حسن كاظم').map((m) => m.item.username), ['hassan.kadhim']);
      expect(VoiceResolver.arabicSkeleton('كاظم'), VoiceResolver.latinSkeleton('kadhim'));
      expect(VoiceResolver.arabicSkeleton('خالد'), VoiceResolver.latinSkeleton('khaled'));
      expect(VoiceResolver.rank(s, 'زينب'), isEmpty, reason: 'لا تطابق ⇒ لا مرشّح');
    });

    test('الأجهزة: بالاسم بلا «ال»، والنوع يقدّم، وبلا اسم ⇒ كلّ أجهزة النوع', () {
      final devs = [_d(1, 'سكتر الشمال', 'sector'), _d(2, 'راوتر البرج', 'router'), _d(3, 'سكتر الجنوب', 'sector', ip: '10.0.0.9')];
      expect(VoiceResolver.rankDevices(devs, 'الشمال').first.item.id, 1);
      expect(VoiceResolver.rankDevices(devs, 'شمال', kind: 'sector').first.item.id, 1);
      expect(VoiceResolver.rankDevices(devs, 'البرج').first.item.id, 2);
      expect(VoiceResolver.rankDevices(devs, '', kind: 'sector').map((m) => m.item.id).toSet(), {1, 3});
      expect(VoiceResolver.rankDevices(devs, '10.0.0.9').first.item.id, 3);
      expect(VoiceResolver.rankDevices(devs, 'الشرق'), isEmpty);
    });

    test('الحساب الكبير: بحث الشركة (لا القائمة الكاملة)، وأطول كلمة إن لم يجد النصّ كلّه', () async {
      final asked = <String>[];
      VoiceResolver.bigProbe = () async => 89000;
      VoiceResolver.bigSearch = (q) async {
        asked.add(q);
        return q == 'حسين' ? [subs.first] : <Subscriber>[];
      };
      VoiceResolver.loadSubscribers = () async => throw StateError('لا قائمة كاملة للكبير');
      addTearDown(() {
        VoiceResolver.bigProbe = () async => 0;
        VoiceResolver.loadSubscribers = () async => const [];
      });
      final m = await VoiceResolver.subscribers('علي حسين');
      expect(asked, ['علي حسين', 'حسين']);
      expect(m.items.first.item.username, 'ali.hussein');
      expect(m.error, isNull);
    });
  });
}
