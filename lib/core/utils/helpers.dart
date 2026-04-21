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

  /// Format date to Arabic-friendly format (24h)
  static String formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final baghdad = toBaghdadTime(date);
    return intl.DateFormat('yyyy/MM/dd HH:mm').format(baghdad);
  }

  /// Format expiration / due date in 12-hour style with Arabic AM/PM.
  /// Example: "2026/04/25 ‏05:59 مساءً"
  ///
  /// SAS4 returns expirations as naive strings like "2026-04-20 20:46:00"
  /// that are **already in Baghdad time** — no timezone suffix. The
  /// previous implementation called DateTime.tryParse (which treats naive
  /// input as device-local) and then piped the result through
  /// toBaghdadTime, blindly adding another +3h. That made every expiration
  /// display 3 hours ahead of what SAS4 actually stored — a subscriber
  /// whose DB row said 20:46 rendered as 23:46 on the phone.
  ///
  /// Match the pattern used by subscriber_model / dashboard_provider /
  /// home_screen: append +03:00 for naive strings so the parser anchors
  /// them as Baghdad, and only convert when the string explicitly carries
  /// UTC (Z/+HH:MM).
  static String formatExpiration(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    final s = dateStr.trim();
    DateTime? date;
    if (s.contains('T') || s.contains('+') || s.endsWith('Z')) {
      date = DateTime.tryParse(s);
    } else {
      date = DateTime.tryParse('${s.replaceAll(' ', 'T')}+03:00');
    }
    if (date == null) return dateStr;
    final baghdad = date.isUtc ? toBaghdadTime(date) : date;
    final datePart = intl.DateFormat('yyyy/MM/dd').format(baghdad);
    return '$datePart  ${_twelveHourTime(baghdad, withSeconds: true)}';
  }

  /// 12-hour variant for report rows (yyyy/MM/dd hh:mm صباحاً/مساءً).
  /// Accepts either an ISO string (UTC → Baghdad conversion) or a local
  /// DateTime parsable string. Defaults to '—' when empty/invalid.
  /// Includes the 4-digit year so rows spanning years (e.g. financial
  /// statements across a New Year boundary) are unambiguous.
  static String formatReportDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final baghdad = date.isUtc ? toBaghdadTime(date) : date;
    final datePart = intl.DateFormat('yyyy/MM/dd').format(baghdad);
    return '$datePart  ${_twelveHourTime(baghdad)}';
  }

  /// 12h-only (hh:mm صباحاً/مساءً) for report rows that already show the date
  /// in a separate column.
  static String formatReportTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.isUtc ? toBaghdadTime(dt) : dt;
    return _twelveHourTime(local);
  }

  static String _twelveHourTime(DateTime dt, {bool withSeconds = false}) {
    final hour24 = dt.hour;
    final hour12 =
        hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    final meridiem = hour24 < 12 ? 'صباحاً' : 'مساءً';
    final timePart = withSeconds
        ? '${hour12.toString().padLeft(2, '0')}:$minute:$second'
        : '${hour12.toString().padLeft(2, '0')}:$minute';
    return '$timePart $meridiem';
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

  /// Format numbers in text (e.g. "السعر: -30000 IQD" → "السعر: 30,000 IQD")
  static String formatNumbersInText(String text) {
    return text.replaceAllMapped(
      RegExp(r'-?(\d{4,})'),
      (m) {
        final num = int.tryParse(m.group(1)!);
        if (num == null) return m.group(0)!;
        return intl.NumberFormat('#,###').format(num);
      },
    );
  }

  /// Parse debt from notes field (negative = debt)
  static double parseDebt(String? notes) {
    if (notes == null || notes.isEmpty) return 0;
    return double.tryParse(notes.replaceAll(',', '').trim()) ?? 0;
  }

  /// Check if subscriber has debt
  static bool hasDebt(String? notes) => parseDebt(notes) < 0;

  /// Check if subscriber is expired (remaining_days < 0 means truly expired)
  static bool isExpired(int? remainingDays) =>
      remainingDays != null && remainingDays < 0;

  /// Get status color for remaining days
  static Color getRemainingDaysColor(int? days) {
    if (days == null) return Colors.grey;
    if (days < 0) return Colors.red;
    if (days == 0) return Colors.deepOrange;
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
