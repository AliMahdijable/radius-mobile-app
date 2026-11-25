import 'package:flutter/material.dart';

import '../../services/notif_sounds.dart';
import '../../theme/colors.dart';

/// لون كلّ عائلة (مربّع الأيقونة): الطلبات أخضر الهويّة، الأعطال أحمر، المال أزرق، والتذكيرات محايدة.
({Color fg, Color bg}) soundFamilyStyle(SoundFamily f) => switch (f) {
      SoundFamily.requests => (fg: AppColors.brand, bg: AppColors.brandSoftBg),
      SoundFamily.devices => (fg: AppColors.error, bg: AppColors.dangerSoftBg),
      SoundFamily.money => (fg: AppColors.info, bg: AppColors.infoSoftBg),
      SoundFamily.reminders => (fg: AppColors.textMid, bg: AppColors.surfaceInput),
    };

/// لون فئة: أجهزة المشتركين تحذيرٌ (كهرمانيّ) لا عطلٌ عندك (أحمر).
({Color fg, Color bg}) soundCategoryStyle(SoundCategory c) => c.id == 'sub_devices'
    ? (fg: AppColors.warning, bg: AppColors.warningSoftBg)
    : soundFamilyStyle(c.family);
