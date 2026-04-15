import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CsvExport {
  static Future<void> exportAndShare({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final bom = '\uFEFF';
    final headerLine = headers.map(_escape).join(',');
    final dataLines =
        rows.map((r) => r.map(_escape).join(',')).join('\n');
    final csv = '$bom$headerLine\n$dataLines';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csv, flush: true);

    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(file.path)]);
  }

  static String _escape(String v) {
    final clean = v.replaceAll('"', '""').replaceAll('\n', ' ');
    return '"$clean"';
  }
}
