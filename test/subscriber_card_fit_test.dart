import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/split_fit_row.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// كرت المشترك لا يخرج منه نصٌّ ولا يُقصّ ما لا يصحّ قصّه — مهما كثرت المعلومات.
///
/// المالك ١٤ نوفمبر: «وبوضع المعلومات الهواي جاي الكتابه تطلع من الكارتات هم تاكد منها هاي». قِيس على الجذع قبل الإصلاح بهذه
/// الحالات نفسها: ٦٠ فيضاناً (صفّ الباقة: القياسات ابنٌ غير مرن في `Row`) — «وضع VPN» بقراءاته (إشارة + CCQ + الكيبل + شارة
/// VPN) يفيض بكلّ العروض حتى ٤٨٠، والوضع العاديّ على الهواتف الصغيرة وبخطّ الهاتف الكبير — و١٨٥ نصّاً مقصوصاً بـ«…» (تاريخ
/// الانتهاء، «متصل منذ…»، مبلغ الدين) لأنّ القرارات كانت بعتباتٍ ثابتة وقياسٍ بنمطٍ غير الذي يُرسم به.
const _widths = [320.0, 360.0, 375.0, 390.0, 412.0, 430.0, 480.0];
const _scales = [1.0, 1.2];

String _two(int n) => n.toString().padLeft(2, '0');

String _ago(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, 12).subtract(Duration(days: days)).toUtc().toIso8601String();
}

Map<String, dynamic> _row(int i, String user, String first, String last,
    {String profile = 'Economy--2', int price = 35000, int remaining = 20, int session = 609480, bool online = true, Map<String, dynamic>? more}) {
  final exp = DateTime.now().add(Duration(days: remaining, hours: 3));
  return {
    'idx': '$i',
    'username': user,
    'firstname': first,
    'lastname': last,
    'profile_name': profile,
    'profile_id': 40 + i,
    'package_price': price,
    'expiration': '${exp.year}-${_two(exp.month)}-${_two(exp.day)} ${_two(exp.hour)}:${_two(exp.minute)}:00',
    'remaining_days': remaining,
    'online_status': online ? 1 : 0,
    'enabled': 1,
    if (online) 'ip': '10.9.1.$i',
    if (online) 'session_time': session,
    ...?more,
  };
}

const _pin = {'latitude': 32.61, 'longitude': 44.02};

Map<String, dynamic> _nano(int i, int sig, String speed) => {
      'k': 'ubiquiti',
      'ip': '10.9.1.$i',
      'ubnt': {
        'h': 'nano$i',
        'sig': sig,
        'ccq': 96,
        'lan': [
          {'n': 'eth0', 's': speed, 'p': 1},
        ],
      },
    };

class _C {
  _C(this.id, this.label, this.json, {this.snap, this.vpn, this.telegram = false, this.pay});
  final String id, label;
  final Map<String, dynamic> json;
  final Map<String, dynamic>? snap;
  final VpnSubReading? vpn;
  final bool telegram;
  final Map<String, dynamic>? pay;
  late final Subscriber sub = Subscriber.fromJson(json);
}

