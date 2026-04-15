import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../constants/app_constants.dart';

class AppHelpers {
  /// Convert UTC time to Baghdad time (UTC+3)
  static DateTime toBaghdadTime(DateTime utcTime) {
    return utcTime.add(const Duration(hours: AppConstants.baghdadUtcOffset));
  }

  /// Format date to Arabic-friendly format
  static String formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final baghdad = toBaghdadTime(date);
    return intl.DateFormat('yyyy/MM/dd HH:mm').format(baghdad);
  }

  /// Format date relative (e.g., "منذ 5 دقائق")
  static String formatRelative(String? dateStr) {
    if (dateStr == null) return '—';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final diff = DateTime.now().toUtc().difference(date);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
    return formatDate(dateStr);
  }

  /// Format money with IQD currency
  static String formatMoney(dynamic amount) {
    if (amount == null) return '0';
    final num value;
    if (amount is String) {
      value = num.tryParse(amount) ?? 0;
    } else {
      value = amount as num;
    }
    final formatter = intl.NumberFormat('#,###');
    return '${formatter.format(value.abs())} IQD';
  }

  /// Parse debt from notes field (negative = debt)
  static double parseDebt(String? notes) {
    if (notes == null || notes.isEmpty) return 0;
    return double.tryParse(notes) ?? 0;
  }

  /// Check if subscriber has debt
  static bool hasDebt(String? notes) => parseDebt(notes) < 0;

  /// Check if subscriber is expired
  static bool isExpired(int? remainingDays) =>
      remainingDays != null && remainingDays < 0;

  /// Get status color for remaining days
  static Color getRemainingDaysColor(int? days) {
    if (days == null) return Colors.grey;
    if (days < 0) return Colors.red;
    if (days <= 3) return Colors.orange;
    if (days <= 7) return Colors.amber;
    return Colors.green;
  }

  /// Get message status color
  static Color getStatusColor(String status) {
    switch (status) {
      case MessageStatuses.pending:
        return Colors.orange;
      case MessageStatuses.processing:
        return Colors.blue;
      case MessageStatuses.sent:
        return Colors.green;
      case MessageStatuses.failed:
        return Colors.red;
      case MessageStatuses.cancelled:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  /// Get message type icon
  static IconData getMessageTypeIcon(String type) {
    switch (type) {
      case MessageTypes.debtReminder:
        return Icons.credit_card;
      case MessageTypes.expiryWarning:
        return Icons.warning_amber;
      case MessageTypes.serviceEnd:
        return Icons.event_busy;
      case MessageTypes.broadcast:
        return Icons.campaign;
      case MessageTypes.manual:
        return Icons.touch_app;
      case MessageTypes.activationNotice:
        return Icons.check_circle;
      case MessageTypes.payment:
        return Icons.payments;
      case MessageTypes.welcomeMessage:
        return Icons.waving_hand;
      case MessageTypes.renewal:
        return Icons.autorenew;
      default:
        return Icons.message;
    }
  }

  /// Decode base64 QR code image
  static Uint8List? decodeQrImage(String? qrCode) {
    if (qrCode == null || qrCode.isEmpty) return null;
    final stripped = qrCode.replaceFirst(
      RegExp(r'data:image/\w+;base64,'),
      '',
    );
    try {
      return base64.decode(stripped);
    } catch (_) {
      return null;
    }
  }

  /// Format phone number for display
  static String formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '—';
    if (phone.startsWith('964')) {
      return '0${phone.substring(3)}';
    }
    return phone;
  }

  /// Get weekday name in Arabic
  static String getArabicWeekday(int day) {
    const days = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];
    return days[day % 7];
  }
}
