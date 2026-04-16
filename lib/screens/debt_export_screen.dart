import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../core/services/encryption_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../core/utils/csv_export.dart';
import '../widgets/app_snackbar.dart';
import 'package:intl/intl.dart' as intl;

class DebtExportScreen extends ConsumerStatefulWidget {
  const DebtExportScreen({super.key});

  @override
  ConsumerState<DebtExportScreen> createState() => _DebtExportScreenState();
}

class _DebtExportScreenState extends ConsumerState<DebtExportScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _debtors = [];
  bool _loaded = false;

  Future<void> _loadDebtors() async {
    final storage = ref.read(storageServiceProvider);
    final dio = ref.read(sas4DioProvider);
    final adminId = await storage.getAdminId();
    if (adminId == null) return;

    setState(() => _isLoading = true);

    try {
      final allUsers = <Map<String, dynamic>>[];
      int page = 1;

      while (true) {
        final payload = EncryptionService.encrypt({
          'page': page,
          'count': 1000,
          'sortBy': 'username',
          'direction': 'asc',
          'search': '',
          'columns': [
            'idx', 'username', 'firstname', 'lastname', 'name',
            'phone', 'mobile', 'balance', 'notes', 'comments',
          ],
          'status': -1,
          'connection': -1,
          'profile_id': -1,
          'parent_id': -1,
          'sub_users': 1,
          'mac': '',
        });

        final response = await dio.post(
          ApiConstants.sas4ListUsers,
          data: {'payload': payload},
          options: Options(contentType: 'application/x-www-form-urlencoded'),
        );

        dynamic parsed = response.data;
        if (parsed is String) parsed = EncryptionService.decrypt(parsed);

        List<dynamic> pageItems = [];
        if (parsed is Map) {
          final data = parsed['data'];
          if (data is List) pageItems = data;
        } else if (parsed is List) {
          pageItems = parsed;
        }

        for (final item in pageItems) {
          if (item is Map<String, dynamic>) allUsers.add(item);
        }

        if (pageItems.isEmpty) break;
        page++;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final debtors = allUsers.where((u) {
        final notesVal = _parseNum(u['notes'] ?? u['comments']);
        return notesVal != 0;
      }).toList();

      setState(() {
        _debtors = debtors;
        _isLoading = false;
        _loaded = true;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        AppSnackBar.error(context, 'فشل تحميل بيانات المشتركين');
      }
    }
  }

  double _parseNum(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString().replaceAll(',', '').trim()) ?? 0;
  }

  double _getDebt(Map<String, dynamic> u) {
    final notesVal = _parseNum(u['notes'] ?? u['comments']);
    return notesVal;
  }

  Future<void> _exportCsv() async {
    if (_debtors.isEmpty) return;

    final headers = ['اسم المستخدم', 'الاسم العربي', 'الاسم الكامل', 'الهاتف', 'الرصيد (balance)'];
    final rows = _debtors.map((u) {
      final firstname = u['firstname']?.toString() ?? '';
      final lastname = u['lastname']?.toString() ?? '';
      final phone = u['phone']?.toString() ?? u['mobile']?.toString() ?? '';
      final debt = _getDebt(u);
      return [
        u['username']?.toString() ?? '',
        firstname,
        '$firstname $lastname'.trim(),
        phone,
        debt.toStringAsFixed(0),
      ];
    }).toList();

    final date = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
    await CsvExport.exportAndShare(
      fileName: 'debtors-export-$date.csv',
      headers: headers,
      rows: rows,
    );

    if (mounted) {
      AppSnackBar.success(context, 'تم تصدير ${_debtors.length} مشترك');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('تصدير ديون المشتركين')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.infoColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppTheme.infoColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'سيتم تحميل جميع المشتركين وتصفية من لديهم ديون (رصيد غير صفري) ثم تصديرهم كملف CSV',
                    style: TextStyle(
                      color: AppTheme.infoColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_loaded && !_isLoading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _loadDebtors,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('تحميل بيانات المشتركين'),
                ),
              ),
            ),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_loaded && !_isLoading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.people, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${_debtors.length} مشترك بديون',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.file_download_rounded, size: 20),
                    label: const Text('تصدير CSV'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _debtors.length,
                itemBuilder: (ctx, i) {
                  final u = _debtors[i];
                  final debt = _getDebt(u);
                  final isNeg = debt < 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                u['username']?.toString() ?? '—',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          AppHelpers.formatMoney(debt.abs()),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isNeg ? AppTheme.dangerColor : AppTheme.successColor,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