final _cases = <_C>[
  _C('01', 'نانو', _row(1, 'ahmed.k@popq', 'أحمد', 'كاظم'), snap: _nano(1, -58, '100Mbps-Full')),
  _C('02', 'نانو + موقع', _row(2, 'ali.h@popq', 'علي', 'حسن', more: _pin), snap: _nano(2, -61, '100Mbps-Full')),
  _C('03', 'نانو + موقع + باقة طويلة + سعر كبير + 1000',
      _row(3, 'hussein.a@popq', 'حسين', 'علي', profile: 'Unlimited-Platinum-100M', price: 125000, more: _pin),
      snap: _nano(3, -58, '1000Mbps-Full')),
  _C('04', 'نانو + موقع + سعر ثابت (قفل)', _row(4, 'murtada.j@popq', 'مرتضى', 'جواد', more: {..._pin, 'price_source': 'custom'}),
      snap: _nano(4, -72, '100Mbps-Full')),
  _C('05', 'راوتر ضوئيّ (ضوء + حرارة) + موقع', _row(5, 'karrar.m@popq', 'كرار', 'محمد', more: _pin), snap: {
    'k': 'ont',
    'ip': '10.9.1.5',
    'ont': {'rx': '-23.45', 'tx': '2.31', 't': '48', 'v': '3.3', 'b': '12', 's': 'auto', 'vd': 'zte', 'md': 'HS8546V2'},
  }),
  _C('06', 'راوتر وحده (أجهزة) + موقع', _row(6, 'sajjad.a@popq', 'سجاد', 'عباس', more: _pin), snap: {
    'k': 'ubiquiti',
    'ip': '10.9.1.6',
    'ubnt': {'h': '', 'vd': 'tenda', 'md': 'F3', 'pc': 12},
  }),
  _C('07', 'وضع VPN: إشارة + CCQ + كيبل مفصول + موقع', _row(7, 'haider.s@popq', 'حيدر', 'سالم', more: _pin),
      vpn: const VpnSubReading(src: 'cpe', sig: -71, ccq: 88, lan: 'unplugged')),
  _C('08', 'وضع VPN: إشارة + CCQ + 10M', _row(8, 'abbas.r@popq', 'عباس', 'رضا'),
      vpn: const VpnSubReading(src: 'cpe', sig: -64, ccq: 100, lan: '10')),
  _C('09', 'وضع VPN: واصل + زمن', _row(9, 'noor.h@popq', 'نور', 'الهدى', more: _pin), vpn: const VpnSubReading(src: 'ping', ms: 123)),
  _C('10', 'وضع VPN: ضوء الأولت + حرارة', _row(10, 'zainab.k@popq', 'زينب', 'كاظم', more: _pin),
      vpn: const VpnSubReading(src: 'olt', rx: -24.37, temp: 51)),
  _C('11', 'نانو + دين كبير + عمره + زرّان',
      _row(11, 'kareem.t@popq', 'كريم', 'طالب', more: {'notes': '-1250000', 'debt_since': _ago(47), 'debt_kind': 'activate'}),
      snap: _nano(11, -58, '100Mbps-Full')),
  // (سطر «عرض الاستهلاك» خارج هذا الملفّ: مخزنه يجلب بمؤقّتٍ وشبكة — وهو نصٌّ مرن بقصّ، فُحص بعدّة اللقطات.)
  _C('12', 'نانو + آخر تسديد بمبلغ كبير', _row(12, 'yaser.n@popq', 'ياسر', 'نعمة', more: _pin),
      snap: _nano(12, -58, '100Mbps-Full'), pay: {'amount': 1250000, 'created_at': _ago(7)}),
  _C('13', 'غير متّصل + آخر جهاز + آخر اتصال',
      _row(13, 'ruqaya.j@popq', 'رقيّة', 'جواد', online: false, remaining: -5, more: {'last_mac': '68:FF:7B:8A:CD:11', 'last_online': '2026-11-10 08:15:00'})),
  _C('14', 'اسم ويوزر طويلان + تلغرام + نانو + موقع',
      _row(14, 'abdulrahman.abdulkareem.almousawi@popq-karbala', 'عبد الرحمن عبد الكريم', 'عبد الواحد الموسوي', more: _pin),
      snap: _nano(14, -58, '100Mbps-Full'), telegram: true),
  _C('15', 'منتهٍ متّصل + نانو + موقع + مدّة طويلة', _row(15, 'qasim.d@popq', 'قاسم', 'داود', remaining: -3, session: 11059140, more: _pin),
      snap: _nano(15, -79, '10Mbps-Full')),
];

_C _case(String id) => _cases.firstWhere((c) => c.id == id);

Widget _card(_C c) => SubscriberCardV3(
      key: ValueKey(c.id),
      sub: c.sub,
      selected: false,
      lastPayment: c.pay,
      hasTelegram: c.telegram,
      onTap: () {},
      onLongPress: () {},
      onOpenLocation: c.sub.hasLocation ? () {} : null,
      onSendDebtReminder: c.sub.hasDebt ? () {} : null,
      onPayDebt: c.sub.hasDebt ? () {} : null,
    );

