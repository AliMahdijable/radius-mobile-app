import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';
import 'company_route.dart';

/// أسماء الباقات في «بوابة المشترك» — المالك ٢٦ أكتوبر: «بالطباعه والواتساب الاشعارات كلها … اسم الباقة اذا
/// لم يكتب بوابه المشترك فالمتغير يرجع ياخذ اسمه من الافتراضي للساس».
///
/// رقم الباقة ⇒ اسمها الذي كتبه الحساب في «وصف الباقات» (`GET /api/v2/package-names` — صفوف الحساب وحده،
/// server/packageNames.js). ما ليس هنا يبقى باسم الساس. الخادم يملأ رسائله بالقاعدة نفسها؛ هذا لما يُكتب
/// على الجهاز: أزرار كارت المشترك (المعاينة واليدويّ)، تنبيه الاتّصال، والوصل.
@immutable
class PackageNames {
  const PackageNames(this.byId);

  final Map<int, String> byId;

  static const empty = PackageNames(<int, String>{});

  /// ردّ الخادم ⇒ خريطةٌ نظيفة: مفاتيح أرقامٌ موجبة، وقيمٌ نصوصٌ غير فارغة. غير ذلك ⇒ لا أسماء.
  static PackageNames fromJson(Object? body) {
    if (body is! Map || body['success'] != true) return empty;
    final names = body['names'];
    if (names is! Map) return empty;
    final out = <int, String>{};
    names.forEach((k, v) {
      final id = int.tryParse(k.toString().trim());
      final name = v is String ? v.trim() : '';
      if (id != null && id > 0 && name.isNotEmpty) out[id] = name;
    });
    return out.isEmpty ? empty : PackageNames(Map.unmodifiable(out));
  }

  /// الاسم كما يراه المشترك: اسم البوّابة لهذا الرقم إن كُتب، وإلّا اسم الساس كما وصل.
  String? display(int? profileId, String? sasName) {
    final custom = profileId == null ? null : byId[profileId];
    return custom ?? sasName;
  }
}

/// `GET /api/v2/package-names` — مخبّأٌ **بمعرّف الحساب** (أو مفتاح شركة الطلب الموجَّه في «كل الشركات»)
/// ٥ دقائق كإعدادات الوصل، ويُمسح عند حفظ «وصف الباقات» من التطبيق. التعذّر ⇒ لا أسماء (اسم الساس) — لا يمنع
/// رسالةً ولا وصلاً، ولا يُخبّأ (المحاولة التالية تسأل من جديد).
class PackageNamesApi {
  PackageNamesApi._();

  static const _ttl = Duration(minutes: 5);
  static final Map<String, ({DateTime at, PackageNames value})> _cache = {};

  static Future<PackageNames> fetch({bool force = false}) async {
    final key = CompanyRoute.currentKey ?? await AuthStorage.readAdminId();
    if (key == null || key.isEmpty) return PackageNames.empty;
    final c = _cache[key];
    if (!force && c != null && DateTime.now().difference(c.at) < _ttl) return c.value;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/package-names',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final body = r.data;
      if (r.statusCode != 200 || body == null || body['success'] != true) return PackageNames.empty;
      final value = PackageNames.fromJson(body);
      _cache.remove(key);
      _cache[key] = (at: DateTime.now(), value: value);
      while (_cache.length > 20) {
        _cache.remove(_cache.keys.first);
      }
      return value;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[PackageNamesApi] fetch: ${e.type}');
      return PackageNames.empty;
    } catch (e) {
      if (kDebugMode) debugPrint('[PackageNamesApi] fetch: $e');
      return PackageNames.empty;
    }
  }

  /// بعد حفظ «وصف الباقات» أو استعادته — الرسالة والوصل التاليان بالاسم الجديد.
  static void clearCache() => _cache.clear();
}
