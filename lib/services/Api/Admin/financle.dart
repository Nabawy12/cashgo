import 'package:hive/hive.dart';

import '../../db/db_helper.dart';

class FinancialAccount {
  final int? id;
  final double startingAmount;
  final double maxLimit;
  final double? totalInDrawer;
  final DateTime? createdAt;

  FinancialAccount({
    this.id,
    required this.startingAmount,
    required this.maxLimit,
    this.totalInDrawer,
    this.createdAt,
  });

  FinancialAccount.withComputedTotal({
    this.id,
    required this.startingAmount,
    required this.maxLimit,
    DateTime? createdAt,
  })  : totalInDrawer = startingAmount,
        createdAt = createdAt;

  factory FinancialAccount.fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    return FinancialAccount(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      startingAmount:
          parseNum(json['starting_amount'] ?? json['startingAmount']),
      maxLimit: parseNum(json['max_limit'] ?? json['maxLimit']),
      totalInDrawer: json['total_in_drawer'] == null
          ? null
          : parseNum(json['total_in_drawer']),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  Map<String, dynamic> toJsonForServer() => {
        'starting_amount': startingAmount,
        'max_limit': maxLimit,
      };

  Map<String, dynamic> toJsonFull() => {
        'id': id,
        'starting_amount': startingAmount,
        'max_limit': maxLimit,
        'total_in_drawer': totalInDrawer ?? startingAmount,
        'created_at':
            createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      };
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ValidationException implements Exception {
  final List<String> errors;
  ValidationException(this.errors);
  @override
  String toString() => 'ValidationException: ${errors.join(', ')}';
}

class InsertFinancialAccountService {
  final String baseUrl;
  final Duration timeout;

  InsertFinancialAccountService({
    this.baseUrl = 'local-sqlite',
    Duration? timeout,
  }) : timeout = timeout ?? const Duration(seconds: 15);

  Future<void> _ensureBoxesOpen() async {
    if (!Hive.isBoxOpen('financial_accounts'))
      await Hive.openBox('financial_accounts');
    if (!Hive.isBoxOpen('meta')) await Hive.openBox('meta');
  }

  Future<void> _writeMetaFromMap(Map<String, dynamic> map) async {
    final meta = await Hive.openBox('meta');
    final starting = (map['starting_amount'] as num?)?.toDouble() ??
        double.tryParse(map['starting_amount']?.toString() ?? '');
    if (starting != null) await meta.put('starting_amount', starting);
    final id = map['id'];
    if (id != null) await meta.put('financial_account_id', id.toString());
    if (starting != null) {
      await DBHelper.instance.setFixedShiftOpeningBalance(starting);
    }
  }

  Future<FinancialAccount> insert(FinancialAccount payload) async {
    await _ensureBoxesOpen();
    final box = Hive.box('financial_accounts');
    final id = DateTime.now().millisecondsSinceEpoch;
    final map = payload.toJsonFull()..['id'] = id;
    await box.put(id.toString(), map);
    await _writeMetaFromMap(map);
    return FinancialAccount.fromJson(map);
  }

  Future<FinancialAccount> update(FinancialAccount payload) async {
    await _ensureBoxesOpen();
    final box = Hive.box('financial_accounts');
    final id = payload.id ?? DateTime.now().millisecondsSinceEpoch;
    final map = payload.toJsonFull()..['id'] = id;
    await box.put(id.toString(), map);
    await _writeMetaFromMap(map);
    return FinancialAccount.fromJson(map);
  }

  Future<List<FinancialAccount>> getLatest({int limit = 10}) async {
    await _ensureBoxesOpen();
    final box = Hive.box('financial_accounts');
    final rows = <FinancialAccount>[];
    for (final key in box.keys.toList().reversed) {
      if (rows.length >= limit) break;
      final raw = box.get(key);
      if (raw is Map)
        rows.add(FinancialAccount.fromJson(Map<String, dynamic>.from(raw)));
    }
    return rows;
  }

  Future<void> flushQueuedOps() async {}

  void dispose() {}
}
