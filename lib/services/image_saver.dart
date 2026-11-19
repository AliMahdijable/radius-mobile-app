import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// نتيجة «حفظ الصورة».
enum ImageSaveResult {
  /// حُفظت (بالهاتف: في الصور؛ بالحاسبة: حيث اختار المستخدم).
  saved,

  /// أغلق المستخدم نافذة الحفظ بلا اختيار (الحاسبة) — لا شيء حدث.
  cancelled,

  /// رفض المستخدم إذن إضافة الصور (آيفون).
  denied,

  /// الجهاز لا يدعم الحفظ المباشر (أندرويد أقدم من 10، أو منصّة بلا قناة) — المشاركة بديله.
  unsupported,

  /// تعذّر الحفظ.
  failed,
}

/// «حفظ الصورة» (١٩ نوفمبر — رمز دخول المشترك؛ المالك: «نخلي إمكانية حفظ الكيو آر، مو بس مشاركة»).
///
/// - **أندرويد 10 فأحدث**: إلى صور الهاتف (`Pictures/MyServices`) عبر MediaStore — بلا أيّ إذن (الملفّ ملك التطبيق).
///   الأقدم ⇒ [ImageSaveResult.unsupported] (لا إذن تخزين في التطبيق: سياسة Play — انظر AndroidManifest)، والمستدعي يفتح
///   نافذة المشاركة.
/// - **آيفون**: إلى الصور بإذن «الإضافة فقط» (`NSPhotoLibraryAddUsageDescription`).
/// - **الحاسبة (ويندوز/ماك/لينكس)**: نافذة «حفظ باسم» — بلا قناةٍ أصليّة.
///
/// القناة `com.mysvcs.rad_mysvcs/media` في `MainActivity.kt` و`AppDelegate.swift`.
class ImageSaver {
  ImageSaver._();

  static const channel = MethodChannel('com.mysvcs.rad_mysvcs/media');

  /// الحاسبة؟ (تُستبدل في الاختبارات)
  @visibleForTesting
  static bool? debugDesktop;

  /// نافذة «حفظ باسم» ⇒ المسار المختار أو null إن أُغلقت. تُستبدل في الاختبارات (لا نافذة هناك).
  @visibleForTesting
  static Future<String?> Function(String suggestedName) pickPath = _pickPath;

  static bool get _desktop => debugDesktop ?? (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  static Future<String?> _pickPath(String suggestedName) async {
    final loc = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    return loc?.path;
  }

  /// اسم ملفٍّ آمن على كلّ المنصّات: لاتينيّ وأرقام و`_` و`-` وحدها (اسم المشترك قد يحمل `@` أو مسافات)، ≤ 80.
  static String safeName(String raw) {
    var s = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.length > 80) s = s.substring(0, 80);
    return s.isEmpty ? 'image' : s;
  }

  /// يحفظ صورة PNG باسم [name] (بلا الامتداد). لا يرمي.
  static Future<ImageSaveResult> savePng(Uint8List bytes, {required String name}) async {
    if (bytes.isEmpty) return ImageSaveResult.failed;
    final safe = safeName(name);
    try {
      if (kIsWeb) return ImageSaveResult.unsupported;
      if (_desktop) {
        final picked = await pickPath('$safe.png');
        if (picked == null || picked.isEmpty) return ImageSaveResult.cancelled;
        final path = picked.toLowerCase().endsWith('.png') ? picked : '$picked.png';
        await File(path).writeAsBytes(bytes, flush: true);
        return ImageSaveResult.saved;
      }
      final r = await channel.invokeMethod<String>('saveImage', {'bytes': bytes, 'name': safe});
      switch (r) {
        case 'saved':
          return ImageSaveResult.saved;
        case 'denied':
          return ImageSaveResult.denied;
        case 'unsupported':
          return ImageSaveResult.unsupported;
        default:
          return ImageSaveResult.failed;
      }
    } on MissingPluginException {
      return ImageSaveResult.unsupported;
    } catch (_) {
      return ImageSaveResult.failed;
    }
  }
}
