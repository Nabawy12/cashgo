// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class CloseShiftResponse {
  final bool success;
  final String message;
  final int? insertId;
  final String? startTime;
  final String? endTime;

  CloseShiftResponse({
    required this.success,
    required this.message,
    this.insertId,
    this.startTime,
    this.endTime,
  });

  factory CloseShiftResponse.fromJson(Map<String, dynamic> json) {
    return CloseShiftResponse(
      success: json['success'] == true || json['success'] == 1,
      message: json['message']?.toString() ?? '',
      insertId: json.containsKey('insert_id') ? (json['insert_id'] is int ? json['insert_id'] : int.tryParse(json['insert_id'].toString())) : null,
      startTime: json['start_time']?.toString(),
      endTime: json['end_time']?.toString(),
    );
  }
}

class ApiServiceClose_shieft {
  final String baseUrl;

  ApiServiceClose_shieft({this.baseUrl = 'https://nabawisolution.com'});

  /// closeShift: startTimeParam يمكن يكون DateTime أو String.
  /// إذا كان DateTime يتم تحويله إلى "yyyy-MM-dd HH:mm:ss".
  /// إذا كان String نحاول parse بصيغ شائعة لتطبيعها، وإذا فشل نرسله كما هو.
  Future<CloseShiftResponse> closeShift({
    required String cashierName,
    required dynamic startTimeParam, // DateTime or String
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final endpoint = Uri.parse('$baseUrl/close_shift.php');

    String formattedStart;

    // تحضير قيمة start_time كسلسلة
    if (startTimeParam is DateTime) {
      formattedStart = DateFormat('yyyy-MM-dd HH:mm:ss').format(startTimeParam);
    } else if (startTimeParam is String) {
      // نحاول تحويل السلسلة إلى DateTime ثم نصيغها، وإلا نرسلها كما هي
      try {
        final parsed = DateTime.parse(startTimeParam);
        formattedStart = DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
      } catch (_) {
        try {
          final parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parse(startTimeParam);
          formattedStart = DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed);
        } catch (_) {
          // لا نستطيع تحليلها — نرسلها كما وردت
          formattedStart = startTimeParam;
        }
      }
    } else {
      return CloseShiftResponse(success: false, message: 'startTimeParam must be DateTime or String');
    }

    try {
      final resp = await http
          .post(
        endpoint,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: {
          'cashier_name': cashierName,
          'start_time': formattedStart,
        },
      )
          .timeout(timeout);

      // طباعة الجسم الخام للمساعدة في الـ debugging (تحذفها لو تحب)
      // debugPrint('closeShift raw response: ${resp.body}');

      if (resp.statusCode != 200) {
        return CloseShiftResponse(
          success: false,
          message: 'HTTP ${resp.statusCode}: ${resp.reasonPhrase}\n${resp.body}',
        );
      }

      final jsonBody = json.decode(resp.body);
      if (jsonBody is Map<String, dynamic>) {
        return CloseShiftResponse.fromJson(jsonBody);
      } else {
        return CloseShiftResponse(success: false, message: 'Invalid JSON response');
      }
    } catch (e) {
      return CloseShiftResponse(success: false, message: 'Request failed: $e');
    }
  }
}
