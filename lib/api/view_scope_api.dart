import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import 'api_client.dart';

/// مدير فرعي مع حالة إخفائه.
///
/// المخفيّ يُخزَّن على الخادم لا على الجهاز، فالإعداد يتبع الحساب إلى
/// كلّ أجهزته وإلى الويب، ويرثه الموظّفون.
@immutable
class ViewScopeManager {
  const ViewScopeManager({
    required this.username,
    required this.hideDebts,
    required this.hideSubscribers,
  });

  final String username;
  final bool hideDebts;
  final bool hideSubscribers;

  bool get isHidden => hideDebts || hideSubscribers;

  ViewScopeManager copyWith({bool? hideDebts, bool? hideSubscribers}) =>
      ViewScopeManager(
        username: username,
        hideDebts: hideDebts ?? this.hideDebts,
        hideSubscribers: hideSubscribers ?? this.hideSubscribers,
      );

  factory ViewScopeManager.fromJson(Map<String, dynamic> j) => ViewScopeManager(
        username: (j['username'] ?? '').toString(),
        hideDebts: j['hideDebts'] == true,
        hideSubscribers: j['hideSubscribers'] == true,
      );
}

/// قسمٌ من الرئيسيّة وحالة إخفائه.
@immutable
class DashSection {
  const DashSection({required this.key, required this.hidden});
  final String key;
  final bool hidden;

  DashSection copyWith({bool? hidden}) =>
      DashSection(key: key, hidden: hidden ?? this.hidden);

  factory DashSection.fromJson(Map<String, dynamic> j) => DashSection(
        key: (j['key'] ?? '').toString(),
        hidden: j['hidden'] == true,
      );
}

/// تسمية القسم كما تُعرض. المفاتيح ثابتة على الخادم؛ والاسم هنا لأنّه
/// نصّ واجهة لا بيانات — فلا يستحقّ جولة شبكة.
const dashSectionLabels = <String, ({String title, String sub})>{
  'subscribers': (title: 'كارت المشتركين', sub: 'الحلقة وصفوف الحالات'),
  'wallet': (title: 'الرصيد والمدينون', sub: 'كارتا المال أعلى الصفحة'),
  'revenue': (title: 'الإيرادات', sub: 'يومي · أسبوعي · شهري'),
  'activities': (title: 'آخر النشاطات', sub: 'سجل العمليّات الأخيرة'),
  'wa_banner': (title: 'تنبيه واتساب', sub: 'شريط «تحتاج إعادة ربط»'),
};

/// «نطاق العرض» — أيّ مدير فرعي يُخفى، ومنه ماذا.
///
/// تفضيل عرضٍ لا تحكّم وصول: لا يمنع أحداً من شيء، ولا يوقف رسائل
/// الواتساب. الترشيح يقع على الخادم قبل أن يُسلسَل أيّ صفّ، فالتطبيق
/// لا يرشّح شيئاً محليّاً — ولهذا لا يمكن لشاشة أن «تنسى» الترشيح.
class ViewScopeApi {
  ViewScopeApi._();

  static void _log(String what, Object e) {
    if (kDebugMode) debugPrint('🔴 view-scope $what: $e');
  }

  static List<ViewScopeManager> _parse(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ViewScopeManager.fromJson(Map<String, dynamic>.from(m)))
        .where((m) => m.username.isNotEmpty)
        .toList();
  }

  /// GET — القائمة الكاملة للمدراء الفرعيّين مع حالة كلّ واحد.
  /// `null` = فشل الجلب (تُميَّز عن قائمة فارغة = لا مدراء فرعيّون).
  static List<DashSection> _sections(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => DashSection.fromJson(Map<String, dynamic>.from(m)))
        .where((s) => s.key.isNotEmpty)
        .toList();
  }

  /// جولةٌ واحدة تجلب الشقّين — المدراء والأقسام. الشاشة واحدة،
  /// فجلبهما منفصلَين يعني وميضاً وحالتين قد تختلفان.
  static Future<({List<ViewScopeManager>? managers, List<DashSection> sections})>
      load() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/admin/view-scope');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (managers: null, sections: const <DashSection>[]);
      }
      return (
        managers: _parse(body['managers']),
        sections: _sections(body['sections'])
      );
    } catch (e) {
      _log('GET', e);
      return (managers: null, sections: const <DashSection>[]);
    }
  }

  /// يبدّل قسماً من الرئيسيّة ويعيد الحالة المُطبَّعة كاملةً.
  static Future<({bool ok, String? message, List<DashSection> sections})>
      setSection(String key, bool hidden) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/view-scope',
        data: {'sectionKey': key, 'hidden': hidden},
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          message: (body['message'] ?? 'تعذّر الحفظ').toString(),
          sections: const <DashSection>[]
        );
      }
      return (ok: true, message: null, sections: _sections(body['sections']));
    } catch (e) {
      _log('PUT section', e);
      return (
        ok: false,
        message: humanError(e, fallback: 'تعذّر الحفظ'),
        sections: const <DashSection>[]
      );
    }
  }

  /// PUT — يحفظ مديراً واحداً ويعيد الحالة المُطبَّعة كاملةً.
  ///
  /// نتبنّى ما يعيده الخادم لا تخميننا المتفائل: الاسم قد يكون سقط في
  /// التحقّق من شجرة SAS4، فالتفاؤل يعني مفتاحاً يبدو مفعَّلاً ولا أثر
  /// له.
  static Future<({bool ok, String? message, List<ViewScopeManager>? managers})>
      save({
    required String managerUsername,
    required bool hideDebts,
    required bool hideSubscribers,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/admin/view-scope',
        data: {
          'managerUsername': managerUsername,
          'hideDebts': hideDebts,
          'hideSubscribers': hideSubscribers,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          ok: false,
          message: (body['message'] ?? 'تعذّر الحفظ').toString(),
          managers: null,
        );
      }
      return (ok: true, message: null, managers: _parse(body['managers']));
    } on DioException catch (e) {
      _log('PUT', e);
      return (ok: false, message: 'تعذّر الاتصال بالخادم', managers: null);
    } catch (e) {
      _log('PUT', e);
      return (ok: false, message: 'تعذّر الحفظ', managers: null);
    }
  }
}
