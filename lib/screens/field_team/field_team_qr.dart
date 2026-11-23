import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// رمز QR لرابط تطبيق الفريق — الأبيض والحبر الداكن شرطٌ لقراءته بالكاميرا في الوضعين (كبطاقة «دخول المشترك»)، فهذا الملفّ
/// وحده مستثنىً من حارس الألوان الخام.
class FieldTeamQr extends StatelessWidget {
  const FieldTeamQr({super.key, required this.data, this.size = 128});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: size,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        semanticsLabel: 'رمز QR لرابط تطبيق الفريق',
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0F1419)),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0F1419)),
      ),
    );
  }
}
