import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../api/telegram_api.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';

/// telegramBindingsSheet — قائمة المشتركين المربوطين ببوت تلغرام.
/// - بحث نصّي (اسم / يوزر / phone)
/// - Unbind بضغطة (بتأكيد)
/// - عرض اسم المشترك الحقيقي (join مع subscribers list محلياً)
Future<void> showTelegramBindingsSheet(
  BuildContext context, {
  required String adminId,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _BindingsSheet(adminId: adminId, onChanged: onChanged),
  );
}

class _BindingsSheet extends StatefulWidget {
  const _BindingsSheet({required this.adminId, required this.onChanged});
  final String adminId;
  final VoidCallback onChanged;

  @override
  State<_BindingsSheet> createState() => _BindingsSheetState();
}

class _BindingsSheetState extends State<_BindingsSheet> {
  final _searchCtrl = TextEditingController();
  List<TelegramBinding> _all = const [];
  Map<String, Subscriber> _subsByIdx = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      TelegramApi.listBindings(widget.adminId),
      SubscribersApi.loadAll(),
    ]);
    if (!mounted) return;
    final bindings = results[0] as List<TelegramBinding>;
    final subs = (results[1] as List<Subscriber>?) ?? const [];
    final map = <String, Subscriber>{};
    for (final s in subs) {
      if (s.idx != null) map[s.idx!] = s;
    }
    setState(() {
      _all = bindings;
      _subsByIdx = map;
      _loading = false;
    });
  }

  Future<void> _unbind(TelegramBinding b) async {
    final sub = _subsByIdx[b.sas4Idx];
    final display = sub?.fullName ?? sub?.username ?? 'مشترك ${b.sas4Idx}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('فكّ الربط',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: Text('فكّ ربط "$display" من بوت تلغرام؟',
            style: const TextStyle(fontFamily: 'Cairo', height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('فكّ',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await TelegramApi.unbind(widget.adminId, b.sas4Idx);
    if (!mounted) return;
    if (done) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            const Text('تمّ فكّ الربط', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ));
      widget.onChanged();
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            const Text('فشل فكّ الربط', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  List<TelegramBinding> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((b) {
      final sub = _subsByIdx[b.sas4Idx];
      final hay = [
        sub?.fullName ?? '',
        sub?.username ?? '',
        sub?.phone ?? '',
        b.tgUsername ?? '',
        b.tgFirstName ?? '',
        b.sas4Idx,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.users,
                          color: AppColors.success, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المرتبطون',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textHi,
                              )),
                          const SizedBox(height: 2),
                          Text(
                            _searchCtrl.text.trim().isEmpty
                                ? '${_all.length} مشترك مربوط ببوت تلغرام'
                                : '${_filtered.length} من ${_all.length} مشترك مربوط ببوت تلغرام',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.x,
                          size: 20, color: AppColors.textMid),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceInput,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.search,
                          size: 16, color: AppColors.textMid),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: AppColors.textHi,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: 'بحث بالاسم / اليوزر / الرقم',
                            hintStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12.5,
                              color: AppColors.textLow,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        IconButton(
                          icon: Icon(LucideIcons.x,
                              size: 14, color: AppColors.textMid),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          splashRadius: 14,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // List
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _all.isEmpty
                        ? _emptyState()
                        : _filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'لا نتائج مطابقة للبحث',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: AppColors.textMid,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.only(bottom: 24),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) =>
                                    _bindingTile(_filtered[i]),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bindingTile(TelegramBinding b) {
    final sub = _subsByIdx[b.sas4Idx];
    final display = sub?.fullName ?? sub?.username ?? 'مشترك ${b.sas4Idx}';
    final tgHandle = b.tgUsername != null && b.tgUsername!.isNotEmpty
        ? '@${b.tgUsername}'
        : (b.tgFirstName ?? '');
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: null,
        child: Container(
          padding: const EdgeInsetsDirectional.only(
              start: 12, end: 4, top: 10, bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: b.isBlocked ? AppColors.error : AppColors.success,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF229ED9).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(17),
                ),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.send,
                    size: 15, color: Color(0xFF229ED9)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(display,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textHi,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (b.isBlocked) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.dangerSoftBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('محظور',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.error,
                                )),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (sub?.username != null) '@${sub!.username}',
                        if (tgHandle.isNotEmpty) tgHandle,
                      ].join(' · '),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMid,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon:
                    Icon(LucideIcons.unlink, size: 15, color: AppColors.error),
                onPressed: () => _unbind(b),
                tooltip: 'فكّ الربط',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.userX, size: 40, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text('لا يوجد مشتركون مربوطون بعد',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMid,
              )),
          const SizedBox(height: 6),
          Text('استعمل "ربط مشترك" أو "بث روابط جماعي"',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: AppColors.textLow,
              )),
        ],
      ),
    );
  }
}
