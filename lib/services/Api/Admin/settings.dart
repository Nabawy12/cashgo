import 'package:flutter/foundation.dart';

import '../../../models/login.dart';
import '../../db/db_helper.dart';

class ApiService {
  static void _applyPermissionsToSession(dynamic raw) {
    Session.invoice_log = false;
    Session.receive_from_suppliers = false;
    Session.pay_credit = false;
    Session.discount = false;
    Session.canViewCredit = false;

    if (raw is Map) {
      Session.invoice_log = _truthy(raw['invoice_log']);
      Session.receive_from_suppliers = _truthy(raw['receive_from_suppliers']);
      Session.pay_credit = _truthy(raw['pay_credit']);
      Session.discount = _truthy(raw['discount']);
      Session.canViewCredit = _truthy(raw['can_view_credit']);
    }
  }

  static bool _truthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes' || text == 'on';
  }

  static Future<int> syncAllUsers(
      {String? adminUser, String? adminPass}) async {
    final users = await DBHelper.instance.getUsers();
    return users.length;
  }

  static Future<List<Map<String, dynamic>>> getUsers(
      {String? adminUser, String? adminPass}) async {
    return DBHelper.instance.getUsers();
  }

  static Future<void> createUser(
    String username,
    String password, {
    String role = 'cashier',
    String? adminUser,
    String? adminPass,
    Map<String, dynamic>? extraBody,
  }) async {
    final permissions =
        Map<String, dynamic>.from(extraBody?['permissions'] ?? {});
    await DBHelper.instance.insertUser(
      username: username,
      password: password,
      role: role,
      permissions: permissions,
      canViewCredit: _truthy(permissions['can_view_credit']),
    );
  }

  static Future<void> updateUser(
    int id, {
    String? username,
    String? password,
    String? adminUser,
    String? adminPass,
    Map<String, dynamic>? extraBody,
  }) async {
    final permissions = extraBody?['permissions'];
    final permissionMap =
        permissions is Map ? Map<String, dynamic>.from(permissions) : null;
    await DBHelper.instance.updateUserLocal(
      id,
      username: username,
      password: password,
      permissions: permissionMap,
      canViewCredit: permissionMap == null
          ? null
          : _truthy(permissionMap['can_view_credit']),
    );
    if (username != null &&
        Session.currentUsername != null &&
        Session.currentUsername == username) {
      Session.currentUsername = username;
    }
  }

  static Future<void> deleteUser(int id,
      {String? adminUser, String? adminPass}) async {
    await DBHelper.instance.deleteUserLocal(id);
  }

  static Future<void> syncUsersFromList(List<Map<String, String>> rows,
      {String? adminUser, String? adminPass}) async {
    for (final user in rows) {
      final username = user['username'] ?? '';
      final password = user['password'] ?? '';
      if (username.isEmpty || password.isEmpty) continue;
      await createUser(username, password, role: user['role'] ?? 'cashier');
    }
  }

  static Future<Map<String, dynamic>> login(String username, String password,
      {bool allowOffline = true}) async {
    try {
      final user = await DBHelper.instance.login(username, password);
      if (user == null) {
        return {
          'status': 'error',
          'message': 'Invalid local credentials',
          'code': 401
        };
      }

      Session.currentUsername = user['username']?.toString() ?? username;
      Session.currentRole = user['role']?.toString() ?? 'cashier';
      _applyPermissionsToSession(user['permissions']);
      Session.canViewCredit = _truthy(user['can_view_credit']) ||
          (user['permissions'] is Map &&
              _truthy((user['permissions'] as Map)['can_view_credit']));
      Session.updateDateTime();
      await DBHelper.instance
          .setCurrentUserByUsername(Session.currentUsername!);

      return {
        'status': 'success_offline',
        'message': 'Authenticated locally',
        'data': user
      };
    } catch (e, st) {
      if (kDebugMode)
        debugPrint('[ApiService.login] local login failed: $e\n$st');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> loginOnline(
      String username, String password) {
    return login(username, password, allowOffline: true);
  }
}
