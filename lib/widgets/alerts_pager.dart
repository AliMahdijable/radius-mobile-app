import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/alerts_page.dart';
import '../theme/colors.dart';

export '../api/alerts_page.dart';

/// يطلب صفحةً بحجم [size] بعد المؤشّر [before] (null = من الأعلى)؛ [have] = كم صفّاً جاء قبلها من الأعلى (لخادمٍ أقدم بلا مؤشّر:
/// «أوّل have+size» ثمّ يُقصّ). null = تعذّر.
typedef AlertsFetch<T> = Future<AlertsPage<T>?> Function({String? before, required int have, required int size});

/// قائمة تنبيهاتٍ بصفحاتٍ من الخادم (٩ نوفمبر — المالك: «تنبيهات المشتركين والأجهزة — خلّي بيها ١٠ قراءات وتحميل المزيد»):
/// الأحدث ١٠ أوّلاً، و[loadMore] يجلب العشرة التالية وحدها — بعد آخر ما عُرض، فما وصل أعلاها بينهما لا يُكرَّر — حتى لا يبقى شيء.
/// فشل «المزيد» يُبقي ما عُرض ([moreFailed] ⇒ «أعد المحاولة»)، وفشل التحديث يُبقي القائمة كما كانت ([failed]). كلّ تحميلٍ من الأعلى
/// برقم: ردّ ما قبله (ولو «المزيد») يُسقط فلا تختلط قائمتان.
class AlertsPager<T> extends ChangeNotifier {
  AlertsPager({required this.fetch, required this.keyOf, this.pageSize = 10, this.maxRequest = 50});

  final AlertsFetch<T> fetch;

  /// هويّة العنصر — لا يُعرض مرّتين بين صفحتين.
  final Object Function(T item) keyOf;
  final int pageSize;

  /// أكبر صفحةٍ يقبلها الخادم: التحديث بعمق ما عُرض يُطلب على دفعاتٍ بها.
  final int maxRequest;

  List<T> _items = const [];
  String? _next;
  int _offset = 0; // صفوفٌ جاءت من الأعلى (للخادم الأقدم: الصفحة التالية تبدأ بعدها)
  bool _hasMore = false;
  bool _loaded = false;
  bool _reloading = false;
  bool _loadingMore = false;
  bool _failed = false;
  bool _moreFailed = false;
  int? _total;
  int? _sendable;
  int _seq = 0;
  bool _disposed = false;

  List<T> get items => _items;
  bool get hasMore => _hasMore;

  /// وصلت صفحةٌ أولى مرّةً على الأقلّ (قبلها: انتظار).
  bool get loaded => _loaded;
  bool get loadingMore => _loadingMore;

  /// آخر تحميلٍ من الأعلى تعذّر — ما عُرض قبله باقٍ.
  bool get failed => _failed;

  /// آخر «تحميل المزيد» تعذّر — ما عُرض باقٍ والزرّ «أعد المحاولة».
  bool get moreFailed => _moreFailed;

  /// العدد الحقيقيّ بالخادم مع الصفحة الأولى (إن أعطاه) — [AlertsPage.total]/[AlertsPage.sendable].
  int? get total => _total;
  int? get sendable => _sendable;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// من الأعلى: الصفحة الأولى، أو بعمق ما عُرض ([keepDepth] — بعد إجراءٍ لا ترجع القائمة لأوّلها). لا يُخطِر قبل الردّ (يصلح من
  /// initState).
  Future<void> reload({bool keepDepth = false}) async {
    final seq = ++_seq;
    _reloading = true;
    _loadingMore = false;
    final want = keepDepth ? math.max(_items.length, pageSize) : pageSize;
    final got = <T>[];
    final seen = <Object>{};
    String? next;
    var offset = 0;
    var more = false;
    var failedAt = -1;
    int? total;
    int? sendable;
    for (var round = 0; round < 40; round++) {
      final p = await fetch(before: next, have: offset, size: math.min(want - got.length, maxRequest));
      if (_disposed || seq != _seq) return;
      if (p == null) {
        failedAt = got.length;
        break;
      }
      if (round == 0) {
        total = p.total;
        sendable = p.sendable;
      }
      for (final x in p.items) {
        if (seen.add(keyOf(x))) got.add(x);
      }
      offset += p.items.length;
      more = p.hasMore && p.items.isNotEmpty;
      next = p.next;
      if (!more || got.length >= want) break;
    }
    _reloading = false;
    if (failedAt == 0) {
      _failed = true;
    } else {
      _failed = false;
      _loaded = true;
      _items = List.unmodifiable(got);
      _offset = offset;
      _hasMore = more;
      _next = next;
      // فشلٌ بعد صفحاتٍ من التحديث بالعمق: ما وصل يُعرض، والباقي بـ«أعد المحاولة»
      _moreFailed = failedAt > 0;
      _total = total;
      _sendable = sendable;
    }
    _notify();
  }

  /// «تحميل المزيد»: العشرة التالية بعد آخر ما عُرض.
  Future<void> loadMore() async {
    if (_reloading || _loadingMore || !_hasMore) return;
    final seq = _seq;
    _loadingMore = true;
    _moreFailed = false;
    _notify();
    final p = await fetch(before: _next, have: _offset, size: pageSize);
    if (_disposed || seq != _seq) return;
    _loadingMore = false;
    if (p == null) {
      _moreFailed = true;
    } else {
      final seen = {for (final x in _items) keyOf(x)};
      _items = List.unmodifiable([..._items, ...p.items.where((x) => seen.add(keyOf(x)))]);
      _offset += p.items.length;
      _hasMore = p.hasMore && p.items.isNotEmpty;
      _next = p.next;
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// قائمةٌ في الذاكرة (الطافية الآن، المتذبذبة، القراءات الحسّاسة، الكهرباء، تنبيهات الموبايل): ١٠ أوّلاً، و«تحميل المزيد» يكشف
/// ١٠ أخرى. العدّاد فوقها يبقى عدد القائمة كلّها.
class AlertsReveal {
  AlertsReveal([this.step = 10]) : _shown = step;

  final int step;
  int _shown;

  int get shown => _shown;
  List<T> take<T>(List<T> all) => all.length <= _shown ? all : all.sublist(0, _shown);
  bool hasMore(List<Object?> all) => all.length > _shown;
  void more() => _shown += step;
}

/// «تحميل المزيد» أسفل قائمة تنبيهات: يدور وهو يجلب، وبعد فشلٍ «تعذّر التحميل — أعد المحاولة» (ما عُرض باقٍ).
class AlertsMoreButton extends StatelessWidget {
  const AlertsMoreButton({super.key, required this.onTap, this.busy = false, this.failed = false});

  final VoidCallback onTap;
  final bool busy;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(failed ? LucideIcons.refreshCw : LucideIcons.chevronDown, size: 18),
      label: Text(failed ? 'تعذّر التحميل — أعد المحاولة' : 'تحميل المزيد', maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        foregroundColor: failed ? AppColors.error : null,
        side: failed ? BorderSide(color: AppColors.error) : null,
      ),
    );
  }
}
