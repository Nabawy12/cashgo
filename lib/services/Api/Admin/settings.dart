import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../db/db_helper.dart';

class ApiService {
  static const String baseUrl = "https://nabawisolution.com/user_api.php";

  static Future<void> syncUsers() async {
    final db = await DBHelper.instance.database;
    final rows = await db.query('users'); // local sqlite table 'users'

    for (var user in rows) {
      final username = (user['username'] ?? '').toString();
      final password = (user['password'] ?? '').toString(); // raw password so PHP hashes it
      final role = (user['role'] ?? 'cashier').toString();

      try {
        final res = await http.post(
          Uri.parse(baseUrl),
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded"
          },
          body: {
            "action": "create",      // مهم جداً
            "username": username,
            "password": password,
            "role": role,
          },
        );

        // طباعة تفصيلية للديباغ
        print("---- SYNC USER: $username ----");
        print("Status code: ${res.statusCode}");
        print("Response headers: ${res.headers}");
        print("Response body: ${res.body}");

        // حاول تفك JSON لو فيه
        try {
          final decoded = jsonDecode(res.body);
          print("Decoded response: $decoded");
        } catch (e) {
          print("Response not JSON or empty");
        }

        if (res.statusCode == 200) {
          // لو السيرفر رجع JSON ناجح
          if (res.body.isNotEmpty) {
            try {
              final j = jsonDecode(res.body);
              if (j['status'] == 'success') {
                print("تم رفع $username بنجاح (server)");
              } else {
                print("سيرفر رجع خطأ ل $username : ${j['message']}");
              }
            } catch (_) {
              print("Server returned 200 لكن body غير JSON أو غير متوقع.");
            }
          } else {
            print("Server returned 200 لكن body فاضي.");
          }
        } else {
          print("HTTP Error for $username: ${res.statusCode}");
        }
      } catch (e) {
        print("Network/exception while uploading $username: $e");
      }
    }
  }
}
