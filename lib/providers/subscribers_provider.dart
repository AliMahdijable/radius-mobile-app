import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/storage_service.dart';
import '../core/services/encryption_service.dart';
import '../models/subscriber_model.dart';

class SubscribersState {
  final List<SubscriberModel> subscribers;
  final List<SubscriberModel> searchResults;
  final List<PackageModel> packages;
  final bool isLoading;
  final bool isSearching;
  final String? error;
  final int totalRecords;
  final String filter;

  const SubscribersState({
    this.subscribers = const [],
    this.searchResults = const [],
    this.packages = const [],
    this.isLoading = false,
    this.isSearching = false,
    this.error,
    this.totalRecords = 0,
    this.filter = 'all',
  });

  List<SubscriberModel> get filteredSubscribers {
    switch (filter) {
      case 'active':
        return subscribers.where((s) => s.isActive).toList();
      case 'expired':
        return subscribers.where((s) => s.isExpired).toList();
      case 'online':
        return subscribers.where((s) => s.isOnline).toList();
      case 'offline':
        return subscribers.where((s) => s.isOffline).toList();
      case 'debtors':
        return subscribers.where((s) => s.hasDebt).toList();
      case 'nearExpiry':
        return subscribers.where((s) => s.isNearExpiry).toList();
      default:
        return subscribers;
    }
  }

  int get activeCount => subscribers.where((s) => s.isActive).length;
  int get expiredCount => subscribers.where((s) => s.isExpired).length;
  int get onlineCount => subscribers.where((s) => s.isOnline).length;
  int get offlineCount => subscribers.where((s) => s.isOffline).length;
  int get debtorsCount => subscribers.where((s) => s.hasDebt).length;
  int get nearExpiryCount => subscribers.where((s) => s.isNearExpiry).length;

  SubscribersState copyWith({
    List<SubscriberModel>? subscribers,
    List<SubscriberModel>? searchResults,
    List<PackageModel>? packages,
    bool? isLoading,
    bool? isSearching,
    String? error,
    int? totalRecords,
    String? filter,
  }) {
    return SubscribersState(
      subscribers: subscribers ?? this.subscribers,
      searchResults: searchResults ?? this.searchResults,
      packages: packages ?? this.packages,
      isLoading: isLoading ?? this.isLoading,
      isSearching: isSearching ?? this.isSearching,
      error: error,
      totalRecords: totalRecords ?? this.totalRecords,
      filter: filter ?? this.filter,
    );
  }
}

class SubscribersNotifier extends StateNotifier<SubscribersState> {
  final Dio _backendDio;
  final Dio _sas4Dio;
  final StorageService _storage;

  SubscribersNotifier(this._backendDio, this._sas4Dio, this._storage)
      : super(const SubscribersState());

  Map<int, Map<String, dynamic>> _priceMap = {};

  Future<void> loadSubscribers() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      if (state.packages.isEmpty) {
        await loadPackages();
      }

      // Load priceList from SAS4 (simple GET, no encryption)
      if (_priceMap.isEmpty) {
        await _loadPriceList(adminId);
      }

      // Backend: active subscribers with phones
      final response = await _backendDio.get(
        '${ApiConstants.subscribersWithPhones}?adminId=$adminId',
      );

      List<SubscriberModel> activeList = [];
      if (response.data['success'] == true) {
        final rawData = response.data['data'] as List? ?? [];

        if (rawData.isNotEmpty) {
          final first = rawData[0];
          debugPrint('=== DEBUG SUBSCRIBER ===');
          debugPrint('RAW keys: ${first is Map ? first.keys.toList() : "NOT MAP"}');
          debugPrint('RAW profile_name: ${first['profile_name']}');
          debugPrint('RAW profile_id: ${first['profile_id']}');
          debugPrint('RAW profile_details: ${first['profile_details']}');
          debugPrint('RAW price: ${first['price']}');
          debugPrint('RAW profile_price: ${first['profile_price']}');
          debugPrint('========================');
        }

        activeList = rawData
            .map((e) => SubscriberModel.fromJson(e))
            .toList();
      }

      if (activeList.isNotEmpty) {
        final f = activeList[0];
        debugPrint('PARSED[0] profileName="${f.profileName}" profileId=${f.profileId} price="${f.price}"');
      }

