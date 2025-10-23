// insert_financial_account_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

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
    this.totalInDrawer,
    this.createdAt,
  });

  FinancialAccount.withComputedTotal({
    this.id,
    required this.startingAmount,
    required this.maxLimit,
    required this.cashInWallet,
    DateTime? createdAt,
  })  : totalInDrawer = startingAmount + cashInWallet,
        createdAt = createdAt;

  factory FinancialAccount.fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic v, [double fallback = 0.0]) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      try {
        return double.parse(v.toString());
      } catch (_) {
        return fallback;
      }
    }

    return FinancialAccount(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      startingAmount: parseNum(json['starting_amount'] ?? json['startingAmount']),
      maxLimit: parseNum(json['max_limit'] ?? json['maxLimit']),
      cashInWallet: parseNum(json['cash_in_wallet'] ?? json['cashInWallet']),
      totalInDrawer: (json['total_in_drawer'] != null)
          ? parseNum(json['total_in_drawer'])
          : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJsonForServer() {
    return {
      'starting_amount': startingAmount,
      'max_limit': maxLimit,
      'cash_in_wallet': cashInWallet,
    };
  }

  Map<String, dynamic> toJsonFull() {
    return {
      'id': id,
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

/// السيرفيس اللي بيتكلم مع الـ PHP endpoint ويدعم offline queue + local cache
class InsertFinancialAccountService {
  final String baseUrl; // مثال: https://nabawisolution.com
  final http.Client _client;
  final Duration timeout;
  final Uuid _uuid = const Uuid();

  InsertFinancialAccountService({
    this.baseUrl = "https://nabawisolution.com",
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        timeout = timeout ?? const Duration(seconds: 15);

  String _endpoint() => baseUrl.endsWith('/') ? '${baseUrl}financial_account.php' : '$baseUrl/financial_account.php';

  // ---------- Hive boxes helpers ----------
  static const String _BOX_FINANCIAL = 'financial_accounts';
  static const String _BOX_OPS = 'ops';

  Future<void> _ensureBoxesOpen() async {
    if (!Hive.isBoxOpen(_BOX_FINANCIAL)) await Hive.openBox(_BOX_FINANCIAL);
    if (!Hive.isBoxOpen(_BOX_OPS)) await Hive.openBox(_BOX_OPS);
  }

  // queue op structure: { opId, entity, type, payload, timestamp, state, retries }
  Future<String> _queueOp(Map<String, dynamic> op) async {
    await _ensureBoxesOpen();
    final ops = Hive.box(_BOX_OPS);
    final opId = op['opId'] ?? _uuid.v4();
    op['opId'] = opId;
    await ops.put(opId, op);
    return opId;
  }

  // ---------- Connectivity helper ----------
  Future<bool> _isOnline() async {
    try {
      final conn = await Connectivity().checkConnectivity();
      return conn != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }



  Future<FinancialAccount> insert(FinancialAccount payload) async {
    final url = Uri.parse(_endpoint());
    final body = jsonEncode(payload.toJsonForServer());

    try {
      final res = await _client.post(url,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      ).timeout(timeout);

      if (res.statusCode == 200) {
        final respBody = jsonDecode(res.body);
        // تفترض JSON => { success: true, data: {...} }
        final data = (respBody is Map && respBody['data'] != null) ? respBody['data'] : respBody;
        if (data is Map<String, dynamic>) {
          // احفظ محلياً نسخة محدثة من السيرفر
          final box = await Hive.openBox('financial_accounts');
          final server = Map<String, dynamic>.from(data);
          final id = server['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
          await box.put(id, server);
          return FinancialAccount.fromJson(server);
        }
        throw ApiException('استجابة غير متوقعة من السيرفر', res.statusCode);
      } else {
        throw ApiException('HTTP ${res.statusCode}: ${res.body}', res.statusCode);
      }
    } on SocketException catch (_) {
      // لا نت — خزّن محليًا كـ pending و ضع op في ops
      final box = await Hive.openBox('financial_accounts');
      final opsBox = await Hive.openBox('ops');

      final localId = 'local-${DateTime.now().millisecondsSinceEpoch}';
      final localMap = payload.toJsonForServer();
      localMap['local_id'] = localId;
      localMap['created_at'] = DateTime.now().toUtc().toIso8601String();
      localMap['sync_state'] = 'pending';

      await box.put(localId, localMap);

      final opId = const Uuid().v4();
      final op = {
        'opId': opId,
        'entity': 'financial_account',
        'type': 'create',
        'payload': localMap,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'state': 'pending',
        'retries': 0,
        'endpoint': _endpoint(),
      };
      await opsBox.put(opId, op);

      // أعد كائن FinancialAccount من localMap (بدون id من السيرفر)
      return FinancialAccount.fromJson(localMap);
    } catch (e) {
      // حالات أخرى: خزّن محليًا أيضاً كاحتياط
      final box = await Hive.openBox('financial_accounts');
      final localId = 'local-${DateTime.now().millisecondsSinceEpoch}';
      final localMap = payload.toJsonForServer();
      localMap['local_id'] = localId;
      localMap['created_at'] = DateTime.now().toUtc().toIso8601String();
      localMap['sync_state'] = 'pending';
      await box.put(localId, localMap);
      rethrow;
    }
  }

  // ---------- local persistence ----------
  Future<void> _saveLocal(FinancialAccount acct) async {
    await _ensureBoxesOpen();
    final box = Hive.box(_BOX_FINANCIAL);
    final key = acct.id != null ? acct.id.toString() : DateTime.now().microsecondsSinceEpoch.toString();
    // store full JSON for later use
    await box.put(key, acct.toJsonFull());
  }

  Future<FinancialAccount> _saveOfflineAndQueue(FinancialAccount payload, {String? reason}) async {
    await _ensureBoxesOpen();
    final box = Hive.box(_BOX_FINANCIAL);

    // generate negative temp id
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final localRecord = {
      'id': tempId,
      'starting_amount': payload.startingAmount,
      'max_limit': payload.maxLimit,
      'cash_in_wallet': payload.cashInWallet,
      'total_in_drawer': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sync_state': 'pending',
      'sync_reason': reason ?? 'offline',
    };

    await box.put(tempId.toString(), localRecord);

    // queue op
    final op = {
      'opId': _uuid.v4(),
      'entity': 'financial_account',
      'type': 'create',
      'payload': Map<String, dynamic>.from(payload.toJsonForServer())..['local_id'] = tempId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'state': 'pending',
      'retries': 0,
    };
    await _queueOp(op);

    // return local instance
    final account = FinancialAccount(
      id: tempId,
      startingAmount: payload.startingAmount,
      maxLimit: payload.maxLimit,
      cashInWallet: payload.cashInWallet,
      totalInDrawer: null,
      createdAt: DateTime.now().toUtc(),
    );
    return account;
  }

  // ---------- getLatest: online-first then fallback to Hive ----------
  Future<List<FinancialAccount>> getLatest({int limit = 10}) async {
    await _ensureBoxesOpen();
    final online = await _isOnline();
    final url = Uri.parse('${_endpoint()}?limit=$limit');

    if (online) {
      try {
        final res = await _client.get(url).timeout(timeout);
        final status = res.statusCode;
        final respBody = res.body.isNotEmpty ? jsonDecode(res.body) : null;

        if (status == 200) {
          if (respBody is Map && respBody['success'] == true && respBody['data'] is List) {
            final list = List<Map<String, dynamic>>.from(respBody['data']);
            final accounts = <FinancialAccount>[];
            for (var item in list) {
              final map = Map<String, dynamic>.from(item);
              final acc = FinancialAccount.fromJson(map);
              accounts.add(acc);
              // persist locally (overwrite)
              await _saveLocal(acc);
            }
            return accounts;
          } else {
            throw ApiException('Unexpected response from server', status);
          }
        } else {
          throw ApiException('HTTP $status: ${res.body}', status);
        }
      } catch (e) {
        // if online attempt failed, fall back to local
        if (e is! ApiException) {
          // log debug, then continue to local fallback
        }
      }
    }

    // local fallback
    final box = Hive.box(_BOX_FINANCIAL);
    final keys = box.keys.toList().reversed; // newest first
    final out = <FinancialAccount>[];
    for (final k in keys) {
      if (out.length >= limit) break;
      final raw = box.get(k);
      if (raw == null) continue;
      try {
        final map = Map<String, dynamic>.from(raw as Map);
        final acc = FinancialAccount.fromJson(map);
        out.add(acc);
      } catch (_) {}
    }
    return out;
  }

  // ---------- flush queued ops for this entity (best-effort) ----------
  /// يحاول رفع العمليات المعلّقة من صندوق 'ops' التي تخص financial_account
  /// يمكنك استدعاؤها عند عودة الاتصال (أو تضمينها في SyncManager مركزي).
  Future<void> flushQueuedOps() async {
    await _ensureBoxesOpen();
    final ops = Hive.box(_BOX_OPS);
    final keys = ops.keys.toList();

    for (final key in keys) {
      final raw = ops.get(key);
      if (raw == null) {
        await ops.delete(key);
        continue;
      }
      try {
        final op = Map<String, dynamic>.from(raw as Map);
        final entity = op['entity']?.toString() ?? '';
        final type = op['type']?.toString() ?? '';
        if (entity != 'financial_account') continue;

        if (type == 'create') {
          final payload = Map<String, dynamic>.from(op['payload'] ?? {});
          final uri = Uri.parse(_endpoint());
          final resp = await _client.post(uri,
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode(payload)).timeout(timeout);

          if (resp.statusCode == 200) {
            final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
            if (body is Map && body['success'] == true) {
              final data = (body['data'] is Map) ? Map<String, dynamic>.from(body['data']) : null;
              // update local record: replace tempId with server id if provided
              final localId = payload['local_id'] ?? payload['localId'];
              if (localId != null) {
                final boxFin = Hive.box(_BOX_FINANCIAL);
                final localKey = localId.toString();
                final localRec = boxFin.get(localKey);
                if (localRec != null) {
                  final updated = Map<String, dynamic>.from(localRec as Map);
                  updated['sync_state'] = 'synced';
                  if (data != null && data['id'] != null) {
                    updated['id'] = data['id'];
                    // move record to server id key
                    await boxFin.delete(localKey);
                    await boxFin.put(data['id'].toString(), updated);
                  } else {
                    await boxFin.put(localKey, updated);
                  }
                }
              }
              // remove op
              await ops.delete(key);
            } else {
              // server rejected — mark failed and keep op (or delete depending on policy)
              op['state'] = 'failed';
              op['retries'] = (op['retries'] as int? ?? 0) + 1;
              await ops.put(key, op);
            }
          } else {
            // HTTP error — increment retries and keep
            op['state'] = 'failed';
            op['retries'] = (op['retries'] as int? ?? 0) + 1;
            await ops.put(key, op);
          }
        }
      } catch (e) {
        // network or JSON error — keep op for later, maybe increase retries
        try {
          final op = Map<String, dynamic>.from(raw as Map);
          op['state'] = 'failed';
          op['retries'] = (op['retries'] as int? ?? 0) + 1;
          await ops.put(key, op);
        } catch (_) {}
      }
    }
  }

  /// تنظيف موارد الـ http client لو احتجت
  void dispose() {
    _client.close();
  }
}
