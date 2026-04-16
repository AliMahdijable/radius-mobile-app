import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../core/services/encryption_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../widgets/app_snackbar.dart';

class _ImportRow {
  final String username;
  final String? arabicName;
  final double debtAmount;
  int? matchedId;
  String? matchedName;
  String status; // 'pending', 'loading', 'success', 'failed', 'not_found'

  _ImportRow({
    required this.username,
    this.arabicName,
    required this.debtAmount,
    this.matchedId,
    this.matchedName,
    this.status = 'pending',
  });
}

class DebtImportScreen extends ConsumerStatefulWidget {
  const DebtImportScreen({super.key});

  @override
  ConsumerState<DebtImportScreen> createState() => _DebtImportScreenState();
}

class _DebtImportScreenState extends ConsumerState<DebtImportScreen> {
  List<_ImportRow> _rows = [];
  bool _isLoading = false;
  bool _isMatchLoading = false;
  String? _fileName;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);
    _fileName = result.files.single.name;

    setState(() => _isLoading = true);

    try {
      final content = await file.readAsString(encoding: utf8);
      final lines = content
          .split(RegExp(r'[\r\n]+'))
          .where((l) => l.trim().isNotEmpty)
          .toList();

      if (lines.length < 2) {
        if (mounted) AppSnackBar.warning(context, 'الملف فارغ أو لا يحتوي على بيانات');
        setState(() => _isLoading = false);
        return;
      }

      final header = _parseCsvLine(lines.first);
      int usernameCol = -1;
      int balanceCol = -1;
      int nameCol = -1;

      for (int i = 0; i < header.length; i++) {
        final h = header[i].trim().toLowerCase();
        if (h.contains('username') || h.contains('المستخدم')) {
          usernameCol = i;
        } else if (h.contains('balance') || h.contains('الرصيد')) {
          balanceCol = i;
        } else if (h.contains('الاسم') || h.contains('arabic') || h.contains('firstname')) {
          nameCol = i;
        }
      }

      if (usernameCol == -1 || balanceCol == -1) {
        if (mounted) {
          AppSnackBar.error(context, 'لم يتم العثور على أعمدة المستخدم والرصيد');
        }
        setState(() => _isLoading = false);
        return;
      }

      final rows = <_ImportRow>[];
      for (int i = 1; i < lines.length; i++) {
        final cols = _parseCsvLine(lines[i]);
        if (cols.length <= usernameCol || cols.length <= balanceCol) continue;
        final username = cols[usernameCol].trim();
        if (username.isEmpty) continue;
        final balance = double.tryParse(cols[balanceCol].trim()) ?? 0;
        if (balance == 0) continue;
        final name = nameCol >= 0 && cols.length > nameCol
            ? cols[nameCol].trim()
            : null;
        rows.add(_ImportRow(
          username: username,
          arabicName: name,
          debtAmount: balance.abs(),
        ));
      }

      setState(() {
        _rows = rows;
        _isLoading = false;
      });

      if (rows.isNotEmpty) {
        _matchSubscribers();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) AppSnackBar.error(context, 'فشل قراءة الملف');
    }
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    bool inQuote = false;
    final buffer = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (c == ',' && !inQuote) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  Future<void> _matchSubscribers() async {
    final dio = ref.read(sas4DioProvider);

    setState(() => _isMatchLoading = true);

    try {
      final userMap = <String, Map<String, dynamic>>{};
      int page = 1;

      while (true) {
        final payload = EncryptionService.encrypt({
          'page': page,
          'count': 1000,
          'sortBy': 'username',
          'direction': 'asc',
          'search': '',
          'columns': ['idx', 'username', 'firstname', 'lastname'],
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

        List<dynamic> items = [];
        if (parsed is Map) {
          items = parsed['data'] as List? ?? [];
        } else if (parsed is List) {
          items = parsed;
        }

        for (final u in items) {
          if (u is! Map) continue;
          final uname = u['username']?.toString()?.toLowerCase();
          if (uname != null) userMap[uname] = Map<String, dynamic>.from(u);
          final shortName = uname?.split('@').first;
          if (shortName != null && shortName != uname) {
            userMap[shortName] = Map<String, dynamic>.from(u);
          }
        }

        if (items.isEmpty) break;
        page++;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      for (final row in _rows) {
        final key = row.username.toLowerCase();
        final match = userMap[key] ?? userMap[key.split('@').first];
        if (match != null) {
          row.matchedId = match['idx'] is int
              ? match['idx']
              : int.tryParse(match['idx']?.toString() ?? '');
          row.matchedName =
              '${match['firstname'] ?? ''} ${match['lastname'] ?? ''}'.trim();
        } else {
          row.status = 'not_found';
        }
      }

      setState(() => _isMatchLoading = false);
    } catch (e) {
      setState(() => _isMatchLoading = false);
      if (mounted) AppSnackBar.error(context, 'فشل مطابقة المشتركين');
    }
  }

  Future<void> _applyDebt(_ImportRow row) async {
    if (row.matchedId == null) return;
    final dio = ref.read(sas4DioProvider);

    setState(() => row.status = 'loading');

    try {
      final getResp = await dio.get('${ApiConstants.sas4GetUser}/${row.matchedId}');
      final userData = getResp.data is Map
          ? Map<String, dynamic>.from(getResp.data['data'] ?? getResp.data)
          : <String, dynamic>{};

      userData['notes'] = (-row.debtAmount).toString();
      userData.remove('id');
      userData.remove('idx');
      userData.remove('profile_details');

      final payload = EncryptionService.encrypt(userData);
      final putResp = await dio.put(
        '${ApiConstants.sas4GetUser}/${row.matchedId}',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final ok = putResp.statusCode == 200 || putResp.statusCode == 201;
      setState(() => row.status = ok ? 'success' : 'failed');
    } catch (e) {
      setState(() => row.status = 'failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('استيراد ديون المشتركين')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.warningColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppTheme.warningColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'اختر ملف CSV يحتوي على أعمدة "اسم المستخدم" و "الرصيد".\n'
                    'سيتم مطابقة المشتركين وعرض قائمة المعاينة قبل التطبيق.',
                    style: TextStyle(
                      color: AppTheme.warningColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickFile,
                icon: const Icon(Icons.file_upload_rounded),
                label: Text(_fileName ?? 'اختر ملف CSV'),
              ),
            ),
          ),
          if (_isLoading || _isMatchLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_rows.isNotEmpty && !_isLoading && !_isMatchLoading) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.table_chart_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${_rows.length} صف',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _StatLabel(
                    label: 'متطابق',
                    count: _rows.where((r) => r.matchedId != null).length,
                    color: AppTheme.successColor,
                  ),
                  const SizedBox(width: 12),
                  _StatLabel(
                    label: 'غير موجود',
                    count: _rows.where((r) => r.status == 'not_found').length,
                    color: AppTheme.dangerColor,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _rows.length,
                itemBuilder: (ctx, i) => _ImportRowCard(
                  row: _rows[i],
                  onApply: () => _applyDebt(_rows[i]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatLabel extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatLabel({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ImportRowCard extends StatelessWidget {
  final _ImportRow row;
  final VoidCallback onApply;

  const _ImportRowCard({
    required this.row,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNotFound = row.status == 'not_found';
    final isSuccess = row.status == 'success';
    final isFailed = row.status == 'failed';
    final isLoadingRow = row.status == 'loading';
    final canApply = row.matchedId != null && row.status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSuccess
            ? AppTheme.successColor.withOpacity(0.05)
            : isFailed
                ? AppTheme.dangerColor.withOpacity(0.05)
                : isNotFound
                    ? Colors.grey.withOpacity(0.05)
                    : theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSuccess
              ? AppTheme.successColor.withOpacity(0.3)
              : isFailed
                  ? AppTheme.dangerColor.withOpacity(0.3)
                  : isNotFound
                      ? Colors.grey.withOpacity(0.2)
                      : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.username,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          decoration:
                              isNotFound ? TextDecoration.lineThrough : null,
                          color: isNotFound ? Colors.grey : null,
                        ),
                      ),
                    ),
                    Text(
                      AppHelpers.formatMoney(row.debtAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.dangerColor,
                      ),
                    ),
                  ],
                ),
                if (row.matchedName != null && row.matchedName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    row.matchedName!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
                if (isNotFound) ...[
                  const SizedBox(height: 2),
                  Text(
                    'مشترك غير موجود',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.dangerColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isLoadingRow)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (isSuccess)
            const Icon(Icons.check_circle, color: AppTheme.successColor, size: 28)
          else if (isFailed)
            const Icon(Icons.error, color: AppTheme.dangerColor, size: 28)
          else if (canApply)
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: onApply,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
                child: const Text('إضافة دين'),
              ),
            )
          else if (isNotFound)
            Icon(Icons.person_off, color: Colors.grey.shade400, size: 24),
        ],
      ),
    );
  }
}
