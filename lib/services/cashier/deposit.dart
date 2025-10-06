// profit_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ProfitApi {
  final http.Client _client;

  ProfitApi({http.Client? client}) : _client = client ?? http.Client();

  /// يعيد خريطة JSON مفككة من رد السيرفر
  Future<Map<String, dynamic>> send({
    required String cashierName,
    required double depositFromCashToWallet,
    required double depositFromWalletToCash,
  }) async {
    final uri = Uri.parse('https://nabawisolution.com/profit.php');

    final body = jsonEncode({
      'cashier_name': cashierName,
      'deposit_from_cash_to_wallet': depositFromCashToWallet,
      'deposit_from_wallet_to_cash': depositFromWalletToCash,
    });

    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('خطأ من السيرفر ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'success': false, 'message': 'رد غير متوقع من السيرفر', 'raw': decoded};
  }

  void dispose() => _client.close();
}
