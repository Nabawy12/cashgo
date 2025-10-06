// services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../models/cashier/profit.dart';

class ApiServiceProfit {
  ApiServiceProfit._internal();
  static final ApiServiceProfit instance = ApiServiceProfit._internal();

  // عدّل الـ baseUrl بحسب بيئتك
  final String baseUrl = 'https://nabawisolution.com';
  final http.Client _client = http.Client();

  /// Fetch list of profits by cashier name
  Future<List<Profit>> fetchProfitsByCashier(
      String cashierName, {
        Duration timeout = const Duration(seconds: 10),
      }) async {
    final uri = Uri.parse('$baseUrl/get_profit.php');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({'cashier_name': cashierName});

    try {
      final response =
      await _client.post(uri, headers: headers, body: body).timeout(timeout);

      // server responded OK
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        // if backend returns an error object { "error": "..." }
        if (decoded is Map && decoded.containsKey('error')) {
          throw Exception(decoded['error'] ?? 'Unknown server error');
        }

        // expect a list of rows
        if (decoded is List) {
          return decoded
              .map<Profit>((item) => Profit.fromJson(item))
              .toList();
        } else {
          throw Exception('Unexpected response format from server');
        }
      } else {
        // non-200
        String message = 'Server error: ${response.statusCode}';
        // try to extract error message from body
        try {
          final bodyDecoded = jsonDecode(response.body);
          if (bodyDecoded is Map && bodyDecoded.containsKey('error')) {
            message += ' - ${bodyDecoded['error']}';
          }
        } catch (_) {}
        throw Exception(message);
      }
    } on TimeoutException {
      throw Exception('Request timed out. حاول مرة أخرى.');
    } on http.ClientException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  /// Optional: close client when app terminates (not usually necessary)
  void dispose() {
    _client.close();
  }
}
