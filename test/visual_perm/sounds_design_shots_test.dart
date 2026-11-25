import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/my_alerts/notif_sounds_screen.dart';
import 'package:rad_mysvcs/screens/notifications_settings_screen.dart';
import 'package:rad_mysvcs/services/notif_sound_engine.dart';
import 'package:rad_mysvcs/services/notif_sounds.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm_harness.dart';

/// لقطات تصميم «أصوات الإشعارات» (٢٥ نوفمبر) — الشاشة الحقيقيّة بأندرويد والآيفون، ونافذة النغمة، و«إشعاراتي» بسطرها الجديد،
/// والعرض الضيّق 320 بخطٍّ مكبَّر 120% (قاعدة المالك: لا نصّ يُقصّ ولا يطلع برّا).
void main() {
  setUpAll(visualSetUpAll);

  const narrow = VisualDevice('_320x120', Size(320, 2400), 2);
  const narrowSheet = VisualDevice('_320x120', Size(320, 760), 3);

  // تفضيلات العرض: الافتراضيّ + «الانتهاءات» صامتة حتى تُرى حالة «بلا صوت».
  final shown = NotifSoundPrefs.defaults.withOn('expiry', false);

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
  }

  void designCase(String name, Future<void> Function(WidgetTester t, VisualServer server) body,
      {bool ios = false, double? textScale, PhoneSoundStatus? status}) {
    testWidgets(name, (t) async {
      debugDisableShadows = false;
      if (ios) debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      SoundPlatform.isIos = () => ios;
      NotifSoundsHooks.readStatus = () async =>
          status ??
          (ios
              ? const PhoneSoundStatus(notificationsOn: true, soundOn: true)
              : const PhoneSoundStatus(notificationsOn: true, soundOn: true, breaksThrough: false, fixChannel: 'ns_balance_voice'));
      NotifSoundsHooks.onSaved = (_) async {};
      NotifSoundsHooks.loadPrefs = () async => NotifSoundPrefs.defaults;
      if (textScale != null) {
        t.platformDispatcher.textScaleFactorTestValue = textScale;
      }
      final server = await visualSetUp(s1bSasOwner);
      ApiClient.dio.httpClientAdapter = _DesignServer(server);
      try {
        await body(t, server);
        await drain(t);
      } finally {
        await visualTearDown();
        debugDisableShadows = true;
        debugDefaultTargetPlatformOverride = null;
        SoundPlatform.isIos = () => false;
        NotifSoundsHooks.reset();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      }
    });
  }

  Future<void> pushed(WidgetTester t, VisualDevice d, Widget page) async {
    final nav = GlobalKey<NavigatorState>();
    await pumpVisual(t, d, navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg));
    await settle(t, seconds: 1);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
    await settle(t, seconds: 3);
  }

  Future<void> openSheet(WidgetTester t, String id) async {
    final f = find.byKey(ValueKey('sound-$id'));
    await t.ensureVisible(f);
    await settle(t, seconds: 1);
    await t.tap(f);
    await settle(t, seconds: 2);
  }

  // ── الشاشة كاملةً ──
  designCase('android_full', (t, server) async {
    await pushed(t, phoneTall, NotifSoundsScreen(initial: shown));
    await shoot(t, s1bSasOwner, 'sounds_android', phoneTall, server);
  });

  designCase('iphone_full', ios: true, (t, server) async {
    await pushed(t, phoneTall, NotifSoundsScreen(initial: shown));
    await shoot(t, s1bSasOwner, 'sounds_iphone', phoneTall, server);
  });

  designCase('android_dark', (t, server) async {
    await pushed(t, phoneDark, NotifSoundsScreen(initial: shown));
    await shoot(t, s1bSasOwner, 'sounds_android', phoneDark, server);
  });

  // ── نافذة النغمة ──
  designCase('sheet_android', (t, server) async {
    await pushed(t, phone, NotifSoundsScreen(initial: shown));
    await openSheet(t, 'balance');
    await shoot(t, s1bSasOwner, 'sheet_balance_android', phone, server);
  });

  designCase('sheet_iphone', ios: true, (t, server) async {
    await pushed(t, phone, NotifSoundsScreen(initial: shown));
    await openSheet(t, 'balance');
    await shoot(t, s1bSasOwner, 'sheet_balance_iphone', phone, server);
  });

  designCase('sheet_devices_dark', (t, server) async {
    await pushed(t, phoneDark, NotifSoundsScreen(initial: shown));
    await openSheet(t, 'devices');
    await shoot(t, s1bSasOwner, 'sheet_devices', phoneDark, server);
  });

  // ── «إشعاراتي» بسطرها الجديد ──
  designCase('my_alerts', (t, server) async {
    await pushed(t, phone, const NotificationsSettingsScreen());
    await shoot(t, s1bSasOwner, 'my_alerts_with_sounds', phone, server);
  });

  // ── الضيّق 320 × 120% ──
  designCase('narrow', textScale: 1.2, (t, server) async {
    await pushed(t, narrow, NotifSoundsScreen(initial: shown));
    await shoot(t, s1bSasOwner, 'sounds_android', narrow, server);
  });

  designCase('narrow_iphone', ios: true, textScale: 1.2, (t, server) async {
    await pushed(t, narrow, NotifSoundsScreen(initial: shown));
    await shoot(t, s1bSasOwner, 'sounds_iphone', narrow, server);
  });

  designCase('narrow_sheet', textScale: 1.2, (t, server) async {
    await pushed(t, narrowSheet, NotifSoundsScreen(initial: shown));
    await openSheet(t, 'debt_pay');
    await shoot(t, s1bSasOwner, 'sheet_debt_pay_android', narrowSheet, server);
  });
}

/// «إشعاراتي» تحتاج تفضيلاتها وتنبيهات المال — والباقي لخادم العدّة.
class _DesignServer implements HttpClientAdapter {
  _DesignServer(this.base);
  final VisualServer base;

  static ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    final get = o.method.toUpperCase() == 'GET';
    Object? body;
    if (get && p == '/api/v2/agent-notifs') {
      body = {
        'success': true,
        'data': {
          'balance': {'enabled': true, 'threshold': 250000, 'repeat': {'mode': 'every_hours', 'hours': 6}, 'now': 184500, 'days_left': 2},
          'debt_cap': {'enabled': true, 'cap': 5000000, 'repeat': {'mode': 'daily', 'at': '09:00'}, 'now': 4150000},
          'debtors': {
            'enabled': false,
            'min_days': 30,
            'min_amount': 25000,
            'schedule': {'mode': 'weekly', 'weekday': 6, 'at': '10:00'},
            'matching': {'count': 14, 'total': 1265000},
          },
          'recent': <Object?>[],
          'currency': 'IQD',
        },
      };
    } else if (get && p == '/api/admin/notification-prefs') {
      body = {
        'success': true,
        'prefs': {
          'push_near_expiry': true,
          'push_expired_today': true,
          'push_manager_debt': false,
          'quiet_hours_enabled': true,
          'quiet_hours_start': '23:00',
          'quiet_hours_end': '08:00',
        },
      };
    }
    if (body != null) {
      base.log.add('${o.method} $p → 200 (design)');
      return _json(body);
    }
    return base.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
