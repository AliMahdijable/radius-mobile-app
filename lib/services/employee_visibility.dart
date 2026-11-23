import 'permissions_service.dart';

/// «ما يراه الموظّف» (٢٣ نوفمبر ٢٠٢٦ — المالك: «المدير يقدر يخلي الموظف ما يشوف الديون او ما يشوف اليوزرية … ضيف الهاتف …
/// عدد المشتركين»): ماذا يرى الموظّف الحاليّ. صاحب الحساب والمدير يرون كلّ شيء.
///
/// الخادم يخفي الديون والهاتف ورصيد الصفحة من ردوده (تصل null) ويرفض أقسام الديون وحدها؛ هنا تكتب الشاشات «مخفي» حيث كان الرقم
/// (لا «لا دين» كاذباً)، وتخفي اليوزر والأعداد (العمليّات والقائمة تحتاجهما فلا يخفيهما الخادم)، وأزرار الاتصال والواتساب.
abstract final class Sees {
  /// ديون المشتركين: المبالغ ومن عليه دين — ويبقى التسديد (المالك: «اي يسدّد»).
  static bool get debts => PermissionsService.sees('debts');

  /// يوزر المشترك — الاسم العربيّ بداله، والبحث باليوزر يبقى يشتغل.
  static bool get usernames => PermissionsService.sees('usernames');

  /// هاتف المشترك وأرقام تواصله وأزرار الاتصال والواتساب.
  static bool get phones => PermissionsService.sees('phones');

  /// أعداد المشتركين: كارت المشتركين بالرئيسيّة وأعداد التبويبات.
  static bool get counts => PermissionsService.sees('counts');

  /// رصيد الصفحة ونقاطها.
  static bool get balance => PermissionsService.sees('balance');

  /// اسم المشترك للعرض: الاسم، وإلّا اليوزر حين يُرى، وإلّا «بلا اسم».
  static String nameOf(String? name, String username) {
    final n = (name ?? '').trim();
    if (n.isNotEmpty) return n;
    return usernames ? username : kNoNameWord;
  }
}

/// ما يُكتب بمكان صنفٍ أخفاه المدير.
const kHiddenWord = 'مخفي';

/// مشتركٌ بلا اسمٍ واليوزر مخفيّ.
const kNoNameWord = 'بلا اسم';
