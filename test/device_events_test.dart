// التحديث الفوريّ لقسم الأجهزة (المالك ٢٧ أكتوبر): كلّ عمليّة حفظٍ (إضافة/
// تعديل/حذف جهاز، وإضافة/تعديل/حذف منطقة، والجماعيّ) تُطلق إشارة DeviceEvents،
// فتُحدِّث القائمة والنظرة العامّة والبرج بلا إعادة تحميلٍ يدويّ. هذا الاختبار
// يُثبت الجانب المنتج: أنّ كلّ عمليّةٍ تُطلق إشعاراً واحداً للمستمعين.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/network_devices_api.dart';
import 'package:rad_mysvcs/services/device_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Ok implements HttpClientAdapter {
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls.add('${o.method} ${o.uri.path}');
    const device = {
      'id': 1, 'admin_id': '1', 'name': 'سكتر', 'type': 'router',
      'brand': 'mikrotik', 'ip': '10.0.0.1', 'port': 8728,
      'last_status': 'unknown', 'created_at': '2026-10-27 00:00:00',
    };
    const region = {'id': 1, 'name': 'برج', 'sort_order': 0, 'device_count': 0};
    final p = o.uri.path;
    Map<String, dynamic> data;
    if (p.contains('bulk-create')) {
      data = {'success': true, 'created': [device], 'count': 1};
    } else if (p.contains('bulk')) {
      data = {'success': true, 'deleted': 1, 'requested': 1};
    } else if (p.contains('/regions')) {
      data = {'success': true, 'data': region};
    } else if (o.method == 'DELETE') {
      data = {'success': true, 'devices_unassigned': 0};
    } else {
      data = {'success': true, 'data': device};
    }
    return ResponseBody.fromString(jsonEncode(data), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': '1'});
    ApiClient.dio.httpClientAdapter = _Ok();
    DeviceEvents.changes.value = 0;
  });

  test('كلّ عمليّة حفظٍ تُطلق إشارة تغيّرٍ واحدة', () async {
    var fired = 0;
    void onBump() => fired++;
    DeviceEvents.changes.addListener(onBump);
    addTearDown(() => DeviceEvents.changes.removeListener(onBump));

    await NetworkDevicesApi.update(1, {'name': 'جديد'});
    expect(fired, 1, reason: 'تعديل الجهاز');

    await NetworkDevicesApi.create({'name': 'x'});
    await NetworkDevicesApi.delete(1);
    await NetworkDevicesApi.createRegion(name: 'ر');
    await NetworkDevicesApi.updateRegion(1, name: 'ر٢');
    await NetworkDevicesApi.deleteRegion(1);
    await NetworkDevicesApi.bulkCreate([{'name': 'a', 'ip': '10.0.0.2'}]);
    await NetworkDevicesApi.bulkDelete([1]);

    // ٨ عمليّات ⇒ ٨ إشعارات.
    expect(fired, 8);
    expect(DeviceEvents.changes.value, 8);
  });

  test('الإشارة تُشعر المستمعين فعلاً (عقد التحديث الفوريّ)', () async {
    var seen = 0;
    void l() => seen++;
    DeviceEvents.changes.addListener(l);
    addTearDown(() => DeviceEvents.changes.removeListener(l));
    DeviceEvents.bump();
    DeviceEvents.bump();
    expect(seen, 2);
  });
}
