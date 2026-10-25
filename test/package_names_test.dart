// اسم الباقة كما يراه المشترك — المالك ٢٦ أكتوبر: «بالطباعه والواتساب الاشعارات كلها … اسم الباقة اذا لم يكتب
// بوابه المشترك فالمتغير يرجع ياخذ اسمه من الافتراضي للساس». ما يُكتب على الجهاز: أزرار كارت المشترك (المعاينة
// واليدويّ)، تنبيه الاتّصال، والوصل — بقاعدة رسائل الخادم نفسها (server/packageNames.js)، بخادمٍ وهميّ.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/package_names_api.dart';
import 'package:rad_mysvcs/api/portal_settings_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/receipt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Server implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  /// ردّ /api/v2/package-names لكلّ شركة (x-company-key) أو للجلسة ('' ).
  final Map<String, Object> names = {};
  int namesStatus = 200;

  List<RequestOptions> to(String path) => requests.where((r) => r.uri.path == path).toList();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    var status = 200;
    Object data = {'success': true};
    if (o.uri.path == '/api/v2/package-names') {
      status = namesStatus;
      final key = (o.headers['x-company-key'] ?? '').toString();
      data = names[key] ?? {'success': true, 'names': {}};
    }
    final key = o.headers['x-company-key'];
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      // الطلب الموجَّه يُقبل بصدى مفتاحه وحده (api_client._onRoutedResponse) — كالخادم
      if (key != null) 'x-company-key': [key.toString()],
    });
  }

  @override
  void close({bool force = false}) {}
}