/// الكرت كما في القائمة: حاشية ١٦ من الجانبين، عربيّ، بثيم التطبيق (خطّه وتباعد حروف Material الذي يرثه `Text`).
Future<void> _pump(WidgetTester t, Widget child, {required double width, double scale = 1.0, TextDirection dir = TextDirection.rtl}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(width, 1000);
  addTearDown(t.view.reset);
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true, textTheme: ThemeData.light().textTheme.apply(fontFamily: AppType.family)),
    home: Directionality(
      textDirection: dir,
      child: Scaffold(
        body: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [child]),
      ),
    ),
  ));
  await t.pump();
}

RenderParagraph? _para(WidgetTester t, bool Function(String text) test) {
  RenderParagraph? found;
  void walk(RenderObject o) {
    if (found == null && o is RenderParagraph && test(o.text.toPlainText())) found = o;
    if (found == null) o.visitChildren(walk);
  }

  walk(t.renderObject(find.byType(SubscriberCardV3)));
  return found;
}

bool _cut(RenderParagraph p) => p.maxLines == 1 && p.getMaxIntrinsicWidth(double.infinity) > p.size.width + 0.5;

double _top(RenderBox b) => b.localToGlobal(Offset.zero).dy;

RenderSplitFitRow _planRow(WidgetTester t) => t.renderObject<RenderSplitFitRow>(find.byType(SplitFitRow));

