/// canonical → SAS4 prm_* mapping (مطابق server/sas4Permissions.js).
/// نستعمل المفاتيح الـcanonical في كل الـUI gates عشان نفس النظام مع الويب.
const Map<String, String> kSasPermissionMap = {
  'subscribers.view':            'prm_users_index',
  'subscribers.create':          'prm_users_create',
  'subscribers.edit':            'prm_users_update',
  'subscribers.rename':          'prm_users_rename',
  'subscribers.delete':          'prm_users_delete',
  'subscribers.activate':        'prm_users_activate',
  'subscribers.activate_credit': 'prm_users_activate_credit',
  'subscribers.extend':          'prm_users_extend',
  'subscribers.toggle':          'prm_users_enable_disable',
  'subscribers.disconnect':      'prm_users_disconnect',
  'subscribers.show_password':   'prm_users_show_password',
  'subscribers.change_profile':  'prm_users_change_profile',
  'subscribers.pay_debt':        'prm_users_deposit',
  'subscribers.add_debt':        'prm_users_withdrawal',
  'subscribers.history':         'prm_users_history',
  'subscribers.add_traffic':     'prm_users_add_traffic',
  'packages.view':               'prm_profiles_index',
  'packages.create':             'prm_profiles_create',
  'packages.edit':               'prm_profiles_update',
  'packages.delete':             'prm_profiles_delete',
  'managers.view':               'prm_managers_index',
  'managers.create':             'prm_managers_create',
  'managers.edit':               'prm_managers_update',
  'managers.delete':             'prm_managers_delete',
  'managers.deposit':            'prm_managers_deposit',
  'managers.withdrawal':         'prm_managers_withdrawal',
  'reports.activations':         'prm_report_activations',
  'reports.sessions':            'prm_report_sessions',
  'reports.users':               'prm_report_users',
  'reports.financial':           'prm_billing',
};

class UserModel {
  final String id;
  final String username;
  final String role;
  final String token;
  final String expiresAt;
  /// SAS4 permissions (للأدمن العادي) — مثل 'prm_managers_create'.
  final List<String> permissions;
  final bool canAccessManagers;
  final bool canAccessPackages;

  /// الفاعل موظف (نظامنا الداخلي) لا أدمن SAS4. لمّا true الـtoken يكون
  /// JWT خاص بنا (مع marker `_ms`) وليس SAS4 مباشر.
  final bool isEmployee;
  final int? employeeId;
  final String? employeeUsername;
  final String? employeeFullName;
  /// صلاحيات الموظف الـ40 (subscribers.activate, whatsapp.send, ...) كـMap.
  /// فاضي لأي أدمن عادي. يُستعمل لـUI gating محلياً.
  final Map<String, bool> employeePermissions;

  const UserModel({
    required this.id,
    required this.username,
    required this.role,
    required this.token,
    required this.expiresAt,
    this.permissions = const [],
    this.canAccessManagers = false,
    this.canAccessPackages = false,
    this.isEmployee = false,
    this.employeeId,
    this.employeeUsername,
    this.employeeFullName,
    this.employeePermissions = const {},
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final rawPermissions = (json['permissions'] as List?) ??
        (user['permissions'] as List?) ??
        const [];
    final isEmp = (user['role']?.toString() ?? 'admin') == 'employee';
    final emp = user['employee'] as Map<String, dynamic>?;
    final empPermsRaw = emp?['permissions'];
    final empPerms = <String, bool>{};
    if (empPermsRaw is Map) {
      empPermsRaw.forEach((k, v) {
        empPerms[k.toString()] = v == true;
      });
    }
    return UserModel(
      id: (user['id'] ?? json['adminId'] ?? '').toString(),
      username: (user['username'] ?? json['adminUsername'] ?? '').toString(),
      role: (user['role'] ?? 'admin').toString(),
      token: (json['token'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      permissions: rawPermissions.map((e) => e.toString()).toList(),
      canAccessManagers:
          (json['canAccessManagers'] ?? user['canAccessManagers']) == true,
      canAccessPackages:
          (json['canAccessPackages'] ?? user['canAccessPackages']) == true,
      isEmployee: isEmp,
      employeeId: emp != null ? int.tryParse(emp['id']?.toString() ?? '') : null,
      employeeUsername: emp?['username']?.toString(),
      employeeFullName: emp?['full_name']?.toString(),
      employeePermissions: empPerms,
    );
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? role,
    String? token,
    String? expiresAt,
    List<String>? permissions,
    bool? canAccessManagers,
    bool? canAccessPackages,
    bool? isEmployee,
    int? employeeId,
    String? employeeUsername,
    String? employeeFullName,
    Map<String, bool>? employeePermissions,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
      permissions: permissions ?? this.permissions,
      canAccessManagers: canAccessManagers ?? this.canAccessManagers,
      canAccessPackages: canAccessPackages ?? this.canAccessPackages,
      isEmployee: isEmployee ?? this.isEmployee,
      employeeId: employeeId ?? this.employeeId,
      employeeUsername: employeeUsername ?? this.employeeUsername,
      employeeFullName: employeeFullName ?? this.employeeFullName,
      employeePermissions: employeePermissions ?? this.employeePermissions,
    );
  }

  /// فحص صلاحية موظف. الأدمن العادي = true دائماً (full access).
  bool hasEmployeePermission(String key) {
    if (!isEmployee) return true;
    return employeePermissions[key] == true;
  }

  /// فحص أي صلاحية من قائمة (anyOf).
  bool hasAnyEmployeePermission(List<String> keys) {
    if (!isEmployee) return true;
    return keys.any((k) => employeePermissions[k] == true);
  }

  /// فحص صلاحية أدمن SAS4 — يقبل canonical key (مثل 'subscribers.delete').
  /// لو المفتاح مش في الـmap (ميزة محلية مثل send_whatsapp): يرجع true.
  /// الموظف: نستعمل employeePermissions بدلها.
  bool canSas(String canonicalKey) {
    if (isEmployee) return employeePermissions[canonicalKey] == true;
    final prm = kSasPermissionMap[canonicalKey];
    if (prm == null) return true; // ميزة محلية، السماح افتراضي للأدمن
    return permissions.contains(prm);
  }

  /// مزدوجة: الموظف يحتاج permission خاصته AND الأدمن SAS4 يسمح. للحالة الموحّدة:
  /// الموظف يستعمل employeePermissions، الأدمن SAS — `can(key)` يغطّي كلاهما.
  bool can(String canonicalKey) => canSas(canonicalKey);

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role,
        'token': token,
        'expiresAt': expiresAt,
        'permissions': permissions,
        'canAccessManagers': canAccessManagers,
        'canAccessPackages': canAccessPackages,
        'isEmployee': isEmployee,
        'employeeId': employeeId,
        'employeeUsername': employeeUsername,
        'employeeFullName': employeeFullName,
        'employeePermissions': employeePermissions,
      };
}
