import 'package:flutter/foundation.dart';

/// «الحوالات» (٢٣ نوفمبر — المالك: «نحتاج طريقة نعلم انه الفلوس هو استلمهن عن طريق الماستر كارد… مو اجت… مال الصندوق مباشرة»):
/// طريقة استلام المبلغ في التفعيل النقديّ والتسديد وإضافة الرصيد — كاش (الافتراضيّ) أو حوالة بطريقتها. الكاش يدخل الصندوق وبيد
/// مستلمه؛ الحوالة رصيدٌ لطريقتها خارج الصندوق (ولا على الموظّف) حتى «سحب للصندوق». رصيدٌ لكلّ طريقة: زين كاش، ماستر، وأخرى باسمها.
class PaidVia {
  const PaidVia(this.key, [this.name]);

  /// cash | zaincash | master | other — يُرسَل كما هو (`paid_via`).
  final String key;

  /// اسم «أخرى» كما كتبه الوكيل (`paid_via_name`).
  final String? name;

  static const cash = PaidVia('cash');
  static const zaincash = PaidVia('zaincash');
  static const master = PaidVia('master');

  bool get isCash => key == 'cash';
  bool get isTransfer => !isCash;

  /// «أخرى» بلا اسم لا تُرسَل.
  bool get valid => key != 'other' || (name ?? '').trim().isNotEmpty;

  String get label => switch (key) {
        'zaincash' => 'زين كاش',
        'master' => 'ماستر',
        'other' => (name ?? '').trim().isEmpty ? 'أخرى' : name!.trim(),
        _ => 'كاش',
      };

  /// ما يُضاف لجسم الطلب — والكاش لا يُرسل شيئاً (خادمٌ أقدم وأحدث يعدّانه كاشاً كما كان).
  Map<String, Object?> toBody() => isCash ? const {} : {'paid_via': key, if (key == 'other') 'paid_via_name': name!.trim()};

  /// من طريقة طلب البوّابة (renew/debt-pay: zaincash | master | other).
  static PaidVia fromRequest(String? payMethod) => switch (payMethod) {
        'zaincash' => zaincash,
        'master' => master,
        _ => cash,
      };

  @override
  bool operator ==(Object other) => other is PaidVia && other.key == key && (other.name ?? '') == (name ?? '');

  @override
  int get hashCode => Object.hash(key, name ?? '');
}

/// هل يعرف الخادم «الحوالات»؟ قبله لا يُعرض الاختيار ولا يُرسل شيء (كلّ شيءٍ كاش كما كان).
abstract final class TransferPay {
  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  /// أسماء «أخرى» التي استعملها الوكيل (للاختيار السريع).
  static final ValueNotifier<List<String>> recentOthers = ValueNotifier<List<String>>(const []);
}
