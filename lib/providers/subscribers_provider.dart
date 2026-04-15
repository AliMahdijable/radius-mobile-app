import 'dart:developer' as dev;
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
  final String sortBy;
  final String sortDirection;
  final Map<String, Map<String, dynamic>> lastPayments;

  const SubscribersState({
    this.subscribers = const [],
    this.searchResults = const [],
    this.packages = const [],
    this.isLoading = false,
    this.isSearching = false,
    this.error,
    this.totalRecords = 0,
    this.filter = 'all',
    this.sortBy = 'username',
    this.sortDirection = 'asc',
    this.lastPayments = const {},
  });

  List<SubscriberModel> get filteredSubscribers {
    List<SubscriberModel> list;
    switch (filter) {
      case 'active':
        list = subscribers.where((s) => s.isActive).toList();
        break;
      case 'expired':
        list = subscribers.where((s) => s.isExpired).toList();
        break;
      case 'online':
        list = subscribers.where((s) => s.isOnline).toList();
        break;
      case 'offline':
        list = subscribers.where((s) => s.isOffline).toList();
        break;
      case 'debtors':
        list = subscribers.where((s) => s.hasDebt).toList();
        break;
      case 'nearExpiry':
        list = subscribers.where((s) => s.isNearExpiry).toList();
        break;
      default:
        list = List.of(subscribers);
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
          result = (a.remainingDays ?? 0).compareTo(b.remainingDays ?? 0);
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
    String? sortBy,
    String? sortDirection,
    Map<String, Map<String, dynamic>>? lastPayments,
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
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      lastPayments: lastPayments ?? this.lastPayments,
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
      if (_priceMap.isEmpty) {
        await _loadPriceList(adminId);
      }

      if (state.packages.isEmpty) {
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

      state = state.copyWith(
        subscribers: enriched,
        isLoading: false,
        totalRecords: enriched.length,
      );

      loadLastPayments();
    } catch (e) {
      dev.log('loadSubscribers error: $e', name: 'SUBS');
      state = state.copyWith(isLoading: false, error: 'خطأ في تحميل البيانات');
    }
  }

  Future<void> loadLastPayments() async {
    final adminId = await _storage.getAdminId();
    if (adminId == null) return;
    try {
      final res = await _backendDio.get('${ApiConstants.lastPayments}/$adminId');
      if (res.data is Map && res.data['success'] == true) {
        final payments = res.data['payments'] as List? ?? [];
        final map = <String, Map<String, dynamic>>{};
        for (final p in payments) {
          if (p is Map<String, dynamic>) {
            final username = p['subscriber_username']?.toString() ?? '';
            if (username.isNotEmpty) map[username] = p;
          }
        }
        state = state.copyWith(lastPayments: map);
      }
    } catch (e) {
      dev.log('loadLastPayments error: $e', name: 'SUBS');
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

        await Future.delayed(const Duration(milliseconds: 200));
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
    final localResults = state.subscribers.where((s) {
      return s.username.toLowerCase().contains(q) ||
          s.firstname.toLowerCase().contains(q) ||
          s.lastname.toLowerCase().contains(q) ||
          s.fullName.toLowerCase().contains(q) ||
          (s.phone ?? '').contains(q) ||
          (s.mobile ?? '').contains(q) ||
          (s.profileName ?? '').toLowerCase().contains(q) ||
          (s.parentUsername ?? '').toLowerCase().contains(q);
    }).toList();

    state = state.copyWith(searchResults: localResults, isSearching: false);
  }

  void setFilter(String filter) {
    state = state.copyWith(filter: filter);
  }

  void setSort(String field, String direction) {
    state = state.copyWith(sortBy: field, sortDirection: direction);
  }

  Future<void> loadPackages() async {
    try {
      final adminId = await _storage.getAdminId();

      // 1) Load priceList for user_price lookup (like web's getUserPrice)
      if (_priceMap.isEmpty && adminId != null) {
        await _loadPriceList(adminId);
      }

      List<Map<String, dynamic>> rawPackages = [];

      // 2) PRIMARY: POST /index/profile (same as web fetchAddPackages)
      //    This endpoint returns only regular profiles, NOT extensions
      try {
        dev.log('POST /index/profile ...', name: 'PKG');
        final payload = EncryptionService.encrypt({
          'page': 1,
          'count': 10,
          'sortBy': null,
          'direction': 'asc',
          'search': '',
          'columns': [
            'name', 'price', 'pool', 'downrate', 'uprate',
            'type', 'expiration_amount', 'users_count', 'online_users_count',
          ],
        });

        final response = await _sas4Dio.post(
          ApiConstants.sas4Profiles,
          data: {'payload': payload},
          options: Options(contentType: 'application/x-www-form-urlencoded'),
        );

        var resData = response.data;
        dev.log('POST response type: ${resData.runtimeType}', name: 'PKG');
        if (resData is String) {
          dev.log('POST response is String, decrypting...', name: 'PKG');
          resData = EncryptionService.decrypt(resData);
          dev.log('Decrypted type: ${resData.runtimeType}', name: 'PKG');
        }

        if (resData is Map && resData['data'] is List) {
          rawPackages = (resData['data'] as List)
              .whereType<Map<String, dynamic>>().toList();
          dev.log('POST parsed ${rawPackages.length} from data[]', name: 'PKG');
        } else if (resData is List) {
          rawPackages = resData.whereType<Map<String, dynamic>>().toList();
          dev.log('POST parsed ${rawPackages.length} from root[]', name: 'PKG');
        } else {
          dev.log('POST unexpected response: $resData', name: 'PKG');
        }
      } catch (e) {
        dev.log('POST /index/profile FAILED: $e', name: 'PKG');
      }

      // 3) FALLBACK 1: GET /list/profile/5 (no permission needed)
      if (rawPackages.isEmpty) {
        try {
          dev.log('GET /list/profile/5 ...', name: 'PKG');
          final response = await _sas4Dio.get(ApiConstants.sas4ListProfile);

          var resData = response.data;
          dev.log('GET response type: ${resData.runtimeType}', name: 'PKG');
          if (resData is String) {
            resData = EncryptionService.decrypt(resData);
          }

          if (resData is Map && resData['data'] is List) {
            rawPackages = (resData['data'] as List)
                .whereType<Map<String, dynamic>>().toList();
          } else if (resData is List) {
            rawPackages = resData.whereType<Map<String, dynamic>>().toList();
          }
          dev.log('GET parsed ${rawPackages.length} packages', name: 'PKG');
        } catch (e) {
          dev.log('GET /list/profile/5 FAILED: $e', name: 'PKG');
        }
      }

      // 4) Build PackageModel list + merge user_price from priceList
      final packages = <PackageModel>[];
      if (rawPackages.isNotEmpty) {
        for (final raw in rawPackages) {
          final pkgId = raw['id'] ?? raw['idx'];
          final id = pkgId is int ? pkgId : int.tryParse(pkgId?.toString() ?? '') ?? 0;
          if (id <= 0) continue;
          final name = (raw['name'] ?? '').toString();
          if (name.isEmpty) continue;

          final pi = _priceMap[id];
          final userPrice = pi?['user_price']?.toString()
              ?? raw['user_price']?.toString();

          packages.add(PackageModel(
            idx: id,
            name: name,
            price: (raw['price'] ?? raw['profile_price'])?.toString(),
            userPrice: userPrice,
            type: raw['type']?.toString(),
            expirationAmount: raw['expiration_amount'] is int
                ? raw['expiration_amount']
                : int.tryParse(raw['expiration_amount']?.toString() ?? ''),
          ));
        }
        dev.log('Built ${packages.length} from profile API', name: 'PKG');
      }

      // 5) FALLBACK 2: build from priceList if ALL profile APIs failed
      if (packages.isEmpty && _priceMap.isNotEmpty) {
        dev.log('APIs failed, building from priceList (${_priceMap.length})...', name: 'PKG');
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
        dev.log('Built ${packages.length} from priceList fallback', name: 'PKG');
      }

      dev.log('=== FINAL: ${packages.length} packages ===', name: 'PKG');
      for (final p in packages) {
        dev.log('  [${p.idx}] ${p.name} price=${p.displayPrice} type=${p.type}', name: 'PKG');
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
        data: {'payload': payload},
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

        String actionType;
        String paymentLabel;
        if (isCash) {
          if (isPartialCash) {
            actionType = 'activate_subscriber_partial_cash';
            paymentLabel = 'نقدي جزئي';
          } else {
            actionType = 'activate_subscriber_cash';
            paymentLabel = 'نقدي';
          }
        } else {
          actionType = 'activate_subscriber_non_cash';
          paymentLabel = 'غير نقدي';
        }

        final subName = _findUsername(userId);
        logActivity(
          action: actionType,
          description: 'تفعيل $paymentLabel - المستخدم: $subName | السعر: $userPrice',
          targetId: userId,
          targetName: subName,
          metadata: {
            'user_price': userPrice,
            'payment_type': paymentLabel,
            'partial_cash_amount': isPartialCash ? partialCashAmount : null,
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
      final payload =
          EncryptionService.encrypt({'new_username': newUsername});
      final response = await _sas4Dio.post(
        '${ApiConstants.sas4RenameUser}/$userId',
        data: {'payload': payload},
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
      return response.data?['status'] == 200 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changeProfile(int userId, int profileId) async {
    try {
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
      return response.data?['status'] == 200 || response.statusCode == 200;
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
      final payload = EncryptionService.encrypt({'user_ids': [id]});
      final endpoint =
          enable ? ApiConstants.sas4EnableUser : ApiConstants.sas4DisableUser;

      final response = await _sas4Dio.post(
        endpoint,
        data: {'payload': payload},
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

      final currentNotes = double.tryParse(details['notes']?.toString() ?? '') ?? 0;
      final newNotes = currentNotes + amount;
      final remaining = newNotes < 0 ? newNotes.abs() : 0.0;
      final credit = newNotes > 0 ? newNotes : 0.0;

      final ok = await updateUserNotes(userId, newNotes);
      if (ok) {
        logActivity(
          action: 'deduct_balance',
          description: 'تسديد دين ${amount.toStringAsFixed(0)} من المشترك: $username${paymentNotes != null ? ' - $paymentNotes' : ''}',
          targetId: userId,
          targetName: username,
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

      final currentNotes = double.tryParse(details['notes']?.toString() ?? '') ?? 0;
      final newNotes = currentNotes - amount;

      final ok = await updateUserNotes(userId, newNotes);
      if (ok) {
        logActivity(
          action: 'add_balance',
          description: 'إضافة دين للمشترك: $username${comment != null ? ' - $comment' : ''}',
          targetId: userId,
          targetName: username,
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
          final notes =
              double.tryParse(details['notes']?.toString() ?? '') ?? 0;
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
  );
});
