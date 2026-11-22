import '../screens/reports/v2/report_sheets.dart';
import 'api_client.dart';
import 'company_route.dart';
import 'employees_api.dart';

/// مدراء وموظّفو شركةٍ لورقة فلاتر التقرير الموحّد (٢٢ نوفمبر) — [of] يثبّت شركتهما: المفتوحة، أو شركة «كل الشركات» بمفتاحها
/// (المساران موجَّهان للقراءة). `parent_id` حين يرسله الخادم ⇒ شجرة المدراء الفرعيّين.
class ReportPeopleApi {
  ReportPeopleApi._();

  static Future<List<RpPerson>?> managers() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/managers');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final out = <RpPerson>[];
      for (final row in (body['data'] as List?) ?? const []) {
        if (row is! Map) continue;
        final id = '${row['id'] ?? ''}'.trim();
        final username = '${row['username'] ?? ''}'.trim();
        if (id.isEmpty || id == '0' || username.isEmpty) continue;
        final full = '${row['firstname'] ?? ''} ${row['lastname'] ?? ''}'.trim();
        final parent = '${row['parent_id'] ?? ''}'.trim();
        out.add(RpPerson(id, full.isEmpty ? username : '$full ($username)', username: username, parentId: parent.isEmpty || parent == '0' ? null : parent));
      }
      out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    } catch (_) {
      return null;
    }
  }

  static List<RpPerson>? _employees(({List<Employee> rows, String? error}) r) {
    if (r.error != null) return null;
    return [
      for (final e in r.rows)
        RpPerson('${e.id}', (e.fullName ?? '').trim().isEmpty ? e.username : e.fullName!.trim(),
            username: e.username, sub: e.isActive ? null : 'موقوف'),
    ];
  }

  /// قائمتا شركةٍ معاً — [companyKey] null = المفتوحة صراحةً (لا وجهة قسمٍ موجَّهٍ مفتوحٍ تحت التقرير). null في أيٍّ منهما = تعذّر.
  static Future<({List<RpPerson>? managers, List<RpPerson>? employees})> of(String? companyKey) async {
    // شركة المجموعة في الورقة (مفتاحها، أو المفتوحة) — CompanyRoute.pin: مفتاحٌ صالح ⇒ لها، وإلّا ⇒ المفتوحة
    final group = (companyKey: companyKey);
    final m = CompanyRoute.pin(group.companyKey, managers);
    final e = CompanyRoute.pin(group.companyKey, () => EmployeesApi.list(withDeleted: true));
    return (managers: await m, employees: _employees(await e));
  }
}
