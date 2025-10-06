// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../models/login.dart';

/// ApiService موحّد: يدعم Basic Auth عبر adminUser/adminPass، يدعم extraBody
/// (Map/List تُرمّز إلى JSON تلقائياً)، ويحاول أسماء actions متعددة للمرونة.
class ApiService {
  static const String baseUrl = "https://nabawisolution.com/user_api.php";

  // --- داخلي: POST واحد موثوق مع دعم Basic Auth و debug logs ---
  static Future<Map<String, dynamic>> _post(
      Map<String, String> body, {
        String? adminUser,
        String? adminPass,
        Duration timeout = const Duration(seconds: 15),
      }) async {
    final uri = Uri.parse(baseUrl);
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };

    if (adminUser != null && adminPass != null) {
      final token = base64Encode(utf8.encode('$adminUser:$adminPass'));
      headers['Authorization'] = 'Basic $token';
    }

    if (kDebugMode) {
      print('=== API POST ===');
      print('URL: $uri');
      print('Headers: $headers');
      print('Body: $body');
    }

    final res = await http.post(uri, headers: headers, body: body).timeout(timeout);

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

    // اعتبر 200 أو 201 نجاح عام — وإلا نرفع استثناء بمسج من السيرفر إن وُجد
    if (res.statusCode == 200 || res.statusCode == 201) {
      return j;
    } else {
      final msg = (j['message'] ?? j['error'] ?? 'Server error ${res.statusCode}').toString();
      throw Exception(msg);
    }
  }

  // --- مساعدة: stringify أي خريطة إلى Map<String,String> مع ترميز JSON للقيم المركبة ---
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

  // ---------------------------
  // Helper: apply permissions to Session
  // accepts Map / List / JSON-string / comma-separated string
  // ---------------------------
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
        final k = it?.toString()?.toLowerCase();
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
    if (k == 'discount' || k.contains('discount') || k.contains('discount') || k.contains('discount')) {
      Session.discount = true;
      return;
    }
  }

  // ================== Users API ==================

  /// جلب المستخدمين. بعض الخوادم تطلب مصادقة لإظهار القائمة — يمكنك تمرير adminUser/adminPass.
  /// بعد الاستجابة نبحث عن المستخدم الحالي (Session.currentUsername) ونحدث صلاحيات الجلسة إن وُجدت.
  static Future<List<Map<String, dynamic>>> getUsers({String? adminUser, String? adminPass}) async {
    try {
      final j = await _post({'action': 'list_users'}, adminUser: adminUser, adminPass: adminPass);
      if (j['status'] == 'success' && j['data'] is List) {
        final list = List<Map<String, dynamic>>.from(j['data']);
        // حاول تحديث Session من سجل المستخدم إذا وجد نفس اسم المستخدم
        for (var u in list) {
          final uname = (u['username'] ?? '').toString();
          if (Session.currentUsername != null && uname == Session.currentUsername) {
            _applyPermissionsToSession(u['permissions']);
            // update role if available
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
      throw Exception(j['message'] ?? 'Unexpected response for list_users');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('unauthorized') || msg.contains('authentication') || msg.contains('required')) {
        throw Exception('list_users requires admin authentication or is not supported by server: ${e.toString()}');
      }
      rethrow;
    }
  }

  /// إنشاء مستخدم. يدعم extraBody (مثلاً {'permissions': { ... }})
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
      final body = _stringifyBody(merged);
      try {
        final j = await _post(body, adminUser: adminUser, adminPass: adminPass);
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

  /// تحديث مستخدم (يدعم username, password, extraBody مثل permissions)
  /// ملاحظة: نحدّث Session فقط إذا كان واضحًا أن الهدف هو المستخدم الحالي
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
      final body = _stringifyBody(merged);
      try {
        final j = await _post(body, adminUser: adminUser, adminPass: adminPass);
        if (j['status'] == 'success' || j['status'] == 'ok') {
          // لو المستخدم اللي حدثناه هو نفس المستخدم في الجلسة (بالمطابقة بالاسم) حدّث Session
          if (username != null && Session.currentUsername != null && username == Session.currentUsername) {
            Session.currentUsername = username;
            if (merged.containsKey('role')) Session.currentRole = merged['role']?.toString() ?? Session.currentRole;
            if (merged.containsKey('permissions')) _applyPermissionsToSession(merged['permissions']);
          } else {
            // احتمال آخر: لو extraBody يحتوي permissions ولا يوجد username ممرّر،
            // لا نغيّر Session لأننا لا نعرف إن كان الهدف هو المستخدم الحالي.
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

  /// حذف مستخدم
  static Future<void> deleteUser(int id, {String? adminUser, String? adminPass}) async {
    final attempts = [
      {'action': 'delete_user', 'user_id': id.toString(), 'id': id.toString()},
      {'action': 'delete', 'user_id': id.toString(), 'id': id.toString()},
    ];
    Exception? lastErr;
    for (var bodyBase in attempts) {
      final body = Map<String, String>.from(bodyBase);
      try {
        final j = await _post(body, adminUser: adminUser, adminPass: adminPass);
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

  /// مزامنة قائمة مستخدمين (مفيد لاستيراد)
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

  // ====== Login (كما كان) ======
  static Future<Map<String, dynamic>?> loginOnline(String username, String password) async {
    final uri = Uri.parse(baseUrl);
    try {
      final resp = await http.post(uri, body: {
        'action': 'login',
        'username': username,
        'password': password,
      }).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        print('=== API LOGIN ===');
        print('URL: $uri');
        print('Status: ${resp.statusCode}');
        print('Headers: ${resp.headers}');
        print('Body: ${resp.body}');
      }

      Map<String, dynamic>? jsonResp;
      try {
        jsonResp = json.decode(resp.body) as Map<String, dynamic>?;
      } catch (_) {
        jsonResp = null;
      }

      if (resp.statusCode == 200) {
        // إذا الرجوع ناجح وحملنا بيانات المستخدم، حدّث Session تلقائياً
        if (jsonResp != null) {
          final data = jsonResp['data'] ?? jsonResp;
          if (data is Map) {
            Session.currentUsername = data['username']?.toString() ?? Session.currentUsername;
            Session.currentRole = data['role']?.toString() ?? Session.currentRole;
            _applyPermissionsToSession(data['permissions']);
            Session.updateDateTime();
          }
        }
        return jsonResp ?? {'status': 'error', 'message': 'Invalid response from server'};
      } else if (resp.statusCode == 401) {
        final msg = jsonResp != null && jsonResp['message'] != null ? jsonResp['message'].toString() : 'Unauthorized';
        return {'status': 'error', 'message': msg, 'code': 401};
      } else {
        final msg = jsonResp != null && jsonResp['message'] != null ? jsonResp['message'].toString() : 'Server error ${resp.statusCode}';
        return {'status': 'error', 'message': msg, 'code': resp.statusCode};
      }
    } on SocketException catch (e) {
      if (kDebugMode) print('SocketException: $e');
      rethrow;
    } catch (e) {
      rethrow;
    }
  }
}
