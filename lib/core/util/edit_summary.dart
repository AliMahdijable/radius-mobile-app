/// «من → إلى» لسطر تعديل (المالك ٢٢ نوفمبر: «سابقاً قلنا بالتعديل وصف التعديل أو النقر عليه يفتح كيف تعديل من إلى»): ما تغيّر نصّاً من
/// action_data — بقواعد «سجلّ التعديلات» (server/subscriberEdits.js): كلمات المرور «تغيّرت» بلا قيمة، الملاحظة الخاصّة «أُضيفت/عُدّلت/حُذفت»
/// بلا نصّها، وإعداد الجهاز «تغيّر» بلا قيمه (قيمه لمن يملك صلاحيّة الأجهزة في «سجلّ التعديلات» بصفحة المشترك). السطور منذ ٢٠ نوفمبر تحمل
/// `diff` (القيم)، والأقدم `changes` (أسماء الحقول ⇒ «عُدّل: الباقة، رقم الهاتف»). null = لا تفاصيل.
library;

const _fields = <String, String>{
  'username': 'اسم المستخدم',
  'profile': 'الباقة',
  'firstname': 'الاسم الأوّل',
  'lastname': 'اسم العائلة',
  'name': 'الاسم',
  'phone': 'رقم الهاتف',
  'expiration': 'تاريخ الانتهاء',
  'parent': 'المدير',
  'password': 'كلمة المرور',
  'wa_phone2': 'الرقم الثاني (واتساب)',
  'tg_contact': 'تلغرام',
  'note': 'الملاحظة الخاصّة',
  'device_type': 'نوع الجهاز',
  'device_ip': 'عنوان الجهاز',
  'device_user': 'اسم مستخدم الجهاز',
  'device_pass': 'كلمة مرور الجهاز',
  'device_note': 'ملاحظة الجهاز',
  'second_address': 'عنوان الجهاز الثاني',
  'second_user': 'اسم مستخدم الجهاز الثاني',
  'second_pass': 'كلمة مرور الجهاز الثاني',
  'location': 'الموقع',
};
const _secret = {'password', 'device_pass', 'second_pass'};
const _device = {'device_type', 'device_ip', 'device_user', 'device_pass', 'device_note', 'second_address', 'second_user', 'second_pass'};
const _noteWords = {'added': 'أُضيفت', 'edited': 'عُدّلت', 'removed': 'حُذفت'};

final _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::\d{2})?)?$');
final _arabic = RegExp(r'[\u0600-\u06FF]');
const _lri = '\u2066';
const _pdi = '\u2069';

/// «2026-12-01 00:00:00» ⇒ «2026/12/01 00:00» (التواريخ أرقام)؛ غيرها كما هو، معزولاً LTR (رقم الهاتف لا ينقلب في سطرٍ عربيّ).
String _value(Object? v) {
  final s = (v?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty || s == 'null') return '';
  final m = _dateRe.firstMatch(s);
  final out = m == null ? s : (m.group(4) != null ? '${m[1]}/${m[2]}/${m[3]} ${m[4]}:${m[5]}' : '${m[1]}/${m[2]}/${m[3]}');
  return _arabic.hasMatch(out) ? out : '$_lri$out$_pdi';
}

String? editSummaryOf(Map<String, dynamic> data) {
  final diff = data['diff'];
  if (diff is List && diff.isNotEmpty) {
    final parts = <String>[];
    for (final raw in diff) {
      if (raw is! Map) continue;
      final f = '${raw['f'] ?? ''}';
      final label = _fields[f];
      if (label == null) continue;
      if (_secret.contains(f) || raw['secret'] == true) {
        parts.add('$label: تغيّرت');
      } else if (f == 'note') {
        parts.add('$label: ${_noteWords['${raw['change']}'] ?? 'عُدّلت'}');
      } else if (_device.contains(f)) {
        parts.add('$label: تغيّر');
      } else {
        final from = _value(raw['from']);
        final to = _value(raw['to']);
        final when = raw['at_expiry'] == true ? ' (عند انتهاء الاشتراك)' : '';
        parts.add(from.isEmpty ? '$label: صار ${to.isEmpty ? 'فارغ' : to}$when' : '$label: من $from إلى ${to.isEmpty ? 'فارغ' : to}$when');
      }
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
  final changes = data['changes'];
  if (changes is List && changes.isNotEmpty) {
    final out = <String>[];
    void add(String l) {
      if (!out.contains(l)) out.add(l);
    }

    for (final c in changes) {
      final s = '${c ?? ''}';
      if (s.startsWith('profile_change_cancelled')) {
        add('إلغاء تغيير الباقة المجدول');
      } else if (RegExp(r'^profile\b').hasMatch(s)) {
        add(_fields['profile']!);
      } else if (RegExp(r'^username\b').hasMatch(s)) {
        add(_fields['username']!);
      } else if (s == 'parent_id') {
        add(_fields['parent']!);
      } else if (s == 'password') {
        continue;
      } else if (_fields.containsKey(s)) {
        add(_fields[s]!);
      }
    }
    return out.isEmpty ? null : 'عُدّل: ${out.join('، ')}';
  }
  return null;
}
