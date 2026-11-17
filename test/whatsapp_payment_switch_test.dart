// «تأكيد التسديد» (١٧ نوفمبر — المالك: «تمام سويها»): مفتاحٌ بإعدادات الواتساب لرسالة المشترك بعد «تسديد دين».
// مفعّلٌ افتراضيّاً، والخادم القديم لا يرسل الحقل ⇒ غيابه = مفعّل (كالخادم الجديد: NULL = مفعّل)؛ والحفظ يرسله دائماً.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';

void main() {
  group('WhatsFeatures.sendOnPayment', () {
    test('غيابه من ردّ الخادم (القديم) = مفعّل، والافتراضيّ مفعّل', () {
      expect(const WhatsFeatures().sendOnPayment, isTrue);
      expect(WhatsFeatures.fromJson(const {}).sendOnPayment, isTrue);
      expect(WhatsFeatures.fromJson(const {'sendOnPayment': null}).sendOnPayment, isTrue);
    });

    test('قيمه المقروءة: false/0/"false" مطفأ، true/1/"true" مفعّل', () {
      for (final off in [false, 0, 'false']) {
        expect(WhatsFeatures.fromJson({'sendOnPayment': off}).sendOnPayment, isFalse, reason: '$off');
      }
      for (final on in [true, 1, 'true']) {
        expect(WhatsFeatures.fromJson({'sendOnPayment': on}).sendOnPayment, isTrue, reason: '$on');
      }
    });

    test('الحفظ يرسله، والنسخ يحفظه، وبقيّة المفاتيح كما هي', () {
      final f = WhatsFeatures.fromJson(const {
        'notificationsEnabled': true, 'sendOnActivation': true, 'debtReminder': true, 'sendOnPayment': false,
      });
      expect(f.toJson()['sendOnPayment'], isFalse);
      final g = f.copyWith(sendOnActivation: false);
      expect(g.sendOnPayment, isFalse, reason: 'copyWith لا يعيده للافتراضيّ');
      expect(g.debtReminder, isTrue);
      final h = g.copyWith(sendOnPayment: true);
      expect(h.sendOnPayment, isTrue);
      expect(h.sendOnActivation, isFalse);
      expect(WhatsFeatures.fromJson(h.toJson()).toJson(), h.toJson(), reason: 'ذهابٌ وإياب');
    });
  });

  test('الشاشة تعرض المفتاح بنصّه في اللغتين وتحفظه', () {
    final src = File('lib/screens/whatsapp/whatsapp_status_screen.dart').readAsStringSync();
    expect(src, contains("'wa.payment_notif'.tr()"));
    expect(src, contains('value: f.sendOnPayment'));
    expect(src, contains('f.copyWith(sendOnPayment: v)'));
    for (final lang in ['ar', 'en']) {
      final j = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      final wa = j['wa'] as Map<String, dynamic>;
      expect((wa['payment_notif'] as String?)?.trim().isNotEmpty, isTrue, reason: lang);
    }
    final ar = jsonDecode(File('assets/translations/ar.json').readAsStringSync()) as Map<String, dynamic>;
    expect((ar['wa'] as Map<String, dynamic>)['payment_notif'], 'تأكيد التسديد', reason: 'اسم القالب نفسه بشاشة القوالب');
  });
}
