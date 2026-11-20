import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api/balance_reports_api.dart';
import '../api/big_subscribers_api.dart';
import '../api/subscribers_api.dart';
import '../models/subscriber.dart';
import 'permissions_service.dart';

/// أسماء المشتركين العربيّة لحركات «تقارير الأرصدة» (٢٠ نوفمبر — المالك: «اريد اضيف اسم المشترك الي بالعربي»).
///
/// من قائمة المشتركين المخبّأة ([SubscribersApi.loadAll] — ٤٥ث للتطبيق كلّه، فلا طلبٌ جديد غالباً)، وللحساب الكبير (≥ ٥٠٠٠)
/// أسماء صفوف الصفحة وحدها من الساس ([BigSubscribersApi.lookup] ≤ ١٠٠ — لا القائمة الكاملة أبداً)، كالخصومات القائمة والويب.
/// لا طلب ولا اسم (اليوزر وحده كما كان): موظّفٌ بلا «عرض المشتركين»، أو «كل الشركات» (قائمة التطبيق لشركة الجلسة لا المختارة —
/// يوزرٌ مشابه في شركةٍ أخرى يعطي اسماً خطأً). لا يرمي.
class BalanceSubNames {
  BalanceSubNames({this.companyKey});

  /// الشركة المختارة في «كل الشركات» — null للصفحة المفتوحة.
  final String? companyKey;

  final _names = <String, String>{};
  final _asked = <String>{};
  bool? _big;
  bool _allLoaded = false;

  // مصادر القائمة — الحقيقيّة افتراضاً؛ الاختبار يبدّلها.
  @visibleForTesting
  static Future<int> Function() probe = BigSubscribersApi.probe;
  @visibleForTesting
  static Future<List<Subscriber>> Function(List<String> usernames) lookup = _lookup;
  @visibleForTesting
  static Future<List<Subscriber>?> Function() loadAll = SubscribersApi.loadAll;

  @visibleForTesting
  static void debugReset() {
    probe = BigSubscribersApi.probe;
    lookup = _lookup;
    loadAll = SubscribersApi.loadAll;
  }

  static Future<List<Subscriber>> _lookup(List<String> usernames) => BigSubscribersApi.lookup(usernames: usernames);

  /// هل تُطلب الأسماء أصلاً لهذه الجلسة.
  bool get enabled => companyKey == null && PermissionsService.has('subscribers.view');

  /// الاسم العربيّ ليوزر (بلا حساسيّة الأحرف)، أو null.
  String? of(String username) => _names[username.trim().toLowerCase()];

  /// يوزرات الحركات التي تحمل اسم مشترك: التفعيل وتسديد الدين (لا المدراء الفرعيّون ولا التسوية).
  static Iterable<String> usersOf(Iterable<BalanceMove> moves) sync* {
    for (final m in moves) {
      if (m is BalanceActMove) yield m.username;
      if (m is BalancePayMove) yield m.username;
    }
  }

  /// يكمل أسماء [usernames] ممّا لم يُسأل عنه بعد. true إن عُرف اسمٌ جديد.
  Future<bool> fill(Iterable<String> usernames) async {
    if (!enabled) return false;
    final want = <String>[];
    for (final u in usernames) {
      final t = u.trim();
      if (t.isEmpty || !_asked.add(t.toLowerCase())) continue;
      want.add(t);
    }
    if (want.isEmpty) return false;
    final before = _names.length;
    try {
      _big ??= await probe() > 0;
      if (_big!) {
        for (var i = 0; i < want.length; i += 100) {
          _add(await lookup(want.sublist(i, math.min(i + 100, want.length))));
        }
      } else if (!_allLoaded) {
        final all = await loadAll();
        if (all != null) {
          _allLoaded = true;
          _add(all);
        } else {
          // تعذّرت القائمة: يُسأل عنها من جديد مع الصفحة التالية (لا تبقى الأسماء غائبةً بعثرة شبكة)
          for (final t in want) {
            _asked.remove(t.toLowerCase());
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🟡 balance names: $e');
    }
    return _names.length > before;
  }

  void _add(Iterable<Subscriber> subs) {
    for (final s in subs) {
      final u = s.username.trim();
      final n = balanceSubName(u, firstname: s.firstname, lastname: s.lastname);
      if (u.isNotEmpty && n != null) _names.putIfAbsent(u.toLowerCase(), () => n);
    }
  }
}
