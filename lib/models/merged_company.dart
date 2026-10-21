/// «كل الشركات»: شركةٌ من شركات حساب Pro (صفّ `GET /api/account/merged/companies`) — كقارئ الويب (client-v2 lib/merged.ts
/// parseMergedCompanies) حرفاً: مفتاحٌ بصيغته وإلّا يُسقط، والمكرّر يُسقط، والعملة مجهولةٌ (null) لساسٍ لم تُقرأ عملته.
enum MergedProvider { sas4, earthlink, ftth }

enum MergedStatus { ok, needsLogin, unavailable, loading }

class MergedCompany {
  const MergedCompany({
    required this.key,
    required this.code,
    required this.username,
    required this.name,
    required this.provider,
    required this.colorIndex,
    required this.adminId,
    required this.ns,
    required this.currency,
    required this.home,
    required this.status,
    required this.index,
    this.reason,
    this.message,
    this.retryAfterMs,
  });

  /// c + 12 hex — هو x-company-key.
  final String key;

  /// كود الساس (supernet، jt، earthlink…).
  final String code;

  /// يوزر المدير في الربط — يحسم تحت أيّ صفحةٍ يُعرض مشتركٌ تراه صفحتان (المدير المباشر).
  final String username;

  /// الاسم للعرض (صفحتان بالاسم نفسه ⇒ «الاسم · اليوزر» من الخادم).
  final String name;
  final MergedProvider provider;

  /// ترتيب الشركة في الحساب — مرجع لونها.
  final int colorIndex;

  /// المعرّف المؤهَّل (jt:6836، earthlink:12، العاري لسوبرنت).
  final String adminId;

  /// مجال إزالة المكرّر: SAS4 = مضيف الساس (صفحتان على ساسٍ واحد تشتركان)، EL/FTTH = الموزّع.
  final String ns;

  /// العملة — المجاميع تجمع IQD وحدها؛ null: لم يعرفها الخادم ⇒ تُسمّى ولا تُجمع.
  final String? currency;

  /// الساس الأصل (سوبرنت).
  final bool home;
  final MergedStatus status;

  /// سبب الحال غير ok (session، captcha، 2fa، subscription-ended، ftth_web_only…).
  final String? reason;

  /// نصّ الخادم العربيّ للحال غير ok.
  final String? message;
  final int? retryAfterMs;

  /// ترتيبها في الردّ (ترتيب الربط) — «الأقدم ربطاً» في إزالة المكرّر.
  final int index;

  /// FTTH يعمل من الويب وحده الآن (الخادم يرفضه من التطبيق: ftth_web_only).
  bool get appCapable => provider != MergedProvider.ftth;

  /// تُسأل وتدخل الدمج والمجاميع.
  bool get usable => status == MergedStatus.ok && appCapable;

  static final RegExp _keyRe = RegExp(r'^c[0-9a-f]{12}$');

  static String? _text(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim());
  }

  static MergedProvider _provider(Object? v) => switch ('${v ?? ''}'.toLowerCase()) {
        'earthlink' => MergedProvider.earthlink,
        'ftth' => MergedProvider.ftth,
        _ => MergedProvider.sas4,
      };

  static MergedStatus _status(Object? v) => switch (v) {
        'ok' => MergedStatus.ok,
        'needs_login' => MergedStatus.needsLogin,
        'loading' => MergedStatus.loading,
        _ => MergedStatus.unavailable,
      };

  /// صفوف الردّ ⇒ الشركات (مفتاحٌ بلا صيغته أو مكرّرٌ يُسقط).
  static List<MergedCompany> listFrom(Object? raw) {
    final list = raw is List ? raw : const [];
    final out = <MergedCompany>[];
    final seen = <String>{};
    for (final row in list) {
      if (row is! Map) continue;
      final key = _text(row['key']);
      if (key == null || !_keyRe.hasMatch(key) || !seen.add(key)) continue;
      final code = (_text(row['code']) ?? '').toLowerCase();
      final provider = _provider(row['provider']);
      final ci = _int(row['color_index']);
      final cur = _text(row['currency']);
      out.add(MergedCompany(
        key: key,
        code: code,
        username: _text(row['username']) ?? '',
        name: _text(row['name']) ?? (code.isEmpty ? key : code),
        provider: provider,
        colorIndex: ci != null && ci >= 0 ? ci : out.length,
        adminId: _text(row['admin_id']) ?? '',
        ns: _text(row['ns']) ?? key,
        currency: cur != null ? cur.toUpperCase() : (provider != MergedProvider.sas4 ? 'IQD' : null),
        home: row['home'] == true || row['home'] == 1,
        status: _status(row['status']),
        reason: _text(row['reason']),
        message: _text(row['message']),
        retryAfterMs: _int(row['retry_after_ms']),
        index: out.length,
      ));
    }
    return out;
  }
}

/// ردّ الشركات: التوجيه والتنفيذ مفتوحان لهذا الحساب؟ وشركاته.
class MergedCompaniesData {
  const MergedCompaniesData({required this.routing, required this.writes, required this.companies});

  final bool routing;
  final bool writes;
  final List<MergedCompany> companies;

  static MergedCompaniesData from(Map<String, dynamic>? d) {
    if (d == null) return const MergedCompaniesData(routing: false, writes: false, companies: []);
    final routing = d['routing'] == true;
    return MergedCompaniesData(
      routing: routing,
      writes: routing && d['writes'] == true,
      companies: MergedCompany.listFrom(d['companies']),
    );
  }

  List<MergedCompany> get usable => companies.where((c) => c.usable).toList();
}
