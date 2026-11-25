// تشخيصٌ مؤقّت (٢٥ نوفمبر — المالك: «تطبيق الويندوز والمايكروسوفت … من يسوي تعديل قالب بمجرد ما يكتب اي شي يصير كراش»):
// يفتح محرّر قالب الواتساب و«تنبيه المشترك» داخل تطبيقٍ حقيقيّ على ويندوز (المحرّك والخطوط الحقيقيّة) ويكتب بلوحة مفاتيح
// حقيقيّة عبر SendInput — إنجليزيّ بأزرار، ثمّ عربيّ بتخطيط 00000401، ثمّ يونيكود — ويطبع كلّ خطوة. ليس للإصدار.
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/whatsapp/connection_alerts_screen.dart';
import 'package:rad_mysvcs/screens/whatsapp/whatsapp_templates_screen.dart';
import 'package:win32/win32.dart';

import '../test/support/ai_status_overlay.dart';
import '../test/visual_perm/visual_perm_harness.dart';

const desk = VisualDevice('_desk', Size(1280, 800), 1);

void say(String s) {
  // ignore: avoid_print
  print('[typing] $s');
}

Future<void> settle(WidgetTester t, [int ms = 1500]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

int hwndOfApp() {
  final title = 'MyServices Pro'.toNativeUtf16();
  final h = FindWindow(nullptr, title);
  free(title);
  return h;
}

void foreground() {
  final h = hwndOfApp();
  say('hwnd=$h setForeground=${SetForegroundWindow(h)} foregroundNow=${GetForegroundWindow() == h}');
}

int _send(List<(int vk, int scan, int flags)> keys) {
  final inputs = calloc<INPUT>(keys.length);
  for (var i = 0; i < keys.length; i++) {
    inputs[i].type = INPUT_KEYBOARD;
    inputs[i].ki.wVk = keys[i].$1;
    inputs[i].ki.wScan = keys[i].$2;
    inputs[i].ki.dwFlags = keys[i].$3;
    inputs[i].ki.time = 0;
    inputs[i].ki.dwExtraInfo = 0;
  }
  final n = SendInput(keys.length, inputs, sizeOf<INPUT>());
  calloc.free(inputs);
  return n;
}

/// أزرار حقيقيّة (VK) — يُترجمها تخطيط لوحة المفاتيح النشط (إنجليزيّ أو عربيّ) كما لو ضغطها المستخدم.
int typeKeys(String letters) {
  var sent = 0;
  for (final ch in letters.toUpperCase().split('')) {
    final vk = ch == ' ' ? VK_SPACE : ch.codeUnitAt(0);
    final scan = MapVirtualKey(vk, MAPVK_VK_TO_VSC);
    sent += _send([(vk, scan, 0), (vk, scan, KEYEVENTF_KEYUP)]);
  }
  return sent;
}

/// يونيكود مباشر (VK_PACKET) — كلوحة المفاتيح على الشاشة وبعض أدوات الإدخال.
int typeUnicode(String s) {
  var sent = 0;
  for (final u in s.codeUnits) {
    sent += _send([(0, u, KEYEVENTF_UNICODE), (0, u, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP)]);
  }
  return sent;
}

int activateLayout(String klid) {
  final p = klid.toNativeUtf16();
  final h = LoadKeyboardLayout(p, KLF_ACTIVATE);
  free(p);
  return h;
}

String fieldText(WidgetTester t, Finder field) {
  final et = t.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText)));
  return et.textEditingValue.text;
}

Future<void> typeRound(WidgetTester t, Finder field, String label) async {
  await t.ensureVisible(field);
  await settle(t, 400);
  await t.tap(field);
  await settle(t, 600);
  foreground();
  final before = fieldText(t, field);
  say('$label: focused, length=${before.length}');

  final en = typeKeys('abc de');
  await settle(t);
  final afterEn = fieldText(t, field);
  say('$label: english keys sent=$en, length ${before.length} -> ${afterEn.length}, exception=${t.takeException()}');

  final ar = activateLayout('00000401');
  say('$label: arabic layout handle=$ar');
  final arSent = typeKeys('afj kl');
  await settle(t);
  final afterAr = fieldText(t, field);
  say('$label: arabic-layout keys sent=$arSent, length ${afterEn.length} -> ${afterAr.length}, '
      'tail=${afterAr.substring(afterAr.length > 12 ? afterAr.length - 12 : 0)}, exception=${t.takeException()}');

  final un = typeUnicode('سلام ');
  await settle(t);
  final afterUn = fieldText(t, field);
  say('$label: unicode sent=$un, length ${afterAr.length} -> ${afterUn.length}, exception=${t.takeException()}');

  // Enter + Backspace داخل الحقل متعدّد الأسطر
  _send([(VK_RETURN, MapVirtualKey(VK_RETURN, 0), 0), (VK_RETURN, MapVirtualKey(VK_RETURN, 0), KEYEVENTF_KEYUP)]);
  _send([(VK_BACK, MapVirtualKey(VK_BACK, 0), 0), (VK_BACK, MapVirtualKey(VK_BACK, 0), KEYEVENTF_KEYUP)]);
  await settle(t);
  say('$label: enter+backspace length=${fieldText(t, field).length}, exception=${t.takeException()}');
  activateLayout('00000409');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(visualSetUpAll);

  testWidgets('قوالب الواتساب — كتابة حقيقيّة على ويندوز', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff);
    await pumpVisual(t, desk, home: (_) => const WhatsAppTemplatesScreen());
    await settle(t, 2500);
    final tiles = find.byType(InkWell);
    say('templates: tiles=${tiles.evaluate().length}');
    await t.tap(tiles.first, warnIfMissed: false);
    await settle(t, 1500);
    final fields = find.byType(TextField);
    say('templates: text fields=${fields.evaluate().length}');
    await typeRound(t, fields.last, 'wa-template');
    say('templates: DONE');
  });

  testWidgets('«تنبيه المشترك» — كتابة حقيقيّة على ويندوز', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: {
      'GET /api/v2/connection-alerts/settings': {
        'success': true,
        'data': {'enabled': true, 'signal_dbm': -60, 'ccq_pct': 50, 'fiber_rx_dbm': -27, 'fiber_temp_c': 70, 'name_mode': 'name', 'is_default': false},
      },
    });
    await pumpVisual(t, desk, home: (_) => const ConnectionAlertsScreen());
    await settle(t, 2500);
    final fields = find.byType(TextField);
    say('conn-alerts: text fields=${fields.evaluate().length}');
    if (fields.evaluate().isEmpty) {
      say('conn-alerts: no field visible (wide layout) — scrolling');
      await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await settle(t, 800);
    }
    final f2 = find.byType(TextField);
    say('conn-alerts: text fields after scroll=${f2.evaluate().length}');
    if (f2.evaluate().isNotEmpty) await typeRound(t, f2.first, 'conn-alert');
    say('conn-alerts: DONE');
  });

  testWidgets('حقل بسيط (مرجع) — كتابة حقيقيّة', (t) async {
    final c = TextEditingController(text: 'مرحباً {name} ✅ 📶\nسطر ثانٍ');
    await t.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: TextField(controller: c, minLines: 8, maxLines: 14))),
      ),
    ));
    await settle(t, 800);
    await typeRound(t, find.byType(TextField), 'plain-multiline');
    say('plain: DONE text=${c.text.length}');
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  });
}
