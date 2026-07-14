import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/broadcast_api.dart';
import '../../api/send_scope_api.dart';
import '../../api/subscribers_api.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../message_logs/message_logs_screen.dart';

/// شاشة "التبليغات" (Broadcast) — نقل حرفي من client-v2/Notifications.tsx.
/// يسمح للمدير بإرسال رسائل واتساب جماعيّة للمشتركين حسب فلتر (كل/مدينون/
/// منتهي/قرب انتهاء) مع نطاق إرسال (عام/محدّد) + محرّر متغيّرات.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

enum _Filter { all, debtors, expired, expiring }
enum _Scope { all, specific }

class _BroadcastScreenState extends State<BroadcastScreen> {
  _Filter _filter = _Filter.all;
  _Scope _scope = _Scope.all;
  final Set<String> _selected = <String>{};
  final TextEditingController _msg = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _msgFocus = FocusNode();

  List<Subscriber> _subs = const [];
  bool _loading = true;
  bool _sending = false;
  bool _retrying = false;

  /// المدراء الفرعيون المتاحون للفلترة (من SendScopeApi.fetch).
  /// null = لم يُحمَّل بعد. فارغة = المدير ما عنده مدراء فرعيون —
  /// فلتر المدير يُخفى.
  List<String>? _subManagers;
  /// selectedSubManagers = null أو فارغة → "الكل" (بدون فلترة).
  /// خلاف ذلك = فقط مشتركو هؤلاء المدراء.
  final Set<String> _managerFilter = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    _loadScope();
  }

  Future<void> _loadScope() async {
    final s = await SendScopeApi.fetch();
    if (!mounted) return;
    setState(() => _subManagers = s?.subManagers ?? const []);
  }

  @override
  void dispose() {
    _msg.dispose();
    _search.dispose();
    _msgFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final subs = await SubscribersApi.loadAll();
    if (!mounted) return;
    setState(() {
      _subs = subs ?? const [];
      _loading = false;
    });
  }

  // ─── فلاتر ─────────────────────────────────────

  List<Subscriber> get _withPhone => _subs
      .where((s) =>
          (s.phone?.length ?? 0) >= 10 || (s.mobile?.length ?? 0) >= 10)
      .toList();

  /// المشتركون بعد فلتر الفئة (all/debtors/expired/expiring).
  List<Subscriber> get _byCategory {
    switch (_filter) {
      case _Filter.all:
        return _withPhone;
      case _Filter.debtors:
        return _withPhone.where((s) {
          if (s.hasDebtFlag) return true;
          if ((s.debt ?? 0) > 0) return true;
          final n = double.tryParse((s.notes ?? '0').replaceAll(',', ''));
          return n != null && n < 0;
        }).toList();
      case _Filter.expired:
        return _withPhone.where((s) => s.isExpired).toList();
      case _Filter.expiring:
        return _withPhone.where((s) => s.isNearExpiry).toList();
    }
  }

  /// المرشّحون النهائيون = فلتر الفئة + (اختياراً) فلتر مدير الأب.
  /// لو _managerFilter فارغة = بدون قيود مدير.
  List<Subscriber> get _candidates {
    if (_managerFilter.isEmpty) return _byCategory;
    final allowedLower = _managerFilter.map((m) => m.toLowerCase()).toSet();
    return _byCategory.where((s) {
      final p = (s.parentUsername ?? '').toLowerCase();
      return allowedLower.contains(p);
    }).toList();
  }

  List<Subscriber> get _visibleCandidates {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _candidates;
    return _candidates.where((s) {
      return s.username.toLowerCase().contains(q) ||
          s.firstname.toLowerCase().contains(q) ||
          s.lastname.toLowerCase().contains(q) ||
          (s.phone ?? '').contains(q) ||
          (s.mobile ?? '').contains(q);
    }).toList();
  }

  List<Subscriber> get _targets => _scope == _Scope.all
      ? _candidates
      : _candidates.where((s) => _selected.contains(s.username)).toList();

  Map<_Filter, int> get _counts {
    int debtors = 0;
    int expired = 0;
    int expiring = 0;
    for (final s in _withPhone) {
      final hasDebt = s.hasDebtFlag ||
          (s.debt ?? 0) > 0 ||
          (double.tryParse((s.notes ?? '0').replaceAll(',', '')) ?? 0) < 0;
      if (hasDebt) debtors++;
      if (s.isExpired) expired++;
      if (s.isNearExpiry) expiring++;
    }
    return {
      _Filter.all: _withPhone.length,
      _Filter.debtors: debtors,
      _Filter.expired: expired,
      _Filter.expiring: expiring,
    };
  }

  MessageIntent get _intent {
    switch (_filter) {
      case _Filter.all:
        return MessageIntent.general;
      case _Filter.debtors:
        return MessageIntent.debtors;
      case _Filter.expired:
        return MessageIntent.expired;
      case _Filter.expiring:
        return MessageIntent.expiring;
    }
  }

  bool get _messageOptional => _intent.messageOptional;

  bool get _canSend =>
      !_sending &&
      _targets.isNotEmpty &&
      (_messageOptional || _msg.text.trim().isNotEmpty) &&
      Perms.has('whatsapp.broadcast');

  // ─── actions ─────────────────────────────────────

  void _selectFilter(_Filter f) {
    setState(() {
      _filter = f;
      _selected.clear();
    });
  }

  void _toggleSelect(String username) {
    setState(() {
      if (_selected.contains(username)) {
        _selected.remove(username);
      } else {
        _selected.add(username);
      }
    });
  }

  void _toggleSelectAllVisible() {
    setState(() {
      final visible = _visibleCandidates;
      final allSelected = visible.every((s) => _selected.contains(s.username));
      if (allSelected) {
        for (final s in visible) {
          _selected.remove(s.username);
        }
      } else {
        for (final s in visible) {
          _selected.add(s.username);
        }
      }
    });
  }

  void _insertVariable(String token) {
    HapticFeedback.selectionClick();
    final sel = _msg.selection;
    final txt = _msg.text;
    final start = sel.start < 0 ? txt.length : sel.start;
    final end = sel.end < 0 ? txt.length : sel.end;
    final next =
        txt.substring(0, start) + token + (start == txt.length ? '' : txt.substring(end));
    final needsSpace = start > 0 && !txt.substring(0, start).endsWith(' ');
    final withSpace = needsSpace ? ' $token' : token;
    final finalText =
        txt.substring(0, start) + withSpace + txt.substring(end);
    _msg.value = TextEditingValue(
      text: finalText,
      selection: TextSelection.collapsed(offset: start + withSpace.length),
    );
    _msgFocus.requestFocus();
  }

  Future<void> _send() async {
    final targets = _targets;
    if (targets.isEmpty) return;
    final confirm = await _confirmDialog(
      'إرسال الرسالة',
      'إرسال إلى ${targets.length} مشترك؟',
      confirmLabel: 'إرسال',
      confirmColor: AppColors.brand,
    );
    if (confirm != true) return;
    setState(() => _sending = true);
    final r = await BroadcastApi.broadcast(
      intent: _intent,
      message: _msg.text.trim(),
      targetUsernames: _scope == _Scope.specific
          ? targets.map((t) => t.username).toList()
          : null,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _snack(
        'تم إرسال ${r.queued ?? targets.length} رسالة إلى الطابور',
        isError: false,
      );
      setState(() {
        _msg.clear();
        _selected.clear();
      });
    } else {
      _snack(r.message ?? 'فشل الإرسال', isError: true);
    }
  }

  Future<void> _retryFailed() async {
    final confirm = await _confirmDialog(
      'إعادة الفاشلة',
      'إعادة محاولة الرسائل الفاشلة من آخر 24 ساعة؟',
      confirmLabel: 'إعادة',
      confirmColor: const Color(0xFFE08F2D),
    );
    if (confirm != true) return;
    setState(() => _retrying = true);
    final r = await BroadcastApi.retryFailed();
    if (!mounted) return;
    setState(() => _retrying = false);
    _snack(
      r.ok ? (r.message ?? 'تمّت إعادة المحاولة') : (r.message ?? 'فشلت إعادة المحاولة'),
      isError: !r.ok,
    );
  }

  void _openLogs() {
    // نفتح الشاشة الكاملة بدل الورقة السفلية — تدعم كل الأنواع + بحث +
    // فلاتر + auto-refresh للـpending، وأي رسالة بعثتها الآن رح تظهر
    // مباشرةً بحالة "انتظار" ثم تتحول لـ"أُرسلت" تلقائياً.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MessageLogsScreen(),
      ),
    );
  }

  Future<bool?> _confirmDialog(
    String title,
    String message, {
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title,
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text(message,
            style: AppType.subtitle(color: AppColors.textMid)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel,
                style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── UI ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bell, size: 16, color: AppColors.brand),
            const SizedBox(width: 6),
            Text(
              'التبليغات',
              style:
                  AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
            ),
          ],
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                          Sp.lg, Sp.md, Sp.lg, Sp.huge),
                      children: [
                        _buildFilterCard(),
                        // فلتر مدير فرعي — يظهر فقط لو المدير الرئيسي
                        // عنده مدراء تحته (matches SendScopePanel visibility).
                        if ((_subManagers ?? const []).isNotEmpty) ...[
                          const SizedBox(height: Sp.md),
                          _buildManagerFilterCard(),
                        ],
                        const SizedBox(height: Sp.md),
                        _buildScopeCard(),
                        if (_scope == _Scope.specific &&
                            _candidates.isNotEmpty) ...[
                          const SizedBox(height: Sp.md),
                          _buildSelectionCard(),
                        ],
                        const SizedBox(height: Sp.md),
                        _buildMessageCard(),
                      ],
                    ),
                  ),
                ),
                _buildActionBar(),
              ],
            ),
    );
  }

  // ─── Sections ─────────────────────────────

  Widget _buildFilterCard() {
    final counts = _counts;
    return _sectionCard(
      icon: LucideIcons.users,
      title: 'الفئة',
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _filterChip(_Filter.all, 'كل المشتركين', LucideIcons.users,
                  counts[_Filter.all] ?? 0, AppColors.brand),
              _filterChip(
                  _Filter.debtors,
                  'المدينون',
                  LucideIcons.wallet,
                  counts[_Filter.debtors] ?? 0,
                  const Color(0xFFE11D48)),
              _filterChip(_Filter.expired, 'منتهي الصلاحية',
                  LucideIcons.clock, counts[_Filter.expired] ?? 0, AppColors.error),
              _filterChip(
                  _Filter.expiring,
                  'قرب الانتهاء (3 أيام)',
                  LucideIcons.triangleAlert,
                  counts[_Filter.expiring] ?? 0,
                  const Color(0xFFE08F2D)),
            ],
          ),
          if (_candidates.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE08F2D).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.triangleAlert,
                      size: 12, color: Color(0xFFE08F2D)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'لا يوجد مشتركون يطابقون الفئة (يحتاجون أرقام هواتف صالحة)',
                      style: AppType.muted().copyWith(
                          fontSize: 10.5,
                          color: const Color(0xFFE08F2D)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(_Filter f, String label, IconData icon, int count, Color color) {
    final active = _filter == f;
    return Material(
      color: active ? color.withValues(alpha: 0.1) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectFilter(f),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? color.withValues(alpha: 0.4) : AppColors.border,
              width: active ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 14, color: active ? color : AppColors.textMid),
                  Text(
                    count.toString(),
                    style: AppType.title(
                            color: active ? color : AppColors.textHi)
                        .copyWith(fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppType.muted().copyWith(
                    fontSize: 10.5,
                    color: active ? color : AppColors.textMid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// كارت فلتر المدير الفرعي — يظهر فقط لمن عنده مدراء فرعيون.
  /// التحديد فارغ = بدون قيد (كل المدراء).
  Widget _buildManagerFilterCard() {
    final mgrs = _subManagers ?? const <String>[];
    final allSelected = _managerFilter.isEmpty;
    return _sectionCard(
      icon: LucideIcons.userCog,
      title: allSelected
          ? 'الفلترة حسب المدير (الكل)'
          : 'الفلترة حسب المدير (${_managerFilter.length}/${mgrs.length})',
      trailing: allSelected
          ? null
          : TextButton.icon(
              onPressed: () {
                setState(() {
                  _managerFilter.clear();
                  _selected.clear();
                });
              },
              icon: Icon(LucideIcons.x, size: 12, color: AppColors.textMid),
              label: Text(
                'مسح',
                style: AppType.button(color: AppColors.textMid)
                    .copyWith(fontSize: 11),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اختر مدراء لإرسال الرسائل لمشتركيهم فقط',
            style: AppType.muted().copyWith(fontSize: 10.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final u in mgrs)
                _managerFilterChip(
                  username: u,
                  checked: _managerFilter.contains(u),
                  onToggle: (nowChecked) {
                    setState(() {
                      if (nowChecked) {
                        _managerFilter.add(u);
                      } else {
                        _managerFilter.remove(u);
                      }
                      _selected.clear(); // تنظيف الاختيار المحدَّد اليدوي
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _managerFilterChip({
    required String username,
    required bool checked,
    required ValueChanged<bool> onToggle,
  }) {
    return Material(
      color: checked
          ? AppColors.brand.withValues(alpha: 0.1)
          : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onToggle(!checked),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: checked
                  ? AppColors.brand.withValues(alpha: 0.4)
                  : AppColors.border,
              width: checked ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                checked ? LucideIcons.squareCheck : LucideIcons.square,
                size: 12,
                color: checked ? AppColors.brand : AppColors.textLow,
              ),
              const SizedBox(width: 4),
              Text(
                username,
                style: AppType.button(
                  color: checked ? AppColors.brand : AppColors.textMid,
                ).copyWith(fontSize: 10.5, fontFamily: 'monospace'),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeCard() {
    return _sectionCard(
      icon: LucideIcons.layers,
      title: 'نطاق الإرسال',
      child: Row(
        children: [
          Expanded(
            child: _scopeChip(
              _Scope.all,
              icon: LucideIcons.layers,
              title: 'عام',
              subtitle: 'للكل (${_candidates.length})',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _scopeChip(
              _Scope.specific,
              icon: LucideIcons.userCheck,
              title: 'محدّد',
              subtitle: _selected.isEmpty
                  ? 'اختر يدوياً'
                  : '${_selected.length} مختار',
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeChip(_Scope s,
      {required IconData icon,
      required String title,
      required String subtitle}) {
    final active = _scope == s;
    return Material(
      color: active
          ? AppColors.brand.withValues(alpha: 0.1)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _scope = s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: active
                  ? AppColors.brand.withValues(alpha: 0.4)
                  : AppColors.border,
              width: active ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? AppColors.brand : AppColors.textMid),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 12),
                    ),
                    Text(
                      subtitle,
                      style: AppType.muted().copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionCard() {
    final visible = _visibleCandidates;
    final allSelected = visible.isNotEmpty &&
        visible.every((s) => _selected.contains(s.username));
    return _sectionCard(
      icon: LucideIcons.userCheck,
      title: 'اختيار المشتركين (${_selected.length}/${_candidates.length})',
      trailing: TextButton.icon(
        onPressed: _toggleSelectAllVisible,
        icon: Icon(
          allSelected ? LucideIcons.square : LucideIcons.squareCheck,
          size: 14,
          color: AppColors.brand,
        ),
        label: Text(
          allSelected ? 'إلغاء الكل' : 'تحديد الكل',
          style: AppType.button(color: AppColors.brand)
              .copyWith(fontSize: 11),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
      child: Column(
        children: [
          // Search
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الهاتف…',
              hintStyle: AppType.muted().copyWith(fontSize: 12),
              prefixIcon: Icon(LucideIcons.search,
                  size: 14, color: AppColors.textMid),
              filled: true,
              fillColor: AppColors.surfaceInput,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.brand),
              ),
            ),
            style: AppType.input(color: AppColors.textHi)
                .copyWith(fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'لا نتائج',
                style: AppType.muted().copyWith(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(R.sm),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) => _candidateTile(visible[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _candidateTile(Subscriber s) {
    final isSel = _selected.contains(s.username);
    return InkWell(
      onTap: () => _toggleSelect(s.username),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: isSel ? AppColors.brand.withValues(alpha: 0.06) : null,
        child: Row(
          children: [
            Icon(
              isSel ? LucideIcons.squareCheck : LucideIcons.square,
              size: 16,
              color: isSel ? AppColors.brand : AppColors.textLow,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.fullName,
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Text(
                        s.username,
                        style: AppType.muted().copyWith(fontSize: 10),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.textLow,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.phone ?? s.mobile ?? '',
                        style: AppType.muted().copyWith(
                            fontSize: 10, fontFamily: 'monospace'),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard() {
    return _sectionCard(
      icon: LucideIcons.messageSquare,
      title: 'الرسالة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Variables strip
          Text('اضغط متغيّراً لإدراجه:',
              style: AppType.muted().copyWith(fontSize: 10)),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: BroadcastVariables.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final v = BroadcastVariables.all[i];
                return Material(
                  color: AppColors.brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(R.pill),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _insertVariable(v.token),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.plus,
                              size: 11, color: AppColors.brand),
                          const SizedBox(width: 3),
                          Text(
                            v.label,
                            style: AppType.button(color: AppColors.brand)
                                .copyWith(fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Textarea
          TextField(
            controller: _msg,
            focusNode: _msgFocus,
            maxLines: 6,
            minLines: 4,
            maxLength: 2000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _messageOptional
                  ? 'اختياري — يستخدم القالب التلقائي لو فاضي'
                  : 'اكتب الرسالة هنا…',
              hintStyle: AppType.muted().copyWith(fontSize: 12),
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.brand),
              ),
              counterText: '',
              contentPadding: const EdgeInsets.all(12),
            ),
            style: AppType.input(color: AppColors.textHi)
                .copyWith(fontSize: 13, height: 1.55),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _messageOptional
                      ? 'لو فاضي، يُستخدم قالب افتراضي'
                      : 'المتغيرات تُستبدل تلقائياً لكل مشترك',
                  style: AppType.muted().copyWith(fontSize: 10),
                ),
              ),
              Text(
                '${_msg.text.length} / 2000',
                style: AppType.muted().copyWith(
                    fontSize: 10,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 10, Sp.lg, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
            top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _scope == _Scope.all
                        ? 'إرسال للكل'
                        : 'إرسال للمحدّدين',
                    style: AppType.muted().copyWith(fontSize: 10),
                  ),
                  Text(
                    '${_targets.length} مشترك',
                    style: AppType.title(color: AppColors.brand)
                        .copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
            // logs
            IconButton(
              tooltip: 'حالة الإرسال',
              icon: Icon(LucideIcons.history,
                  size: 18, color: AppColors.brand),
              onPressed: _openLogs,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brand.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(width: 6),
            // retry failed
            IconButton(
              tooltip: 'إعادة الفاشلة',
              icon: _retrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(LucideIcons.rotateCw,
                      size: 18, color: const Color(0xFFE08F2D)),
              onPressed: _retrying ? null : _retryFailed,
              style: IconButton.styleFrom(
                backgroundColor:
                    const Color(0xFFE08F2D).withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(width: 6),
            // send
            ElevatedButton.icon(
              onPressed: _canSend ? _send : null,
              icon: _sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 14),
              label: Text(
                _sending ? 'جاري الإرسال...' : 'إرسال',
                style: AppType.button(color: Colors.white)
                    .copyWith(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.brand.withValues(alpha: 0.4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.sm)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 12),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