      debugPrint('PriceMap: ${_priceMap.length} by ID, ${_priceByName.length} by name');
      if (_priceMap.isNotEmpty) {
        final firstKey = _priceMap.keys.first;
        debugPrint('PriceMap[$firstKey] = ${_priceMap[firstKey]}');
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
        debugPrint('Profile missing, fetching from SAS4...');
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

      if (activeList.isNotEmpty) {
        final f = activeList[0];
        debugPrint('FINAL[0] profileName="${f.profileName}" price="${f.price}" id=${f.profileId}');
      }

      dev.log('Backend: ${activeList.length} active subscribers', name: 'SUBS');

      // Paginated SAS4 call: get ALL subscribers with is_online field
      final sas4All = await _fetchAllSas4();

      debugPrint('SAS4: ${sas4All.length} total subscribers');

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
          ));
        }
      } else {
        debugPrint('SAS4 returned empty, using backend data as fallback');
        finalList = activeList;
      }

      final enriched = finalList
          .map((s) => _enrichWithPackage(s, pkgs))
          .map((s) => _enrichWithPriceList(s))
          .toList();

      debugPrint('Final: ${enriched.length} subs, ${enriched.where((s) => s.isOnline).length} online, ${enriched.where((s) => s.isExpired).length} expired');

      state = state.copyWith(
        subscribers: enriched,
        isLoading: false,
        totalRecords: enriched.length,
      );
    } catch (e) {
      dev.log('loadSubscribers error: $e', name: 'SUBS');
      state = state.copyWith(isLoading: false, error: 'خطأ في تحميل البيانات');
    }
  }

  Map<String, Map<String, dynamic>> _priceByName = {};

  Future<void> _loadPriceList(String adminId) async {
    try {
      final response = await _sas4Dio.get(
        '${ApiConstants.sas4PriceList}/$adminId',
      );

      List<dynamic> items = [];
      if (response.data is Map && response.data['data'] is List) {
        items = response.data['data'];
      } else if (response.data is List) {
        items = response.data;
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
      dev.log('PriceList: ${_priceMap.length} by ID, ${_priceByName.length} by name', name: 'SUBS');
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
        data: 'payload=$payload',
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
      debugPrint('SAS4 profile map: ${result.length} subscribers with profile data');
    } catch (e) {
      debugPrint('fetchProfileMap error: $e');
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
    final plPrice = (userPrice ?? matched['price'] ?? matched['sell_price'])?.toString();
    final resolvedId = sub.profileId
        ?? (matched['id'] is int ? matched['id'] : int.tryParse(matched['id']?.toString() ?? ''));

    final resolvedName = (sub.profileName == null || sub.profileName!.isEmpty)
        ? plName
        : sub.profileName;

    // user_price from priceList ALWAYS takes priority over subscriber.price
    final resolvedPrice = plPrice ?? sub.price;

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

  /// Fetches ALL subscribers from SAS4 with sequential pagination.
  /// Server returns ~10 per page regardless of count, so we loop.
  Future<List<Map<String, dynamic>>> _fetchAllSas4() async {
    final allItems = <Map<String, dynamic>>[];
    int page = 1;
    int totalCount = 0;
    int retries = 0;

    while (true) {
      try {
        final payload = EncryptionService.encrypt({
          'page': page,
          'count': 100,
          'sortBy': 'username',
          'direction': 'asc',
          'search': '',
          'columns': [
            'idx', 'username', 'firstname', 'lastname', 'name',
            'expiration', 'remaining_days', 'notes', 'balance',
            'phone', 'mobile', 'is_online', 'online_status',
            'enabled', 'parent_username', 'profile_details',
            'framedipaddress', 'framed_ip_address',
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
          data: 'payload=$payload',
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

        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        retries++;
        if (retries > 3) {
          debugPrint('SAS4 pagination: giving up at page $page after $retries retries');
          break;
        }
        debugPrint('SAS4 pagination: retry $retries for page $page');
        await Future.delayed(Duration(milliseconds: 800 * retries));
      }
    }

    debugPrint('SAS4 fetched: ${allItems.length}/$totalCount in ${page - 1} pages');
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
    if (query.length < 2) {
      state = state.copyWith(searchResults: [], isSearching: false);
      return;
    }
    state = state.copyWith(isSearching: true);
    try {
      final response = await _backendDio.get(
        '${ApiConstants.subscribersSearch}?search=$query&count=30',
      );
      if (response.data['success'] == true) {
        final rawList = (response.data['data'] as List? ?? [])
            .map((e) => SubscriberModel.fromJson(e))
            .toList();
        final pkgs = state.packages;
        final list = rawList.map((s) => _enrichWithPackage(s, pkgs)).toList();
        state = state.copyWith(searchResults: list, isSearching: false);
      }
    } catch (_) {
      state = state.copyWith(isSearching: false);
    }
  }

  void setFilter(String filter) {
    state = state.copyWith(filter: filter);
  }

  Future<void> loadPackages() async {
    try {
      dev.log('Loading packages from SAS4...', name: 'SUBS');
      final payload = EncryptionService.encrypt({
        'page': 1,
        'count': 100,
        'columns': [
          'idx', 'name', 'name_en', 'rate_limit', 'rate_limit_dl',
          'monthly_fee', 'price', 'profile_price',
        ],
      });

      final response = await _sas4Dio.post(
        ApiConstants.sas4Profiles,
        data: 'payload=$payload',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
        ),
      );

      final data = response.data['data'] as List? ?? [];
      final packages = data.map((e) => PackageModel.fromJson(e)).toList();
      dev.log('Loaded ${packages.length} packages', name: 'SUBS');
      state = state.copyWith(packages: packages);
    } catch (e) {
      dev.log('loadPackages error: $e', name: 'SUBS');
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
  }) async {
    try {
      final adminId = await _storage.getAdminId();
      final payload = EncryptionService.encrypt({
        'username': username,
        'enabled': 1,
        'password': password,
        'confirm_password': password,
        'profile_id': profileId,
        'parent_id': int.tryParse(adminId ?? ''),
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
        data: 'payload=$payload',
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      return response.statusCode == 200 || response.statusCode == 201;
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

  Future<Map<String, dynamic>?> getActivationData(int userId) async {
    try {
      final response =
          await _sas4Dio.get('${ApiConstants.sas4ActivationData}/$userId');
      final data = response.data;
      if (data is Map && data['status'] == 200 && data['data'] != null) {
        return Map<String, dynamic>.from(data['data']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> activateSubscriber({
    required int userId,
    required double userPrice,
    required int activationUnits,
    required String currentNotes,
    String method = 'credit',
  }) async {
    try {
      final currentBalance = double.tryParse(currentNotes) ?? 0;
      final newNotes = (currentBalance - userPrice).toString();
      final txnId = 'txn_${DateTime.now().millisecondsSinceEpoch}_$userId';

      final payload = EncryptionService.encrypt({
        'method': method,
        'pin': '',
        'user_id': userId.toString(),
        'money_collected': 1,
        'notes': newNotes,
        'user_price': userPrice,
        'issue_invoice': true,
        'transaction_id': txnId,
        'activation_units': activationUnits,
      });

      final response = await _sas4Dio.post(
        ApiConstants.sas4ActivateUser,
        data: {'payload': payload},
      );

      if (response.data?['status'] == 200) {
        await _sas4Dio.put(
          '${ApiConstants.sas4GetUser}/$userId',
          data: 'payload=${EncryptionService.encrypt({'notes': newNotes})}',
          options: Options(contentType: 'application/x-www-form-urlencoded'),
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
    String method = 'credit',
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
      );

      return response.data?['status'] == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleSubscriber(int id, {required bool enable}) async {
    try {
      final payload = EncryptionService.encrypt({'user_ids': [id]});
      final endpoint =
          enable ? ApiConstants.sas4EnableUser : ApiConstants.sas4DisableUser;

      final response = await _sas4Dio.post(
        endpoint,
        data: 'payload=$payload',
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      return response.data?['status'] == 200 ||
          response.data?['success'] == true ||
          response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateSubscriber(int userId, Map<String, dynamic> data) async {
    try {
      final payload = EncryptionService.encrypt(data);
      final response = await _sas4Dio.put(
        '${ApiConstants.sas4GetUser}/$userId',
        data: 'payload=$payload',
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSubscriber(int id, {bool forceSkipDebtCheck = false}) async {
    try {
      if (!forceSkipDebtCheck) {
        final details = await getSubscriberDetails(id);
        if (details != null) {
          final notes =
              double.tryParse(details['notes']?.toString() ?? '') ?? 0;
          if (notes < 0) return false;
        }
      }

      final response = await _sas4Dio.delete('${ApiConstants.sas4GetUser}/$id');
      return response.data?['status'] == 200 || response.statusCode == 200;
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
  );
});
