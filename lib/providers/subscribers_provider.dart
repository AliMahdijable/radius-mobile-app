import 'dart:developer' as dev;
import 'package:intl/intl.dart' as intl;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../core/services/encryption_service.dart';
import '../models/subscriber_model.dart';
import 'dashboard_provider.dart';
import 'reports_provider.dart';

class SubscribersState {
  final List<SubscriberModel> subscribers;
  final List<SubscriberModel> searchResults;
  final List<SubscriberModel> onlineUsers;
  final List<PackageModel> packages;
  final bool isLoading;
  final bool isSearching;
  final String? error;
  final int totalRecords;
  final String filter;
  final String sortBy;
  final String sortDirection;
  final Map<String, Map<String, dynamic>> lastPayments;
  final String? managerFilter;
  final int? sas4OfflineCount;

  const SubscribersState({
    this.subscribers = const [],
    this.searchResults = const [],
    this.onlineUsers = const [],
    this.packages = const [],
    this.isLoading = false,
    this.isSearching = false,
    this.error,
    this.totalRecords = 0,
    this.filter = 'all',
    // Default sort: newest activation first. remaining_days desc puts
    // freshly-renewed subs at the top and pushes expired ones to the
    // bottom — matches the admin's expected mental model when the
    // "الكل" tab opens.
    this.sortBy = 'remaining_days',
    this.sortDirection = 'desc',
    this.lastPayments = const {},
    this.managerFilter,
    this.sas4OfflineCount,
  });

