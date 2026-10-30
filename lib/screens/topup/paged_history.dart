import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/history_page.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

typedef HistoryFetch<T> = Future<HistoryPage<T>?> Function({String? before, String? query, required int limit});

/// «آخر العمليّات» بصفحات — ١٠ ثمّ «عرض المزيد»، وبحثٌ برقم العمليّة من الخادم.
///
/// المالك ٣٠ أكتوبر: «خلي ماكس يظهر ١٠ ويكمل يحمل ويبحث ع رقم عمليه… حتى ان صدف وكيل عنده عمليات شحن هواي ولفتره طويله
/// متصير القائمة مزعجه». الصفحة التالية = ما قبل آخر صفٍّ معروض (`before`)، فلا تكرار ولا قفز ولو وصلت عمليّةٌ جديدة. كلّ
/// تحميلٍ برقم: بحثٌ أحدث أو إعادة تحميلٍ تُسقط ردّ ما قبلها (لا تختلط قائمتان). فشل القراءة يُبقي ما عُرض.
class PagedHistoryController<T> extends ChangeNotifier {
  PagedHistoryController({
    required this.fetch,
    required this.idOf,
    this.pageSize = 10,
    this.debounce = const Duration(milliseconds: 400),
  });

  final HistoryFetch<T> fetch;
  final String Function(T row) idOf;
  final int pageSize;
  final Duration debounce;

  List<T> _rows = const [];
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _failed = false;
  bool _loaded = false;
  String _query = '';
  String? _term;
  int _seq = 0;
  Timer? _timer;
  bool _disposed = false;

  List<T> get rows => _rows;
  bool get hasMore => _hasMore;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get failed => _failed;

  /// النصّ كما كُتب في الحقل، والرقم الذي يُبحث به (null = بلا بحث).
  String get query => _query;
  String? get term => _term;

  /// المكتوب ليس رقم عمليّة — يقال تحت الحقل ولا يُرسل شيء.
  bool get badQuery {
    final q = _query.trim();
    return q.isNotEmpty && q != '#' && termOf(q) == null;
  }

  /// حقل البحث: حين تزيد العمليّات على صفحة، أو والبحث جارٍ.
  bool get showSearch => _query.isNotEmpty || _term != null || _hasMore || _rows.length >= pageSize;

  /// القسم يُرسم: له صفوف، أو بحثٌ جارٍ (فيقول «لا عمليّة برقم …»).
  bool get visible => _rows.isNotEmpty || _query.isNotEmpty || _term != null;

  /// رقم العمليّة كما يقبله الخادم: أرقامٌ/حروفٌ لاتينيّة وشرطة (١–٤٠)، العربيّة ⇒ لاتينيّة، و«#» في أوّله يُهمل.
  static String? termOf(String raw) {
    final s = raw
        .replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}')
        .replaceAllMapped(RegExp('[۰-۹]'), (m) => '${m[0]!.codeUnitAt(0) - 0x06F0}')
        .trim()
        .replaceFirst(RegExp(r'^#+'), '');
    return RegExp(r'^[0-9A-Za-z-]{1,40}$').hasMatch(s) ? s : null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// صفوفٌ معروفة قبل أوّل قراءة (من «النظرة») — لا تُرسم قائمةٌ فارغة ريثما تصل الصفحة الأولى.
  void seed(List<T> rows) {
    if (_loaded || _rows.isNotEmpty || rows.isEmpty) return;
    _rows = List.unmodifiable(rows.take(pageSize));
    _notify();
  }

  /// الصفحة الأولى بالبحث الحاليّ.
  Future<void> reload() async {
    final seq = ++_seq;
    _loading = true;
    _loadingMore = false;
    _notify();
    final p = await fetch(query: _term, limit: pageSize);
    if (_disposed || seq != _seq) return;
    _loading = false;
    if (p == null) {
      _failed = true;
    } else {
      _failed = false;
      _loaded = true;
      _rows = List.unmodifiable(p.rows);
      _hasMore = p.hasMore;
    }
    _notify();
  }

  /// «عرض المزيد»: ما قبل آخر صفٍّ معروض.
  Future<void> loadMore() async {
    if (_loadingMore || _loading || !_hasMore || _rows.isEmpty) return;
    final seq = _seq;
    _loadingMore = true;
    _notify();
    final p = await fetch(before: idOf(_rows.last), query: _term, limit: pageSize);
    if (_disposed || seq != _seq) return;
    _loadingMore = false;
    if (p == null) {
      _failed = true;
    } else {
      _failed = false;
      final seen = {for (final r in _rows) idOf(r)};
      _rows = List.unmodifiable([..._rows, ...p.rows.where((r) => !seen.contains(idOf(r)))]);
      _hasMore = p.hasMore;
    }
    _notify();
  }

  /// كتابةٌ في حقل البحث ⇒ بحثٌ بعد توقّفها. ما ليس رقماً لا يُرسل؛ والمسح يرجع للقائمة كلّها.
  void search(String raw) {
    _query = raw;
    _timer?.cancel();
    final q = raw.trim();
    final t = termOf(q);
    if (q.isNotEmpty && q != '#' && t == null) {
      _notify();
      return;
    }
    _timer = Timer(debounce, () {
      if (_disposed || (t == _term && _loaded)) return;
      _term = t;
      unawaited(reload());
    });
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// «آخر العمليّات» بصفحاتها: حقل البحث (حين يلزم)، الصفوف، «لا عمليّة برقم …»، و«عرض المزيد».
class PagedHistoryList<T> extends StatefulWidget {
  const PagedHistoryList({super.key, required this.history, required this.rowBuilder, this.divided = false});

  final PagedHistoryController<T> history;
  final Widget Function(T row) rowBuilder;

  /// خطٌّ بين الصفوف (صفوف «شحن الرصيد»)؛ صفوف pay الجزيرة بحشوتها.
  final bool divided;

  @override
  State<PagedHistoryList<T>> createState() => _PagedHistoryListState<T>();
}

class _PagedHistoryListState<T> extends State<PagedHistoryList<T>> {
  late final _search = TextEditingController(text: widget.history.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ListenableBuilder(
      listenable: widget.history,
      builder: (context, _) {
        final h = widget.history;
        final rows = h.rows;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (h.showSearch) ...[
              SheetSearchField(controller: _search, hint: 'ابحث برقم العمليّة', onChanged: h.search),
              if (h.badQuery) ...[
                const SizedBox(height: Sp.xs),
                Text('اكتب رقم العمليّة بالأرقام', style: AppType.muted(color: AppTone.danger.onSoft)),
              ],
              const SizedBox(height: Sp.md),
            ],
            if (rows.isEmpty && !h.loading && h.term != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.md),
                child: Text('لا عمليّة برقم ${h.term}', textAlign: TextAlign.center, style: AppType.muted()),
              ),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0 && widget.divided) Divider(height: Sp.lg, color: AppColors.divider),
              widget.rowBuilder(rows[i]),
            ],
            if (h.loading && rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Sp.lg),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandAccent),
                  ),
                ),
              ),
            if (h.failed && !h.loading) ...[
              const SizedBox(height: Sp.sm),
              Text('تعذّر تحميل السجلّ — حدّث الشاشة', style: AppType.muted(color: AppTone.danger.onSoft)),
            ],
            if (h.hasMore) ...[
              const SizedBox(height: Sp.sm),
              TextButton(
                onPressed: h.loadingMore ? null : h.loadMore,
                child: h.loadingMore
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandAccent),
                      )
                    : Text('عرض المزيد', style: AppType.link(color: AppColors.brandAccent)),
              ),
            ],
          ],
        );
      },
    );
  }
}
