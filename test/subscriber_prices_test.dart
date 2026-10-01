import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';

/// «أسعار المشتركين» — حارس ما يعتمد عليه التطبيق من القائمة.
///
/// الخادم يضع الثابت في `user_price` ويعلّم الصفّ `price_source:'custom'`
/// لصفوف الثابت وحدها. والتطبيق يقرأ `user_price` قبل غيره، فيظهر الثابت
/// حتّى في نسخه القديمة — وهذا الحارس يُثبت أنّ الجديدة تفهم العلامة.
void main() {
  Map<String, dynamic> row(Map<String, dynamic> extra) => {
        'idx': '55',
        'username': 'ali@net',
        'firstname': 'علي',
        'lastname': '',
        'profile_id': 7,
        'package_price': 25000,
        'discount': 0,
        ...extra,
      };

  group('القراءة من القائمة', () {
    test('صفّ الثابت: السعر هو الثابت والعلامة مرفوعة', () {
      final s = Subscriber.fromJson(row({
        'user_price': 20000,
        'package_price': 20000,
        'price_source': 'custom',
        'base_package_price': 25000,
      }));
      expect(s.isFixedPrice, isTrue);
      expect(s.price, 20000);
      expect(s.basePackagePrice, 25000);
      expect(s.needsRepricing, isFalse);
    });

    test('🚨 صفٌّ عاديّ لا يتغيّر شيءٌ فيه', () {
      final s = Subscriber.fromJson(row({}));
      expect(s.isFixedPrice, isFalse);
      expect(s.needsRepricing, isFalse);
      expect(s.basePackagePrice, isNull);
    });

    test('تغيّرت الباقة: تنبيهٌ بلا ثابت', () {
      final s = Subscriber.fromJson(row({'price_needs_repricing': true}));
      expect(s.isFixedPrice, isFalse);
      expect(s.needsRepricing, isTrue);
    });
  });

  test('🚨 العلامات تنجو من نسخ النموذج (الاتّصال · الموقع · الباقات)', () {
    final s = Subscriber.fromJson(row({
      'user_price': 20000,
      'price_source': 'custom',
      'base_package_price': 25000,
    }));
    for (final c in [
      s.copyWithOnline(online: true, ip: '10.0.0.9'),
      s.copyWithLocation(latitude: 33.3, longitude: 44.4),
      s.enrichWithPackages(
          {'7': const PackageInfo(name: 'Gold', price: 25000)}),
    ]) {
      expect(c.isFixedPrice, isTrue);
      expect(c.basePackagePrice, 25000);
      expect(c.price, 20000, reason: 'الكتالوج لا يكتب فوق الثابت');
    }
  });

  test('🚨 كلّ مفتاح sp.* مستعمل موجودٌ في اللغتين، واللغتان متطابقتان', () {
    Map<String, dynamic> load(String loc) => (jsonDecode(
            File('assets/translations/$loc.json').readAsStringSync())
        as Map<String, dynamic>)['sp'] as Map<String, dynamic>;
    final ar = load('ar'), en = load('en');
    expect(ar.keys.toSet(), en.keys.toSet());
    final used = <String>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      used.addAll(RegExp(r"'sp\.([a-z0-9_]+)'")
          .allMatches(f.readAsStringSync())
          .map((m) => m.group(1)!));
    }
    expect(used, isNotEmpty);
    for (final k in used) {
      expect(ar.containsKey(k), isTrue, reason: 'sp.$k مفقود');
    }
  });
}
