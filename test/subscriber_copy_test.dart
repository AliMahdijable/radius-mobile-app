import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/util/clipboard_helper.dart';
import 'package:rad_mysvcs/core/widgets/copyable.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_chip_micro.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// طلب المستخدم ٢٠٢٦-١٠-١٨: «امكانيه نسخ كل معلومات كارت المشترك يعني كل
/// المتغيرات قابله للنسخ».
///
/// ثلاث طبقات تُحرس هنا:
///   ١. الضغط المطوّل على أيّ معلومة ينسخها وحدها (`Copyable`).
///   ٢. «نسخ كلّ المعلومات» يجمعها سطر «التسمية: القيمة» — بلا أيّ جلب،
///      وكلمة السرّ فيه حين تظهر وحدها.
///   ٣. إشعار النسخ يُرى **فوق الشيتات** (كان على `ScaffoldMessenger` فيُرسم
///      تحت أيّ شيتٍ مفتوح) وفوق لوحة المفاتيح، وواحدٌ لا يتكدّس.
///
/// لكلّ المزوّدين: الشاشة نفسها لـSAS4 وايرث لنك، فالحالات تُعاد للاثنين.

// ═══════════════════════ بيانات ═══════════════════════

/// مشترك SAS4 كامل البيانات — متّصل، عليه دين، تحت مدير، له موقع.
Map<String, Object?> _full({bool online = true}) => {
      'idx': '7',
      'username': 'user7',
      'firstname': 'علي',
      'lastname': 'حسن',
      'phone': '9647701234567',
      'profile_name': '10M-Unlimited',
      'profile_id': 7,
      'expiration': '2026-11-20 14:30:00',
      'online_status': online ? 1 : 0,
      'enabled': 1,
      'notes': '-35000',
      'parent_username': 'najaf650',
      'package_price': 25000,
      if (online) 'ip': '10.100.11.254',
      'static_ip': '192.168.100.254',
      if (online) 'session_time': 93784, // 1 يوم 2س 3د
      if (online) 'download': 5261334938, // 4.9 GB
      if (online) 'upload': 1288490188, // 1.2 GB
      if (!online) 'last_online': '2026-10-17 21:05:00',
      'latitude': 32.5,
      'longitude': 44.4,
      'address_raw': 'gps:32.5,44.4',
    };

Subscriber _sub(Map<String, Object?> j) =>
    Subscriber.fromJson(Map<String, dynamic>.from(j));

final _now = DateTime(2026, 10, 18, 12, 0);

const _ont = DeviceHealthSnapshot(
  kind: DeviceKind.ont,
  ip: '10.100.11.254',
  ont: OntOpticalInfo(
    txPower: '2.31',
    rxPower: '-21.55',
    voltage: '3300',
    temperature: '45',
    bias: '10',
    sendStatus: 'OK',
  ),
);

const _ubnt = DeviceHealthSnapshot(
  kind: DeviceKind.ubiquiti,
  ip: '10.100.11.254',
  ubnt: UbiquitiStatus(
    hostname: 'NanoBeam-7',
    firmware: 'XW.v6.3.6',
    uptimeSeconds: 3 * 86400 + 5 * 3600,
    ssid: 'Sector-North',
    mode: 'sta',
    signalDbm: -61,
    noiseFloorDbm: -95,
    ccqPercent: 94,
    distanceMeters: 800,
    txRateKbps: 144400,
    rxRateKbps: 300000,
    lanPorts: [
      LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true),
      LanPort(name: 'eth1', speed: null, plugged: false),
    ],
    peerMac: 'AA:BB:CC:DD:EE:FF',
    peerCount: 1,
    baseUrl: 'https://10.100.11.254',
  ),
);

/// [config] ما رُسم به كارت الاتّصال (العنوان المثبَّت)، و[snap]/[at]/[notes]
/// ما يرسمه كارت الجهاز — كما يمرّرهما `_copyAll` من الكارتين.
String _text(
  Subscriber sub, {
  String? password,
  bool passwordVisible = false,
  DeviceConfig? config,
  DeviceHealthSnapshot? snap,
  DateTime? at,
  String? notes,
}) =>
    copyFieldsText(subscriberCopyFields(
      sub,
      password: password,
      passwordVisible: passwordVisible,
      deviceConfig: config,
      device: snap == null && notes == null
          ? null
          : (
              snap: snap,
              at: snap == null ? null : (at ?? DateTime(2026, 10, 18, 11, 55)),
              notes: notes,
            ),
      now: _now,
    ));

/// يلتقط كلّ نصٍّ يُكتب في الحافظة (والاهتزاز يمرّ صامتاً).
List<String> _mockClipboard(WidgetTester t) {
  final clips = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clips.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() => t.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return clips;
}

