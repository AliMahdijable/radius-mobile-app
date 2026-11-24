import '../../core/util/order_rules.dart';
import '../../models/subscriber.dart';
import 'widgets/sort_sheet.dart';

/// «الترتيب بالنقر» — المرحلة ٥ (توحيد المشتركين، المالك ٢٤ نوفمبر: «ابدي ببيهن»): حقول القائمة العاديّة بقواعد كلّ القوائم
/// ([sortList] — والموقع lib/sort.ts نفسها): النصّ مطبَّعاً (أ إ آ = ا، ى = ي، ة = ه) وأرقامه بقيمتها (user2 قبل user10)، والفارغ
/// آخراً بالاتّجاهين (كان الاسم الفارغ يصعد أوّلاً تنازليّاً، ومَن بلا انتهاءٍ أوّلاً تصاعديّاً)، والتعادل بترتيب القائمة (كان
/// `List.sort` غير مستقرّ فيقافز الصفوف المتساوية). «أيّام الدين» والاستهلاك ومقاييس الأجهزة بمساراتها في الشاشة كما هي.
List<Subscriber> orderSubscribers(List<Subscriber> list, SortField field, SortDirection dir, {DateTime? now}) {
  final kind = switch (field) {
    SortField.notes || SortField.remainingDays || SortField.sessionTime => OrderKind.number,
    SortField.expiration => OrderKind.date,
    _ => OrderKind.text,
  };
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  Object? valueOf(Subscriber s) => switch (field) {
        SortField.username => s.username,
        SortField.firstname => s.fullName,
        SortField.profileName => s.profileName,
        SortField.phone => s.displayPhone,
        SortField.parentUsername => s.parentUsername,
        SortField.expiration => s.parsedExpiration ?? s.expiration,
        // بلحظة الانتهاء (الساس يدوّر الأيّام لصفر لمن بقيت له ساعات)، والأيّام حين لا تاريخ، ولا هذا ولا ذاك ⇒ آخراً
        SortField.remainingDays =>
          s.parsedExpiration?.millisecondsSinceEpoch ?? (s.remainingDays == null ? null : at + s.remainingDays! * 86400000),
        SortField.notes => s.balanceAmount,
        SortField.sessionTime => s.sessionTime,
        _ => null,
      };
  final f = OrderField(field.name, field.name, kind);
  final v = OrderValue(f.key, dir == SortDirection.asc ? OrderDir.asc : OrderDir.desc);
  return sortList<Subscriber>(list, v, [f], (s, _) => valueOf(s));
}