void main() {
  setUpAll(() async {
    await loadAppFonts();
    final now = DateTime.now().toIso8601String();
    SharedPreferences.setMockInitialValues({
      'device_probe.cache.v1': jsonEncode({
        for (final c in _cases)
          if (c.snap != null) c.snap!['ip'] as String: {'at': now, 'snap': c.snap},
      }),
    });
    await DeviceProbeApi.hydrateFromPrefs();
  });

  setUp(() {
    AppColors.setDarkMode(false);
    // «وضع VPN»: قراءات الخادم تتقدّم على قراءة الموبايل لمن له قراءة.
    VpnNow.debugApply(
      VpnNowKind.subscribers,
      VpnNowResult(ok: true, message: '', readings: {
        for (final c in _cases)
          if (c.vpn != null) c.sub.username.toLowerCase(): c.vpn!,
      }),
    );
    VpnNow.mode.value = true;
  });

  tearDown(() {
    VpnNow.mode.value = false;
    VpnNow.reset();
  });

  group('لا يخرج نصٌّ من الكرت ولا يُقصّ ما لا يصحّ قصّه', () {
    for (final scale in _scales) {
      for (final w in _widths) {
        testWidgets('عرض ${w.round()} · خطّ ×$scale — ${_cases.length} حالة', (t) async {
          for (final c in _cases) {
            await _pump(t, _card(c), width: w, scale: scale);
            final where = 'عرض ${w.round()} ×$scale — ${c.id} ${c.label}';
            final ex = t.takeException();
            expect(ex, isNull, reason: 'فيضان/استثناء في $where:\n$ex');
            final card = t.renderObject<RenderBox>(find.byType(SubscriberCardV3));
            final box = card.localToGlobal(Offset.zero) & card.size;
            // القصّ المشروع: الاسم واليوزر واسم الباقة (ما يطول بلا حدّ)، ووصف «آخر تسديد» بجانب مبلغه.
            final mayCut = {c.sub.username, c.sub.profileName ?? '', c.sub.fullName};
            void walk(RenderObject o) {
              if (o is RenderParagraph && o.hasSize) {
                final text = o.text.toPlainText();
                final r = o.localToGlobal(Offset.zero) & o.size;
                expect(r.left >= box.left - 0.5 && r.right <= box.right + 0.5, isTrue, reason: '«$text» خارج الكرت في $where');
                if (!mayCut.contains(text) && !text.startsWith('تسديد دين')) {
                  expect(_cut(o), isFalse, reason: '«$text» مقصوص في $where');
                }
              }
              o.visitChildren(walk);
            }

            walk(card);
          }
        });
      }
    }
  });

  group('صفّ الباقة والقياسات', () {
    testWidgets('يتّسع ⇒ سطرٌ واحد كما كان، والقياسات لا تزيد ارتفاع الكرت', (t) async {
      for (final w in [390.0, 412.0, 480.0]) {
        await _pump(t, _card(_case('01')), width: w);
        expect(_planRow(t).debugSplit, isFalse, reason: 'نانو بلا موقع على ${w.round()}: سطر واحد');
        final withMetrics = t.getSize(find.byType(SubscriberCardV3)).height;
        // المشترك نفسه بلا قراءة جهاز (عنوانٌ ليس في الكاش)
        final bare = _C('01b', '', {..._case('01').json, 'ip': '10.9.9.9', 'username': 'bare.k@popq'});
        await _pump(t, _card(bare), width: w);
        expect(t.getSize(find.byType(SubscriberCardV3)).height, withMetrics, reason: 'القياسات على السطر نفسه لا تكبّر الكرت (${w.round()})');
      }
    });

    testWidgets('شاشة 480: نانو + موقع يبقى سطراً واحداً والاسم كاملاً', (t) async {
      await _pump(t, _card(_case('02')), width: 480);
      expect(_planRow(t).debugSplit, isFalse);
      expect(_cut(_para(t, (s) => s == 'Economy--2')!), isFalse);
      final name = _para(t, (s) => s == 'Economy--2')!;
      final sig = _para(t, (s) => s == '-61 dBm')!;
      expect((_top(name) + name.size.height / 2 - _top(sig) - sig.size.height / 2).abs(), lessThan(3), reason: 'الباقة والإشارة على سطرٍ واحد');
    });

    testWidgets('«وضع VPN» بقراءاتٍ كثيرة: تنزل لسطرٍ تحته كاملةً، والباقة والسعر كاملان فوقها (حتى على 480)', (t) async {
      for (final w in [360.0, 390.0, 430.0, 480.0]) {
        await _pump(t, _card(_case('07')), width: w);
        expect(t.takeException(), isNull);
        expect(_planRow(t).debugSplit, isTrue, reason: 'عرض ${w.round()}');
        final name = _para(t, (s) => s == 'Economy--2')!;
        expect(_cut(name), isFalse, reason: 'اسم الباقة كامل (${w.round()})');
        for (final text in ['-71 dBm', 'CCQ 88%', 'الكيبل مفصول', 'VPN', '35,000 د.ع']) {
          final p = _para(t, (s) => s == text);
          expect(p, isNotNull, reason: '«$text» ظاهر (${w.round()})');
          expect(_cut(p!), isFalse, reason: '«$text» كامل (${w.round()})');
        }
        expect(_top(_para(t, (s) => s == 'CCQ 88%')!), greaterThan(_top(name) + 8), reason: 'القياسات تحت الباقة (${w.round()})');
      }
    });

    testWidgets('هاتف 360: اسم الباقة لا يُمحى — نانو + موقع ينزل، ونانو وحده يبقى سطراً', (t) async {
      await _pump(t, _card(_case('02')), width: 360);
      expect(_planRow(t).debugSplit, isTrue);
      expect(_cut(_para(t, (s) => s == 'Economy--2')!), isFalse);
      await _pump(t, _card(_case('01')), width: 360);
      expect(_planRow(t).debugSplit, isFalse, reason: 'ما دام يبقى من الاسم ما يُقرأ فلا يكبر الكرت');
    });

    testWidgets('زرّ الموقع يُنقر في الحالتين — على سطر الباقة وحين ينزل مع القياسات', (t) async {
      var taps = 0;
      Widget card(_C c) => SubscriberCardV3(
            sub: c.sub,
            selected: false,
            onTap: () => fail('النقر على الموقع فتح الكرت'),
            onLongPress: () {},
            onOpenLocation: () => taps++,
          );
      await _pump(t, card(_case('02')), width: 480);
      expect(_planRow(t).debugSplit, isFalse);
      await t.tap(find.byIcon(Icons.location_on_rounded));
      expect(taps, 1);
      await _pump(t, card(_case('07')), width: 390);
      expect(_planRow(t).debugSplit, isTrue);
      await t.tap(find.byIcon(Icons.location_on_rounded));
      expect(taps, 2);
    });

    testWidgets('أضيق هاتفٍ بأكبر خطّ: القياسات تلتفّ داخل سطرها ولا تخرج', (t) async {
      await _pump(t, _card(_case('07')), width: 320, scale: 1.2);
      expect(t.takeException(), isNull);
      final card = t.renderObject<RenderBox>(find.byType(SubscriberCardV3));
      final right = card.localToGlobal(Offset.zero).dx + card.size.width;
      for (final text in ['-71 dBm', 'CCQ 88%', 'الكيبل مفصول', 'VPN']) {
        final p = _para(t, (s) => s == text)!;
        final x = p.localToGlobal(Offset.zero).dx;
        expect(x >= card.localToGlobal(Offset.zero).dx && x + p.size.width <= right, isTrue, reason: '«$text» داخل الكرت');
        expect(_cut(p), isFalse);
      }
    });
  });

  group('صفّ الانتهاء ونصّ الجلسة', () {
    testWidgets('يتّسعان في حصّتيهما ⇒ سطرٌ واحد ونصّ الجلسة في عموده المعتاد', (t) async {
      await _pump(t, _card(_case('01')), width: 480);
      final date = _para(t, (s) => RegExp(r'^\d{4}/\d\d/\d\d').hasMatch(s))!;
      final session = _para(t, (s) => s.startsWith('متصل منذ'))!;
      expect((_top(date) - _top(session)).abs(), lessThan(4));
      expect(_cut(date) || _cut(session), isFalse);
      // عموده: حصّة ٤ من ٩ (بعد فاصل ٨) من محتوى الكرت — يبدأ نصّ الجلسة (بأيقونته) عند حافّتها اليمنى.
      final card = t.renderObject<RenderBox>(find.byType(SubscriberCardV3));
      final content = card.size.width - 30;
      final regionRight = card.localToGlobal(Offset.zero).dx + 15 + (content - 8) * 4 / 9;
      final textRight = session.localToGlobal(Offset.zero).dx + session.size.width;
      expect(textRight, closeTo(regionRight - 14 - 5, 1.5));
    });

    testWidgets('خطّ الهاتف الكبير على 412/430: لا يُقصّ التاريخ ولا «متصل منذ» — ينزل نصّ الجلسة لسطره', (t) async {
      for (final w in [412.0, 430.0]) {
        await _pump(t, _card(_case('01')), width: w, scale: 1.2);
        final date = _para(t, (s) => RegExp(r'^\d{4}/\d\d/\d\d').hasMatch(s))!;
        final session = _para(t, (s) => s.startsWith('متصل منذ'))!;
        expect(_cut(date), isFalse, reason: 'التاريخ كامل (${w.round()})');
        expect(_cut(session), isFalse, reason: 'نصّ الجلسة كامل (${w.round()})');
        expect(_top(session), greaterThan(_top(date) + 8), reason: 'تحته (${w.round()})');
      }
    });

    testWidgets('مدّة اتّصالٍ طويلة على 430: تبقى على السطر نفسه كاملةً (منطقتها بقدر حاجتها) بدل أن تُقصّ', (t) async {
      await _pump(t, _card(_case('15')), width: 430);
      final date = _para(t, (s) => RegExp(r'^\d{4}/\d\d/\d\d').hasMatch(s))!;
      final session = _para(t, (s) => s.startsWith('متصل منذ'))!;
      expect(session.text.toPlainText(), 'متصل منذ 127 يوم 23س 59د');
      expect(_cut(session) || _cut(date), isFalse);
      expect((_top(date) - _top(session)).abs(), lessThan(4), reason: 'يتّسعان معاً ⇒ لا يكبر الكرت');
    });
  });

  group('شريط الدين', () {
    testWidgets('المبلغ أوّلاً: مبلغٌ كبير بخطٍّ كبير ⇒ يسقط نصّ الزرّين ولا يُقصّ المبلغ', (t) async {
      await _pump(t, _card(_case('11')), width: 412, scale: 1.2);
      expect(t.takeException(), isNull);
      final amount = _para(t, (s) => s == '1,250,000 د.ع')!;
      expect(_cut(amount), isFalse);
      expect(find.text('تسديد'), findsNothing, reason: 'الزرّان بأيقونتيهما');
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    });

    testWidgets('مبلغٌ معتاد على شاشة واسعة: الزرّان بنصّيهما كما كانا', (t) async {
      final c = _C('11b', '', {..._case('11').json, 'notes': '-35000', 'username': 'small.debt@popq', 'ip': '10.9.9.8'});
      await _pump(t, _card(c), width: 480);
      expect(find.text('تسديد'), findsOneWidget);
      expect(find.text('تذكير دين'), findsOneWidget);
      expect(_cut(_para(t, (s) => s == '35,000 د.ع')!), isFalse);
    });
  });

  group('SplitFitRow', () {
    Widget box(Key k, double w, [double h = 20]) => SizedBox(key: k, width: w, height: h);
    const lead = Key('lead'), tail = Key('tail'), end = Key('end');

    Future<void> pumpRow(WidgetTester t, {required double width, required double leadW, double tailW = 50, double endW = 100, double minLead = 40, TextDirection dir = TextDirection.rtl}) async {
      await t.pumpWidget(Directionality(
        textDirection: dir,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SplitFitRow(
              minLead: minLead,
              // بدايةٌ تضيق: صندوقٌ بعرضه الطبيعيّ ما اتّسع
              lead: ConstrainedBox(key: lead, constraints: BoxConstraints(maxWidth: leadW), child: const SizedBox(height: 20, width: double.infinity)),
              tail: box(tail, tailW),
              end: endW == 0 ? const SizedBox.shrink(key: end) : box(end, endW, 16),
            ),
          ),
        ),
      ));
    }

    testWidgets('يتّسع الجميع ⇒ سطرٌ واحد: البداية وملاصقها من جهة، والنهاية عند الحافّة الأخرى', (t) async {
      await pumpRow(t, width: 300, leadW: 80);
      final r = t.renderObject<RenderSplitFitRow>(find.byType(SplitFitRow));
      expect(r.debugSplit, isFalse);
      expect(r.size, const Size(300, 20));
      expect(t.getTopLeft(find.byKey(lead)).dx, 220); // عربيّ: من اليمين
      expect(t.getTopLeft(find.byKey(tail)).dx, 170);
      expect(t.getTopLeft(find.byKey(end)), const Offset(0, 2)); // موسَّطة رأسيّاً
      await pumpRow(t, width: 300, leadW: 80, dir: TextDirection.ltr);
      expect(t.getTopLeft(find.byKey(lead)).dx, 0);
      expect(t.getTopLeft(find.byKey(tail)).dx, 80);
      expect(t.getTopLeft(find.byKey(end)).dx, 200);
    });

    testWidgets('يضيق: البداية تُقصّ حتى حدّها الأدنى قبل أن ينزل شيء', (t) async {
      await pumpRow(t, width: 220, leadW: 120); // 220 − 50 − 6 − 100 = 64 ≥ 40
      final r = t.renderObject<RenderSplitFitRow>(find.byType(SplitFitRow));
      expect(r.debugSplit, isFalse);
      expect(t.getSize(find.byKey(lead)).width, 64);
    });

    testWidgets('أضيق من الحدّ الأدنى ⇒ النهاية تنزل لسطرٍ ثانٍ والبداية تأخذ سطرها كاملاً', (t) async {
      await pumpRow(t, width: 190, leadW: 120); // 190 − 156 = 34 < 40
      final r = t.renderObject<RenderSplitFitRow>(find.byType(SplitFitRow));
      expect(r.debugSplit, isTrue);
      expect(t.getSize(find.byKey(lead)).width, 120);
      expect(r.size, const Size(190, 20 + 6 + 16));
      expect(t.getTopLeft(find.byKey(end)), const Offset(0, 26));
    });

    testWidgets('بدايةٌ أقصر من الحدّ الأدنى: حدّها عرضها الطبيعيّ (اسم باقةٍ قصير لا يُنزل القياسات)', (t) async {
      await pumpRow(t, width: 190, leadW: 30); // 30 + 50 + 6 + 100 = 186 ≤ 190
      expect(t.renderObject<RenderSplitFitRow>(find.byType(SplitFitRow)).debugSplit, isFalse);
    });

    testWidgets('بلا نهاية: البداية تأخذ كلّ ما بقي بلا فاصل', (t) async {
      await pumpRow(t, width: 150, leadW: 200, endW: 0);
      final r = t.renderObject<RenderSplitFitRow>(find.byType(SplitFitRow));
      expect(r.debugSplit, isFalse);
      expect(t.getSize(find.byKey(lead)).width, 100);
    });
  });
}
