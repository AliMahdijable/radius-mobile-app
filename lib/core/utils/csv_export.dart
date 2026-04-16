import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CsvExport {
  static String buildCsvString({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final bom = '\uFEFF';
    final headerLine = headers.map(_escape).join(',');
    final dataLines = rows.map((r) => r.map(_escape).join(',')).join('\n');
    return '$bom$headerLine\n$dataLines';
  }

  static Future<void> exportAndShare({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final csv = buildCsvString(headers: headers, rows: rows);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csv, flush: true);

    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(file.path)]);
  }

  /// Opens the system save dialog (e.g. SAF on Android) so the user can pick
  /// Downloads or another folder on the device.
  static Future<String?> saveWithSystemPicker({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final csv = buildCsvString(headers: headers, rows: rows);
    final baseName = fileName.toLowerCase().endsWith('.csv')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final bytes = Uint8List.fromList(utf8.encode(csv));
    return FileSaver.instance.saveFile(
      name: baseName,
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  static String _escape(String v) {
    final clean = v.replaceAll('"', '""').replaceAll('\n', ' ');
    return '"$clean"';
  }
}