  List<String> get availableManagers {
    final set = <String>{};
    for (final s in subscribers) {
      if (s.parentUsername != null && s.parentUsername!.isNotEmpty) {
        set.add(s.parentUsername!);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  List<SubscriberModel> get filteredSubscribers {
    List<SubscriberModel> source = managerFilter != null
        ? subscribers.where((s) => s.parentUsername == managerFilter).toList()
        : List.of(subscribers);

    List<SubscriberModel> list;
    switch (filter) {
      case 'active':
        list = source.where((s) => s.isActive).toList();
        break;
      case 'expired':
        list = source.where((s) => s.isExpired).toList();
        break;
      case 'online':
        if (managerFilter != null) {
          list = source.where((s) => s.isOnline).toList();
        } else {
          list = onlineUsers.isNotEmpty
              ? List.of(onlineUsers)
              : source.where((s) => s.isOnline).toList();
        }
        break;
      case 'offline':
        list = source.where((s) => s.isOffline).toList();
        break;
      case 'disabled':
        list = source.where((s) => s.isDisabled).toList();
        break;
      case 'debtors':
        list = source.where((s) => s.hasDebt).toList();
        break;
      case 'nearExpiry':
        list = source.where((s) => s.isNearExpiry).toList();
        // sort handled by _defaultSortByFilter + _applySorting below
        break;
      default:
        list = source;
    }
    return _applySorting(list);
  }

  List<SubscriberModel> _applySorting(List<SubscriberModel> list) {
    final asc = sortDirection == 'asc';
    list.sort((a, b) {
      int result;
      switch (sortBy) {
        case 'name':
          result = (a.profileName ?? '').compareTo(b.profileName ?? '');
          break;
        case 'mobile':
          result = (a.displayPhone).compareTo(b.displayPhone);
          break;
        case 'expiration':
          result = (a.expiration ?? '').compareTo(b.expiration ?? '');
          break;
        case 'notes':
          result = (a.debtAmount).compareTo(b.debtAmount);
          break;
        case 'remaining_days':
          // Sort by the precise expiration timestamp (down to the minute)
          // rather than the truncated integer `remainingDays`, otherwise
          // all subs with "1 day X minutes" tie on integer 1 and end up in
          // arbitrary order even though the card shows distinct
          // minute-level remainders. Falls back to integer days when the
          // expiration string is missing/unparseable.
          final ax = DateTime.tryParse(
                  (a.expiration ?? '').replaceAll(' ', 'T'))
              ?.millisecondsSinceEpoch;
          final bx = DateTime.tryParse(
                  (b.expiration ?? '').replaceAll(' ', 'T'))
              ?.millisecondsSinceEpoch;
          if (ax != null && bx != null) {
            result = ax.compareTo(bx);
          } else if (ax != null) {
            result = -1;
          } else if (bx != null) {
            result = 1;
          } else {
            result = (a.remainingDays ?? 0).compareTo(b.remainingDays ?? 0);
          }
          break;
        case 'session_time':
          result = (a.sessionTime ?? 0).compareTo(b.sessionTime ?? 0);
          break;
        case 'parent_username':
          result = (a.parentUsername ?? '').compareTo(b.parentUsername ?? '');
          break;
        case 'firstname':
          result = a.fullName.compareTo(b.fullName);
          break;
        default:
          result = a.username.compareTo(b.username);
      }
      return asc ? result : -result;
    });
    return list;
  }

  List<SubscriberModel> get _managerScoped => managerFilter != null
      ? subscribers.where((s) => s.parentUsername == managerFilter).toList()
      : subscribers;

  int get allCount => _managerScoped.length;
  int get activeCount => _managerScoped.where((s) => s.isActive).length;
  int get expiredCount => _managerScoped.where((s) => s.isExpired).length;
  int get onlineCount => _managerScoped.where((s) => s.isOnline).length;
  int get offlineCount {
    // Use SAS4 offline count from dashboard if available (more accurate from backend)
    if (sas4OfflineCount != null) {
      return sas4OfflineCount!;
    }
    // Fallback to local calculation
    return _managerScoped.where((s) => s.isOffline).length;
  }
  int get debtorsCount => _managerScoped.where((s) => s.hasDebt).length;
  int get nearExpiryCount => _managerScoped.where((s) => s.isNearExpiry).length;
  int get disabledCount => _managerScoped.where((s) => s.isDisabled).length;

  /// Sum of outstanding debt across subscribers in the current
  /// manager-filter scope (respects the "المدراء" dropdown so when the
  /// admin picks a single sub-manager the total only counts that
  /// sub-manager's debtors). Value is always non-negative — we sum the
  /// absolute of `debtAmount` so the UI doesn't have to worry about sign
  /// conventions.
  double get totalDebtAmount => _managerScoped
      .where((s) => s.hasDebt)
      .fold<double>(0, (sum, s) => sum + s.debtAmount.abs());

  SubscribersState copyWith({
    List<SubscriberModel>? subscribers,
    List<SubscriberModel>? searchResults,
    List<SubscriberModel>? onlineUsers,
    List<PackageModel>? packages,
    bool? isLoading,
    bool? isSearching,
    String? error,
    int? totalRecords,
    String? filter,
    String? sortBy,
    String? sortDirection,
    Map<String, Map<String, dynamic>>? lastPayments,
    String? managerFilter,
    int? sas4OfflineCount,
    bool clearManager = false,
  }) {
    return SubscribersState(
      subscribers: subscribers ?? this.subscribers,
      searchResults: searchResults ?? this.searchResults,
      onlineUsers: onlineUsers ?? this.onlineUsers,
      packages: packages ?? this.packages,
      isLoading: isLoading ?? this.isLoading,
      isSearching: isSearching ?? this.isSearching,
      error: error,
      totalRecords: totalRecords ?? this.totalRecords,
      filter: filter ?? this.filter,
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      lastPayments: lastPayments ?? this.lastPayments,
      managerFilter: clearManager ? null : (managerFilter ?? this.managerFilter),
      sas4OfflineCount: sas4OfflineCount ?? this.sas4OfflineCount,
    );
  }
}

class SubscribersNotifier extends StateNotifier<SubscribersState> {
  final Dio _backendDio;
  final Dio _sas4Dio;
  final StorageService _storage;
  final Ref _ref;

  SubscribersNotifier(this._backendDio, this._sas4Dio, this._storage, this._ref)
      : super(const SubscribersState());

  Map<int, Map<String, dynamic>> _priceMap = {};

  static double _parseNotes(Map<String, dynamic>? details) {
    if (details == null) return 0;
    final raw = (details['notes'] ?? details['comments'])?.toString() ?? '';
    if (raw.isEmpty) return 0;
    return double.tryParse(raw.replaceAll(',', '').trim()) ?? 0;
  }

  static String? _nonEmptyString(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  static int? _parseRemainingDays(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static int? _calculateRemainingDays(String? expiration) {
    if (expiration == null || expiration.trim().isEmpty) return null;
    try {
      final raw = expiration.trim();
      final parsed = raw.contains('T') || raw.contains('+')
          ? DateTime.tryParse(raw)
          : DateTime.tryParse('${raw.replaceAll(' ', 'T')}+03:00');
      if (parsed == null) return null;
      final diff = parsed.difference(DateTime.now());
      if (diff.isNegative) return diff.inDays;
      // Use ceil rather than truncating `inDays`. SAS4 sets `expiration =
      // server_now + N*86400s` exactly on activation; by the time the client
      // parses the response, `client_now` is a few seconds later, so the diff
      // is N days minus a tiny epsilon — `inDays` would drop a whole day
      // (showing 29 instead of 30 right after activation). Ceil keeps that
      // boundary stable.
      return (diff.inSeconds / 86400.0).ceil();
    } catch (_) {
      return null;
    }
  }

  List<SubscriberModel> _replaceSubscriberInList(
    List<SubscriberModel> source,
    SubscriberModel updated,
  ) {
    final index = source.indexWhere((s) => s.idx == updated.idx);
    if (index == -1) return source;
    final next = List<SubscriberModel>.from(source);
    next[index] = updated;
    return next;
  }

  SubscriberModel _mergeSubscriberDetails(
    SubscriberModel existing,
    Map<String, dynamic> details,
    int userId,
  ) {
    final expiration =
        _nonEmptyString(details['expiration']) ?? existing.expiration;
    final remainingDays = _parseRemainingDays(details['remaining_days']) ??
        _calculateRemainingDays(expiration) ??
        existing.remainingDays;
    final merged = <String, dynamic>{
      'id': userId.toString(),
      'idx': userId.toString(),
      'username': _nonEmptyString(details['username']) ?? existing.username,
      'firstname': _nonEmptyString(details['firstname']) ?? existing.firstname,
      'lastname': _nonEmptyString(details['lastname']) ?? existing.lastname,
      'phone': _nonEmptyString(details['phone']) ?? existing.phone,
      'mobile': _nonEmptyString(details['mobile']) ?? existing.mobile,
      'expiration': expiration,
      'remaining_days': remainingDays,
      'notes': details['notes'] ?? details['comments'] ?? existing.notes,
      'profile_name': _nonEmptyString(details['profile_name']) ??
          (details['profile_details'] is Map
              ? _nonEmptyString(details['profile_details']['name'])
              : null) ??
          existing.profileName,
      'profile_id': details['profile_id'] ??
          (details['profile_details'] is Map
              ? details['profile_details']['id']
              : null) ??
          existing.profileId,
      'balance': _nonEmptyString(details['balance']) ?? existing.balance,
      'price': existing.price,
      // Refresh parent_username from the SAS4 response when present (so a
      // re-parent done from the Edit sheet is reflected on the list/cards
      // immediately). Fall back to the existing value when SAS4 doesn't
      // include it.
      'parent_username': _nonEmptyString(details['parent_username']) ??
          (details['parent_details'] is Map
              ? _nonEmptyString(details['parent_details']['username'])
              : null) ??
          existing.parentUsername,
      'is_online': existing.isOnline,
      'enabled': details['enabled'] ?? existing.enabled,
      'framedipaddress':
          _nonEmptyString(details['framedipaddress']) ?? existing.ipAddress,
      'callingstationid':
          _nonEmptyString(details['callingstationid']) ?? existing.macAddress,
      'acctsessiontime': existing.sessionTime,
      'acctinputoctets': existing.uploadBytes,
      'acctoutputoctets': existing.downloadBytes,
      'oui': existing.deviceVendor,
    };

    var updated = SubscriberModel.fromJson(merged);
    updated = _enrichWithPackage(updated, state.packages);
    updated = _enrichWithPriceList(updated);
    return updated;
  }

  Future<void> loadSubscribers() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      if (state.packages.isEmpty || _priceMap.isEmpty) {
        await loadPackages();
      }

      // Backend: active subscribers with phones
      final response = await _backendDio.get(
        '${ApiConstants.subscribersWithPhones}?adminId=$adminId',
      );

      List<SubscriberModel> activeList = [];
      if (response.data['success'] == true) {
        final rawData = response.data['data'] as List? ?? [];
        activeList = rawData
            .map((e) => SubscriberModel.fromJson(e))
            .toList();
      }

      final pkgs = state.packages;
      activeList = activeList
          .map((s) => _enrichWithPackage(s, pkgs))
          .map((s) => _enrichWithPriceList(s))
          .toList();

      // If backend didn't return profile data, fetch from SAS4 and merge
      final needsProfile = activeList.isNotEmpty &&
          (activeList[0].profileName == null || activeList[0].profileName!.isEmpty) &&
          activeList[0].profileId == null;

      if (needsProfile) {
        final profileMap = await _fetchProfileMapFromSas4();
        if (profileMap.isNotEmpty) {
          activeList = activeList.map((sub) {
            final sd = profileMap[sub.username];
            if (sd == null) return sub;
            final pId = sd['profileId'] as int?;
            final pName = sd['profileName'] as String?;
            final pi = pId != null ? _priceMap[pId] : null;
            return SubscriberModel(
              idx: sub.idx, username: sub.username,
              firstname: sub.firstname, lastname: sub.lastname,
              phone: sub.phone, mobile: sub.mobile,
              expiration: sub.expiration, remainingDays: sub.remainingDays,
              notes: sub.notes, debt: sub.debt, hasDebtFlag: sub.hasDebtFlag,
              profileName: pName ?? sub.profileName,
              profileId: pId ?? sub.profileId,
              balance: sub.balance,
              price: (pi?['user_price'] ?? pi?['price'])?.toString() ?? sub.price,
              parentUsername: sub.parentUsername,
              isOnlineFlag: sub.isOnlineFlag, enabled: sub.enabled,
            );
          }).toList();
        }
      }

      dev.log('Backend: ${activeList.length} active subscribers', name: 'SUBS');

      // Paginated SAS4 call: get ALL subscribers with is_online field
      final sas4All = await _fetchAllSas4();

      dev.log('SAS4: ${sas4All.length} total subscribers', name: 'SUBS');

      List<SubscriberModel> finalList;

      if (sas4All.isNotEmpty) {
        final backendMap = <String, SubscriberModel>{};
        for (final s in activeList) {
          backendMap[s.username.toLowerCase()] = s;
        }

        // Deduplicate by username (pagination can return duplicates)
        final seen = <String>{};
        finalList = [];

        for (final e in sas4All) {
          final sub = SubscriberModel.fromJson(e);
          final key = sub.username.toLowerCase();
          if (seen.contains(key)) continue;
          seen.add(key);

          final isOnline = e['online_status'] == 1 ||
              e['is_online'] == true ||
              e['is_online'] == 1 ||
              e['is_online'] == '1';
          final backend = backendMap[key];

          // Calculate remaining_days from expiration if server returns null
          int? days = sub.remainingDays ?? backend?.remainingDays;
          if (days == null || days == 0) {
            final expStr = sub.expiration ?? backend?.expiration;
            if (expStr != null) {
              final exp = DateTime.tryParse(expStr);
              if (exp != null) {
                days = exp.difference(DateTime.now()).inDays;
              }
            }
          }

          finalList.add(SubscriberModel(
            idx: sub.idx ?? backend?.idx,
            username: sub.username,
            firstname: (backend != null && backend.firstname.isNotEmpty) ? backend.firstname : sub.firstname,
            lastname: (backend != null && backend.lastname.isNotEmpty) ? backend.lastname : sub.lastname,
            phone: backend?.phone ?? sub.phone,
            mobile: backend?.mobile ?? sub.mobile,
            expiration: sub.expiration ?? backend?.expiration,
            remainingDays: days,
            notes: backend?.notes ?? sub.notes,
            debt: backend?.debt, hasDebtFlag: backend?.hasDebtFlag,
            profileName: sub.profileName ?? backend?.profileName,
            profileId: sub.profileId ?? backend?.profileId,
            balance: backend?.balance ?? sub.balance,
            price: backend?.price ?? sub.price,
            parentUsername: sub.parentUsername ?? backend?.parentUsername,
            isOnlineFlag: isOnline,
            enabled: sub.enabled ?? backend?.enabled,
            ipAddress: (e['framedipaddress'] ?? e['framed_ip_address'])?.toString(),
            macAddress: e['callingstationid']?.toString(),
            sessionTime: e['acctsessiontime'] is int
                ? e['acctsessiontime']
                : int.tryParse(e['acctsessiontime']?.toString() ?? ''),
            downloadBytes: e['acctoutputoctets'] is int
                ? e['acctoutputoctets']
                : int.tryParse(e['acctoutputoctets']?.toString() ?? ''),
            uploadBytes: e['acctinputoctets'] is int
                ? e['acctinputoctets']
                : int.tryParse(e['acctinputoctets']?.toString() ?? ''),
            deviceVendor: e['oui']?.toString(),
          ));
        }
      } else {
        dev.log('SAS4 returned empty, using backend data as fallback', name: 'SUBS');
        finalList = activeList;
      }

      final enriched = finalList
          .map((s) => _enrichWithPackage(s, pkgs))
          .map((s) => _enrichWithPriceList(s))
          .toList();

      dev.log('Final: ${enriched.length} subs, online=${enriched.where((s) => s.isOnline).length}, expired=${enriched.where((s) => s.isExpired).length}', name: 'SUBS');

      final localOffline = enriched.where((s) => s.isOffline).length;
      try {
        _ref.read(dashboardProvider.notifier).updateOfflineCount(localOffline);
      } catch (e) {
        dev.log('Could not update dashboard offline count: $e', name: 'SUBS');
      }

      try {
        final nearExpirySubs = enriched.where((s) => s.isNearExpiry).toList();
        nearExpirySubs.sort((a, b) {
          final da = a.remainingDays ?? 0;
          final db = b.remainingDays ?? 0;
          return da.compareTo(db);
        });
        _ref.read(dashboardProvider.notifier).updateNearExpiryFromSubscribers(
              nearExpirySubs.length,
              list: nearExpirySubs
                  .map((s) => {
                        'username': s.username,
                        'firstname': s.firstname,
                        'lastname': s.lastname,
                        'expiration': s.expiration,
                        'remaining_days': s.remainingDays,
                        'phone': s.phone ?? s.mobile,
                        'profile_name': s.profileName,
                      })
                  .toList(),
            );
      } catch (e) {
        dev.log('Could not update dashboard near-expiry count: $e', name: 'SUBS');
      }

      state = state.copyWith(
        subscribers: enriched,
        isLoading: false,
        totalRecords: enriched.length,
        sas4OfflineCount: localOffline,
      );

      loadLastPayments();
      // لا ننتظر — تخصيب IP للمشتركين المتصلين يجري بالخلفية
      loadOnlineIps();
    } catch (e) {
      dev.log('loadSubscribers error: $e', name: 'SUBS');
      state = state.copyWith(isLoading: false, error: 'خطأ في تحميل البيانات');
    }
  }

  /// يجلب أحدث الجلسات من SAS4 ويملأ حقل ipAddress لكل مشترك متصل
  /// (يشمل المنتهي صلاحيته الذي ما زالت جلسته الراديوسية مفتوحة).
  Future<void> loadOnlineIps() async {
    try {
      final payload = EncryptionService.encrypt({
        'page': 1,
        'count': 2000,
        'sortBy': 'acctstarttime',
        'direction': 'desc',
        'search': '',
        'columns': [
          'username',
          'acctstarttime',
          'acctstoptime',
          'framedipaddress',
        ],
        'framedipaddress': '',
        'username': '',
        'mac': '',
        'start_date': '',
        'end_date': '',
      });

      final res = await _sas4Dio.post(
        ApiConstants.sas4UserSessions,
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      dynamic data = res.data;
      if (data is String) data = EncryptionService.decrypt(data);

      List rows = const [];
      if (data is Map && data['data'] is List) rows = data['data'] as List;
      else if (data is Map && data['sessions'] is List) rows = data['sessions'] as List;
      else if (data is List) rows = data;

      // IP + start-time from open sessions (acctstoptime empty). The
      // start-time lets us compute live uptime on the detail screen even
      // when the earlier /online-users payload didn't carry a sessionTime
      // (e.g. for subscribers whose profile happens to be expired but are
      // still connected).
      final openIpByUser = <String, String>{};
      final openStartByUser = <String, DateTime>{};
      final recentIpByUser = <String, String>{};
      for (final r in rows) {
        if (r is! Map) continue;
        final uname = r['username']?.toString().trim().toLowerCase();
        final ip = r['framedipaddress']?.toString().trim();
        if (uname == null || uname.isEmpty) continue;
        if (ip == null || ip.isEmpty || ip == '-') continue;
        final stop = r['acctstoptime']?.toString().trim() ?? '';
        final isOpen = stop.isEmpty || stop == '-' || stop.toLowerCase() == 'null';
        if (isOpen) {
          openIpByUser.putIfAbsent(uname, () => ip);
          final rawStart = r['acctstarttime']?.toString().trim() ?? '';
          if (rawStart.isNotEmpty) {
            // SAS4 returns start time as Baghdad-naive "yyyy-MM-dd HH:mm:ss"
            // or ISO with offset. Interpret naive as Baghdad (+03:00).
            DateTime? start;
            if (rawStart.contains('T') ||
                rawStart.contains('+') ||
                rawStart.endsWith('Z')) {
              start = DateTime.tryParse(rawStart);
            } else {
              start = DateTime.tryParse(
                  '${rawStart.replaceAll(' ', 'T')}+03:00');
            }
            if (start != null) {
              openStartByUser.putIfAbsent(uname, () => start!);
            }
          }
        }
        recentIpByUser.putIfAbsent(uname, () => ip);
      }

      int? _uptimeSecondsFor(String usernameLower) {
        final start = openStartByUser[usernameLower];
        if (start == null) return null;
        final secs = DateTime.now().difference(start).inSeconds;
        return secs > 0 ? secs : null;
      }

      final current = state.subscribers;
      var changed = 0;
      final updated = <SubscriberModel>[];
      for (final s in current) {
        final key = s.username.toLowerCase();
        final openIp = openIpByUser[key];
        final recentIp = recentIpByUser[key];
        final uptime = _uptimeSecondsFor(key);

        // 1) جلسة مفتوحة → online مع IP + مدة الاتصال
        if (openIp != null &&
            (openIp != (s.ipAddress ?? '') ||
                (uptime != null && uptime != s.sessionTime))) {
          updated.add(_copyWithIp(s, openIp,
              markOnline: true, sessionSeconds: uptime));
          changed++;
          continue;
        }
        // 2) لم توجد جلسة مفتوحة لكن admin_list علّمه online → استخدم آخر IP معروف
        if (openIp == null && s.isOnline && (s.ipAddress ?? '').isEmpty && recentIp != null) {
          updated.add(_copyWithIp(s, recentIp, markOnline: true));
          changed++;
          continue;
        }
        updated.add(s);
      }
      if (changed > 0) {
        dev.log('loadOnlineIps: enriched $changed subscribers (open=${openIpByUser.length}, recent=${recentIpByUser.length})', name: 'SUBS');
        state = state.copyWith(subscribers: updated);
      }

      // Per-user UserSessions fallback. The bulk 2000-row fetch above
      // returns the most recent sessions globally — so subscribers who
      // have been continuously connected for days end up pushed past
      // the window and their IP goes missing (e.g. hal@xuuo under
      // admin@xuuo stayed connected 3+ days while newer sessions filled
      // the list). Targeted search=username hits the exact session row
      // regardless of how old the start time is.
      final stillMissing = state.subscribers
          .where((s) =>
              s.isOnline &&
              (s.ipAddress ?? '').trim().isEmpty &&
              s.username.trim().isNotEmpty)
          .take(10) // حدّ أعلى للإنصاف على SAS4
          .toList();
      if (stillMissing.isNotEmpty) {
        dev.log('loadOnlineIps: ${stillMissing.length} online subs still missing IP — doing per-user lookup',
            name: 'SUBS');
      }
      for (final s in stillMissing) {
        try {
          final userPayload = EncryptionService.encrypt({
            'page': 1, 'count': 3,
            'sortBy': 'acctstarttime', 'direction': 'desc',
            'search': s.username,
            'columns': ['username', 'framedipaddress', 'acctstarttime', 'acctstoptime'],
            'framedipaddress': '', 'username': s.username, 'mac': '',
            'start_date': '', 'end_date': '',
          });
          final userRes = await _sas4Dio.post(
            ApiConstants.sas4UserSessions,
            data: {'payload': userPayload},
            options: Options(contentType: 'application/x-www-form-urlencoded'),
          );
          dynamic ud = userRes.data;
          if (ud is String) ud = EncryptionService.decrypt(ud);
          final urows = (ud is Map && ud['data'] is List)
              ? ud['data'] as List
              : (ud is Map && ud['sessions'] is List)
                  ? ud['sessions'] as List
                  : (ud is List ? ud : const []);
          // The very first open row is the live session.
          for (final r in urows) {
            if (r is! Map) continue;
            final stop = r['acctstoptime']?.toString().trim() ?? '';
            final open = stop.isEmpty || stop == '-' || stop.toLowerCase() == 'null';
            if (!open) continue;
            final ip = r['framedipaddress']?.toString().trim();
            if (ip == null || ip.isEmpty || ip == '-') continue;
            // Parse start time for uptime display.
            int? uptimeSec;
            final rawStart = r['acctstarttime']?.toString().trim() ?? '';
            if (rawStart.isNotEmpty) {
              DateTime? st;
              if (rawStart.contains('T') || rawStart.contains('+') || rawStart.endsWith('Z')) {
                st = DateTime.tryParse(rawStart);
              } else {
                st = DateTime.tryParse('${rawStart.replaceAll(' ', 'T')}+03:00');
              }
              if (st != null) {
                uptimeSec = DateTime.now().difference(st).inSeconds;
                if (uptimeSec < 0) uptimeSec = null;
              }
            }
            // Merge into state.
            final i = state.subscribers.indexWhere((x) => x.username == s.username);
            if (i == -1) break;
            final next = List<SubscriberModel>.from(state.subscribers);
            next[i] = _copyWithIp(next[i], ip, markOnline: true, sessionSeconds: uptimeSec);
            state = state.copyWith(subscribers: next);
            break;
          }
        } catch (e) {
          dev.log('per-user session lookup failed for ${s.username}: $e', name: 'SUBS');
        }
      }
    } catch (e) {
      dev.log('loadOnlineIps error: $e', name: 'SUBS');
    }
  }

  SubscriberModel _copyWithIp(
    SubscriberModel s,
    String ip, {
    bool markOnline = false,
    int? sessionSeconds,
  }) {
    return SubscriberModel(
      idx: s.idx,
      username: s.username,
      firstname: s.firstname,
      lastname: s.lastname,
      phone: s.phone,
      mobile: s.mobile,
      expiration: s.expiration,
      remainingDays: s.remainingDays,
      notes: s.notes,
      debt: s.debt,
      hasDebtFlag: s.hasDebtFlag,
      profileName: s.profileName,
      profileId: s.profileId,
      balance: s.balance,
      price: s.price,
      parentUsername: s.parentUsername,
      isOnlineFlag: markOnline ? true : s.isOnlineFlag,
      enabled: s.enabled,
      ipAddress: ip,
      macAddress: s.macAddress,
      sessionTime: sessionSeconds ?? s.sessionTime,
      uploadBytes: s.uploadBytes,
      downloadBytes: s.downloadBytes,
      deviceVendor: s.deviceVendor,
    );
  }

  Future<void> loadLastPayments() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null) return;

    void applyPayments(dynamic data) {
      if (data is! Map || data['success'] != true) return;
      final payments = data['payments'] as List? ?? [];
      final map = <String, Map<String, dynamic>>{};
      for (final p in payments) {
        if (p is Map<String, dynamic>) {
          final username = p['subscriber_username']?.toString() ?? '';
          if (username.isNotEmpty) map[username] = p;
        }
      }
      state = state.copyWith(lastPayments: map);
    }

    try {
      final res = await _backendDio.get(
        '${ApiConstants.lastFinancialMovements}/$adminId',
      );
      applyPayments(res.data);
    } catch (e) {
      dev.log('loadLastPayments modern endpoint failed: $e', name: 'SUBS');
      try {
        final legacyRes = await _backendDio.get(
          '${ApiConstants.lastPayments}/$adminId',
        );
        applyPayments(legacyRes.data);
      } catch (legacyError) {
        dev.log('loadLastPayments legacy endpoint failed: $legacyError', name: 'SUBS');
      }
    }
  }

  Map<String, Map<String, dynamic>> _priceByName = {};

  Future<void> _loadPriceList(String adminId) async {
    try {
      final response = await _sas4Dio.get(
        '${ApiConstants.sas4PriceList}/$adminId',
      );

      var resData = response.data;
      if (resData is String) {
        resData = EncryptionService.decrypt(resData);
      }

      List<dynamic> items = [];
      if (resData is Map && resData['data'] is List) {
        items = resData['data'];
      } else if (resData is List) {
        items = resData;
      }

      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final id = item['id'] ?? item['profile_id'];
          final name = (item['name'] ?? item['profile_name'])?.toString();
          if (id != null) {
            _priceMap[int.tryParse(id.toString()) ?? 0] = item;
          }
          if (name != null && name.isNotEmpty) {
            _priceByName[name] = item;
          }
        }
      }
      dev.log('PriceList loaded: ${_priceMap.length} by ID, ${_priceByName.length} by name', name: 'SUBS');

      // Fallback لـsub-reseller: priceList يرجع فاضي، نجلب أسعار من
      // /index/profile (نفس fix loadPackages). يخلّي عرض السعر بكرت
      // المشترك يشتغل لـadmin@husxxx وأمثاله.
      if (_priceMap.isEmpty) {
        try {
          final encryptedPayload = EncryptionService.encrypt({
            'page': 1, 'count': 200, 'sortBy': null, 'direction': 'asc',
            'search': '',
            'columns': ['id', 'name', 'price', 'sale_price', 'user_price'],
          });
          final r = await _sas4Dio.post(
            ApiConstants.sas4Profiles,
            data: {'payload': encryptedPayload},
            options: Options(contentType: 'application/x-www-form-urlencoded'),
          );
          var d = r.data;
          if (d is String) d = EncryptionService.decrypt(d);
          final items2 = (d is Map && d['data'] is List) ? d['data'] as List : <dynamic>[];
          for (final raw in items2) {
            if (raw is Map<String, dynamic>) {
              final id = raw['id'] is int ? raw['id'] as int : int.tryParse(raw['id']?.toString() ?? '') ?? 0;
              if (id <= 0) continue;
              final name = raw['name']?.toString();
              _priceMap[id] = {
                'id': id,
                'name': name,
                'price': raw['price'],
                'sale_price': raw['sale_price'],
                'user_price': raw['user_price'],
              };
              if (name != null && name.isNotEmpty) _priceByName[name] = _priceMap[id]!;
            }
          }
          dev.log('PriceList /index/profile fallback: ${_priceMap.length} by ID', name: 'SUBS');
        } catch (e) {
          dev.log('PriceList fallback failed: $e', name: 'SUBS');
        }
      }
    } catch (e) {
      dev.log('loadPriceList error: $e', name: 'SUBS');
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfileMapFromSas4() async {
    final result = <String, Map<String, dynamic>>{};
    try {
      final payload = EncryptionService.encrypt({
        'page': 1,
        'count': 500,
        'sortBy': 'username',
        'direction': 'asc',
        'search': '',
        'columns': [
          'idx', 'username', 'profile_details', 'profile_id', 'profile_name',
        ],
        'status': 1,
        'connection': -1,
        'profile_id': -1,
        'parent_id': -1,
        'sub_users': 1,
        'mac': '',
      });

      final response = await _sas4Dio.post(
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
        final username = u['username']?.toString();
        if (username == null) continue;

        final pd = u['profile_details'];
        final pdId = pd is Map ? pd['id'] : null;
        final pdName = pd is Map ? pd['name']?.toString() : null;
        final pId = pdId ?? u['profile_id'];
        final pName = pdName ?? u['profile_name']?.toString();

        if (pId != null || (pName != null && pName.isNotEmpty)) {
          result[username] = {
            'profileId': pId is int ? pId : int.tryParse(pId?.toString() ?? ''),
            'profileName': pName ?? '',
          };
        }
      }
      dev.log('SAS4 profile map: ${result.length} entries', name: 'SUBS');
    } catch (e) {
      dev.log('fetchProfileMap error: $e', name: 'SUBS');
    }
    return result;
  }

  SubscriberModel _enrichWithPriceList(SubscriberModel sub) {
    if (_priceMap.isEmpty && _priceByName.isEmpty) return sub;

    Map<String, dynamic>? matched;

    if (sub.profileId != null && _priceMap.containsKey(sub.profileId)) {
      matched = _priceMap[sub.profileId];
    }

    if (matched == null && sub.profileName != null && sub.profileName!.isNotEmpty) {
      matched = _priceByName[sub.profileName];
    }

    if (matched == null) return sub;

    final userPrice = matched['user_price'];
    final plName = (matched['name'] ?? matched['profile_name'])?.toString();
    final plPrice = (matched['sale_price'] ?? matched['sell_price'] ?? userPrice ?? matched['price'])?.toString();
    final resolvedId = sub.profileId
        ?? (matched['id'] is int ? matched['id'] : int.tryParse(matched['id']?.toString() ?? ''));

    final resolvedName = (sub.profileName == null || sub.profileName!.isEmpty)
        ? plName
        : sub.profileName;

    // الـbackend (/api/subscribers/with-phones) يحسب سعر البيع الصحيح
    // عبر activationData لكل profile_id (MAX of user_price + n_required).
    // لا نطغى عليه — نستعمل priceMap كـfallback فقط إذا sub.price فاضي.
    // قبلاً كان priceMap يطغى ويرجع cost (19k) بدل sale (35k) لـsub-reseller.
    final hasBackendPrice = sub.price != null
        && sub.price!.isNotEmpty
        && sub.price != '0'
        && sub.price != '0.00';
    final resolvedPrice = hasBackendPrice ? sub.price : plPrice;

    if (resolvedName == sub.profileName && resolvedPrice == sub.price && resolvedId == sub.profileId) {
      return sub;
    }

    return SubscriberModel(
      idx: sub.idx,
      username: sub.username,
      firstname: sub.firstname,
      lastname: sub.lastname,
      phone: sub.phone,
      mobile: sub.mobile,
      expiration: sub.expiration,
      remainingDays: sub.remainingDays,
      notes: sub.notes,
      debt: sub.debt,
      hasDebtFlag: sub.hasDebtFlag,
      profileName: resolvedName,
      profileId: resolvedId,
      balance: sub.balance,
      price: resolvedPrice,
      parentUsername: sub.parentUsername,
      isOnlineFlag: sub.isOnlineFlag,
      enabled: sub.enabled,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllSas4() async {
    final allItems = <Map<String, dynamic>>[];
    int page = 1;
    int totalCount = 0;
    int retries = 0;

    while (true) {
      try {
        final payload = EncryptionService.encrypt({
          'page': page,
          'count': 1000,
          'sortBy': 'username',
          'direction': 'asc',
          'search': '',
          'columns': [
            'idx', 'username', 'firstname', 'lastname', 'name',
            'expiration', 'remaining_days', 'notes', 'comments', 'balance',
            'phone', 'mobile', 'is_online', 'online_status',
            'enabled', 'parent_username', 'profile_details',
            'framedipaddress', 'framed_ip_address',
            'acctsessiontime', 'acctinputoctets', 'acctoutputoctets',
            'callingstationid', 'oui',
          ],
          'status': -1,
          'connection': -1,
          'profile_id': -1,
          'parent_id': -1,
          'sub_users': 1,
          'mac': '',
        });

      final response = await _sas4Dio.post(
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
          final tc = parsed['totalCount'] ?? parsed['total'] ?? parsed['count'];
          if (tc != null) {
            totalCount = tc is int ? tc : (int.tryParse(tc.toString()) ?? totalCount);
          }
        } else if (parsed is List) {
          pageItems = parsed;
        }

        for (final item in pageItems) {
          if (item is Map<String, dynamic>) allItems.add(item);
        }

        retries = 0;
        if (pageItems.isEmpty) break;
        if (totalCount > 0 && allItems.length >= totalCount) break;
        page++;

        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        retries++;
        if (retries > 3) {
          dev.log('SAS4 pagination: giving up at page $page after $retries retries', name: 'SUBS');
          break;
        }
        dev.log('SAS4 pagination: retry $retries for page $page', name: 'SUBS');
        await Future.delayed(Duration(milliseconds: 800 * retries));
      }
    }

    dev.log('SAS4 fetched: ${allItems.length}/$totalCount in ${page - 1} pages', name: 'SUBS');
    return allItems;
  }

  SubscriberModel _enrichWithPackage(SubscriberModel sub, List<PackageModel> pkgs) {
    if (pkgs.isEmpty) return sub;

    PackageModel? matched;

    if (sub.profileId != null) {
      final byId = pkgs.where((p) => p.idx == sub.profileId);
      if (byId.isNotEmpty) matched = byId.first;
    }

    if (matched == null &&
        sub.profileName != null &&
        sub.profileName!.isNotEmpty) {
      final byName = pkgs.where((p) => p.name == sub.profileName);
      if (byName.isNotEmpty) matched = byName.first;
    }

    if (matched == null) return sub;

    final needsName = sub.profileName == null || sub.profileName!.isEmpty;
    final needsPrice = sub.price == null || sub.price!.isEmpty;

    if (!needsName && !needsPrice) return sub;

    return SubscriberModel(
      idx: sub.idx,
      username: sub.username,
      firstname: sub.firstname,
      lastname: sub.lastname,
      phone: sub.phone,
      mobile: sub.mobile,
      expiration: sub.expiration,
      remainingDays: sub.remainingDays,
      notes: sub.notes,
      debt: sub.debt,
      hasDebtFlag: sub.hasDebtFlag,
      profileName: needsName ? matched.name : sub.profileName,
      profileId: sub.profileId ?? matched.idx,
      balance: sub.balance,
      price: needsPrice ? matched.price : sub.price,
      parentUsername: sub.parentUsername,
      isOnlineFlag: sub.isOnlineFlag,
      enabled: sub.enabled,
    );
  }

  Future<void> searchSubscribers(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(searchResults: [], isSearching: false);
      return;
    }
    state = state.copyWith(isSearching: true);

    final q = query.toLowerCase().trim();
    bool matchesQuery(SubscriberModel s) {
      return s.username.toLowerCase().contains(q) ||
          s.firstname.toLowerCase().contains(q) ||
          s.lastname.toLowerCase().contains(q) ||
          s.fullName.toLowerCase().contains(q) ||
          (s.phone ?? '').contains(q) ||
          (s.mobile ?? '').contains(q) ||
          (s.profileName ?? '').toLowerCase().contains(q) ||
          (s.parentUsername ?? '').toLowerCase().contains(q);
    }

    final onlineMap = <String, SubscriberModel>{};
    for (final o in state.onlineUsers) {
      onlineMap[o.username.toLowerCase()] = o;
    }

    // قيّد البحث على التبويب الحالي (online/active/expired/...) بدل قائمة
    // المشتركين الكاملة. كان الـbug: المستخدم بتبويب "اونلاين" يبحث "ali"
    // → يطلع كل المشتركين باسم ali حتى المنقطعين.
    final scoped = state.filteredSubscribers;
    final localResults = scoped.where(matchesQuery).map((s) {
      final online = onlineMap[s.username.toLowerCase()];
      if (online != null) {
        return SubscriberModel(
          idx: s.idx, username: s.username,
          firstname: s.firstname.isNotEmpty ? s.firstname : online.firstname,
          lastname: s.lastname.isNotEmpty ? s.lastname : online.lastname,
          phone: s.phone ?? online.phone, mobile: s.mobile ?? online.mobile,
          expiration: s.expiration, remainingDays: s.remainingDays,
          notes: s.notes, debt: s.debt, hasDebtFlag: s.hasDebtFlag,
          profileName: s.profileName ?? online.profileName,
          profileId: s.profileId ?? online.profileId,
          balance: s.balance, price: s.price,
          parentUsername: s.parentUsername,
          isOnlineFlag: true, enabled: s.enabled,
          ipAddress: online.ipAddress, macAddress: online.macAddress,
          sessionTime: online.sessionTime,
          downloadBytes: online.downloadBytes, uploadBytes: online.uploadBytes,
          deviceVendor: online.deviceVendor,
        );
      }
      return s;
    }).toList();

    state = state.copyWith(searchResults: localResults, isSearching: false);
  }

  // Default sort field + direction per filter tab. Applied automatically
  // on tab switch so each tab opens in the order the user expects:
  //   - active       → most remaining days first
  //   - online       → longest active session first
  //   - expired      → most recently expired first (closest → farthest)
  //   - debtors      → largest debt first
  //   - nearExpiry   → soonest to expire first
  // Users can still override via the sort picker while on the tab.
  // Default sort per filter chip — applied automatically when the admin
  // taps a chip so each tab opens in the order they expect (no need
  // to also touch the sort dropdown). Per admin spec:
  //   • all / active   → newest activation first (remaining_days desc)
  //   • online         → longest connection time first
  //   • nearExpiry     → closest to expiry first (lowest remaining)
  //   • expired        → most recently expired first
  //   • debtors        → largest debt first (debtAmount is negative,
  //                       so ascending = most-negative = biggest debt)
  static const Map<String, (String, String)> _defaultSortByFilter = {
    'all':         ('remaining_days', 'desc'),
    'active':      ('remaining_days', 'desc'),
    'online':      ('session_time',   'desc'),
    'expired':     ('expiration',     'desc'),
    'debtors':     ('notes',          'asc'),
    'nearExpiry':  ('remaining_days', 'asc'),
  };

  void setFilter(String filter) {
    final def = _defaultSortByFilter[filter];
    if (def != null) {
      state = state.copyWith(filter: filter, sortBy: def.$1, sortDirection: def.$2);
    } else {
      state = state.copyWith(filter: filter);
    }
    if (filter == 'online') {
      loadOnlineUsers();
    }
  }

  void setManagerFilter(String? manager) {
    if (manager == null) {
      state = state.copyWith(clearManager: true);
    } else {
      state = state.copyWith(managerFilter: manager);
    }
  }

  Future<void> loadOnlineUsers() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null) return;

    try {
      final payload = EncryptionService.encrypt({
        'page': 1,
        'count': 500,
        'sortBy': 'username',
        'direction': 'asc',
        'search': '',
        'parent_id': -1,
        'columns': [
          'id', 'username', 'firstname', 'lastname',
          'acctoutputoctets', 'acctinputoctets',
          'user_profile_name', 'parent_username',
          'framedipaddress', 'callingstationid',
          'acctsessiontime', 'oui', 'profile_details',
          'expiration', 'remaining_days', 'notes', 'phone', 'mobile',
        ],
      });

      final response = await _sas4Dio.post(
        ApiConstants.sas4OnlineUsers,
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      dynamic parsed = response.data;
      if (parsed is String) {
        parsed = EncryptionService.decrypt(parsed);
      }

      if (parsed is Map && parsed['data'] is List) {
        final list = (parsed['data'] as List).map((e) {
          final m = Map<String, dynamic>.from(e);
          return SubscriberModel(
            idx: m['id']?.toString(),
            username: (m['username'] ?? '').toString(),
            firstname: (m['firstname'] ?? '').toString(),
            lastname: (m['lastname'] ?? '').toString(),
            phone: m['phone']?.toString(),
            mobile: m['mobile']?.toString(),
            expiration: m['expiration']?.toString(),
            remainingDays: m['remaining_days'] is int
                ? m['remaining_days']
                : int.tryParse(m['remaining_days']?.toString() ?? ''),
            notes: (m['notes'] ?? m['comments'])?.toString(),
            profileName: m['user_profile_name']?.toString() ??
                (m['profile_details'] is Map ? m['profile_details']['name'] : null)?.toString(),
            profileId: m['profile_details'] is Map
                ? int.tryParse(m['profile_details']['id']?.toString() ?? '')
                : null,
            parentUsername: m['parent_username']?.toString(),
            isOnlineFlag: true,
            enabled: 1,
            ipAddress: (m['framedipaddress'] ?? m['framed_ip_address'])?.toString(),
            macAddress: m['callingstationid']?.toString(),
            sessionTime: m['acctsessiontime'] is int
                ? m['acctsessiontime']
                : int.tryParse(m['acctsessiontime']?.toString() ?? ''),
            downloadBytes: m['acctoutputoctets'] is int
                ? m['acctoutputoctets']
                : int.tryParse(m['acctoutputoctets']?.toString() ?? ''),
            uploadBytes: m['acctinputoctets'] is int
                ? m['acctinputoctets']
                : int.tryParse(m['acctinputoctets']?.toString() ?? ''),
            deviceVendor: m['oui']?.toString(),
          );
        }).toList();

        final subs = state.subscribers;
        final subMap = <String, SubscriberModel>{};
        for (final s in subs) {
          subMap[s.username.toLowerCase()] = s;
        }

        final enriched = list.map((o) {
          final match = subMap[o.username.toLowerCase()];
          if (match != null) {
            return SubscriberModel(
              idx: o.idx, username: o.username,
              firstname: match.firstname.isNotEmpty ? match.firstname : o.firstname,
              lastname: match.lastname.isNotEmpty ? match.lastname : o.lastname,
              phone: o.phone ?? match.phone,
              mobile: o.mobile ?? match.mobile,
              expiration: o.expiration ?? match.expiration,
              remainingDays: o.remainingDays ?? match.remainingDays,
              notes: o.notes ?? match.notes,
              profileName: o.profileName ?? match.profileName,
              profileId: o.profileId ?? match.profileId,
              balance: match.balance, price: match.price,
              parentUsername: o.parentUsername ?? match.parentUsername,
              isOnlineFlag: true, enabled: 1,
              ipAddress: o.ipAddress, macAddress: o.macAddress,
              sessionTime: o.sessionTime,
              downloadBytes: o.downloadBytes, uploadBytes: o.uploadBytes,
              deviceVendor: o.deviceVendor,
            );
          }
          return o;
        }).toList();

        dev.log('Online users loaded: ${enriched.length}', name: 'SUBS');
        state = state.copyWith(onlineUsers: enriched);
      }
    } catch (e) {
      dev.log('loadOnlineUsers error: $e', name: 'SUBS');
    }
  }

  Future<bool> disconnectUser(String sessionId) async {
    try {
      // Immediately remove from online list for instant UI feedback
      final updatedOnline = state.onlineUsers
          .where((u) => u.idx != sessionId)
          .toList();
      final updatedSubs = state.subscribers.map((s) {
        if (s.idx == sessionId) {
          return SubscriberModel(
            idx: s.idx, username: s.username,
            firstname: s.firstname, lastname: s.lastname,
            phone: s.phone, mobile: s.mobile,
            expiration: s.expiration, remainingDays: s.remainingDays,
            notes: s.notes, debt: s.debt, hasDebtFlag: s.hasDebtFlag,
            profileName: s.profileName, profileId: s.profileId,
            balance: s.balance, price: s.price,
            parentUsername: s.parentUsername,
            isOnlineFlag: false,
            enabled: s.enabled,
          );
        }
        return s;
      }).toList();
      state = state.copyWith(onlineUsers: updatedOnline, subscribers: updatedSubs);

      final response = await _sas4Dio.get(
        '${ApiConstants.sas4DisconnectUser}/$sessionId',
      );
      dev.log('Disconnect user $sessionId: ${response.statusCode}', name: 'SUBS');
      await loadOnlineUsers();
      return true;
    } catch (e) {
      dev.log('disconnectUser error: $e', name: 'SUBS');
      return false;
    }
  }

  void setSort(String field, String direction) {
    state = state.copyWith(sortBy: field, sortDirection: direction);
  }

  /// Re-applies the per-filter default sort for the currently active
  /// filter tab. Called by the subscribers screen after clearing the
  /// device-health sort so the list snaps back to the expected order
  /// (e.g. remaining_days desc on "active") instead of staying in
  /// whatever order the device sort produced.
  void resetSortToFilterDefault() {
    final def = _defaultSortByFilter[state.filter];
    if (def != null) {
      state = state.copyWith(sortBy: def.$1, sortDirection: def.$2);
    }
  }

  Future<void> loadPackages() async {
    try {
      final adminId = await _storage.getAdminId();
      if (adminId == null) {
        dev.log('No adminId — cannot load packages', name: 'PKG');
        return;
      }

      // Step 1: load priceList (works for root managers — empty for sub-managers)
      await _loadPriceList(adminId);
      dev.log('priceMap has ${_priceMap.length} entries', name: 'PKG');

      // Step 2: GET /list/profile/5 — authoritative list of assignable profiles
      //         for the current admin (works for both managers and sub-managers).
      //         Response: {status: 200, data: [{id: 134, name: "..."}, ...]}
      final listProfileItems = <Map<String, dynamic>>[];
      try {
        final response = await _sas4Dio.get(ApiConstants.sas4ListProfile);
        var resData = response.data;
        if (resData is String) resData = EncryptionService.decrypt(resData);

        List<dynamic> items = [];
        if (resData is Map && resData['data'] is List) {
          items = resData['data'];
        } else if (resData is List) {
          items = resData;
        }

        for (final raw in items) {
          if (raw is Map<String, dynamic>) listProfileItems.add(raw);
        }
        dev.log('/list/profile/5 returned ${listProfileItems.length} items', name: 'PKG');
      } catch (e) {
        dev.log('/list/profile/5 failed: $e', name: 'PKG');
      }

      // Step 2.5: Fallback لما _priceMap فاضي (sub-reseller، normal-reseller).
      // /priceList/{adminId} يرجع فاضي للمدير الفرعي. نجلب الأسعار من
      // /index/profile الذي يحتوي p.price مباشرة (يشتغل لكل المدراء).
      // هذا يصلح bug admin@husxxx — كانت الباقات تطلع 0 ع كل مكان.
      if (_priceMap.isEmpty && listProfileItems.isNotEmpty) {
        try {
          final encryptedPayload = EncryptionService.encrypt({
            'page': 1, 'count': 200, 'sortBy': null, 'direction': 'asc',
            'search': '',
            'columns': ['id', 'name', 'price', 'sale_price', 'user_price'],
          });
          final r = await _sas4Dio.post(
            ApiConstants.sas4Profiles,
            data: {'payload': encryptedPayload},
            options: Options(contentType: 'application/x-www-form-urlencoded'),
          );
          var d = r.data;
          if (d is String) d = EncryptionService.decrypt(d);
          final items = (d is Map && d['data'] is List) ? d['data'] as List : <dynamic>[];
          for (final raw in items) {
            if (raw is Map<String, dynamic>) {
              final id = raw['id'] is int ? raw['id'] as int : int.tryParse(raw['id']?.toString() ?? '') ?? 0;
              if (id <= 0) continue;
              _priceMap[id] = {
                'price': raw['price'],
                'sale_price': raw['sale_price'],
                'user_price': raw['user_price'],
                'name': raw['name'],
              };
            }
          }
          dev.log('[/index/profile fallback] _priceMap now ${_priceMap.length} entries', name: 'PKG');
        } catch (e) {
          dev.log('/index/profile fallback failed: $e', name: 'PKG');
        }
      }

      // Step 3: Build packages.
      //   - If /list/profile/5 returned items → use them as the source (covers sub-managers)
      //     and enrich prices from _priceMap when the id matches.
      //   - Otherwise fall back to _priceMap entries (covers old/permissive APIs).
      final packages = <PackageModel>[];
      if (listProfileItems.isNotEmpty) {
        for (final item in listProfileItems) {
          final rawId = item['id'] ?? item['profile_id'];
          final id = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '') ?? 0;
          if (id <= 0) continue;
          final name = (item['name'] ?? item['profile_name'] ?? '').toString();
          if (name.isEmpty) continue;
          final priced = _priceMap[id];
          packages.add(PackageModel(
            idx: id,
            name: name,
            price: (priced?['price'] ?? priced?['profile_price'] ?? priced?['sale_price'] ?? item['price'])?.toString(),
            userPrice: (priced?['user_price'] ?? item['user_price'])?.toString(),
          ));
        }
      } else {
        for (final entry in _priceMap.entries) {
          if (entry.key <= 0) continue;
          final item = entry.value;
          final name = (item['name'] ?? item['profile_name'] ?? '').toString();
          if (name.isEmpty) continue;
          packages.add(PackageModel(
            idx: entry.key,
            name: name,
            price: (item['price'] ?? item['profile_price'])?.toString(),
            userPrice: item['user_price']?.toString(),
          ));
        }
      }

      dev.log('=== FINAL: ${packages.length} packages ===', name: 'PKG');
      for (final p in packages) {
        dev.log('  [${p.idx}] ${p.name} price=${p.displayPrice}', name: 'PKG');
      }
      state = state.copyWith(packages: packages);
    } catch (e, st) {
      dev.log('loadPackages error: $e\n$st', name: 'PKG');
    }
  }

  Future<bool> createSubscriber({
    required String username,
    required String password,
    required int profileId,
    required String firstname,
    required String lastname,
    required String phone,
    required String expiration,
    int? parentId,
  }) async {
    try {
      final adminId = await _storage.getAdminId();
      final resolvedParentId = parentId ?? int.tryParse(adminId ?? '');
      final payload = EncryptionService.encrypt({
        'username': username,
        'enabled': 1,
        'password': password,
        'confirm_password': password,
        'profile_id': profileId,
        'parent_id': resolvedParentId,
        'site_id': null,
        'mac_auth': 0,
        'allowed_macs': null,
        'use_separate_portal_password': 0,
        'portal_password': null,
        'group_id': null,
        'firstname': firstname,
        'lastname': lastname,
        'company': null,
        'email': null,
        'phone': phone,
        'city': null, 'address': null, 'apartment': null, 'street': null,
        'contract_id': null, 'national_id': null,
        'notes': null,
        'auto_renew': 0,
        'expiration': expiration,
        'simultaneous_sessions': 1,
        'static_ip': null,
        'user_type': '0',
        'restricted': 0,
      });

      final response = await _sas4Dio.post(
        '/user',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final ok = response.statusCode == 200 || response.statusCode == 201;
      if (ok) {
        final displayName =
            [firstname, lastname].where((p) => p.trim().isNotEmpty).join(' ').trim();
        logActivity(
          action: 'add_subscriber',
          description: 'إضافة مشترك جديد: $username'
              '${displayName.isNotEmpty ? ' - $displayName' : ''}',
          targetName: username,
          refreshDashboard: true,
          metadata: {
            'username': username,
            'firstname': firstname,
            'lastname': lastname,
            'phone': phone,
            'profile_id': profileId,
            'expiration': expiration,
          },
        );
      }
      return ok;
    } catch (e) {
      dev.log('createSubscriber error: $e', name: 'SUBS');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSubscriberDetails(int userId) async {
    try {
      final response = await _sas4Dio.get('${ApiConstants.sas4GetUser}/$userId');
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data['data'] ?? data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshSingleSubscriber(int userId) async {
    try {
      final details = await getSubscriberDetails(userId);
      if (details == null) return;
      final idx = state.subscribers.indexWhere((s) => s.idx == userId.toString());
      if (idx == -1) return;
      final existing = state.subscribers[idx];
      final updated = _mergeSubscriberDetails(existing, details, userId);
      final newList = List<SubscriberModel>.from(state.subscribers);
      newList[idx] = updated;
      final newSearchResults =
          _replaceSubscriberInList(state.searchResults, updated);
      final newOnlineUsers = updated.isOnline
          ? _replaceSubscriberInList(state.onlineUsers, updated)
          : state.onlineUsers.where((s) => s.idx != updated.idx).toList();
      final localOffline = newList.where((s) => s.isOffline).length;
      try { _ref.read(dashboardProvider.notifier).updateOfflineCount(localOffline); } catch (_) {}
      state = state.copyWith(
        subscribers: newList,
        searchResults: newSearchResults,
        onlineUsers: newOnlineUsers,
        sas4OfflineCount: localOffline,
      );
    } catch (e) {
      dev.log('refreshSingleSubscriber error: $e', name: 'SUBS');
    }
  }

  void setLastPaymentPreview({
    required String username,
    required String description,
    double? amount,
    String? actionType,
    String? movementLabel,
    String? paymentType,
  }) {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || description.trim().isEmpty) return;
    final updated = Map<String, Map<String, dynamic>>.from(state.lastPayments);
    updated[cleanUsername] = {
      'subscriber_username': cleanUsername,
      'action_type': actionType,
      'action_description': description,
      'amount': amount,
      'movement_label': movementLabel,
      'payment_type': paymentType,
      'created_at': DateTime.now().toIso8601String(),
    };
    state = state.copyWith(lastPayments: updated);
  }

  Future<void> refreshSubscriberAfterOperation(
    int userId, {
    bool refreshLastPayments = false,
    String? paymentUsername,
    String? paymentDescription,
    double? paymentAmount,
    String? paymentActionType,
    String? paymentMovementLabel,
    String? paymentType,
  }) async {
    await refreshSingleSubscriber(userId);

    if (paymentUsername != null && paymentDescription != null) {
      setLastPaymentPreview(
        username: paymentUsername,
        description: paymentDescription,
        amount: paymentAmount,
        actionType: paymentActionType,
        movementLabel: paymentMovementLabel,
        paymentType: paymentType,
      );
    }

    if (refreshLastPayments) {
      await Future.delayed(const Duration(milliseconds: 350));
      await loadLastPayments();
    }
  }

  void removeSubscriberFromList(int userId) {
    final newList = state.subscribers.where((s) => s.idx != userId.toString()).toList();
    final localOffline = newList.where((s) => s.isOffline).length;
    try { _ref.read(dashboardProvider.notifier).updateOfflineCount(localOffline); } catch (_) {}
    state = state.copyWith(subscribers: newList, totalRecords: newList.length, sas4OfflineCount: localOffline);
  }

  Future<Map<String, dynamic>?> getActivationData(int userId) async {
    try {
      final response =
          await _sas4Dio.get('${ApiConstants.sas4ActivationData}/$userId');
      final data = response.data;
      if (data is Map && data['status'] == 200 && data['data'] != null) {
        return Map<String, dynamic>.from(data['data']);
      }
      dev.log(
        'getActivationData unexpected payload: ${data is Map ? "status=${data['status']} message=${data['message']}" : data.runtimeType}',
        name: 'SUBS',
      );
      return null;
    } on DioException catch (e) {
      dev.log(
        'getActivationData failed: ${e.response?.statusCode} ${e.requestOptions.uri} body=${e.response?.data}',
        name: 'SUBS',
      );
      return null;
    } catch (e) {
      dev.log('getActivationData error: $e', name: 'SUBS');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getExtensionData(int userId) async {
    try {
      final response =
          await _sas4Dio.get('${ApiConstants.sas4ExtensionData}/$userId');
      final data = response.data;
      if (data is Map && data['status'] == 200 && data['data'] != null) {
        return Map<String, dynamic>.from(data['data']);
      }
      if (data is Map && data['data'] != null) {
        return Map<String, dynamic>.from(data['data']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllowedExtensions(int packageId) async {
    try {
      final response = await _sas4Dio
          .get('${ApiConstants.sas4AllowedExtensions}/$packageId');
      if (response.data is Map && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (response.data is List) {
        return (response.data as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getPackageDetails(int packageId) async {
    try {
      final response =
          await _sas4Dio.get('${ApiConstants.sas4ProfileDetail}/$packageId');
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data['data'] ?? data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> activateSubscriber({
    required int userId,
    required double userPrice,
    required dynamic activationUnits,
    required String currentNotes,
    bool isCash = false,
    bool isPartialCash = false,
    double partialCashAmount = 0,
    String? packageName,
    double? originalPrice,
    double? discountAmount,
  }) async {
    try {
      final currentBalance = double.tryParse(currentNotes) ?? 0;
      double newNotes;

      if (isCash) {
        if (isPartialCash) {
          newNotes = currentBalance - userPrice + partialCashAmount;
        } else {
          newNotes = currentBalance;
        }
      } else {
        newNotes = currentBalance - userPrice;
      }

      final txnId = 'txn_${DateTime.now().millisecondsSinceEpoch}_$userId';

      final payload = EncryptionService.encrypt({
        'method': 'credit',
        'pin': '',
        'user_id': userId.toString(),
        'money_collected': 1,
        'notes': newNotes.toString(),
        'user_price': userPrice,
        'issue_invoice': true,
        'transaction_id': txnId,
        'activation_units': activationUnits,
      });

      final response = await _sas4Dio.post(
        ApiConstants.sas4ActivateUser,
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final rData = response.data;
      final isSuccess = response.statusCode == 200 ||
          rData?['status'] == 200 ||
          rData?['success'] == true;

      if (isSuccess) {
        await updateUserNotes(userId, newNotes);

        String paymentLabel;
        if (isCash) {
          paymentLabel = isPartialCash ? 'نقدي جزئي' : 'نقدي';
        } else {
          paymentLabel = 'غير نقدي';
        }

        final subName = _findUsername(userId);
        final activateAction = isCash
            ? (isPartialCash ? 'activate_subscriber_partial_cash' : 'activate_subscriber_cash')
            : 'activate_subscriber_non_cash';
        final pkgName = packageName ?? '';
        final priceFormatted = _formatIQD(userPrice);
        String desc = 'تفعيل المشترك $subName | الباقة: $pkgName | السعر: $priceFormatted IQD | $paymentLabel';
        if (isPartialCash) {
          desc += ' (${_formatIQD(partialCashAmount)} IQD)';
        }
        logActivity(
          action: activateAction,
          description: desc,
          targetId: userId,
          targetName: subName,
          refreshDashboard: true,
          metadata: {
            'package_name': pkgName,
            'user_price': userPrice,
            'original_price': originalPrice ?? userPrice,
            'discount_amount': discountAmount ?? 0,
            'has_discount': (discountAmount ?? 0) > 0,
            'amount': userPrice,
            'price': userPrice,
            'final_price': userPrice,
            'payment_type': paymentLabel,
            'partial_cash_amount': isPartialCash ? partialCashAmount : 0,
            'new_balance': newNotes,
            'previous_balance': double.tryParse(currentNotes) ?? 0,
            'units': activationUnits,
            'username': subName,
          },
        );

        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> extendSubscription({
    required int userId,
    required int profileId,
    required String method,
  }) async {
    try {
      final txnId = 'txn_${DateTime.now().millisecondsSinceEpoch}_$userId';

      final payload = EncryptionService.encrypt({
        'user_id': userId.toString(),
        'profile_id': profileId.toString(),
        'method': method,
        'transaction_id': txnId,
      });

      final response = await _sas4Dio.post(
        ApiConstants.sas4ExtendUser,
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      if (response.data?['status'] == 200) {
        final subName = _findUsername(userId);
        logActivity(
          action: 'extend_subscriber',
          description: 'تمديد اشتراك المشترك: $subName',
          targetId: userId,
          targetName: subName,
          refreshDashboard: true,
          metadata: {
            'package_id': profileId,
            'extension_type': method == 'reward_points' ? 'نقاط' : 'رصيد',
            'username': subName,
          },
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> renameSubscriber(int userId, String newUsername) async {
    try {
      final oldName = _findUsername(userId);
      final payload =
          EncryptionService.encrypt({'new_username': newUsername});
      final response = await _sas4Dio.post(
        '${ApiConstants.sas4RenameUser}/$userId',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      final ok = response.data?['status'] == 200 || response.statusCode == 200;
      if (ok) {
        logActivity(
          action: 'edit_subscriber',
          description: 'تغيير اسم المشترك من $oldName إلى $newUsername',
          targetId: userId,
          targetName: newUsername,
          metadata: {
            'old_username': oldName,
            'new_username': newUsername,
          },
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changeProfile(int userId, int profileId) async {
    try {
      final subName = _findUsername(userId);
      final payload = EncryptionService.encrypt({
        'user_id': userId.toString(),
        'profile_id': profileId,
        'change_type': 'immediate',
      });
      final response = await _sas4Dio.post(
        ApiConstants.sas4ChangeProfile,
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      final ok = response.data?['status'] == 200 || response.statusCode == 200;
      if (ok) {
        logActivity(
          action: 'edit_subscriber',
          description: 'تغيير باقة المشترك: $subName',
          targetId: userId,
          targetName: subName,
          metadata: {
            'profile_id': profileId,
            'username': subName,
          },
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getUserOverview(int userId) async {
    try {
      final response =
          await _sas4Dio.get('${ApiConstants.sas4UserOverview}/$userId');
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data['data'] ?? data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> toggleSubscriber(int id, {required bool enable}) async {
    try {
      final subName = _findUsername(id);
      final payload = EncryptionService.encrypt({'user_ids': [id]});
      final endpoint =
          enable ? ApiConstants.sas4EnableUser : ApiConstants.sas4DisableUser;

      final response = await _sas4Dio.post(
        endpoint,
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      final ok = response.data?['status'] == 200 ||
          response.data?['success'] == true ||
          response.statusCode == 200;
      if (ok) {
        logActivity(
          action: 'edit_subscriber',
          description: enable
              ? 'تفعيل حساب المشترك: $subName'
              : 'تعطيل حساب المشترك: $subName',
          targetId: id,
          targetName: subName,
          metadata: {
            'enabled': enable,
            'username': subName,
          },
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateSubscriber(int userId, Map<String, dynamic> data) async {
    try {
      final payload = EncryptionService.encrypt(data);
      final response = await _sas4Dio.put(
        '${ApiConstants.sas4GetUser}/$userId',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      final ok = response.statusCode == 200 || response.statusCode == 201;
      if (ok) {
        logActivity(
          action: 'edit_subscriber',
          description: 'تعديل بيانات المشترك: ${data['username'] ?? userId}',
          targetId: userId,
          targetName: data['username']?.toString() ?? userId.toString(),
          refreshDashboard: true,
          metadata: {
            'firstname': data['firstname'],
            'lastname': data['lastname'],
            'phone': data['phone'],
          },
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  static String _formatIQD(double v) {
    final intl_fmt = intl.NumberFormat('#,###');
    return intl_fmt.format(v.abs().round());
  }

  String _findUsername(int userId) {
    final match = state.subscribers.where(
      (s) => s.idx == userId.toString(),
    );
    if (match.isNotEmpty) return match.first.username;
    return userId.toString();
  }

  Future<void> logActivity({
    required String action,
    required String description,
    dynamic targetId,
    String? targetName,
    Map<String, dynamic>? metadata,
    bool refreshDashboard = false,
  }) async {
    try {
      final adminId = await _storage.getAdminId();
      final adminUsername = await _storage.getAdminUsername();
      if (adminId == null) return;
      await _backendDio.post(
        '/api/activities/log-subscriber',
        data: {
          'adminId': adminId,
          'adminUsername': adminUsername ?? adminId,
          'action': action,
          'description': description,
          'targetId': targetId?.toString(),
          'targetName': targetName,
          'metadata': metadata,
        },
      );
      if (refreshDashboard) {
        // Daily activations list + counters
        try {
          await _ref
              .read(dashboardProvider.notifier)
              .refreshDailyActivations(adminId);
        } catch (_) {}
        // Totals on the dashboard (total / active / expired / online) so a
        // new subscriber, a delete, a toggle etc. visibly shift the KPI
        // cards without waiting for the 30s auto-timer.
        try {
          await _ref.read(dashboardProvider.notifier).refreshCountsOnly();
        } catch (_) {}
        // Reports screens re-fetch when the epoch bumps.
        try {
          _ref.read(reportsProvider.notifier).triggerRefresh();
        } catch (_) {}
      }
    } catch (e) {
      dev.log('logActivity error: $e', name: 'SUBS');
    }
  }

  /// Matches React's updateUserComments: GET full user, merge notes, PUT back.
  Future<bool> updateUserNotes(int userId, double newNotesValue) async {
    try {
      final userDetails = await getSubscriberDetails(userId);
      if (userDetails == null) return false;

      userDetails['notes'] = newNotesValue.toString();
      userDetails.remove('id');
      userDetails.remove('idx');
      userDetails.remove('profile_details');

      final payload = EncryptionService.encrypt(userDetails);
      final response = await _sas4Dio.put(
        '${ApiConstants.sas4GetUser}/$userId',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      dev.log('updateUserNotes error: $e', name: 'SUBS');
      return false;
    }
  }

  /// Pay debt: newNotes = current + amount (moves negative toward zero)
  Future<bool> payDebt({
    required int userId,
    required String username,
    required double amount,
    String? paymentNotes,
  }) async {
    try {
      final details = await getSubscriberDetails(userId);
      if (details == null) return false;

      final currentNotes = _parseNotes(details);
      final newNotes = currentNotes + amount;
      final remaining = newNotes < 0 ? newNotes.abs() : 0.0;
      final credit = newNotes > 0 ? newNotes : 0.0;

      final ok = await updateUserNotes(userId, newNotes);
      if (ok) {
        logActivity(
          action: 'deduct_balance',
          description: 'تسديد دين ${_formatIQD(amount)} IQD من المشترك: $username${paymentNotes != null ? ' - $paymentNotes' : ''}',
          targetId: userId,
          targetName: username,
          refreshDashboard: true,
          metadata: {
            'amount': amount,
            'previous_balance': currentNotes,
            'new_balance': newNotes,
            'remaining_debt': remaining,
            'credit': credit,
            'payment_notes': paymentNotes,
          },
        );
      }
      return ok;
    } catch (e) {
      dev.log('payDebt error: $e', name: 'SUBS');
      return false;
    }
  }

  /// Add debt: newNotes = current - amount (makes more negative)
  Future<bool> addDebt({
    required int userId,
    required String username,
    required double amount,
    String? comment,
  }) async {
    try {
      final details = await getSubscriberDetails(userId);
      if (details == null) return false;

      final currentNotes = _parseNotes(details);
      final newNotes = currentNotes - amount;

      final ok = await updateUserNotes(userId, newNotes);
      if (ok) {
        logActivity(
          action: 'add_balance',
          description: 'إضافة دين ${_formatIQD(amount)} IQD للمشترك: $username${comment != null ? ' - $comment' : ''}',
          targetId: userId,
          targetName: username,
          refreshDashboard: true,
          metadata: {
            'amount': amount,
            'previous_comment': currentNotes,
            'new_comment': newNotes,
            'comment': comment,
          },
        );
      }
      return ok;
    } catch (e) {
      dev.log('addDebt error: $e', name: 'SUBS');
      return false;
    }
  }

  Future<bool> deleteSubscriber(int id, {bool forceSkipDebtCheck = false}) async {
    try {
      if (!forceSkipDebtCheck) {
        final details = await getSubscriberDetails(id);
        if (details != null) {
          final notes = _parseNotes(details);
          if (notes < 0) return false;
        }
      }

      final response = await _sas4Dio.delete('${ApiConstants.sas4GetUser}/$id');
      final ok = response.data?['status'] == 200 || response.statusCode == 200;
      if (ok) {
        final subName = _findUsername(id);
        logActivity(
          action: 'delete_subscriber',
          description: 'حذف مشترك: $subName',
          targetId: id,
          targetName: subName,
          refreshDashboard: true,
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> manageDebt(int userId, Map<String, dynamic> debtData) async {
    try {
      final payload = EncryptionService.encrypt(debtData);
      await _sas4Dio.post(
        '${ApiConstants.sas4UserDebt}/$userId',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final subscribersProvider =
    StateNotifierProvider<SubscribersNotifier, SubscribersState>((ref) {
  return SubscribersNotifier(
    ref.read(backendDioProvider),
    ref.read(sas4DioProvider),
    ref.read(storageServiceProvider),
    ref,
  );
});
