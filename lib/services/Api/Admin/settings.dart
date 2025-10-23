// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../models/login.dart';

/// ApiService موحّد: يدعم Basic Auth عبر adminUser/adminPass، يدعم extraBody
/// (Map/List تُرمّز إلى JSON تلقائيًا)، ويحاول أسماء actions متعددة للمرونة.
/// **جديد:** لو لا يوجد اتصال، يحفظ الطلب في صندوق 'ops' داخل Hive كعملية للرفع لاحقًا.
/// كما يدعم تسجيل الدخول أوفلاين (بعد حفظ بيانات مستخدم ناجح أونلاين).
class ApiService {
  static const String baseUrl = "https://nabawisolution.com/user_api.php";
  static final Uuid _uuid = Uuid();

  // ================== Helpers: apply permissions to Session ==================
  static void _applyPermissionsToSession(dynamic raw) {
    // safe defaults
    Session.invoice_log = false;
    Session.receive_from_suppliers = false;
    Session.wallet_tx = false;
    Session.pay_credit = false;
    Session.discount = false;

    if (raw == null) return;

    // if Map
    if (raw is Map) {
      Session.invoice_log = _truthy(raw['invoice_log']);
      Session.receive_from_suppliers = _truthy(raw['receive_from_suppliers']);
      Session.wallet_tx = _truthy(raw['wallet_tx']);
      Session.pay_credit = _truthy(raw['pay_credit']);
      Session.discount = _truthy(raw['discount']);
      return;
    }

    // if List of keys
    if (raw is List) {
      for (var it in raw) {
        final k = it?.toString().toLowerCase();
        if (k == null) continue;
        _setSessionByKey(k);
      }
      return;
    }

    // if String: try decode JSON, else comma-separated
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return;
      try {
        final dec = json.decode(s);
        _applyPermissionsToSession(dec);
        return;
      } catch (_) {
        final parts = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
        for (var p in parts) {
          _setSessionByKey(p.toLowerCase());
        }
        return;
      }
    }
  }

  static bool _truthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'on';
  }

  static void _setSessionByKey(String k) {
    if (k == 'invoice_log' || k.contains('invoice') || k.contains('فاتورة') || k.contains('فواتير')) {
      Session.invoice_log = true;
      return;
    }
    if (k == 'receive_from_suppliers' || k.contains('receive') || k.contains('استلام') || k.contains('مورد')) {
      Session.receive_from_suppliers = true;
      return;
    }
    if (k == 'wallet_tx' || k.contains('wallet') || k.contains('محفظة') || k.contains('سحب') || k.contains('ايداع') || k.contains('إيداع')) {
      Session.wallet_tx = true;
      return;
    }
    if (k == 'pay_credit' || k.contains('credit') || k.contains('كريدت') || k.contains('دفع')) {
      Session.pay_credit = true;
      return;
    }
    if (k == 'discount' || k.contains('discount') || k.contains('خصم') || k.contains('تخفيض')) {
      Session.discount = true;
      return;
    }
  }

  // ===========================
  // Utility: hashing & local user store (for offline login)
  // ===========================
  static String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(salt + password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static String _generateSalt() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final randomSeed = utf8.encode('$now-${_uuid.v4()}');
    return sha256.convert(randomSeed).toString().substring(0, 16);
  }

  static Future<void> _saveUserLocally(
      Map<String, dynamic> userData, {
        String? plainPassword,
        String? passwordHash,
        String? salt,
      }) async {
    final box = await Hive.openBox('users'); // key = username
    final username = (userData['username'] ?? userData['user'] ?? '').toString();
    if (username.isEmpty) return;

    String storeSalt = '';
    String storeHash = '';

    // 1) إذا السيرفر أعطانا hash/salt نستخدمهم مباشرة (أفضل)
    if (passwordHash != null && passwordHash.isNotEmpty) {
      storeHash = passwordHash;
      storeSalt = salt ?? '';
    } else if (plainPassword != null && plainPassword.isNotEmpty) {
      // 2) إذا عندنا الباسورد بالنص (من محاولة login ناجحة) نولد salt ونحسب hash محليًا
      storeSalt = _generateSalt();
      storeHash = _hashPassword(plainPassword, storeSalt);
    } else {
      // 3) لا شيء جديد: احتفظ بالقيم القديمة إن وجدت
      final existing = box.get(username);
      if (existing != null && existing is Map) {
        storeSalt = existing['salt'] ?? '';
        storeHash = existing['password_hash'] ?? '';
      }
    }

    final local = <String, dynamic>{
      'username': username,
      'salt': storeSalt,
      'password_hash': storeHash,
      'role': userData['role']?.toString() ?? '',
      'permissions': userData['permissions'] ?? userData['perms'] ?? null,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
      'raw': userData, // original payload for convenience
    };

    await box.put(username, local);
  }
  static Future<Map<String, dynamic>?> _getLocalUser(String username) async {
    final box = await Hive.openBox('users');
    final v = box.get(username);
    if (v == null) return null;
    try {
      return Map<String, dynamic>.from(v as Map);
    } catch (_) {
      return null;
    }
  }

  static bool _verifyLocalPassword(String plainPassword, Map<String, dynamic> localUser) {
    final salt = (localUser['salt'] ?? '').toString();
    final stored = (localUser['password_hash'] ?? '').toString();
    if (salt.isEmpty || stored.isEmpty) return false;
    final h = _hashPassword(plainPassword, salt);
    return h == stored;
  }

  // ===========================
  // Offline helper: queue API operation into Hive 'ops'
  // ===========================
  static Future<Map<String, dynamic>> _queueApiOp(Map<String, dynamic> body) async {
    final opsBox = await Hive.openBox('ops');
    final opId = _uuid.v4();
    final op = {
      'opId': opId,
      'type': 'api',
      'endpoint': baseUrl,
      'method': 'POST',
      'body': body,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'state': 'pending',
      'retries': 0,
    };
    await opsBox.put(opId, op);
    return op;
  }

  // ===========================
  // Connectivity quick check (simple)
  // ===========================
  static Future<bool> _isOnline() async {
    try {
      final c = await Connectivity().checkConnectivity();
      if (c == ConnectivityResult.none) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================
  // New: sync all users from server and save them locally
  // ===========================
  /// Attempts to fetch the full users list from the server and save each user locally.
  /// Returns true if fetch & local save attempted (and list parsed), false otherwise.
  static Future<int> syncAllUsers({String? adminUser, String? adminPass}) async {
    try {
      // نستخدم _post مباشرة؛ اجعل queueIfOffline=false هنا لأننا نريد فشل واضح لو في مشكلة شبكة
      final j = await _post({'action': 'list_users'}, adminUser: adminUser, adminPass: adminPass, queueIfOffline: false);

      List<Map<String, dynamic>> users = [];
      if (j['status'] == 'success' && j['data'] is List) {
        users = List<Map<String, dynamic>>.from(j['data']);
      } else if (j['users'] is List) {
        users = List<Map<String, dynamic>>.from(j['users']);
      } else {
        if (kDebugMode) debugPrint('[ApiService.syncAllUsers] unexpected response: $j');
        return 0;
      }

      int saved = 0;
      for (var u in users) {
        try {
          final Map<String, dynamic> mu = Map<String, dynamic>.from(u);
          // لو السيرفر يحتوي على password_hash/salt استخدمهم
          final pwHash = mu['password_hash']?.toString();
          final salt = mu['salt']?.toString();

          if ((pwHash?.isNotEmpty ?? false)) {
            await _saveUserLocally(mu, plainPassword: null, passwordHash: pwHash, salt: salt);
          } else {
            // خزّن بيانات المستخدم بدون hash — يبقى مش هينفعه login أوفلاين لحد ما يعمل login مرة أونلاين
            await _saveUserLocally(mu, plainPassword: null);
          }
          saved++;
        } catch (e) {
          if (kDebugMode) debugPrint('[ApiService.syncAllUsers] failed saving user: $e');
        }
      }

      if (kDebugMode) debugPrint('[ApiService.syncAllUsers] synced $saved users locally.');
      return saved;
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiService.syncAllUsers] error: $e');
      rethrow;
    }
  }
  // --- داخلي: POST واحد موثوق مع دعم Basic Auth و debug logs ---
  /// إذا queueIfOffline=true ووجدنا offline، سنخزن العملية في 'ops' ونعيد
  /// Map({ 'status': 'queued', 'opId': '...', 'message': 'Saved to ops' })
  static Future<Map<String, dynamic>> _post(
      Map<String, dynamic> body, {
        String? adminUser,
        String? adminPass,
        Duration timeout = const Duration(seconds: 15),
        bool queueIfOffline = true,
      }) async {
    // stringify body to Map<String,String>
    final mapBody = _stringifyBody(body);

    // debug logs
    if (kDebugMode) {
      print('=== API POST (attempt) ===');
      print('URL: $baseUrl');
      print('Headers: {Content-Type: application/x-www-form-urlencoded, Accept: application/json, Authorization?}');
      print('Body: $mapBody');
    }

    final online = await _isOnline();
    if (!online) {
      if (queueIfOffline) {
        final op = await _queueApiOp(body);
        if (kDebugMode) debugPrint('[ApiService] Offline — queued op ${op['opId']}');
        return {'status': 'queued', 'message': 'No connectivity — queued locally', 'opId': op['opId']};
      } else {
        throw Exception('No network connectivity');
      }
    }

    // build headers
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };
    if (adminUser != null && adminPass != null) {
      final token = base64Encode(utf8.encode('$adminUser:$adminPass'));
      headers['Authorization'] = 'Basic $token';
    }

    try {
      final uri = Uri.parse(baseUrl);
      final res = await http.post(uri, headers: headers, body: mapBody).timeout(timeout);

      if (kDebugMode) {
        print('Status: ${res.statusCode}');
        print('Response: ${res.body}');
      }

      if (res.body.isEmpty) {
        throw Exception('Empty response from server (${res.statusCode})');
      }

      Map<String, dynamic> j;
      try {
        j = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid JSON from server: ${res.body}');
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        return j;
      } else {
        final msg = (j['message'] ?? j['error'] ?? 'Server error ${res.statusCode}').toString();
        throw Exception(msg);
      }
    } on SocketException catch (e) {
      // شبكي مفاجئ — نسمح بالـ queue كخيار احتياطي
      if (queueIfOffline) {
        final op = await _queueApiOp(body);
        if (kDebugMode) debugPrint('[ApiService] SocketException — queued op ${op['opId']}: $e');
        return {'status': 'queued', 'message': 'SocketException — queued locally', 'opId': op['opId']};
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------
  // Helper: stringify أي خريطة إلى Map<String,String> مع ترميز JSON للقيم المركبة ---
  static Map<String, String> _stringifyBody(Map<String, dynamic> src) {
    final Map<String, String> out = {};
    src.forEach((k, v) {
      if (v == null) return;
      if (v is String) {
        out[k] = v;
      } else if (v is num || v is bool) {
        out[k] = v.toString();
      } else if (v is Map || v is List) {
        out[k] = json.encode(v);
      } else {
        out[k] = v.toString();
      }
    });
    return out;
  }

  // ================== Users API ==================
  static Future<List<Map<String, dynamic>>> getUsers({String? adminUser, String? adminPass}) async {
    try {
      final j = await _post({'action': 'list_users'}, adminUser: adminUser, adminPass: adminPass);
      if (j['status'] == 'success' && j['data'] is List) {
        final list = List<Map<String, dynamic>>.from(j['data']);
        for (var u in list) {
          final uname = (u['username'] ?? '').toString();
          if (Session.currentUsername != null && uname == Session.currentUsername) {
            _applyPermissionsToSession(u['permissions']);
            Session.currentRole = u['role']?.toString() ?? Session.currentRole;
            break;
          }
        }
        return list;
      }
      if (j['users'] is List) {
        final list = List<Map<String, dynamic>>.from(j['users']);
        for (var u in list) {
          final uname = (u['username'] ?? '').toString();
          if (Session.currentUsername != null && uname == Session.currentUsername) {
            _applyPermissionsToSession(u['permissions']);
            Session.currentRole = u['role']?.toString() ?? Session.currentRole;
            break;
          }
        }
        return list;
      }
      // if queued (offline) return empty list to indicate nothing fetched now
      if (j['status'] == 'queued') return [];
      throw Exception(j['message'] ?? 'Unexpected response for list_users');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('unauthorized') || msg.contains('authentication') || msg.contains('required')) {
        throw Exception('list_users requires admin authentication or is not supported by server: ${e.toString()}');
      }
      rethrow;
    }
  }

  static Future<void> createUser(
      String username,
      String password, {
        String role = 'cashier',
        String? adminUser,
        String? adminPass,
        Map<String, dynamic>? extraBody,
      }) async {
    final attempts = [
      {'action': 'create_user'},
      {'action': 'create'},
    ];
    Exception? lastErr;
    for (var base in attempts) {
      final merged = Map<String, dynamic>.from(base);
      merged['username'] = username;
      merged['password'] = password;
      merged['role'] = role;
      if (extraBody != null) merged.addAll(extraBody);
      try {
        final j = await _post(merged, adminUser: adminUser, adminPass: adminPass);
        // if queued, return early (we consider queued as accepted for offline workflow)
        if (j['status'] == 'queued') return;
        if (j['status'] == 'success' || j['status'] == 'ok') return;
        if (j['message'] != null) throw Exception(j['message']);
      } catch (e) {
        lastErr = e is Exception ? e : Exception(e.toString());
        final low = e.toString().toLowerCase();
        if (low.contains('unauthorized') || low.contains('authentication') || low.contains('required')) {
          throw Exception('Authentication required to create user: ${e.toString()}');
        }
      }
    }
    throw lastErr ?? Exception('Create user failed');
  }

  static Future<void> updateUser(
      int id, {
        String? username,
        String? password,
        String? adminUser,
        String? adminPass,
        Map<String, dynamic>? extraBody,
      }) async {
    if ((username == null || username.isEmpty) && (password == null || password.isEmpty) && (extraBody == null || extraBody.isEmpty)) {
      throw Exception('No fields to update');
    }

    final attempts = [
      {'action': 'update_user', 'user_id': id.toString(), 'id': id.toString()},
      {'action': 'update', 'user_id': id.toString(), 'id': id.toString()},
    ];

    Exception? lastErr;
    for (var base in attempts) {
      final merged = Map<String, dynamic>.from(base);
      if (username != null && username.isNotEmpty) merged['username'] = username;
      if (password != null && password.isNotEmpty) merged['password'] = password;
      if (extraBody != null) merged.addAll(extraBody);
      try {
        final j = await _post(merged, adminUser: adminUser, adminPass: adminPass);
        if (j['status'] == 'queued') return; // queued treated as success for offline workflow
        if (j['status'] == 'success' || j['status'] == 'ok') {
          if (username != null && Session.currentUsername != null && username == Session.currentUsername) {
            Session.currentUsername = username;
            if (merged.containsKey('role')) Session.currentRole = merged['role']?.toString() ?? Session.currentRole;
            if (merged.containsKey('permissions')) _applyPermissionsToSession(merged['permissions']);
          }
          return;
        }
        if (j['message'] != null) throw Exception(j['message']);
      } catch (e) {
        lastErr = e is Exception ? e : Exception(e.toString());
        final low = e.toString().toLowerCase();
        if (low.contains('unauthorized') || low.contains('authentication')) {
          throw Exception('Authentication required to update user: ${e.toString()}');
        }
      }
    }
    throw lastErr ?? Exception('Update user failed');
  }

  static Future<void> deleteUser(int id, {String? adminUser, String? adminPass}) async {
    final attempts = [
      {'action': 'delete_user', 'user_id': id.toString(), 'id': id.toString()},
      {'action': 'delete', 'user_id': id.toString(), 'id': id.toString()},
    ];
    Exception? lastErr;
    for (var bodyBase in attempts) {
      try {
        final j = await _post(Map<String, dynamic>.from(bodyBase), adminUser: adminUser, adminPass: adminPass);
        if (j['status'] == 'queued') return;
        if (j['status'] == 'success' || j['status'] == 'ok') return;
        if (j['message'] != null) throw Exception(j['message']);
      } catch (e) {
        lastErr = e is Exception ? e : Exception(e.toString());
        final low = e.toString().toLowerCase();
        if (low.contains('unauthorized') || low.contains('authentication')) {
          throw Exception('Authentication required to delete user: ${e.toString()}');
        }
      }
    }
    throw lastErr ?? Exception('Delete user failed');
  }

  // ====== Utilities ======
  static Future<void> syncUsersFromList(List<Map<String, String>> rows, {String? adminUser, String? adminPass}) async {
    for (var user in rows) {
      final username = user['username'] ?? '';
      final password = user['password'] ?? '';
      final role = user['role'] ?? 'cashier';
      if (username.isEmpty || password.isEmpty) {
        if (kDebugMode) print('Skipping invalid row: $user');
        continue;
      }
      try {
        await createUser(username, password, role: role, adminUser: adminUser, adminPass: adminPass);
        if (kDebugMode) print('Created $username');
      } catch (e) {
        if (kDebugMode) print('Failed to create $username: $e');
      }
    }
  }

  // ====== Login (offline-capable) ======
  /// Attempts online login first; if fails and allowOffline==true, tries local authentication.
  /// Returns a Map with status: 'success', 'success_offline', 'error', or 'queued' for queued ops.
  static Future<Map<String, dynamic>> login(String username, String password, {bool allowOffline = true}) async {
    // Attempt online first if connectivity is available
    try {
      final conn = await Connectivity().checkConnectivity();
      final online = conn != ConnectivityResult.none;

      if (online) {
        final uri = Uri.parse(baseUrl);
        final resp = await http.post(uri, body: {
          'action': 'login',
          'username': username,
          'password': password,
        }).timeout(const Duration(seconds: 12));

        Map<String, dynamic>? jsonResp;
        try {
          jsonResp = json.decode(resp.body) as Map<String, dynamic>?;
        } catch (_) {
          jsonResp = null;
        }

        if (resp.statusCode == 200 && jsonResp != null) {
          final data = jsonResp['data'] ?? jsonResp;
          if (data is Map) {
            // حفظ المستخدم الحالي محلياً مع هاش الباسورد (مهم للأوفلاين)
            await _saveUserLocally(Map<String, dynamic>.from(data), plainPassword: password);

            // تحديث الـ Session
            Session.currentUsername = data['username']?.toString() ?? username;
            Session.currentRole = data['role']?.toString() ?? Session.currentRole;
            _applyPermissionsToSession(data['permissions']);
            Session.updateDateTime();

            // محاولة مزامنة جميع المستخدمين بعد حفظ المستخدم الحالي
            // (best-effort — لو فشلت مش هنعطل تسجيل الدخول)
            try {
              await syncAllUsers();
            } catch (e) {
              if (kDebugMode) debugPrint('[ApiService.login] syncAllUsers failed: $e');
            }
          }
          return {'status': 'success', 'data': jsonResp};
        } else if (resp.statusCode == 401) {
          final msg = jsonResp != null && jsonResp['message'] != null ? jsonResp['message'].toString() : 'Unauthorized';
          return {'status': 'error', 'message': msg, 'code': 401};
        } else {
          final msg = jsonResp != null && jsonResp['message'] != null ? jsonResp['message'].toString() : 'Server error ${resp.statusCode}';
          if (!allowOffline) return {'status': 'error', 'message': msg, 'code': resp.statusCode};
          // else fallthrough to try local
          if (kDebugMode) debugPrint('[ApiService.login] server returned error, will attempt offline if allowed: $msg');
        }
      }
    } catch (e) {
      if (!(allowOffline)) {
        rethrow;
      }
      if (kDebugMode) debugPrint('[ApiService.login] online attempt failed: $e');
    }

    // Offline fallback: try local credentials
    if (allowOffline) {
      final local = await _getLocalUser(username);
      if (local != null) {
        final ok = _verifyLocalPassword(password, local);
        if (ok) {
          final raw = local['raw'];
          if (raw is Map) {
            Session.currentUsername = raw['username']?.toString() ?? username;
            Session.currentRole = raw['role']?.toString() ?? Session.currentRole;
            _applyPermissionsToSession(raw['permissions']);
          } else {
            Session.currentUsername = username;
          }
          Session.updateDateTime();
          return {'status': 'success_offline', 'message': 'Authenticated locally', 'data': local};
        } else {
          return {'status': 'error', 'message': 'Invalid credentials (offline) - wrong password', 'code': 401};
        }
      } else {
        return {'status': 'error', 'message': 'No local credentials available', 'code': 404};
      }
    }

    return {'status': 'error', 'message': 'Login failed'};
  }

  /// Backwards-compatible wrapper (calls login with allowOffline=false)
  static Future<Map<String, dynamic>?> loginOnline(String username, String password) async {
    final res = await login(username, password, allowOffline: false);
    // adapt to previous nullable Map return type
    return res;
  }
}
