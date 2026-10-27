import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/cards/cards_widgets.dart';
import 'package:rad_mysvcs/services/dashboard_cache.dart';

/// §١٢ التفعيل بالكارت + قسم «الكارتات» — الشكل كما في عقد الخادم والتطبيق.
///
/// الحارسان الأهمّ: «تعذّرت القراءة» (`available: null`) لا تُقرأ صفراً، وغياب
/// الحقول (خادمٌ أقدم) يُبقي سلوك اليوم حرفيّاً — رصيدٌ بلا خيار، وطلبٌ بلا
/// حقل `method`.
void main() {
  Map<String, dynamic> activationData(Map<String, dynamic> extra) => {
        'user_price': 46000,
        'price_after_discount': 46000,
        'profile_name': 'Family',
        'manager_balance': 0,
        ...extra,
      };

  group('activation-data — طرق التفعيل', () {
    test('🚨 خادمٌ أقدم بلا الحقل: رصيدٌ بلا خيار ولا كارت', () {
      final m = ActivationMethods.fromActivationData(activationData({}));
      expect(m.credit, isTrue);
      expect(m.card, isFalse);
      expect(m.canChoose, isFalse);
      expect(m.cardOnly, isFalse);
      expect(ActivationMethods.fromActivationData(null).credit, isTrue);
    });

    test('الطريقان مسموحان: خيارٌ، والرصيد هو الافتراض', () {
      final m = ActivationMethods.fromActivationData(activationData({
        'activation_methods': {'credit': true, 'card': true},
      }));
      expect(m.canChoose, isTrue);
      expect(m.cardOnly, isFalse);
    });

    test('الكارت وحده (بلا صلاحيّة رصيد): يُختار تلقائيّاً بلا بلاطات', () {
      final m = ActivationMethods.fromActivationData(activationData({
        'activation_methods': {'credit': false, 'card': true},
      }));
      expect(m.cardOnly, isTrue);
      expect(m.canChoose, isFalse);
    });

    test('بلا صلاحيّة كارت أو بلا سلاسل: لا خيار', () {
      final m = ActivationMethods.fromActivationData(activationData({
        'activation_methods': {'credit': true, 'card': false},
      }));
      expect(m.card, isFalse);
      expect(m.canChoose, isFalse);
    });

    test('🚨 الكارت لا يُفتح إلّا بـtrue صريحة', () {
      for (final v in [null, 'yes', 0, 'false', 2]) {
        final m = ActivationMethods.fromJson({'credit': true, 'card': v});
        expect(m.card, isFalse, reason: 'card=$v');
      }
      // والرصيد يغيب أو يصل null ⇒ يبقى كما اليوم، فلا يُفرض «الكارت وحده».
      expect(ActivationMethods.fromJson({'card': true}).credit, isTrue);
      final nullCredit =
          ActivationMethods.fromJson({'credit': null, 'card': true});
      expect(nullCredit.credit, isTrue);
      expect(nullCredit.cardOnly, isFalse);
      expect(nullCredit.canChoose, isTrue);
    });
  });

  group('activation-data — مخزون باقة المشترك', () {
    CardStockInfo stock(Object? cards) => CardStockInfo.fromActivationData(
        activationData({if (cards != null) 'cards': cards}));

    test('عيّنة العقد: ٣ كارتات Family', () {
      final s = stock({
        'enabled': true,
        'profile_id': 4,
        'profile_name': 'Family',
        'available': 3,
      });
      expect(s.enabled, isTrue);
      expect(s.profileId, 4);
      expect(s.profileName, 'Family');
      expect(s.available, 3);
      expect(s.level, CardStockLevel.available);
    });

    test('صفرٌ مقروء: ممنوع', () {
      final s = stock({'enabled': true, 'profile_id': 4, 'available': 0});
      expect(s.available, 0);
      expect(s.level, CardStockLevel.empty);
    });

    test('🚨 null = تعذّرت القراءة — ليس صفراً', () {
      final s = stock({'enabled': true, 'profile_id': 4, 'available': null});
      expect(s.available, isNull);
      expect(s.level, CardStockLevel.unknown);
      expect(s.level, isNot(CardStockLevel.empty));
    });

    test('رقمٌ نصّيّ يُقرأ، والسالب والعبث «غير معروف» لا صفر', () {
      expect(stock({'enabled': true, 'available': '12'}).available, 12);
      expect(stock({'enabled': true, 'available': -1}).available, isNull);
      expect(stock({'enabled': true, 'available': 'x'}).available, isNull);
      expect(stock({'enabled': true, 'available': true}).available, isNull);
    });

    test('بلا صلاحيّة: معطّل', () {
      final s = stock({'enabled': false, 'available': null});
      expect(s.enabled, isFalse);
    });

    test('غياب cards (خادمٌ أقدم): معطّل وغير معروف', () {
      final s = stock(null);
      expect(s.enabled, isFalse);
      expect(s.available, isNull);
      expect(s.profileName, isNull);
    });

    test('بعد رفض NO_CARDS يصير صفراً ويبقى الباقي', () {
      final s = stock({
        'enabled': true,
        'profile_id': 4,
        'profile_name': 'Family',
        'available': 2,
      }).withAvailable(0);
      expect(s.level, CardStockLevel.empty);
      expect(s.profileName, 'Family');
      expect(s.enabled, isTrue);
    });
  });

  group('ردّ activate', () {
    test('نجاحٌ بكارت: الكارت والمتبقّي ولا رمز', () {
      final r = SubscribersApi.activateResultFromBody({
        'success': true,
        'message': 'تم التفعيل',
        'card': {
          'series': '2026-52224',
          'serial_tail': '1234',
          'profile_name': 'Family',
          'remaining': 2,
        },
      });
      expect(r.ok, isTrue);
      expect(r.code, isNull);
      expect(r.card, isNotNull);
      expect(r.card!.series, '2026-52224');
      expect(r.card!.serialTail, '1234');
      expect(r.card!.profileName, 'Family');
      expect(r.card!.remaining, 2);
    });

    test('🚨 آخر أربع خانات فقط — حتّى لو وصل الرقم التسلسليّ كاملاً', () {
      final r = SubscribersApi.activateResultFromBody({
        'success': true,
        'card': {'serial_tail': '1234567890123454821'},
      });
      expect(r.card!.serialTail, '4821');
      expect(r.card!.remaining, isNull);
    });

    test('NO_CARDS (409): الرمز والرسالة، بلا كارت', () {
      final r = SubscribersApi.activateResultFromBody({
        'success': false,
        'code': 'NO_CARDS',
        'message': 'ما عندك كارت متاح لباقة «Family»',
      });
      expect(r.ok, isFalse);
      expect(r.code, CardsApi.codeNoCards);
      expect(r.message, contains('Family'));
      expect(r.card, isNull);
    });

    test('CARD_NOT_ALLOWED (403)', () {
      final r = SubscribersApi.activateResultFromBody({
        'success': false,
        'code': 'CARD_NOT_ALLOWED',
        'message': 'حسابك في الساس لا يملك صلاحيّة التفعيل بالكارت',
      });
      expect(r.ok, isFalse);
      expect(r.code, CardsApi.codeCardNotAllowed);
    });

    test('🚨 نجاحٌ بالرصيد كما اليوم: لا كارت ولا رمز، والواتساب يُقرأ', () {
      final r = SubscribersApi.activateResultFromBody({
        'success': true,
        'message': 'ok',
        'wa': {'sent': false, 'reason': 'no_phone'},
      });
      expect(r.ok, isTrue);
      expect(r.card, isNull);
      expect(r.code, isNull);
      expect(r.wa?.reason, 'no_phone');
    });

    test('فشلٌ بلا رسالة يبقى بلا رسالة (الشيت يعرض «خطأ»)', () {
      final r = SubscribersApi.activateResultFromBody({'success': false});
      expect(r.ok, isFalse);
      expect(r.message, isNull);
      expect(r.code, isNull);
    });
  });

  group('/api/v2/cards/summary', () {
    final sample = {
      'success': true,
      'enabled': true,
      'totals': {'remaining': 3, 'used': 627, 'qty': 630, 'series': 42},
      'profiles': [
        {
          'profile_id': 4,
          'profile_name': 'Family',
          'value': 46000,
          'remaining': 3,
          'qty': 500,
          'used': 497,
          'series': 30,
        },
      ],
      'series': [
        {
          'series': '2026-52224',
          'type': 0,
          'profile_id': 4,
          'profile_name': 'Family',
          'value': 46000,
          'qty': 30,
          'used': 27,
          'remaining': 3,
          'expiration': '2027-09-01',
          'expired': false,
          'suspended': false,
          'created_at': '2026-10-01 23:31:35',
        },
      ],
      'updated_at': '2026-10-08T20:10:00.000Z',
    };

    test('عيّنة العقد', () {
      final s = CardsSummary.fromJson(sample);
      expect(s.enabled, isTrue);
      expect(s.totals.remaining, 3);
      expect(s.totals.used, 627);
      expect(s.totals.qty, 630);
      expect(s.totals.series, 42);
      expect(s.profiles, hasLength(1));
      final p = s.profiles.single;
      expect(p.profileId, 4);
      expect(p.profileName, 'Family');
      expect(p.value, 46000);
      expect(p.remaining, 3);
      expect(p.series, 30);
      final ser = s.series.single;
      expect(ser.series, '2026-52224');
      expect(ser.isRefill, isTrue);
      expect(ser.remaining, 3);
      expect(ser.usable, isTrue);
      expect(ser.expirationDate, DateTime(2027, 9, 1));
      expect(ser.createdAtDate, DateTime(2026, 10, 1, 23, 31, 35));
      expect(s.updatedAt, DateTime.utc(2026, 10, 8, 20, 10).toLocal());
    });

    test('معطّل: مصفوفاتٌ فارغة ومجاميع صفر', () {
      final s = CardsSummary.fromJson({
        'success': true,
        'enabled': false,
        'totals': {'remaining': 0, 'used': 0, 'qty': 0, 'series': 0},
        'profiles': [],
        'series': [],
      });
      expect(s.enabled, isFalse);
      expect(s.profiles, isEmpty);
      expect(s.series, isEmpty);
      expect(s.totals.remaining, 0);
      expect(s.updatedAt, isNull);
    });

    test('أشكال الساس الخام تُقرأ، والمتبقّي يُحسب إن غاب، والتالف يسقط', () {
      final s = CardsSummary.fromJson({
        'enabled': 1,
        'profiles': [
          {'profile_name': 'بلا معرّف'},
          {'profile_id': '5', 'value': '56000.000'},
        ],
        'series': [
          {'qty': 10},
          {
            'series': '2026-1',
            'qty': '30',
            'used': '27',
            'value': '46000.000',
            'suspended': 1,
          },
          'ليس صفّاً',
        ],
      });
      expect(s.enabled, isTrue);
      expect(s.totals.remaining, 0);
      expect(s.profiles.single.profileId, 5);
      expect(s.profiles.single.profileName, '#5');
      expect(s.profiles.single.value, 56000);
      final ser = s.series.single;
      expect(ser.remaining, 3);
      expect(ser.value, 46000);
      expect(ser.suspended, isTrue);
      expect(ser.usable, isFalse, reason: 'المعلّقة لا يُسحب منها');
    });

    test('المنتهية والفارغة لا يُسحب منها', () {
      final expired = CardSeries.fromJson({
        'series': 'a',
        'qty': 5,
        'used': 1,
        'expired': true,
      })!;
      final empty = CardSeries.fromJson({'series': 'b', 'qty': 5, 'used': 5})!;
      expect(expired.usable, isFalse);
      expect(empty.remaining, 0);
      expect(empty.usable, isFalse);
    });
  });

  group('/api/v2/cards/series/:series', () {
    test('عيّنة العقد: مستعملٌ لمن ومتى، وغير مستعمل', () {
      final page = CardsPage.fromJson({
        'success': true,
        'series': {
          'series': '2026-52224',
          'type': 0,
          'profile_id': 4,
          'profile_name': 'Family',
          'value': 46000,
          'qty': 30,
          'used': 27,
          'remaining': 3,
        },
        'cards': [
          {
            'id': 1066490,
            'serial_tail': '7710',
            'used': false,
            'used_at': null,
            'subscriber': null,
          },
          {
            'id': 1066487,
            'serial_tail': '4821',
            'used': true,
            'used_at': '2026-10-02 01:19:46',
            'subscriber': {'id': 219677, 'username': '5@ahm3'},
          },
        ],
        'total': 30,
        'page': 1,
        'count': 50,
      });
      expect(page.series?.series, '2026-52224');
      expect(page.cards, hasLength(2));
      final free = page.cards.first;
      expect(free.used, isFalse);
      expect(free.usedAt, isNull);
      expect(free.subscriberId, isNull);
      final used = page.cards.last;
      expect(used.used, isTrue);
      expect(used.serialTail, '4821');
      expect(used.subscriberId, '219677');
      expect(used.subscriberUsername, '5@ahm3');
      expect(used.usedAtDate, DateTime(2026, 10, 2, 1, 19, 46));
      expect(page.total, 30);
      expect(page.hasMore, isFalse);
    });

    test('الرقم التسلسليّ الكامل يُقرأ ويُعرض (قرار المالك)، وبديلٌ آخر ٤ خاناتٍ حين يغيب', () {
      final page = CardsPage.fromJson({
        'success': true,
        'series': {'series': '2026-1', 'type': 0, 'profile_id': 4, 'value': 46000, 'qty': 2, 'used': 0, 'remaining': 2},
        'cards': [
          {'id': 1, 'serial': '1234567890123454821', 'serial_tail': '4821', 'used': false},
          {'id': 2, 'serial_tail': '7710', 'used': false}, // خادمٌ أقدم بلا الحقل الكامل
        ],
      });
      expect(page.cards[0].serial, '1234567890123454821');
      expect(cardSerial(page.cards[0]), '1234567890123454821', reason: 'الكامل يُعرض');
      expect(page.cards[1].serial, isNull);
      expect(cardSerial(page.cards[1]), '••7710', reason: 'بديلٌ حين يغيب الكامل');
    });

    test('🚨 رقمٌ تسلسليٌّ مشبوه (مسافات/رموز) يُرفض ⇒ null', () {
      final page = CardsPage.fromJson({
        'success': true,
        'series': {'series': '2026-1', 'type': 0, 'profile_id': 4, 'value': 1, 'qty': 1, 'used': 0, 'remaining': 1},
        'cards': [
          {'id': 1, 'serial': '12 34<script>', 'serial_tail': '0001', 'used': false},
        ],
      });
      expect(page.cards[0].serial, isNull);
      expect(cardSerial(page.cards[0]), '••0001');
    });

    test('🚨 لا PIN ولا رقمٌ تسلسليّ كامل يبقى في النموذج', () {
      const pin = '83920174';
      const serial = '1234567890123454821';
      final item = CardItem.fromJson({
        'id': 1,
        'serial_tail': serial,
        'serialnumber': serial,
        'pin': pin,
        'password': 'x',
      })!;
      expect(item.serialTail, '4821');
      final fields = [
        item.serialTail,
        item.usedAt,
        item.subscriberId,
        item.subscriberUsername,
      ];
      for (final f in fields) {
        expect(f ?? '', isNot(contains(pin)));
        expect(f ?? '', isNot(contains(serial)));
      }
    });

    test('used يُستنتج حين يغيب، والصفّ بلا id يسقط', () {
      final page = CardsPage.fromJson({
        'cards': [
          {'serial_tail': '1111'},
          {'id': 2, 'used_at': '2026-10-02 01:19:46'},
          {'id': 3},
        ],
      }, page: 2);
      expect(page.cards.map((c) => c.id), [2, 3]);
      expect(page.cards.first.used, isTrue);
      expect(page.cards.last.used, isFalse);
      expect(page.page, 2, reason: 'الصفحة المطلوبة حين يغيب الحقل');
    });

    test('hasMore: الصفحة الأولى من ١٢٠ بخمسين', () {
      final page = CardsPage.fromJson({
        'cards': [],
        'total': 120,
        'page': 1,
        'count': 50,
      });
      expect(page.hasMore, isTrue);
      final last = CardsPage.fromJson({
        'cards': [],
        'total': 120,
        'page': 3,
        'count': 50,
      });
      expect(last.hasMore, isFalse);
    });
  });

  group('CardsState — شارة الكارتات المتبقّية', () {
    setUp(CardsState.reset);

    test('admin-widgets: الحقل يضبط، وغيابه لا يمسح', () {
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 3});
      expect(CardsState.badge.value,
          const CardsBadge(enabled: true, remaining: 3));
      CardsState.applyAdminWidgets(null);
      expect(CardsState.badge.value?.remaining, 3);
    });

    test('🚨 remaining:null = تعذّر — ليس صفراً', () {
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': null});
      expect(CardsState.badge.value?.enabled, isTrue);
      expect(CardsState.badge.value?.remaining, isNull);
    });

    test('تفعيلٌ بكارت ينقص واحداً، ولا يخترع رقماً مجهولاً', () {
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 1});
      CardsState.consumeOne();
      expect(CardsState.badge.value?.remaining, 0);
      CardsState.consumeOne();
      expect(CardsState.badge.value?.remaining, 0);

      CardsState.applyAdminWidgets({'enabled': true, 'remaining': null});
      CardsState.consumeOne();
      expect(CardsState.badge.value?.remaining, isNull);

      CardsState.reset();
      CardsState.consumeOne();
      expect(CardsState.badge.value, isNull);
    });

    test('الملخّص يضبط الشارة، والقيمة نفسها لا تُعيد الإشعار', () {
      var ticks = 0;
      void listener() => ticks++;
      CardsState.badge.addListener(listener);
      addTearDown(() => CardsState.badge.removeListener(listener));
      final s = CardsSummary.fromJson({
        'enabled': true,
        'totals': {'remaining': 3},
      });
      CardsState.applySummary(s);
      CardsState.applySummary(s);
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 3});
      expect(CardsState.badge.value?.remaining, 3);
      expect(ticks, 1);
    });
  });

  group('SubscribersApi.activate — جسم الطلب', () {
    late _FakeAdapter adapter;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      adapter = _FakeAdapter();
      ApiClient.dio.httpClientAdapter = adapter;
    });

    test('🚨 الرصيد (الافتراض): لا حقل method — الطلب كما كان حرفيّاً',
        () async {
      adapter.reply = (200, {'success': true});
      final r = await SubscribersApi.activate(
        idx: '55',
        paymentType: 'non-cash',
        activationData: activationData({}),
      );
      expect(r.ok, isTrue);
      final body = adapter.lastBody;
      expect(body.containsKey('method'), isFalse);
      expect(body.keys.toSet(), {'paymentType', 'activationData'});

      await SubscribersApi.activate(
        idx: '55',
        paymentType: 'cash',
        activationData: activationData({}),
        method: 'credit',
      );
      expect(adapter.lastBody.containsKey('method'), isFalse);
    });

    test('الكارت: method=card مع بقيّة الجسم كما هو', () async {
      adapter.reply = (
        200,
        {
          'success': true,
          'card': {
            'series': '2026-52224',
            'serial_tail': '1234',
            'profile_name': 'Family',
            'remaining': 2,
          },
        }
      );
      final r = await SubscribersApi.activate(
        idx: '55',
        paymentType: 'partial-cash',
        activationData: activationData({}),
        partialAmount: 10000,
        method: 'card',
      );
      expect(adapter.lastPath, '/api/v2/subscribers/55/activate');
      expect(adapter.lastBody['method'], 'card');
      expect(adapter.lastBody['paymentType'], 'partial-cash');
      expect(adapter.lastBody['partialAmount'], 10000);
      expect(adapter.lastBody.containsKey('pin'), isFalse);
      expect(r.ok, isTrue);
      expect(r.card?.serialTail, '1234');
      expect(r.card?.remaining, 2);
    });

    test('409 NO_CARDS يصل ردّاً برمزه (لا رميةً)', () async {
      adapter.reply = (
        409,
        {
          'success': false,
          'code': 'NO_CARDS',
          'message': 'ما عندك كارت متاح لباقة «Family»',
        }
      );
      final r = await SubscribersApi.activate(
        idx: '55',
        paymentType: 'non-cash',
        activationData: activationData({}),
        method: 'card',
      );
      expect(r.ok, isFalse);
      expect(r.code, 'NO_CARDS');
      expect(r.message, contains('Family'));
      expect(r.card, isNull);
    });

    test('403 CARD_NOT_ALLOWED يصل ردّاً برمزه', () async {
      adapter.reply = (
        403,
        {
          'success': false,
          'code': 'CARD_NOT_ALLOWED',
          'message': 'حسابك في الساس لا يملك صلاحيّة التفعيل بالكارت',
        }
      );
      final r = await SubscribersApi.activate(
        idx: '55',
        paymentType: 'non-cash',
        activationData: activationData({}),
        method: 'card',
      );
      expect(r.ok, isFalse);
      expect(r.code, 'CARD_NOT_ALLOWED');
    });

    test('CardsApi.summary: النجاح يضبط الشارة، والرفض رسالةٌ بلا بيانات',
        () async {
      CardsState.reset();
      adapter.reply = (
        200,
        {
          'success': true,
          'enabled': true,
          'totals': {'remaining': 7, 'used': 3, 'qty': 10, 'series': 1},
          'profiles': [],
          'series': [],
        }
      );
      final ok = await CardsApi.summary();
      expect(adapter.lastPath, '/api/v2/cards/summary');
      expect(ok.data?.totals.remaining, 7);
      expect(CardsState.badge.value?.remaining, 7);

      adapter.reply = (403, {'success': false, 'message': 'لا تملك صلاحيّة'});
      final denied = await CardsApi.summary();
      expect(denied.data, isNull);
      expect(denied.message, 'لا تملك صلاحيّة');
      expect(CardsState.badge.value?.remaining, 7, reason: 'الرفض لا يمسح');
    });

    test('CardsApi.seriesCards: المسار مُرمَّز والصفحة ترسل', () async {
      adapter.reply = (
        200,
        {'success': true, 'cards': [], 'total': 0, 'page': 2, 'count': 50}
      );
      final r = await CardsApi.seriesCards('2026-52224', page: 2);
      expect(adapter.lastPath, '/api/v2/cards/series/2026-52224');
      expect(adapter.lastQuery['page'], 2);
      expect(r.data?.page, 2);

      adapter.reply =
          (404, {'success': false, 'message': 'السلسلة غير موجودة'});
      final missing = await CardsApi.seriesCards('x/y');
      expect(adapter.lastPath, '/api/v2/cards/series/x%2Fy');
      expect(missing.data, isNull);
      expect(missing.message, 'السلسلة غير موجودة');
    });
  });

  group('admin-widgets — شارة الكارتات تركب طلب المحفظة', () {
    late _FakeAdapter adapter;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // `fetchWallet` لا يطلب بلا توكن.
      FlutterSecureStorage.setMockInitialValues({'auth.token': 't'});
      adapter = _FakeAdapter();
      ApiClient.dio.httpClientAdapter = adapter;
      CardsState.reset();
    });

    test('الحقل يصل: في المحفظة (للكاش) وفي الشارة (للشاشات) معاً', () async {
      adapter.reply = (
        200,
        {
          'success': true,
          'balance': 0,
          'points': 7,
          'cards': {'enabled': true, 'remaining': 3},
        }
      );
      final w = await DashboardApi.fetchWallet();
      expect(adapter.lastPath, '/api/v2/admin-widgets');
      expect(w?.balance, 0);
      expect(w?.points, 7);
      expect(w?.cards, const CardsBadge(enabled: true, remaining: 3));
      expect(CardsState.badge.value,
          const CardsBadge(enabled: true, remaining: 3));
    });

    test('🚨 خادمٌ أقدم بلا الحقل: لا شارة في المحفظة، ولا مسحٌ لما نعرفه',
        () async {
      CardsState.set(const CardsBadge(enabled: true, remaining: 5));
      adapter.reply = (200, {'success': true, 'balance': 1000, 'points': 0});
      final w = await DashboardApi.fetchWallet();
      expect(w?.balance, 1000);
      expect(w?.cards, isNull);
      expect(CardsState.badge.value?.remaining, 5);
    });

    test('بلا كارتات (enabled:false): تصل كما هي — البطاقة تختفي بها', () async {
      adapter.reply = (
        200,
        {
          'success': true,
          'balance': 0,
          'points': 0,
          'cards': {'enabled': false, 'remaining': 0},
        }
      );
      final w = await DashboardApi.fetchWallet();
      expect(w?.cards?.enabled, isFalse);
      expect(CardsState.badge.value?.enabled, isFalse);
    });

    test('🚨 remaining:null يبقى «تعذّر» عبر الكاش ذهاباً وإياباً', () async {
      adapter.reply = (
        200,
        {
          'success': true,
          'balance': 0,
          'points': 0,
          'cards': {'enabled': true, 'remaining': null},
        }
      );
      final w = await DashboardApi.fetchWallet();
      expect(w!.cards!.remaining, isNull);
      final back = WalletResult.fromJson(
          jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
      expect(back.cards, const CardsBadge(enabled: true, remaining: null));
    });
  });

  group('كاش المحفظة — متوافقٌ في الاتّجاهين بلا رفع v', () {
    test('بلا كارتات: الحمولة المكتوبة كما كانت حرفيّاً', () {
      const w = WalletResult(balance: 250000, points: 7);
      expect(w.toJson(), {'balance': 250000, 'points': 7});
    });

    test('مع الكارتات: تُختم لصاحبها وتعود، ولا تُقرأ لغيره', () {
      const w = WalletResult(
        balance: 0,
        points: 7,
        cards: CardsBadge(enabled: true, remaining: 3),
      );
      final raw = jsonEncode({'v': 1, 'adminId': '2', 'w': w.toJson()});
      final back = DashboardCache.decodeFor(raw, '2');
      expect(back?.cards, const CardsBadge(enabled: true, remaining: 3));
      expect(back?.points, 7);
      expect(DashboardCache.decodeFor(raw, '9'), isNull);
    });

    test('حمولةٌ مختومة كُتبت قبل الكارتات تُقرأ بلا شارة', () {
      final raw = jsonEncode({
        'v': 1,
        'adminId': '2',
        'w': {'balance': 250000, 'points': 7},
      });
      final back = DashboardCache.decodeFor(raw, '2');
      expect(back?.balance, 250000);
      expect(back?.cards, isNull);
    });

    test('شارةٌ تالفة في الكاش لا تُسقط الرصيد', () {
      final back = WalletResult.fromJson({
        'balance': 10,
        'points': 1,
        'cards': 'ليست كائناً',
      });
      expect(back.balance, 10);
      expect(back.cards, isNull);
    });
  });

  group('CardsState — الحقبة، والكاش، والطلب الاحتياطيّ', () {
    late _FakeAdapter adapter;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      adapter = _FakeAdapter();
      ApiClient.dio.httpClientAdapter = adapter;
      CardsState.reset();
    });

    test('🚨 ملخّصٌ يصل بعد خروج صاحبه لا يُكتب في جلسة من بعده', () async {
      final gate = Completer<void>();
      adapter.gate = gate;
      adapter.reply = (
        200,
        {
          'success': true,
          'enabled': true,
          'totals': {'remaining': 9},
        }
      );
      final pending = CardsApi.summary();
      await Future<void>.delayed(Duration.zero);
      CardsState.reset(); // خرج المدير والطلب في الطريق
      gate.complete();
      final r = await pending;
      expect(r.data?.totals.remaining, 9, reason: 'المستدعي يأخذ ردّه');
      expect(CardsState.badge.value, isNull, reason: 'الشارة للجلسة الجديدة');
      expect(CardsState.lastSummary, isNull);
    });

    test('والحقبة نفسها على admin-widgets', () {
      final before = CardsState.epoch;
      CardsState.reset();
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 3},
          epoch: before);
      expect(CardsState.badge.value, isNull);
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 3},
          epoch: CardsState.epoch);
      expect(CardsState.badge.value?.remaining, 3);
    });

    test('seed: من كاش اللوحة حين تُجهل الشارة وحدها', () {
      CardsState.seed(const CardsBadge(enabled: true, remaining: 4));
      expect(CardsState.badge.value?.remaining, 4);
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 2});
      CardsState.seed(const CardsBadge(enabled: true, remaining: 4));
      expect(CardsState.badge.value?.remaining, 2,
          reason: 'الكاش لا يغلب ردّاً حيّاً سبقه');
      CardsState.seed(null);
      expect(CardsState.badge.value?.remaining, 2);
    });

    test('آخر ملخّص: يُحفظ، ويسقط حين تخالفه الشارة، ويُمسح بالخروج', () {
      final s = CardsSummary.fromJson({
        'enabled': true,
        'totals': {'remaining': 3},
      });
      CardsState.applySummary(s);
      expect(CardsState.lastSummary, same(s));
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': 3});
      expect(CardsState.lastSummary, same(s), reason: 'العدد نفسه — يبقى');
      CardsState.consumeOne();
      expect(CardsState.lastSummary, isNull,
          reason: 'سُحب كارت: ملخّصٌ يقول ٣ يناقض اللوحة التي تقول ٢');
      CardsState.applySummary(s);
      CardsState.applyAdminWidgets({'enabled': true, 'remaining': null});
      expect(CardsState.lastSummary, isNull);
      CardsState.applySummary(s);
      CardsState.reset();
      expect(CardsState.lastSummary, isNull);
    });

    test('ensureKnown: طلبٌ واحدٌ جارٍ، ولا شيء حين تُعرف الشارة', () async {
      final gate = Completer<void>();
      adapter.gate = gate;
      adapter.reply = (
        200,
        {
          'success': true,
          'enabled': true,
          'totals': {'remaining': 3},
        }
      );
      final a = CardsState.ensureKnown();
      final b = CardsState.ensureKnown();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([a, b]);
      expect(adapter.calls, 1);
      expect(adapter.lastPath, '/api/v2/cards/summary');
      expect(CardsState.badge.value?.remaining, 3);
      await CardsState.ensureKnown();
      expect(adapter.calls, 1, reason: 'معروفة — لا طلب');
    });

    test('ensureKnown: الفشل يبرّد، والجلسة الجديدة لا ترث التبريد', () async {
      adapter.reply = (403, {'success': false, 'message': 'x'});
      await CardsState.ensureKnown();
      expect(adapter.calls, 1);
      expect(CardsState.badge.value, isNull, reason: 'الفشل لا يُقرأ «لا كارتات»');
      await CardsState.ensureKnown();
      expect(adapter.calls, 1, reason: 'لا يُطرق الخادم مع كلّ تحديثٍ للوحة');
      CardsState.reset();
      await CardsState.ensureKnown();
      expect(adapter.calls, 2);
    });
  });

  group('قسم «الكارتات» — ترتيبٌ وعرض', () {
    CardSeries s(String id, String? at) => CardSeries.fromJson({
          'series': id,
          if (at != null) 'created_at': at,
        })!;

    test('السلاسل الأحدث أوّلاً، والتعادل والغائب بترتيب الخادم', () {
      final out = newestFirst([
        s('a', '2026-01-01 10:00:00'),
        s('b', null),
        s('c', '2026-10-01 23:31:35'),
        s('d', '2026-01-01 10:00:00'),
        s('e', null),
      ]);
      expect(out.map((e) => e.series), ['c', 'a', 'd', 'b', 'e']);
    });

    test('🚨 الذيل أربع خانات بعد نقطتين — والغائب نقاطٌ لا رقم', () {
      expect(cardTail('4821'), '••4821');
      expect(cardTail(null), '••••••');
    });

    test('تاريخ الساس يُعرض كما هو بلا إزاحة منطقة', () {
      final c = CardItem.fromJson({
        'id': 1,
        'used': true,
        'used_at': '2026-10-02 01:19:46',
      })!;
      expect(cardsWhen(c.usedAtDate), '2026-10-02 01:19');
      expect(cardsWhen(null), '—');
      expect(cardsDay(DateTime(2027, 9, 1)), '2027-09-01');
    });
  });

  test('🚨 كلّ مفتاح cards.* مستعمل موجودٌ في اللغتين، واللغتان متطابقتان', () {
    Map<String, dynamic> load(String loc) =>
        (jsonDecode(File('assets/translations/$loc.json').readAsStringSync())
            as Map<String, dynamic>)['cards'] as Map<String, dynamic>;
    final ar = load('ar'), en = load('en');
    expect(ar.keys.toSet(), en.keys.toSet());
    // والعناصر النائبة نفسها في اللغتين — {n} ناقصة في واحدةٍ تُطبع حرفيّاً.
    final ph = RegExp(r'\{[a-z]+\}');
    for (final k in ar.keys) {
      Set<String> of(Map<String, dynamic> m) =>
          ph.allMatches(m[k] as String).map((x) => x.group(0)!).toSet();
      expect(of(ar), of(en), reason: 'cards.$k');
    }
    final used = <String>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      used.addAll(RegExp(r"'cards\.([a-z0-9_]+)'")
          .allMatches(f.readAsStringSync())
          .map((m) => m.group(1)!));
    }
    expect(used, isNotEmpty);
    for (final k in used) {
      expect(ar.containsKey(k), isTrue, reason: 'cards.$k مفقود');
    }
  });
}

/// خادمٌ وهميّ لـ`ApiClient.dio` — يردّ بما في [reply] ويحفظ آخر طلب.
class _FakeAdapter implements HttpClientAdapter {
  (int, Map<String, dynamic>) reply = (200, {'success': true});
  RequestOptions? _last;

  /// عدد الطلبات التي وصلت.
  int calls = 0;

  /// حين يُضبط: الردّ ينتظره — لمحاكاة طلبٍ عالقٍ في الطريق.
  Completer<void>? gate;

  String get lastPath => _last!.path;
  Map<String, dynamic> get lastBody =>
      Map<String, dynamic>.from(_last!.data as Map);
  Map<String, dynamic> get lastQuery => _last!.queryParameters;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _last = options;
    calls++;
    final g = gate;
    if (g != null) await g.future;
    final (status, body) = reply;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
