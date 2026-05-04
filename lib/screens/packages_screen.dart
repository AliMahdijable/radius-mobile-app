import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/encryption_service.dart';
import '../core/services/storage_service.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_snackbar.dart';

class _PriceItem {
  final int id;
  final String name;
  double cost;
  double price;
  double userPrice;

  _PriceItem({
    required this.id,
    required this.name,
    required this.cost,
    required this.price,
    required this.userPrice,
  });

  factory _PriceItem.fromJson(Map<String, dynamic> json) {
    return _PriceItem(
      id: _toInt(json['id']),
      name: json['name']?.toString() ?? '',
      cost: _toDouble(json['cost']),
      price: _toDouble(json['price']),
      userPrice: _toDouble(json['user_price']),
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  _PriceItem copyWith({double? price, double? userPrice}) {
    return _PriceItem(
      id: id,
      name: name,
      cost: cost,
      price: price ?? this.price,
      userPrice: userPrice ?? this.userPrice,
    );
  }
}

class _ManagerNode {
  final int id;
  final String username;
  final int? parentId;
  final int depth;

  _ManagerNode({
    required this.id,
    required this.username,
    this.parentId,
    this.depth = 0,
  });
}

class PackagesScreen extends ConsumerStatefulWidget {
  const PackagesScreen({super.key});

  @override
  ConsumerState<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends ConsumerState<PackagesScreen> {
  List<_ManagerNode> _managers = [];
  _ManagerNode? _selectedManager;
  List<_PriceItem> _priceList = [];
  List<_PriceItem> _originalPriceList = [];
  bool _loadingManagers = true;
  bool _loadingPrices = false;
  bool _saving = false;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _fetchManagers();
  }

  Dio get _sas4Dio => ref.read(sas4DioProvider);

  Future<void> _fetchManagers() async {
    final canAccessManagers =
        ref.read(authProvider).user?.canAccessManagers ?? false;
    if (!canAccessManagers) {
      setState(() => _loadingManagers = false);
      return;
    }

    setState(() => _loadingManagers = true);
    try {
      final res = await _sas4Dio.get(ApiConstants.sas4ManagerTree);
      final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
      final list = data is List ? data : [data];
      final flat = <_ManagerNode>[];
      _flatten(list, flat, 0);
      setState(() {
        _managers = flat;
        _loadingManagers = false;
      });
    } catch (e) {
      setState(() => _loadingManagers = false);
      if (mounted) AppSnackBar.error(context, 'فشل في جلب المدراء');
    }
  }

  void _flatten(List<dynamic> nodes, List<_ManagerNode> acc, int depth) {
    for (final n in nodes) {
      if (n is! Map) continue;
      acc.add(_ManagerNode(
        id: _PriceItem._toInt(n['id'] ?? n['manager_id']),
        username: n['username']?.toString() ?? n['name']?.toString() ?? 'مدير ${n['id']}',
        parentId: n['parent_id'] != null ? _PriceItem._toInt(n['parent_id']) : null,
        depth: depth,
      ));
      final children = n['children'];
      if (children is List && children.isNotEmpty) {
        _flatten(children, acc, depth + 1);
      }
    }
  }

  Future<void> _fetchPriceList(int managerId) async {
    setState(() {
      _loadingPrices = true;
      _priceList = [];
      _originalPriceList = [];
      _isDirty = false;
    });
    try {
      final res = await _sas4Dio.get('${ApiConstants.sas4PriceList}/$managerId');
      final data = res.data is Map ? (res.data['data'] ?? []) : res.data;
      final list = (data is List ? data : [])
          .map<_PriceItem>((e) => _PriceItem.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _priceList = list;
        _originalPriceList = list.map((e) => e.copyWith()).toList();
        _loadingPrices = false;
      });
    } catch (e) {
      setState(() => _loadingPrices = false);
      if (mounted) AppSnackBar.error(context, 'فشل في جلب أسعار الباقات');
    }
  }

  void _onPriceChange(int index, String field, String value) {
    final numVal = double.tryParse(value) ?? 0;
    setState(() {
      if (field == 'price') {
        _priceList[index] = _priceList[index].copyWith(price: numVal);
      } else {
        _priceList[index] = _priceList[index].copyWith(userPrice: numVal);
      }
      _isDirty = true;
    });
  }

  Future<void> _save() async {
    if (_selectedManager == null || _priceList.isEmpty || !_isDirty) return;

    setState(() => _saving = true);
    try {
      final payload = EncryptionService.encrypt({
        'manager_id': _selectedManager!.id,
        'priceList': _priceList
            .map((item) => {
                  'profile_id': item.id,
                  'profile_name': item.name,
                  'price': item.price,
                  'cost': item.cost,
                  'user_price': item.userPrice,
                })
            .toList(),
      });

      await _sas4Dio.post(
        ApiConstants.sas4PriceList,
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      setState(() {
        _originalPriceList = _priceList.map((e) => e.copyWith()).toList();
        _isDirty = false;
        _saving = false;
      });
      if (mounted) AppSnackBar.success(context, 'تم حفظ أسعار الباقات بنجاح');
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) AppSnackBar.error(context, 'فشل في حفظ أسعار الباقات');
    }
  }

  bool get _isRootManager =>
      _selectedManager != null && _selectedManager!.parentId == null;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final canAccessManagers = user?.canAccessManagers ?? false;
    // الموظف بحاجة packages.edit_prices لحفظ التغييرات. الأدمن العادي =
    // كل شيء مسموح. لو الفاعل موظف بدون الصلاحية، الحقول read-only.
    final canEditPrices = user?.hasEmployeePermission('packages.edit_prices') ?? true;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!canAccessManagers) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('تسعير الباقات',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 46,
                    color: theme.colorScheme.onSurface.withOpacity(0.35)),
                const SizedBox(height: 12),
                Text(
                  'لا تملك صلاحية الوصول إلى هذا القسم',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تسعير الباقات',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          if (_isDirty && !_saving && canEditPrices)
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              tooltip: 'حفظ الأسعار',
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Manager selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color ?? (isDark ? Colors.grey.shade900 : Colors.white),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _loadingManagers
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _selectedManager?.id,
                        hint: const Text('اختر المدير',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        items: _managers.map((m) {
                          final prefix = m.depth > 0
                              ? '${'  ' * m.depth}└ '
                              : '';
                          return DropdownMenuItem<int>(
                            value: m.id,
                            child: Text(
                              '$prefix${m.username}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: m.depth == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          final mgr = _managers.firstWhere((m) => m.id == id);
                          setState(() => _selectedManager = mgr);
                          _fetchPriceList(id);
                        },
                      ),
                    ),
            ),
          ),

          if (_isDirty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: AppTheme.actionButtonHeight,
                child: ElevatedButton.icon(
                  onPressed: (_saving || !canEditPrices) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _saving ? 'جاري الحفظ...' : 'حفظ الأسعار',
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Content
          Expanded(
            child: _buildContent(theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    if (_selectedManager == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: theme.colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text('اختر مديراً لعرض أسعار الباقات',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    color: theme.colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }

    if (_loadingPrices) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_priceList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded,
                size: 64, color: theme.colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text('لا توجد باقات لهذا المدير',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    color: theme.colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
      itemCount: _priceList.length,
      itemBuilder: (context, index) {
        final item = _priceList[index];
        final original = index < _originalPriceList.length
            ? _originalPriceList[index]
            : null;
        final changed = original != null &&
            (item.price != original.price ||
                item.userPrice != original.userPrice);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: theme.cardTheme.color ??
                (isDark ? Colors.grey.shade900 : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: changed
                ? Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1.5)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.wifi_rounded,
                          size: 20, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (changed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('معدّل',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Cost (read-only)
                    Expanded(
                      child: _PriceField(
                        label: 'الكلفة',
                        value: _isRootManager ? '—' : item.cost.toStringAsFixed(0),
                        readOnly: true,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Price (editable, disabled for root)
                    Expanded(
                      child: _PriceField(
                        label: 'السعر',
                        value: item.price.toStringAsFixed(0),
                        readOnly: _isRootManager,
                        isDark: isDark,
                        onChanged: _isRootManager
                            ? null
                            : (v) => _onPriceChange(index, 'price', v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // User price (always editable)
                    Expanded(
                      child: _PriceField(
                        label: 'سعر البيع',
                        value: item.userPrice.toStringAsFixed(0),
                        readOnly: false,
                        isDark: isDark,
                        highlight: true,
                        onChanged: (v) =>
                            _onPriceChange(index, 'user_price', v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PriceField extends StatefulWidget {
  final String label;
  final String value;
  final bool readOnly;
  final bool isDark;
  final bool highlight;
  final ValueChanged<String>? onChanged;

  const _PriceField({
    required this.label,
    required this.value,
    required this.readOnly,
    required this.isDark,
    this.highlight = false,
    this.onChanged,
  });

  @override
  State<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<_PriceField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _PriceField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            )),
        const SizedBox(height: 4),
        widget.readOnly
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    widget.value,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ),
              )
            : TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: widget.highlight
                      ? AppTheme.primary
                      : theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: widget.highlight
                          ? AppTheme.primary.withOpacity(0.3)
                          : theme.colorScheme.onSurface.withOpacity(0.15),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: widget.highlight
                          ? AppTheme.primary.withOpacity(0.3)
                          : theme.colorScheme.onSurface.withOpacity(0.15),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: widget.highlight
                      ? AppTheme.primary.withOpacity(0.04)
                      : null,
                ),
                onChanged: widget.onChanged,
              ),
      ],
    );
  }
}
