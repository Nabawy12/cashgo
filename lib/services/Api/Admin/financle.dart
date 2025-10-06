// insert_financial_account_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// موديل للسجل المالي
class FinancialAccount {
  final int? id;
  final double startingAmount;
  final double maxLimit;
  final double cashInWallet;

  /// الآن للقراءة فقط — قد تكون null عند إنشاء سجل جديد محليًا
  final double? totalInDrawer;
  final DateTime? createdAt;

  FinancialAccount({
    this.id,
    required this.startingAmount,
    required this.maxLimit,
    required this.cashInWallet,
    this.totalInDrawer, // قد تكون null إذا السجل لم يُرجع من السيرفر بعد
    this.createdAt,
  });

  /// لو عايز totalInDrawer يتحسب لو مش موجود (اختياري)
  FinancialAccount.withComputedTotal({
    this.id,
    required this.startingAmount,
    required this.maxLimit,
    required this.cashInWallet,
    DateTime? createdAt,
  })  : totalInDrawer = startingAmount + cashInWallet,
        createdAt = createdAt;

  factory FinancialAccount.fromJson(Map<String, dynamic> json) {
    double? parseNullableNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      try {
        return double.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return FinancialAccount(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      startingAmount: (json['starting_amount'] ?? json['startingAmount']) is num
          ? (json['starting_amount'] ?? json['startingAmount']).toDouble()
          : double.parse((json['starting_amount'] ?? json['startingAmount']).toString()),
      maxLimit: (json['max_limit'] ?? json['maxLimit']) is num
          ? (json['max_limit'] ?? json['maxLimit']).toDouble()
          : double.parse((json['max_limit'] ?? json['maxLimit']).toString()),
      cashInWallet: (json['cash_in_wallet'] ?? json['cashInWallet']) is num
          ? (json['cash_in_wallet'] ?? json['cashInWallet']).toDouble()
          : double.parse((json['cash_in_wallet'] ?? json['cashInWallet']).toString()),
      // هنا نقرأ totalInDrawer من السيرفر إن كان موجود — وإلا نخليها null
      totalInDrawer: parseNullableNum(json['total_in_drawer'] ?? json['totalInDrawer']),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  /// JSON طالع للـ POST — **لا نرسل total_in_drawer** لأن الحقل قراءة فقط في السيرفر.
  /// (نحتفظ بtoJson كمحتوى يُرسل للـ API عند إنشاء/تحديث)
  Map<String, dynamic> toJsonForServer() {
    return {
      'starting_amount': startingAmount,
      'max_limit': maxLimit,
      'cash_in_wallet': cashInWallet,
      // لا نضع 'total_in_drawer' هنا عمدًا
    };
  }

  /// لو احتجت تمثيل كامل محلي (بما في ذلك total لو موجود) — لكن لا تستخدمه للـ POST.
  Map<String, dynamic> toJsonFull() {
    return {
      'starting_amount': startingAmount,
      'max_limit': maxLimit,
      'cash_in_wallet': cashInWallet,
      'total_in_drawer': totalInDrawer,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'FinancialAccount(id: $id, start: $startingAmount, max: $maxLimit, cash: $cashInWallet, total: $totalInDrawer, createdAt: $createdAt)';
  }
}

/// استثناء عام للـ API
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// استثناء للتحقق (validation) بيرجع قائمة الأخطاء من السيرفر
class ValidationException implements Exception {
  final List<String> errors;
  ValidationException(this.errors);
  @override
  String toString() => 'ValidationException: ${errors.join(', ')}';
}

/// السيرفيس اللي بيتكلم مع الـ PHP endpoint
class InsertFinancialAccountService {
  final String baseUrl; // مثال: https://your-server.com/api
  final http.Client _client;
  final Duration timeout;

  InsertFinancialAccountService({
    this.baseUrl = "https://nabawisolution.com",
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        timeout = timeout ?? const Duration(seconds: 15);

  String _endpoint() => baseUrl.endsWith('/') ? '${baseUrl}/financial_account.php' : '$baseUrl/financial_account.php';

  /// إدراج سجل جديد
  /// نرسل payload بدون totalInDrawer (لأن السيرفر يتجاهله/لا يقبله من العميل)
  /// يرجع FinancialAccount الذي أدخله السيرفر (مع id و created_at و total_in_drawer من السيرفر)
  Future<FinancialAccount> insert(FinancialAccount payload) async {
    final url = Uri.parse(_endpoint());
    // استخدم toJsonForServer لنتأكد أننا لا نرسل total_in_drawer
    final body = jsonEncode(payload.toJsonForServer());

    http.Response res;
    try {
      res = await _client
          .post(
        url,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      )
          .timeout(timeout);
    } on SocketException catch (e) {
      throw ApiException('شبكة غير متاحة: ${e.message}');
    } on Exception catch (e) {
      throw ApiException('فشل الاتصال: ${e.toString()}');
    }

    // تفريغ الرد
    final status = res.statusCode;
    final respBody = res.body.isNotEmpty ? jsonDecode(res.body) : null;

    if (status == 200) {
      if (respBody is Map && respBody['success'] == true) {
        final data = respBody['data'] ?? respBody; // some endpoints return data directly
        if (data is Map<String, dynamic>) {
          return FinancialAccount.fromJson(data);
        } else {
          throw ApiException('استجابة غير متوقعة من السيرفر', status);
        }
      } else if (respBody is Map && respBody['errors'] != null) {
        // Validation errors (422 handled by our PHP with code 422, but just in case)
        final errors = List<String>.from(respBody['errors'].map((e) => e.toString()));
        throw ValidationException(errors);
      } else {
        throw ApiException(respBody?['message'] ?? 'خطأ في الاستجابة', status);
      }
    } else if (status == 422) {
      // رسائل تحقق
      if (respBody is Map && respBody['errors'] != null) {
        final errors = List<String>.from(respBody['errors'].map((e) => e.toString()));
        throw ValidationException(errors);
      } else {
        throw ApiException('بيانات غير صالحة', status);
      }
    } else {
      throw ApiException('HTTP ${status}: ${respBody?['message'] ?? res.body}', status);
    }
  }

  /// جلب آخر سجلات (GET)
  Future<List<FinancialAccount>> getLatest({int limit = 10}) async {
    final url = Uri.parse('${_endpoint()}?limit=$limit');

    http.Response res;
    try {
      res = await _client.get(url).timeout(timeout);
    } on SocketException catch (e) {
      throw ApiException('شبكة غير متاحة: ${e.message}');
    } on Exception catch (e) {
      throw ApiException('فشل الاتصال: ${e.toString()}');
    }

    final status = res.statusCode;
    final respBody = res.body.isNotEmpty ? jsonDecode(res.body) : null;

    if (status == 200) {
      if (respBody is Map && respBody['success'] == true && respBody['data'] != null) {
        final data = respBody['data'];
        if (data is List) {
          return data.map<FinancialAccount>((e) => FinancialAccount.fromJson(Map<String, dynamic>.from(e))).toList();
        }
      }
      throw ApiException('استجابة غير متوقعة من السيرفر', status);
    } else {
      throw ApiException('HTTP ${status}: ${res.body}', status);
    }
  }

  /// تفريغ موارد الـ http client لو احتجت
  void dispose() {
    _client.close();
  }
}