void main() {
  // ═══════════════════ ١. نصّ «التسمية: القيمة» ═══════════════════

  group('copyFieldsText', () {
    test('سطرٌ لكلّ معلومة، والفارغ و«—» لا يظهران', () {
      expect(
        copyFieldsText(const [
          CopyField('الاسم', ' علي '),
          CopyField('الباقة', '—'),
          CopyField('الهاتف', ''),
          CopyField('الحالة', 'متصل'),
        ]),
        'الاسم: علي\nالحالة: متصل',
      );
    });

    test('اسم الإشعار: التسمية ما لم يُعطَ غيرها', () {
      expect(const CopyField('الاسم', 'علي').noun, 'الاسم');
      expect(const CopyField('تابع إلى', 'x', noun: 'اسم المدير').noun,
          'اسم المدير');
    });
  });

  group('subscriberCopyFields — كلّ ما في الكارت', () {
    tearDown(() => ProviderService.debugSet(null));

    test('🚨 مشترك متّصل: الهويّة والاشتراك والمال والاتّصال والموقع', () {
      final dl = 'subscribers.label_download'.tr();
      final ul = 'subscribers.label_upload'.tr();
      final st = 'subscribers.label_session_time'.tr();
      expect(
        _text(_sub(_full())),
        [
          'الاسم: علي حسن',
          'اسم المستخدم: user7',
          // الرقم المحلّيّ كما يُتّصل به — لا 9647… كما يخزّنه الساس.
          'الهاتف: 07701234567',
          'الباقة: 10M-Unlimited',
          'السعر: 25,000 د.ع',
          'تاريخ الانتهاء: 2026/11/20 14:30',
          'المتبقي: 33 يوم 2س 30د',
          'الدين: 35,000 د.ع',
          'الحالة: متصل',
          'تابع إلى: najaf650',
          '$st: 1 يوم 2س 3د',
          '$dl: 4.9 GB',
          '$ul: 1.2 GB',
          'IP الجلسة: 10.100.11.254',
          'IP المثبَّت: 192.168.100.254',
          'الموقع: 32.500000,44.400000',
        ].join('\n'),
      );
    });

    test('🚨 كلمة السرّ: لا تُنسخ وهي مخفيّة، وتُنسخ حين تظهر', () {
      final sub = _sub(_full());
      expect(_text(sub, password: 'pa55word'), isNot(contains('pa55word')));
      final shown = _text(sub, password: 'pa55word', passwordVisible: true);
      expect(shown, contains('كلمة المرور: pa55word'));
      // بعد اسم المستخدم مباشرةً — بيانات الدخول معاً.
      expect(
        shown.split('\n').take(3).toList(),
        ['الاسم: علي حسن', 'اسم المستخدم: user7', 'كلمة المرور: pa55word'],
      );
      // لم تُجلب (لا مفتاح عرضها) ⇒ لا سطر ولو كانت العين «مفتوحة».
      expect(_text(sub, passwordVisible: true), isNot(contains('كلمة المرور')));
    });

    test('غير متّصل: آخر اتّصالٍ بوقته المطلق، ولا أرقام جلسة', () {
      final text = _text(_sub(_full(online: false)));
      expect(text, contains('آخر اتصال: 2026/10/17 21:05'));
      expect(text, contains('الحالة: غير متصل'));
      expect(text, isNot(contains('IP الجلسة')));
      expect(text, isNot(contains('subscribers.label_download'.tr())));
      // المثبَّت خاصّيّة حساب لا جلسة — يبقى للمفصول.
      expect(text, contains('IP المثبَّت: 192.168.100.254'));
    });

    test('إعداد الجهاز: عنوانه يغلب الثابت، والملاحظة ما يرسمه كارت الجهاز', () {
      final text = _text(
        _sub(_full()),
        config: const DeviceConfig(customIp: '10.9.9.9', notes: 'في المخزن'),
        notes: ' فوق السطح ',
      );
      expect(text, contains('IP المثبَّت: 10.9.9.9'));
      expect(text, isNot(contains('192.168.100.254')));
      expect(text, contains('ملاحظة الجهاز: فوق السطح'));
      // ملاحظة الإعداد وحدها ليست ما على الشاشة — كارت الجهاز يرسم ملاحظته.
      expect(text, isNot(contains('في المخزن')));
    });

    test('الرصيد ثلاث حالات بتسميات البلاطة نفسها', () {
      Map<String, Object?> withNotes(String n) => {..._full(), 'notes': n};
      expect(
          _text(_sub(withNotes('15000'))), contains('رصيد دائن: 15,000 د.ع'));
      expect(_text(_sub(withNotes(''))), contains('الرصيد: لا دين ولا رصيد'));
    });

    test('منتهٍ ومعطّل: الحالة والمتبقّي كما يرسمهما الهيرو', () {
      final expired = _sub({..._full(), 'expiration': '2026-10-01 10:00:00'});
      expect(_text(expired), contains('المتبقي: منتهي'));
      expect(_text(expired), contains('الحالة: منتهي'));
      final disabled = _sub({..._full(), 'enabled': 0});
      expect(_text(disabled), contains('الحالة: معطّل'));
    });

    test('بلا اسمٍ ولا باقةٍ ولا هاتف: لا أسطر فارغة ولا تكرار', () {
      final text = _text(_sub({
        'idx': '9',
        'username': 'bare9',
        'firstname': '',
        'lastname': '',
        'enabled': 1,
      }));
      expect(text.split('\n'), [
        'اسم المستخدم: bare9',
        'الرصيد: لا دين ولا رصيد',
        'الحالة: غير متصل',
      ]);
    });

    test('عنوانٌ يدويّ في حقل الساس يُنسخ، وموقع gps: لا يُكرَّر', () {
      final text = _text(_sub({
        ..._full(),
        'latitude': null,
        'longitude': null,
        'address_raw': 'النجف — حيّ الأمير',
      }));
      expect(text, contains('العنوان: النجف — حيّ الأمير'));
      expect(text, isNot(contains('الموقع')));
    });

    test('ايرث لنك: الحقول نفسها — المزوّد لا يغيّر شيئاً في النسخ', () {
      ProviderService.debugSet('earthlink');
      final el = _sub({
        ..._full(),
        'idx': 'earthlink:41',
        'username': 'ahmed41',
        'parent_username': null,
      });
      final text = _text(el, password: 'el-pass', passwordVisible: true);
      expect(text, contains('اسم المستخدم: ahmed41'));
      expect(text, contains('كلمة المرور: el-pass'));
      expect(text, contains('الباقة: 10M-Unlimited'));
      expect(text, isNot(contains('تابع إلى')));
    });
  });

  // ═══════════════ السعر: ما يدفعه المشترك لا سعر الباقة ═══════════════

  group('«السعر» في نسخ الكلّ — بعد الخصم', () {
    String price(Map<String, Object?> extra) => _text(_sub({..._full(), ...extra}))
        .split('\n')
        .firstWhere((l) => l.startsWith('السعر'), orElse: () => '');

    test('🚨 عليه خصم: السعر بعده، و«بعد خصم» تقول لماذا', () {
      // الباقة 25,000 وخصمه 5,000 — يدفع 20,000. كان يُنسخ «25,000 د.ع».
      expect(price({'discount': 5000}), 'السعر: 20,000 د.ع بعد خصم 5,000');
    });

    test('بلا خصم: سعر الباقة كما هو', () {
      expect(price({'discount': 0}), 'السعر: 25,000 د.ع');
      expect(price({}), 'السعر: 25,000 د.ع');
    });

    test('سعرٌ ثابت سارٍ: الثابت نفسه ولا «بعد خصم» (الثابت يلغي الخصم)', () {
      expect(
        price({
          'user_price': 30000,
          'price_source': 'custom',
          'base_package_price': 25000,
          'discount': 0,
          'overridden_discount': 5000,
        }),
        'السعر: 30,000 د.ع',
      );
    });

    test('باقته تغيّرت منذ التسعير: الطبيعيّ ناقص خصمه', () {
      expect(
        price({'price_needs_repricing': true, 'discount': 5000}),
        'السعر: 20,000 د.ع بعد خصم 5,000',
      );
    });

    test('خصمٌ أكبر من السعر: صفر لا سالب', () {
      expect(price({'discount': 30000}), 'السعر: 0 د.ع بعد خصم 30,000');
    });

    test('سعرٌ مجهول أو صفر: لا سطر', () {
      expect(price({'package_price': 0}), '');
      expect(price({'package_price': null}), '');
    });
  });

  // ═══════════ تطابق الموقع: الجدول المشترك للحقول المشتركة ═══════════
  //
  // الحقول التي يعرضها التطبيق والموقع معاً تُنسخ بالتسمية والصياغة نفسيهما
  // وبالترتيب نفسه. السطور أدناه هي نفسها حرفاً في اختبار الموقع
  // (`copy-helpers.test.cjs`، المشترك نفسه) — من يغيّر هنا يغيّر هناك.

  group('تطابق نصّ الموقع — الحقول المشتركة', () {
    Map<String, Object?> web({String notes = '-25000'}) => {
          'idx': '101',
          'username': 'ali.k@poox',
          'firstname': 'علي',
          'lastname': 'كاظم',
          'phone': '9647827381676',
          'profile_name': 'Fiber 50M',
          'parent_username': 'admin@poox',
          'package_price': 30000,
          'discount': 5000,
          'notes': notes,
          'enabled': 1,
        };

    test('الهويّة والاشتراك والمال والمدير — سطراً بسطر وبالترتيب', () {
      expect(
        _text(_sub(web())).split('\n'),
        containsAllInOrder([
          'الاسم: علي كاظم',
          'اسم المستخدم: ali.k@poox',
          'الهاتف: 07827381676',
          'الباقة: Fiber 50M',
          'السعر: 25,000 د.ع بعد خصم 5,000',
          'الدين: 25,000 د.ع',
          'تابع إلى: admin@poox',
        ]),
      );
    });

    test('الرصيد بحالاته الثلاث بصياغةٍ واحدة', () {
      List<String> lines(String notes) => _text(_sub(web(notes: notes)))
          .split('\n')
          .where((l) =>
              l.startsWith('الدين') ||
              l.startsWith('رصيد دائن') ||
              l.startsWith('الرصيد'))
          .toList();
      expect(lines('-25000'), ['الدين: 25,000 د.ع']);
      expect(lines('15000'), ['رصيد دائن: 15,000 د.ع']);
      expect(lines(''), ['الرصيد: لا دين ولا رصيد']);
    });

    test('ترتيب التسميات المشتركة واحد', () {
      // تسميات الجلسة الثلاث من الترجمة («مدة الجلسة» · «تحميل» · «رفع»
      // بالعربيّة — وهي حرفاً تسميات الموقع).
      final order = [
        'الاسم',
        'اسم المستخدم',
        'كلمة المرور',
        'الهاتف',
        'الباقة',
        'السعر',
        'تاريخ الانتهاء',
        'المتبقي',
        'الدين',
        'الحالة',
        'تابع إلى',
        'subscribers.label_session_time'.tr(),
        'subscribers.label_download'.tr(),
        'subscribers.label_upload'.tr(),
        'IP الجلسة',
        'آخر اتصال',
      ];
      for (final online in [true, false]) {
        final labels = _text(
          _sub({..._full(online: online), 'discount': 5000}),
          password: 'pa55word',
          passwordVisible: true,
        ).split('\n').map((l) => l.split(': ').first).where(order.contains);
        expect(labels.toList(), [
          for (final l in order)
            if (labels.contains(l)) l,
        ]);
      }
    });
  });

  group('deviceCopyFields — قراءات الجهاز كما يرسمها كارته', () {
    test('ONT: النوع أوّلاً ثمّ القراءات ووقتها', () {
      expect(
        copyFieldsText(
            deviceCopyFields(_ont, at: DateTime(2026, 10, 18, 11, 55))),
        [
          'نوع الجهاز: Huawei ONT',
          'RX Power: -21.55 dBm',
          'TX Power: 2.31 dBm',
          'الفولتية: 3300 mV',
          'الحرارة: 45 °C',
          'حالة الليف: OK',
          'وقت قراءة الجهاز: 2026/10/18 11:55',
        ].join('\n'),
      );
    });

    test('Ubiquiti: الإصدار والسكتور والمنافذ — وبلا الترافيك اللحظيّ', () {
      final text = copyFieldsText(deviceCopyFields(_ubnt));
      expect(text.split('\n'), [
        'نوع الجهاز: NanoBeam-7 (UBNT)',
        'الإشارة: -61 dBm',
        'CCQ: 94%',
        'الإصدار: XW.v6.3.6',
        'SSID: Sector-North',
        'مدّة التشغيل: 3 أيّام و5 ساعات',
        'TX / RX: 144.4 / 300.0 Mbps',
        'Peer MAC: AA:BB:CC:DD:EE:FF',
        'المنافذ: ETH0 · 100 Mbps، ETH1 · مفصول',
      ]);
      expect(text, isNot(contains('الترافيك')));
    });

    test('ضمن نسخ الكلّ: بعد الاتّصال وقبل الموقع', () {
      final lines = _text(_sub(_full()), snap: _ont).split('\n');
      final kind = lines.indexOf('نوع الجهاز: Huawei ONT');
      expect(kind, greaterThan(lines.indexOf('IP المثبَّت: 192.168.100.254')));
      expect(kind, lessThan(lines.indexOf('الموقع: 32.500000,44.400000')));
    });

    test('جهازٌ لم يُقرأ (لقطة فارغة): لا أسطر جهاز', () {
      expect(
        subscriberCopyFields(_sub(_full()),
                device: (snap: null, at: _now, notes: null), now: _now)
            .where((f) => f.label == 'نوع الجهاز' || f.label.contains('وقت')),
        isEmpty,
      );
    });
  });

  // ═══════════════════ ٢. Copyable + إشعار النسخ ═══════════════════

  group('Copyable — الضغط المطوّل', () {
    Future<void> pump(WidgetTester t, Widget child) => t.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: child))),
        );

    testWidgets('ينسخ القيمة ويُعلن اسمها، والنقر يبقى لصاحبه', (t) async {
      final clips = _mockClipboard(t);
      var taps = 0;
      await pump(
        t,
        Copyable(
          label: 'رقم الهاتف',
          noun: 'الرقم',
          value: ' 07701234567 ',
          child: InkWell(
            onTap: () => taps++,
            child: const Text('9647701234567'),
          ),
        ),
      );
      await t.tap(find.text('9647701234567'));
      await t.pump();
      expect(taps, 1);
      expect(clips, isEmpty, reason: 'النقر القصير لا ينسخ');

      await t.longPress(find.text('9647701234567'));
      await t.pump();
      expect(clips, ['07701234567']);
      expect(taps, 1, reason: 'الضغط المطوّل لا يتّصل');
      expect(find.text('تمّ نسخ الرقم'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      expect(find.text('تمّ نسخ الرقم'), findsNothing);
    });

    testWidgets('قارئ الشاشة: ضغطٌ مطوّل اسمه «نسخ …»', (t) async {
      final semantics = t.ensureSemantics();
      await pump(
        t,
        const Copyable(
          label: 'الباقة',
          noun: 'اسم الباقة',
          value: 'Economy',
          child: Text('Economy'),
        ),
      );
      expect(
        t.getSemantics(find.text('Economy')),
        isSemantics(
          label: 'Economy',
          hasLongPressAction: true,
          onLongPressHint: 'نسخ اسم الباقة',
        ),
      );
      semantics.dispose();
    });

    testWidgets('قيمةٌ فارغة أو «—»: لا نسخ ولا لمس', (t) async {
      final clips = _mockClipboard(t);
      final semantics = t.ensureSemantics();
      await pump(
        t,
        const Column(mainAxisSize: MainAxisSize.min, children: [
          Copyable(label: 'الباقة', value: '—', child: Text('—')),
          Copyable(label: 'الهاتف', value: null, child: Text('بلا')),
        ]),
      );
      expect(t.getSemantics(find.text('—')),
          isSemantics(hasLongPressAction: false));
      await t.longPress(find.text('—'));
      await t.longPress(find.text('بلا'));
      await t.pump(const Duration(seconds: 3));
      expect(clips, isEmpty);
      semantics.dispose();
    });

    testWidgets('قيمةٌ تمتلئ بعد وصولها: يصير قابلاً للنسخ بلا هدم ما تحته',
        (t) async {
      final clips = _mockClipboard(t);
      final value = ValueNotifier<String?>('—');
      await pump(
        t,
        ValueListenableBuilder<String?>(
          valueListenable: value,
          builder: (_, v, __) => Copyable(
            label: 'الترافيك',
            value: v,
            child: const _StateProbe(),
          ),
        ),
      );
      final before = t.state(find.byType(_StateProbe));
      value.value = '↓1.2M ↑300K';
      await t.pump();
      expect(t.state(find.byType(_StateProbe)), same(before),
          reason: 'الحالة تحت المعلومة باقية — لا إعادة بناء من الصفر');
      await t.longPress(find.byType(_StateProbe));
      await t.pump(const Duration(seconds: 3));
      expect(clips, ['↓1.2M ↑300K']);
    });
  });

  group('copyToClipboard — إشعارٌ يُرى أينما نُسخ', () {
    testWidgets('🚨 من داخل شيت: الإشعار فوق الشيت لا تحته', (t) async {
      final clips = _mockClipboard(t);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (page) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: page,
                  builder: (sheet) => SizedBox(
                    height: 500,
                    child: Center(
                      child: TextButton(
                        onPressed: () => copyToClipboard(
                            sheet, 'https://t.me/x',
                            label: 'الرابط'),
                        child: const Text('انسخ'),
                      ),
                    ),
                  ),
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('افتح'));
      await t.pumpAndSettle();
      await t.tap(find.text('انسخ'));
      await t.pump();
      expect(clips, ['https://t.me/x']);

      final toast = find.text('تمّ نسخ الرابط');
      expect(toast, findsOneWidget);
      // كان `ScaffoldMessenger`: يُرسم داخل Scaffold الصفحة — تحت الشيت.
      expect(find.descendant(of: find.byType(Scaffold), matching: toast),
          findsNothing);
      // وفوق الشيت فعلاً: أعلى ما يصيبه اللمس عند منتصفه هو الإشعار.
      final result = HitTestResult();
      t.binding.hitTestInView(result, t.getCenter(toast), t.view.viewId);
      expect(
        result.path.first.target,
        isA<RenderParagraph>()
            .having((p) => p.text.toPlainText(), 'text', 'تمّ نسخ الرابط'),
      );
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('نسخٌ تلو نسخ: إشعارٌ واحد بآخرها لا كومة', (t) async {
      _mockClipboard(t);
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold();
        }),
      ));
      // إطاران لكلّ نسخ: ردّ قناة الحافظة الوهميّة يصل بعد إطار.
      copyToClipboard(ctx, 'a', label: 'الأوّل');
      await t.pump();
      await t.pump();
      expect(find.text('تمّ نسخ الأوّل'), findsOneWidget);
      copyToClipboard(ctx, 'b', label: 'الثاني');
      await t.pump();
      await t.pump();
      expect(find.text('تمّ نسخ الأوّل'), findsNothing);
      expect(find.text('تمّ نسخ الثاني'), findsOneWidget);
      // وإزالة الأوّل لا تُسقط مؤقّته الثاني: يبقى مدّته كاملة.
      await t.pump(const Duration(milliseconds: 1500));
      expect(find.text('تمّ نسخ الثاني'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('تمّ نسخ الثاني'), findsNothing);
    });

    testWidgets('سياقٌ زال قبل النداء: يُنسخ النصّ بلا إشعارٍ ولا استثناء',
        (t) async {
      final clips = _mockClipboard(t);
      late BuildContext gone;
      await t.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          gone = c;
          return const SizedBox();
        }),
      ));
      await t.pumpWidget(const MaterialApp(home: Text('بعد')));
      expect(gone.mounted, isFalse);
      copyToClipboard(gone, 'z', label: 'الرمز');
      await t.pump();
      await t.pump();
      expect(clips, ['z']);
      expect(find.text('تمّ نسخ الرمز'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('لوحة المفاتيح مفتوحة: الإشعار فوقها', (t) async {
      _mockClipboard(t);
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.reset);
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(resizeToAvoidBottomInset: false);
        }),
      ));
      copyToClipboard(ctx, 'x', label: 'الرمز');
      await t.pump();
      expect(t.getRect(find.text('تمّ نسخ الرمز')).bottom,
          lessThanOrEqualTo(800 - 300));
      await t.pump(const Duration(seconds: 3));
    });
  });

  // ═══════════════════ ٣. شاشة المشترك ═══════════════════

  group('شاشة المشترك', () {
    late SimServer server;
    late List<String> clips;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp();
      SubscribersApi.clearAllCaches();
      DeviceConfigApi.clearAllCaches();
      await DeviceProbeApi.clearAllCaches();
      server.reply('GET', '/api/v2/subscribers/7/password', 200, {
        'success': true,
        'data': {'password': 'pa55word'},
      });
      // ملاحظة الجهاز بلا عنوانٍ مخصّص: عنوانٌ هنا يفحصه كارت الجهاز
      // بالشبكة الحقيقيّة — والاختبار لا يلمس الشبكة.
      server.reply('GET', '/api/subscribers/user7/device', 200, {
        'success': true,
        'device': {'notes': 'فوق السطح'},
      });
    });
    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    const v = SimVariant(390, dark: false);

    /// متّصلٌ بأرقام جلسة وبلا عنوان جلسة: كارت الجهاز يفحص عنوان الجلسة
    /// وحده، فبلاه لا شبكة؛ والمثبَّت (الثابت) يبقى في كارت الاتّصال.
    Subscriber testSub() {
      final j = _full()..remove('ip');
      return _sub(j);
    }

    Future<void> open(WidgetTester t) async {
      clips = _mockClipboard(t);
      await pumpSim(t, v,
          home: (_) => SubscriberDetailScreen(sub: testSub()), settle: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    }

    Future<void> longPress(WidgetTester t, Finder f) async {
      await t.ensureVisible(f);
      await t.pump();
      await t.longPress(f);
      await t.pump();
    }

    Future<void> copyAll(WidgetTester t) async {
      await t.tap(find.byTooltip('copy.all'.tr()));
      await t.pump();
    }

    for (final el in [false, true]) {
      final who = el ? 'ايرث لنك' : 'ساس';

      testWidgets('$who: كلّ معلومةٍ تُنسخ بالضغط المطوّل', (t) async {
        ProviderService.debugSet(el ? 'earthlink' : null);
        PermissionsService.debugSet(isEmployee: false);
        await open(t);

        final cases = <(Finder, String, String)>[
          (simText('علي حسن'), 'علي حسن', 'تمّ نسخ الاسم'),
          (simText('user7'), 'user7', 'تمّ نسخ اسم المستخدم'),
          // كلمة السرّ مخفيّة: تُنسخ كما تنسخها أيقونتها، والإشعار لا يكشفها.
          (simText('••••••••'), 'pa55word', 'تمّ نسخ كلمة المرور'),
          (simText('10M-Unlimited'), '10M-Unlimited', 'تمّ نسخ اسم الباقة'),
          // رقم تسمية البلاطة سعرُ الباقة — باسمه، لا «السعر» (ذاك بعد الخصم).
          (simText('الباقة · 25,000'), '25,000 د.ع', 'تمّ نسخ سعر الباقة'),
          (simText('9647701234567'), '07701234567', 'تمّ نسخ الرقم'),
          (simText('تابع إلى najaf650'), 'najaf650', 'تمّ نسخ اسم المدير'),
          (
            simText('2026/11/20 14:30'),
            '2026/11/20 14:30',
            'تمّ نسخ تاريخ الانتهاء'
          ),
          (simText('35,000 د.ع'), '35,000 د.ع', 'تمّ نسخ الدين'),
          (
            simText('192.168.100.254'),
            '192.168.100.254',
            'تمّ نسخ IP المثبَّت'
          ),
          (simText('4.9 GB'), '4.9 GB', 'تمّ نسخ التحميل'),
          (simText('فوق السطح'), 'فوق السطح', 'تمّ نسخ الملاحظة'),
        ];
        for (final (finder, value, toast) in cases) {
          final before = clips.length;
          await longPress(t, finder.first);
          expect(clips.length, before + 1, reason: 'لم يُنسخ $value');
          expect(clips.last, value);
          expect(find.text(toast), findsOneWidget, reason: toast);
          // يزول الإشعار قبل التالي — كي لا يغطّي معلومةً في قاع الشاشة.
          await t.pump(const Duration(seconds: 3));
        }
        expect(t.takeException(), isNull);
        await close(t);
      });

      testWidgets('$who: «نسخ كلّ المعلومات» — وكلمة السرّ حين تظهر وحدها',
          (t) async {
        ProviderService.debugSet(el ? 'earthlink' : null);
        PermissionsService.debugSet(isEmployee: false);
        await open(t);

        await copyAll(t);
        expect(clips, hasLength(1));
        final hidden = clips.single;
        expect(hidden, isNot(contains('pa55word')));
        expect(find.text('copy.all_done_password_hidden'.tr()), findsOneWidget);
        // ما يُبنى ممّا ترسمه الشاشة نفسها — سطراً بسطر (إلّا المتبقّي:
        // يُحسب بالدقيقة ولحظتا الحساب قد تتفاوتان). كارت الجهاز «غير متاح»
        // (لا عنوان يُفحص) وملاحظته ظاهرة.
        final expected = copyFieldsText(subscriberCopyFields(
          testSub(),
          password: 'pa55word',
          deviceConfig: DeviceConfigApi.peekConfig('user7'),
          device: (snap: null, at: null, notes: 'فوق السطح'),
        ));
        bool notRemaining(String l) => !l.startsWith('المتبقي:');
        expect(hidden.split('\n').where(notRemaining),
            expected.split('\n').where(notRemaining));
        expect(hidden, contains('ملاحظة الجهاز: فوق السطح'));
        expect(hidden, contains('IP المثبَّت: 192.168.100.254'));

        // كارت الجهاز تحت حافّة الشاشة لم يُركَّب بعد: نُسخ ما سيرسمه حين
        // يُركَّب (المخزن). ومركَّباً يُنسخ ما يرسمه هو — والنصّان واحد.
        expect(find.text('لم يُتمكّن من الوصول للجهاز'), findsNothing);
        await t.dragUntilVisible(find.text('لم يُتمكّن من الوصول للجهاز'),
            find.byType(ListView), const Offset(0, -200));
        await t.pump(const Duration(seconds: 1));
        await copyAll(t);
        expect(clips.last.split('\n').where(notRemaining),
            hidden.split('\n').where(notRemaining));
        await t.pump(const Duration(seconds: 3));

        await t.dragUntilVisible(find.byIcon(Icons.visibility_rounded),
            find.byType(ListView), const Offset(0, 200));
        await t.pump();
        await t.tap(find.byIcon(Icons.visibility_rounded));
        await t.pump();
        await copyAll(t);
        expect(clips.last, contains('كلمة المرور: pa55word'));
        expect(find.text('copy.all_done_password'.tr()), findsOneWidget);
        await close(t);
      });

      testWidgets('$who: «نسخ كلّ المعلومات» في شيت «المزيد» أيضاً', (t) async {
        ProviderService.debugSet(el ? 'earthlink' : null);
        PermissionsService.debugSet(isEmployee: false);
        await open(t);
        await t.tap(find.text('subscribers.more_actions'.tr()));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        final row = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('copy.all'.tr()),
        );
        await t.ensureVisible(row);
        await t.pump();
        await t.tap(row);
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        expect(clips, hasLength(1));
        expect(clips.single, contains('اسم المستخدم: user7'));
        expect(find.byType(BottomSheet), findsNothing,
            reason: 'الشيت يُغلق كباقي صفوفه');
        await close(t);
      });
    }

    testWidgets('موظّفٌ بلا مفتاح كلمة السرّ: لا تُجلب ولا تُنسخ', (t) async {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'subscribers.view': true});
      await open(t);
      expect(server.calls('GET', '/api/v2/subscribers/7/password'), isEmpty);
      expect(find.byIcon(Icons.visibility_rounded), findsNothing);
      await copyAll(t);
      expect(clips.single, isNot(contains('كلمة المرور')));
      expect(clips.single, contains('اسم المستخدم: user7'));
      expect(find.text('copy.all_done'.tr()), findsOneWidget);
      await close(t);
    });

    for (final el in [false, true]) {
      final who = el ? 'ايرث لنك' : 'ساس';

      testWidgets('🚨 $who: عليه خصم — «السعر» ما يدفعه، وتسمية البلاطة سعر الباقة',
          (t) async {
        ProviderService.debugSet(el ? 'earthlink' : null);
        PermissionsService.debugSet(isEmployee: false);
        clips = _mockClipboard(t);
        await pumpSim(t, v,
            home: (_) => SubscriberDetailScreen(
                sub: _sub({..._full()..remove('ip'), 'discount': 5000})),
            settle: false);
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));

        // البلاطة ترسم سعر الباقة قبل الخصم — ونسخه المفرد باسمه.
        await longPress(t, simText('الباقة · 25,000'));
        expect(clips.last, '25,000 د.ع');
        expect(find.text('تمّ نسخ سعر الباقة'), findsOneWidget);
        await t.pump(const Duration(seconds: 3));

        await copyAll(t);
        final lines = clips.last.split('\n');
        expect(lines, contains('السعر: 20,000 د.ع بعد خصم 5,000'));
        expect(lines, isNot(contains('السعر: 25,000 د.ع')));
        await close(t);
      });
    }

    testWidgets(
        '🚨 الملاحظة كما يرسمها كارت الجهاز — لا ما صار في مخزن الإعداد بعده',
        (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await open(t);
      await t.dragUntilVisible(
          simText('فوق السطح'), find.byType(ListView), const Offset(0, -200));
      await t.pump(const Duration(seconds: 1));

      // إعدادٌ أحدث وصل كارتَ الاتّصال وحده (نبضة الكروت بعد إبطال المخزن)،
      // وكارت الجهاز ما زال يرسم ملاحظته — فالمخزن غير الشاشة الآن.
      server.reply('GET', '/api/subscribers/user7/device', 200, {
        'success': true,
        'device': {'notes': 'ملاحظة أحدث'},
      });
      DeviceConfigApi.invalidateCache('user7');
      DeviceProbeBus.bump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(DeviceConfigApi.peekConfig('user7')?.notes, 'ملاحظة أحدث',
          reason: 'المخزن تغيّر — وإلّا فالاختبار لا يفحص شيئاً');
      expect(simText('فوق السطح'), findsOneWidget);
      expect(simText('ملاحظة أحدث'), findsNothing);

      await copyAll(t);
      expect(clips.last, contains('ملاحظة الجهاز: فوق السطح'));
      expect(clips.last, isNot(contains('ملاحظة أحدث')));
      await close(t);
    });

    testWidgets('زرّ النسخ في الرأس لا يزيح العنوان عن الوسط', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await open(t);
      final title = t.getCenter(find.text('subscribers.detail_title'.tr()));
      expect(title.dx, moreOrLessEquals(390 / 2, epsilon: 0.5));
      expect(find.byIcon(LucideIcons.copy), findsOneWidget);
      await close(t);
    });
  });
}

/// ودجةٌ بحالةٍ تُرصد هويّتها — تكشف إن أُعيد بناء ما تحت `Copyable`.
class _StateProbe extends StatefulWidget {
  const _StateProbe();

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 120, height: 40, child: Text('قياس'));
}
