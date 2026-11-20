import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/message_exclusions_api.dart';
import 'package:rad_mysvcs/screens/comms/comms_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/notifications_settings_screen.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm_harness.dart';

/// لقطات تصميم «التواصل» و«إشعاراتي» (٢٠ نوفمبر) — الشاشات الحقيقيّة أمام خادمٍ وهميّ ببياناتٍ تجريبيّة.
///   comms_more · comms_hub · comms_settings · my_alerts · my_alerts_repeat · my_alerts_digest · my_alerts_filter
void main() {
  setUpAll(visualSetUpAll);

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
  }

  void designCase(String name, Future<void> Function(WidgetTester t, VisualServer server) body) {
    testWidgets(name, (t) async {
      debugDisableShadows = false;
      final server = await visualSetUp(s1bSasOwner);
      ApiClient.dio.httpClientAdapter = _DesignServer(server);
      MessageExclusionsState.reset();
      try {
        await body(t, server);
        await drain(t);
      } finally {
        await visualTearDown();
        MessageExclusionsState.reset();
        debugDisableShadows = true;
      }
    });
  }

  Future<GlobalKey<NavigatorState>> pushed(WidgetTester t, VisualDevice d, Widget page) async {
    final nav = GlobalKey<NavigatorState>();
    await pumpVisual(t, d, navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg));
    await settle(t, seconds: 1);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
    await settle(t, seconds: 3);
    return nav;
  }

  for (final d in [phoneTall, phoneDark]) {
    designCase('more${d.tag}', (t, server) async {
      await pumpVisual(t, d, home: (_) => const MainShell());
      await settle(t, seconds: 2);
      await t.tap(find.text('nav.more'.tr()).last);
      await settle(t, seconds: 3);
      await shoot(t, s1bSasOwner, 'comms_more', d, server);
    });
  }

  for (final d in [phone, phoneDark]) {
    designCase('hub${d.tag}', (t, server) async {
      await pushed(t, d, const CommsScreen());
      await shoot(t, s1bSasOwner, 'comms_hub', d, server);
    });
  }

  designCase('settings', (t, server) async {
    await pushed(t, phoneTall, const SettingsScreen());
    await shoot(t, s1bSasOwner, 'comms_settings', phoneTall, server);
  });

  for (final d in [phoneTall, phoneDark]) {
    designCase('my_alerts${d.tag}', (t, server) async {
      await pushed(t, d, const NotificationsSettingsScreen());
      await shoot(t, s1bSasOwner, 'my_alerts', d, server);
    });
  }

  for (final (key, name) in [
    ('ma-balance-repeat', 'my_alerts_repeat'),
    ('ma-debtors-schedule', 'my_alerts_digest'),
    ('ma-debtors-amount', 'my_alerts_filter'),
    ('ma-balance-threshold', 'my_alerts_amount'),
  ]) {
    designCase(name, (t, server) async {
      await pushed(t, phone, const NotificationsSettingsScreen());
      final f = find.byKey(ValueKey(key));
      await t.ensureVisible(f);
      await settle(t, seconds: 1);
      await t.tap(f);
      await settle(t, seconds: 2);
      await shoot(t, s1bSasOwner, name, phone, server);
    });
  }
}

/// ما تحتاجه الشاشات الجديدة — والباقي لخادم العدّة.
class _DesignServer implements HttpClientAdapter {
  _DesignServer(this.base);
  final VisualServer base;

  static ResponseBody _json(Object body) =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: {
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
          'balance': {
            'enabled': true,
            'threshold': 250000,
            'repeat': {'mode': 'every_hours', 'hours': 6},
            'now': 184500,
            'days_left': 2,
          },
          'debt_cap': {
            'enabled': true,
            'cap': 5000000,
            'repeat': {'mode': 'daily', 'at': '09:00'},
            'now': 4150000,
          },
          'debtors': {
            'enabled': true,
            'min_days': 30,
            'min_amount': 25000,
            'schedule': {'mode': 'weekly', 'weekday': 6, 'at': '10:00'},
            'matching': {'count': 14, 'total': 1265000},
          },
          'recent': [
            {'kind': 'balance', 'title': 'رصيدك 184,500 د.ع — تحت حدّك 250,000', 'at': '2026-11-20T06:00:00Z'},
            {'kind': 'debt_cap', 'title': 'ديون مشتركيك وصلت 83% من السقف', 'at': '2026-11-19T06:00:00Z'},
            {'kind': 'debtors', 'title': '14 مديون أقدم من 30 يوم — 1,265,000 د.ع', 'at': '2026-11-15T07:00:00Z'},
          ],
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
    } else if (get && p == MessageExclusionsApi.allPath) {
      body = {
        'success': true,
        'enabled': true,
        'can_manage': true,
        'groups': [
          {'key': 'reminders', 'label': 'التذكيرات'},
          {'key': 'broadcast', 'label': 'التبليغات'},
        ],
        'exclusions': {
          'u1001': {'groups': ['reminders']},
          'u1002': {'groups': ['broadcast']},
          'u1003': {'groups': ['reminders', 'broadcast']},
        },
        'max': 5000,
      };
    } else if (get && p == '/api/whatsapp/broadcast/channels') {
      body = {
        'success': true,
        'reach': {'whatsapp': 640, 'telegram': 112, 'app': 35},
        'locks': <String, Object?>{},
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