Subscriber _sub({String? profileName = 'Gold', int? profileId = 5, String? companyKey}) => Subscriber(
      username: 'u1',
      firstname: 'علي',
      lastname: '',
      profileName: profileName,
      profileId: profileId,
      companyKey: companyKey,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 'sim-token', 'auth.admin_id': 'speednet-iq:1429'});
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    PackageNamesApi.clearCache();
  });

  group('القاعدة', () {
    test('ردّ الخادم ⇒ خريطةٌ نظيفة: أرقامٌ موجبة وأسماءٌ غير فارغة', () {
      final n = PackageNames.fromJson({
        'success': true,
        'names': {'5': ' باقة الذهب ', '6': '', '0': 'x', 'abc': 'y', '8': 7, '9': 'تسعة'},
      });
      expect(n.byId, {5: 'باقة الذهب', 9: 'تسعة'});
      expect(PackageNames.fromJson({'success': false, 'names': {'5': 'A'}}).byId, isEmpty);
      expect(PackageNames.fromJson({'success': true, 'names': []}).byId, isEmpty);
      expect(PackageNames.fromJson(null).byId, isEmpty);
      expect(PackageNames.fromJson([1, 2]).byId, isEmpty);
    });

    test('اسم البوّابة لهذا الرقم إن كُتب، وإلّا اسم الساس كما وصل', () {
      const n = PackageNames({5: 'باقة الذهب'});
      expect(n.display(5, 'Gold'), 'باقة الذهب');
      expect(n.display(6, 'Silver  2'), 'Silver  2');
      expect(n.display(null, 'Gold'), 'Gold');
      expect(n.display(6, null), isNull);
      expect(PackageNames.empty.display(5, 'Gold'), 'Gold');
    });
  });

  group('الجلب والذاكرة', () {
    test('مرّةً لكلّ حساب خلال ٥ دقائق، و«كل الشركات» بمفتاح شركة الطلب', () async {
      server.names[''] = {'success': true, 'names': {'5': 'A'}};
      server.names['c0123456789ab'] = {'success': true, 'names': {'5': 'B'}};
      expect((await PackageNamesApi.fetch()).byId, {5: 'A'});
      expect((await PackageNamesApi.fetch()).byId, {5: 'A'});
      expect(server.to('/api/v2/package-names'), hasLength(1), reason: 'الثانية من الذاكرة');
      final routed = await CompanyRoute.run('c0123456789ab', PackageNamesApi.fetch);
      expect(routed.byId, {5: 'B'});
      expect(server.to('/api/v2/package-names'), hasLength(2));
      expect(server.to('/api/v2/package-names').last.headers['x-company-key'], 'c0123456789ab');
      expect((await CompanyRoute.run('c0123456789ab', PackageNamesApi.fetch)).byId, {5: 'B'});
      expect(server.to('/api/v2/package-names'), hasLength(2), reason: 'ذاكرة الشركة');
    });

    test('التعذّر ⇒ اسم الساس ولا يُخبّأ (المحاولة التالية تسأل)', () async {
      server.namesStatus = 500;
      server.names[''] = {'success': false, 'message': 'x'};
      expect((await PackageNamesApi.fetch()).byId, isEmpty);
      server.namesStatus = 200;
      server.names[''] = {'success': true, 'names': {'5': 'A'}};
      expect((await PackageNamesApi.fetch()).byId, {5: 'A'});
      expect(server.to('/api/v2/package-names'), hasLength(2));
    });

    test('بلا حسابٍ مخزَّن ⇒ لا نداء', () async {
      FlutterSecureStorage.setMockInitialValues({});
      expect((await PackageNamesApi.fetch()).byId, isEmpty);
      expect(server.to('/api/v2/package-names'), isEmpty);
    });

    test('حفظ «وصف الباقات» أو استعادته يمسح الذاكرة — الرسالة والوصل التاليان بالاسم الجديد', () async {
      server.names[''] = {'success': true, 'names': {'5': 'قديم'}};
      expect((await PackageNamesApi.fetch()).byId, {5: 'قديم'});
      server.names[''] = {'success': true, 'names': {'5': 'جديد'}};
      expect((await PackageNamesApi.fetch()).byId, {5: 'قديم'}, reason: 'بلا حفظٍ: من الذاكرة');
      final saved = await PortalSettingsApi.updatePackage(5, displayName: 'جديد');
      expect(saved.ok, isTrue);
      expect((await PackageNamesApi.fetch()).byId, {5: 'جديد'});
      server.names[''] = {'success': true, 'names': {}};
      expect(await PortalSettingsApi.resetPackage(5), isTrue);
      expect((await PackageNamesApi.fetch()).byId, isEmpty);
    });
  });

  group('ما يُكتب على الجهاز', () {
    test('قوالب الأزرار وتنبيه الاتّصال: {package_name} = البوّابة، و{sas_package_name} = الساس', () {
      const tpl = 'الباقة: {package_name} ({sas_package_name})';
      const n = PackageNames({5: 'باقة الذهب'});
      expect(WhatsAppApi.renderForSubscriber(tpl, _sub(), names: n), 'الباقة: باقة الذهب (Gold)');
      expect(WhatsAppApi.renderForSubscriber(tpl, _sub()), 'الباقة: Gold (Gold)', reason: 'بلا أسماء ⇒ كما كان');
      expect(WhatsAppApi.renderForSubscriber(tpl, _sub(profileId: 6), names: n), 'الباقة: Gold (Gold)',
          reason: 'لم يُكتب اسمٌ لهذه الباقة ⇒ اسم الساس');
      expect(WhatsAppApi.renderForSubscriber(tpl, _sub(profileName: null, profileId: null), names: n), 'الباقة:  ()');
    });

    test('أسماء المشترك تُجلب بشركة صفّه في «كل الشركات»', () async {
      server.names['c0123456789ab'] = {'success': true, 'names': {'5': 'B'}};
      final n = await WhatsAppApi.packageNamesFor(_sub(companyKey: 'c0123456789ab'));
      expect(n.byId, {5: 'B'});
      expect(server.to('/api/v2/package-names').single.headers['x-company-key'], 'c0123456789ab');
    });

    test('الوصل: باقة المشترك برقمها، والاسم المُمرَّر برقمه، وبلا رقمٍ كما هو (باقة التمديد)', () {
      const n = PackageNames({5: 'باقة الذهب', 31: 'فايبر ٣٥'});
      expect(ReceiptService.packageLabel(n, _sub(), null, null), 'باقة الذهب', reason: 'بطاقة المعلومات/التسديد');
      expect(ReceiptService.packageLabel(n, _sub(profileId: 6), null, null), 'Gold');
      expect(ReceiptService.packageLabel(n, _sub(), 'FTTH 35', 31), 'فايبر ٣٥', reason: 'التفعيل بباقةٍ مختارة (ايرث لنك)');
      expect(ReceiptService.packageLabel(n, _sub(), 'تمديد ٧ أيام', null), 'تمديد ٧ أيام', reason: 'التمديد: ليست باقة مشترك');
      expect(ReceiptService.packageLabel(n, _sub(), ' Gold ', 5), 'باقة الذهب');
      expect(ReceiptService.packageLabel(PackageNames.empty, _sub(profileName: ' Gold '), null, null), 'Gold');
      expect(ReceiptService.packageLabel(n, _sub(profileName: null, profileId: null), null, null), '');
    });
  });
}
