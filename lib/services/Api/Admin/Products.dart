// lib/services/Api/Admin/Products.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String _BASE_URL = 'https://nabawisolution.com/products.php';

class ProductApi {
  static final _uuid = Uuid();

  // boxes
  static Box? _productsBox;
  static Box? _opsBox;

  static Future<void> initBoxes() async {
    _productsBox ??= await Hive.openBox('products');
    _opsBox ??= await Hive.openBox('ops');
  }

  // remove incomplete / broken records (one-time cleanup)
  static Future<int> removeIncompleteLocalProducts() async {
    await initBoxes();
    final box = _productsBox!;
    final keysToDelete = <dynamic>[];
    for (final key in box.keys) {
      final v = box.get(key);
      if (v == null) {
        keysToDelete.add(key);
        continue;
      }
      try {
        final m = Map<String, dynamic>.from(v as Map);
        final name = (m['name']?.toString() ?? '').trim();
        final barcode = (m['barcode']?.toString() ?? '').trim();
        final idVal = m['id'];
        // heuristic: حذف السجلات التي ليس لها اسم وبدون باركود وبدون id صالح
        final hasValidId = idVal != null && int.tryParse(idVal.toString()) != null && int.tryParse(idVal.toString())! != 0;
        if (name.isEmpty && barcode.isEmpty && !hasValidId) {
          keysToDelete.add(key);
        }
      } catch (_) {
        keysToDelete.add(key);
      }
    }
    for (final k in keysToDelete) {
      await box.delete(k);
    }
    return keysToDelete.length;
  }


  static Future<bool> _isOnline() async {
    final c = await Connectivity().checkConnectivity();
    return c != ConnectivityResult.none;
  }

  // helper: normalize map
  static Map<String, dynamic> _normalizeProductMap(Map<String, dynamic> raw) {
    final map = <String, dynamic>{};
    map['id'] = _intFrom(raw['id']);
    map['barcode'] = raw['barcode']?.toString();
    map['name'] = raw['name']?.toString() ?? '';
    map['purchase_price'] = _doubleFrom(raw['purchase_price']);
    map['selling_price'] = _doubleFrom(raw['selling_price']);
    map['units_in_carton'] = _intFrom(raw['units_in_carton']);
    map['quantity'] = _intFrom(raw['quantity']);
    map['units_remainder'] = _intFrom(raw['units_remainder']);
    map['production_date'] = raw['production_date']?.toString();
    map['expiry_date'] = raw['expiry_date']?.toString();
    map['created_at'] = raw['created_at']?.toString();
    map['updated_at'] = raw['updated_at']?.toString();

    if (raw.containsKey('total_units') && raw['total_units'] != null) {
      map['total_units'] = _intFrom(raw['total_units']);
    } else {
      map['total_units'] = _computeTotalUnits(map['quantity'], map['units_in_carton'], map['units_remainder']);
    }

    return map;
  }

  static int _intFrom(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    final s = v.toString();
    return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
  }

  static double _doubleFrom(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _computeTotalUnits(int? quantity, int? unitsInCarton, int? remainder) {
    final q = quantity ?? 0;
    final uic = unitsInCarton ?? 0;
    final rem = remainder ?? 0;
    if (uic > 0) {
      return q * uic + rem;
    } else {
      return q + rem;
    }
  }

  // --- local helpers ---
  static Future<List<Map<String, dynamic>>> _getLocalAll() async {
    await initBoxes();
    final box = _productsBox!;
    final list = box.values
        .where((e) => e != null)
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return list;
  }

  static Future<void> _putLocal(Map<String, dynamic> product) async {
    await initBoxes();
    final box = _productsBox!;
    final id = product['id'];
    if (id == null) return;
    await box.put(id.toString(), product);
  }

  static Future<void> _deleteLocal(dynamic id) async {
    await initBoxes();
    final box = _productsBox!;
    await box.delete(id.toString());
  }

  static Future<Map<String, dynamic>?> _getLocalByBarcode(String code) async {
    final all = await _getLocalAll();
    try {
      return all.firstWhere((p) => (p['barcode']?.toString() ?? '') == code);
    } catch (e) {
      return null;
    }
  }

  // operation queue (simple Map-based op stored in box 'ops')
  static Future<void> _queueOperation(Map<String, dynamic> op) async {
    await initBoxes();
    final box = _opsBox!;
    await box.put(op['opId'] as String, op);
  }

  // public methods (matching your original signatures)

  static Future<List<Map<String, dynamic>>> getAllProducts({int count = 1}) async {
    // return local cache first (fast). Then try to refresh from server if online and update cache.
    final local = await _getLocalAll();
    // try remote refresh but don't fail if remote fails
    final online = await _isOnline();
    if (online) {
      try {
        final uri = Uri.parse('$_BASE_URL?action=get_all&count=${count}');
        final resp = await http.get(uri).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true) {
            final data = body['data'];
            List rows = [];
            if (data is Map && data['rows'] is List) rows = data['rows'];
            else if (data is List) rows = data;
            final normalized = rows.map<Map<String, dynamic>>((e) => _normalizeProductMap(Map<String, dynamic>.from(e))).toList();
            // update local cache (overwrite by id)
            for (final p in normalized) {
              await _putLocal(p);
            }
            return normalized;
          }
        }
      } catch (e) {
        // ignore remote failures
      }
    }
    return local;
  }

  static Future<Map<String, dynamic>?> getProductsPage({int count = 1}) async {
    // We will try server first (page semantics), fallback to local if offline.
    final online = await _isOnline();
    if (online) {
      try {
        final uri = Uri.parse('$_BASE_URL?action=get_all&count=${count}');
        final resp = await http.get(uri).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true && body['data'] is Map) {
            final data = body['data'] as Map;
            final meta = data['meta'] ?? {};
            final List rowsRaw = data['rows'] is List ? data['rows'] : [];
            final rows = rowsRaw.map<Map<String, dynamic>>((e) => _normalizeProductMap(Map<String, dynamic>.from(e))).toList();
            // update local
            for (final p in rows) await _putLocal(p);
            return {'meta': Map<String, dynamic>.from(meta), 'rows': rows};
          }
        }
      } catch (e) {
        // fallback
      }
    }

    // offline fallback: paginate local list
    final local = await _getLocalAll();
    final perPage = 10;
    final page = count < 1 ? 1 : count;
    final start = (page - 1) * perPage;
    final rows = (start < local.length) ? local.sublist(start, (start + perPage).clamp(0, local.length)) : <Map<String, dynamic>>[];
    // best-effort meta
    final totalPages = (local.length + perPage - 1) ~/ perPage;
    return {'meta': {'total_pages': totalPages, 'total': local.length, 'per_page': perPage}, 'rows': rows};
  }

  static Future<Map<String, dynamic>?> getProductByBarcode(String code) async {
    await initBoxes();
    final online = await _isOnline();

    if (online) {
      try {
        final uri = Uri.parse('$_BASE_URL?action=get_by_barcode&barcode=${Uri.encodeComponent(code)}');
        final resp = await http.get(uri).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true && body['data'] != null) {
            final normalized = _normalizeProductMap(Map<String, dynamic>.from(body['data']));
            await _putLocal(normalized); // update cache
            return normalized;
          }
        }
      } catch (e) {
        // server failed -> fallthrough to local fallback
      }
    }

    // fallback to local if server unreachable or returned nothing
    final local = await _getLocalByBarcode(code);
    return local;
  }

  static Future<Map<String, dynamic>?> getProductById(int id) async {
    await initBoxes();
    final box = _productsBox!;
    final v = box.get(id.toString());
    if (v != null) return Map<String, dynamic>.from(v as Map);

    final online = await _isOnline();
    if (!online) return null;
    try {
      final uri = Uri.parse('$_BASE_URL?action=get&id=$id');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true && body['data'] != null) {
        final normalized = _normalizeProductMap(Map<String, dynamic>.from(body['data']));
        await _putLocal(normalized);
        return normalized;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Future<bool> saveProduct(Map<String, dynamic> prod) async {
    await initBoxes();
    final online = await _isOnline();

    final hasId = prod.containsKey('id') &&
        (prod['id'] != null) &&
        (prod['id'] is int && prod['id'] > 0 ||
            int.tryParse(prod['id']?.toString() ?? '') != null &&
                int.tryParse(prod['id']?.toString() ?? '')! > 0);
    final isUpdate = hasId;

    if (online) {
      try {
        final action = isUpdate ? 'update' : 'create';
        final bodyMap = Map<String, dynamic>.from(prod);
        bodyMap['action'] = action;
        final uri = Uri.parse('$_BASE_URL');
        final resp = await http
            .post(uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(bodyMap))
            .timeout(const Duration(seconds: 10));
        if (!(resp.statusCode == 200 || resp.statusCode == 201)) return false;
        final body = jsonDecode(resp.body);
        if (body is Map && body['success'] == true) {
          // server may return saved entity in body['data']
          if (body.containsKey('data') && body['data'] != null) {
            final saved =
            _normalizeProductMap(Map<String, dynamic>.from(body['data']));
            await _putLocal(saved);
          } else {
            // fallback: ensure local copy saved (sanitize before putting)
            final local = Map<String, dynamic>.from(prod);
            local['barcode'] = local['barcode']?.toString() ?? '';
            local['name'] = local['name']?.toString() ?? '';
            local['purchase_price'] = _doubleFrom(local['purchase_price']);
            local['selling_price'] = _doubleFrom(local['selling_price']);
            local['units_in_carton'] = _intFrom(local['units_in_carton']);
            local['quantity'] = _intFrom(local['quantity']);
            local['units_remainder'] = _intFrom(local['units_remainder']);
            local['production_date'] = local['production_date']?.toString() ?? '';
            local['expiry_date'] = local['expiry_date']?.toString() ?? '';
            local['updated_at'] = DateTime.now().toUtc().toIso8601String();
            local['total_units'] = _computeTotalUnits(
                local['quantity'], local['units_in_carton'], local['units_remainder']);
            await _putLocal(local);
          }
          return true;
        }
        return false;
      } catch (e) {
        // on failure, fallback to offline queue
      }
    }

    // OFFLINE PATH: store locally with temp negative id if needed and queue op
    final box = _productsBox!;
    int id;
    if (isUpdate) {
      id = int.tryParse(prod['id']?.toString() ?? '') ?? -DateTime.now().millisecondsSinceEpoch;
      prod['id'] = id;
    } else {
      id = -DateTime.now().millisecondsSinceEpoch; // negative temp id
      prod['id'] = id;
    }

    // sanitize / set defaults BEFORE saving locally
    prod['barcode'] = prod['barcode']?.toString() ?? '';
    prod['name'] = prod['name']?.toString() ?? '';
    prod['purchase_price'] = _doubleFrom(prod['purchase_price']);
    prod['selling_price'] = _doubleFrom(prod['selling_price']);
    prod['units_in_carton'] = _intFrom(prod['units_in_carton']);
    prod['quantity'] = _intFrom(prod['quantity']);
    prod['units_remainder'] = _intFrom(prod['units_remainder']);
    prod['production_date'] = prod['production_date']?.toString() ?? '';
    prod['expiry_date'] = prod['expiry_date']?.toString() ?? '';
    prod['updated_at'] = DateTime.now().toUtc().toIso8601String();
    prod['total_units'] =
        _computeTotalUnits(prod['quantity'], prod['units_in_carton'], prod['units_remainder']);

    await box.put(id.toString(), prod);

    final op = {
      'opId': _uuid.v4(),
      'entity': 'product',
      'entityId': id,
      'type': isUpdate ? 'update' : 'create',
      'payload': prod,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'state': 'pending',
      'retries': 0,
    };
    await _queueOperation(op);
    return true;
  }

  static Future<bool> deleteProduct(int id) async {
    await initBoxes();
    final online = await _isOnline();
    if (online) {
      try {
        final uri = Uri.parse('$_BASE_URL?action=delete');
        final resp = await http.post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode({'id': id})).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true) {
            await _deleteLocal(id);
            return true;
          }
        }
      } catch (e) {
        // fallback to offline
      }
    }

    // offline: remove local and queue delete
    await _deleteLocal(id);
    final op = {
      'opId': _uuid.v4(),
      'entity': 'product',
      'entityId': id,
      'type': 'delete',
      'payload': {'id': id},
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'state': 'pending',
      'retries': 0,
    };
    await _queueOperation(op);
    return true;
  }
}
















class ApiDefaults {
  static const String defaultBaseUrl = 'https://nabawisolution.com/user_api.php';
}

class SyncManager {
  static Box? _opsBox;
  static Box? _productsBox;
  static Box? _salesBox;
  static Box? _financialBox;
  static StreamSubscription<dynamic>? _sub;
  static bool _running = false;
  static bool _flushing = false; // يمنع تداخل _flushQueue

  // Endpoints
  static const String _PRODUCTS_BASE_URL = 'https://nabawisolution.com/products.php';
  static const String _SALES_BASE_URL = 'https://nabawisolution.com/invoice_reciept.php';
  static const String _FINANCIAL_BASE_URL = 'https://nabawisolution.com/financial_account.php';

  static Future<void> init() async {
    _opsBox ??= await Hive.openBox('ops');
    _productsBox ??= await Hive.openBox('products');
    _salesBox ??= await Hive.openBox('sales');
    _financialBox ??= await Hive.openBox('financial_accounts');
    await Hive.openBox('meta');
  }

  static Future<void> _clearLastOfflineSaleMeta() async {
    try {
      final meta = await Hive.openBox('meta');
      await meta.put('lastOfflineSale', 0.0);
      debugPrint('[SyncManager] cleared lastOfflineSale in meta');
    } catch (e, st) {
      debugPrint('[SyncManager] failed to clear lastOfflineSale: $e\n$st');
    }
  }

  // يحاول يستخلص ConnectivityResult من أي شكل ممكن
  static ConnectivityResult? _extractConnectivityResult(dynamic event) {
    try {
      if (event is ConnectivityResult) return event;
      if (event is Iterable) {
        final list = event.where((e) => e is ConnectivityResult).cast<ConnectivityResult>().toList();
        if (list.isEmpty) return null;
        return list.firstWhere((e) => e != ConnectivityResult.none, orElse: () => list.first);
      }
      if (event is int) {
        if (event >= 0 && event < ConnectivityResult.values.length) return ConnectivityResult.values[event];
      }
      if (event is String) {
        final s = event.toLowerCase();
        if (s.contains('wifi')) return ConnectivityResult.wifi;
        if (s.contains('mobile') || s.contains('cell')) return ConnectivityResult.mobile;
        if (s.contains('ethernet')) return ConnectivityResult.ethernet;
        if (s.contains('none') || s.contains('disconnected')) return ConnectivityResult.none;
      }
    } catch (e) {
      debugPrint('[SyncManager] _extractConnectivityResult failed: $e');
    }
    return null;
  }

  // start listens to connectivity changes and triggers flush when online is true + real internet
  static void start() {
    if (_running) return;
    _running = true;

    _sub = Connectivity().onConnectivityChanged.listen((dynamic event) async {
      final status = _extractConnectivityResult(event);
      if (status == null) return;
      if (status != ConnectivityResult.none) {
        debugPrint('[SyncManager] Connectivity event: $status -> checking internet then flush');
        await _clearLastOfflineSaleMeta();
        final ok = await _checkOnline();
        if (ok) {
          await _flushQueue();
        } else {
          debugPrint('[SyncManager] connectivity present but internet check failed — skip flush for now');
        }
      }
    });

    // try once at start (if there's internet)
    () async {
      final ok = await _checkOnline();
      if (ok) await _flushQueue();
    }();
  }

  static void stop() {
    _sub?.cancel();
    _running = false;
  }

  static Future<void> flushOnce() async {
    await _flushQueue();
  }

  // quick internet check: try hitting base url with short timeout
  static Future<bool> _checkOnline({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final uri = Uri.parse(ApiDefaults.defaultBaseUrl);
      final resp = await http.get(uri).timeout(timeout);
      // Accept status 200 as online; other statuses also indicate DNS/route worked
      return resp.statusCode >= 200 && resp.statusCode < 500;
    } catch (e) {
      debugPrint('[SyncManager] _checkOnline failed: $e');
      return false;
    }
  }

  static Future<void> _flushQueue() async {
    if (_flushing) {
      debugPrint('[SyncManager] flush already running -> skip');
      return;
    }
    _flushing = true;
    try {
      await init();
      if (_opsBox == null) return;

      final keys = _opsBox!.keys.toList();
      if (keys.isEmpty) {
        debugPrint('[SyncManager] ops box empty');
        return;
      }

      // read all ops
      final List<Map<String, dynamic>> ops = [];
      for (final key in keys) {
        final raw = _opsBox!.get(key);
        if (raw == null) {
          await _opsBox!.delete(key);
          continue;
        }
        try {
          final op = Map<String, dynamic>.from(raw as Map);
          if (op['opId'] == null) op['opId'] = key.toString();
          ops.add(op);
        } catch (e, st) {
          debugPrint('[SyncManager] bad op entry for key=$key : $e\n$st');
          await _opsBox!.delete(key);
        }
      }

      if (ops.isEmpty) {
        debugPrint('[SyncManager] ops box empty after read');
        return;
      }

      debugPrint('[SyncManager] starting flush queue, ops=${ops.length}');

      // merge duplicate close_shift ops: keep latest
      final closeOps = ops.where((o) => _isCloseShiftOp(o)).toList();
      if (closeOps.length > 1) {
        closeOps.sort((a, b) => _opTimestamp(a).compareTo(_opTimestamp(b)));
        final keep = closeOps.last;
        for (final o in closeOps) {
          if (o['opId'] != keep['opId']) {
            try {
              await _opsBox!.delete(o['opId']);
              ops.removeWhere((x) => x['opId'] == o['opId']);
              debugPrint('[SyncManager] removed duplicate close_shift op ${o['opId']} (kept ${keep['opId']})');
            } catch (e) {
              debugPrint('[SyncManager] failed deleting duplicate close_shift ${o['opId']}: $e');
            }
          }
        }
      }

      // sort: non-close_shift first, then close_shift last.
      // within group: by priority (desc), retries asc, timestamp asc.
      ops.sort((a, b) {
        final aIsClose = _isCloseShiftOp(a);
        final bIsClose = _isCloseShiftOp(b);
        if (aIsClose && !bIsClose) return 1;
        if (!aIsClose && bIsClose) return -1;

        final pa = (a['priority'] as int?) ?? 0;
        final pb = (b['priority'] as int?) ?? 0;
        if (pa != pb) return pb.compareTo(pa); // higher priority first

        final ra = (a['retries'] as int?) ?? 0;
        final rb = (b['retries'] as int?) ?? 0;
        if (ra != rb) return ra.compareTo(rb);

        final ta = _opTimestamp(a);
        final tb = _opTimestamp(b);
        return ta.compareTo(tb);
      });

      for (final op in ops) {
        try {
          await _processOp(op);
          await _opsBox!.delete(op['opId']);
          debugPrint('[SyncManager] op ${op['opId']} processed and removed');
        } catch (e, st) {
          debugPrint('[SyncManager] op ${op['opId']} failed: $e');
          op['retries'] = (op['retries'] as int? ?? 0) + 1;
          op['state'] = 'failed';
          op['lastAttempt'] = DateTime.now().toUtc().toIso8601String();
          await _opsBox!.put(op['opId'], op);
        }
      }

      debugPrint('[SyncManager] flushQueue finished');
    } finally {
      _flushing = false;
    }
  }

  static bool _isCloseShiftOp(Map<String, dynamic> op) {
    final entity = (op['entity']?.toString() ?? '').toLowerCase();
    final endpoint = (op['endpoint']?.toString() ?? '').toLowerCase();
    if (entity == 'close_shift' || entity == 'close_shieft' || endpoint.contains('close_shift.php') || endpoint.contains('close_shieft')) return true;
    final body = op['body'] is Map ? Map<String, dynamic>.from(op['body']) : null;
    if (body != null) {
      final action = (body['action']?.toString() ?? '').toLowerCase();
      if (action == 'close_shift' || action == 'close_shieft') return true;
    }
    return false;
  }

  static int _opTimestamp(Map<String, dynamic> op) {
    final ts = op['timestamp']?.toString();
    if (ts != null) {
      try {
        final dt = DateTime.tryParse(ts);
        if (dt != null) return dt.toUtc().millisecondsSinceEpoch;
        try {
          final parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parseLoose(ts);
          return parsed.toUtc().millisecondsSinceEpoch;
        } catch (_) {}
      } catch (_) {}
    }
    final opId = op['opId']?.toString();
    if (opId != null) {
      final numId = int.tryParse(opId);
      if (numId != null) return numId;
    }
    return DateTime.now().toUtc().millisecondsSinceEpoch;
  }

  static Future<void> _processOp(Map<String, dynamic> op) async {
    final entity = (op['entity']?.toString() ?? '').toLowerCase();
    final type = (op['type']?.toString() ?? '').toLowerCase();
    final payload = op.containsKey('payload')
        ? Map<String, dynamic>.from(op['payload'] ?? {})
        : (op.containsKey('body') ? Map<String, dynamic>.from(op['body'] ?? {}) : <String, dynamic>{});

    debugPrint('[SyncManager] processing opId=${op['opId']} entity=$entity type=$type');

    if (type == 'api' || entity == 'api' || entity == 'close_shift' || entity == 'close_shieft') {
      await _processApiOp(op);
      return;
    }

    // --- Product ops ---
    if (entity == 'product') {
      if (type == 'create') {
        final bodyMap = Map<String, dynamic>.from(payload);
        bodyMap['action'] = 'create';
        final uri = Uri.parse(_PRODUCTS_BASE_URL);
        final resp = await http
            .post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(bodyMap))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true && body['data'] != null) {
            final server = Map<String, dynamic>.from(body['data']);
            final tempId = payload['id'];
            if (tempId != null) {
              await _productsBox!.delete(tempId.toString());
            }
            final id = server['id'].toString();
            await _productsBox!.put(id, server);
            return;
          } else {
            throw Exception('product create failed by server: ${resp.body}');
          }
        } else {
          throw Exception('product create failed HTTP ${resp.statusCode}');
        }
      } else if (type == 'update') {
        final bodyMap = Map<String, dynamic>.from(payload);
        bodyMap['action'] = 'update';
        final uri = Uri.parse(_PRODUCTS_BASE_URL);
        final resp = await http
            .post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(bodyMap))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true && body['data'] != null) {
            final server = Map<String, dynamic>.from(body['data']);
            await _productsBox!.put(server['id'].toString(), server);
            return;
          } else {
            throw Exception('product update failed by server: ${resp.body}');
          }
        } else {
          throw Exception('product update failed HTTP ${resp.statusCode}');
        }
      } else if (type == 'delete') {
        final id = payload['id'];
        final uri = Uri.parse('$_PRODUCTS_BASE_URL?action=delete');
        final resp = await http
            .post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode({'id': id}))
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true) {
            await _productsBox!.delete(id.toString());
            return;
          } else {
            throw Exception('product delete failed by server: ${resp.body}');
          }
        } else {
          throw Exception('product delete failed HTTP ${resp.statusCode}');
        }
      } else {
        debugPrint('[SyncManager] unknown product op type=$type');
        return;
      }
    }

    // --- Sale ops ---
    else if (entity == 'sale') {
      if (type == 'create') {
        final salePayload = Map<String, dynamic>.from(payload);
        final uri = Uri.parse(_SALES_BASE_URL);
        final resp = await http
            .post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(salePayload))
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true) {
            final serverData = Map<String, dynamic>.from(body);
            // update local sales box: mark as synced, attach server id if provided
            final localId = salePayload['local_id'] ?? salePayload['localId'] ?? salePayload['id'];
            if (localId != null) {
              final localKey = localId.toString();
              final localRecord = _salesBox!.get(localKey);
              if (localRecord != null) {
                final updated = Map<String, dynamic>.from(localRecord as Map);
                updated['sync_state'] = 'synced';
                if (serverData.containsKey('sale_id')) {
                  updated['server_id'] = serverData['sale_id'];
                } else if (serverData.containsKey('data') && serverData['data'] is Map && serverData['data']['sale_id'] != null) {
                  updated['server_id'] = serverData['data']['sale_id'];
                }
                // If the local record was previously counted_locally, move amounts from delta->online
                if (updated['counted_locally'] == true) {
                  try {
                    final metaBox = await Hive.openBox('meta');
                    final prevDelta = (metaBox.get('totalCash_delta') as num? ?? 0).toDouble();
                    final prevOnline = (metaBox.get('totalCash_online') as num? ?? 0).toDouble();
                    final amount = double.tryParse((updated['total'] ?? updated['total_after_discount'] ?? 0).toString()) ?? 0.0;
                    final newDelta = (prevDelta - amount).clamp(0.0, double.maxFinite);
                    final newOnline = prevOnline + amount;
                    await metaBox.put('totalCash_delta', newDelta);
                    await metaBox.put('totalCash_online', newOnline);
                    debugPrint('[SyncManager] Moved $amount from delta->$newDelta to online->$newOnline');
                  } catch (e, st) {
                    debugPrint('[SyncManager] failed moving delta->online: $e\n$st');
                  }
                }

                updated['counted_locally'] = false;
                await _salesBox!.put(localKey, updated);
              }
            }

            // Clear lastOfflineSale as a safe-measure (we successfully synced a sale)
            await _clearLastOfflineSaleMeta();

            return;
          } else {
            throw Exception('sale create failed by server: ${resp.body}');
          }
        } else {
          throw Exception('sale create HTTP ${resp.statusCode}');
        }
      } else {
        debugPrint('[SyncManager] unknown sale op type=$type');
        return;
      }
    }

    // --- Financial account ops (new) ---
    else if (entity == 'financial_account' || entity == 'financial') {
      if (type == 'create') {
        final payloadMap = Map<String, dynamic>.from(payload);
        final uri = Uri.parse(_FINANCIAL_BASE_URL);
        final resp = await http
            .post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(payloadMap))
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['success'] == true) {
            final data = (body['data'] is Map) ? Map<String, dynamic>.from(body['data']) : null;
            final localId = payloadMap['local_id'] ?? payloadMap['localId'] ?? payloadMap['id'];

            // Update local financial record if exists
            if (localId != null && _financialBox != null) {
              final localKey = localId.toString();
              final localRecord = _financialBox!.get(localKey);
              if (localRecord != null) {
                final updated = Map<String, dynamic>.from(localRecord as Map);
                updated['sync_state'] = 'synced';
                if (data != null && data['id'] != null) {
                  // move local record to server id key
                  updated['id'] = data['id'];
                  // merge server fields if present (total_in_drawer, created_at, etc.)
                  if (data.containsKey('total_in_drawer')) updated['total_in_drawer'] = data['total_in_drawer'];
                  if (data.containsKey('created_at')) updated['created_at'] = data['created_at'];
                  // remove temp key; write under server id
                  await _financialBox!.delete(localKey);
                  await _financialBox!.put(data['id'].toString(), updated);
                } else {
                  // no server id returned, just mark as synced
                  await _financialBox!.put(localKey, updated);
                }
              } else if (data != null && _financialBox != null) {
                // no local record found but server returned data: save it
                await _financialBox!.put(data['id'].toString(), data);
              }
            } else if (data != null && _financialBox != null) {
              // fallback: save server data
              await _financialBox!.put(data['id'].toString(), data);
            }

            return;
          } else {
            throw Exception('financial_account create failed by server: ${resp.body}');
          }
        } else {
          throw Exception('financial_account create HTTP ${resp.statusCode}');
        }
      } else {
        debugPrint('[SyncManager] unknown financial_account op type=$type');
        return;
      }
    }

    // Unknown entity
    else {
      debugPrint('[SyncManager] unknown op entity=$entity');
      return;
    }
  }

  // _processApiOp: يدعم asForm flag ويطبع body للتشخيص
  static Future<void> _processApiOp(Map<String, dynamic> op) async {
    final endpoint = op['endpoint']?.toString() ?? op['body']?['endpoint']?.toString() ?? '';
    final method = (op['method']?.toString() ?? 'POST').toUpperCase();
    final body = op['body'] is Map ? Map<String, dynamic>.from(op['body']) : <String, dynamic>{};
    final asForm = op['asForm'] == true;

    final uri = endpoint.isNotEmpty ? Uri.parse(endpoint) : Uri.parse(ApiDefaults.defaultBaseUrl);
    debugPrint('[SyncManager] processing API op ${op['opId']} -> $method $uri (asForm=$asForm)');
    debugPrint('[SyncManager] API op ${op['opId']} sending body: ${body} (asForm=$asForm)');

    if (method == 'POST') {
      final resp = await (() async {
        if (asForm) {
          return await http
              .post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: body.map((k, v) => MapEntry(k, v?.toString() ?? '')))
              .timeout(const Duration(seconds: 20));
        } else {
          return await http
              .post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode(body))
              .timeout(const Duration(seconds: 20));
        }
      })();

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final parsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        if (parsed is Map && (parsed['success'] == true || parsed['status'] == 'success' || parsed['status'] == 'ok')) {
          debugPrint('[SyncManager] api op ${op['opId']} success');
          return;
        } else {
          throw Exception('api op failed: HTTP ${resp.statusCode} body=${resp.body}');
        }
      } else {
        throw Exception('api op HTTP ${resp.statusCode} body=${resp.body}');
      }
    } else if (method == 'GET') {
      final queryUri = body.isNotEmpty ? uri.replace(queryParameters: body.map((k, v) => MapEntry(k, v?.toString() ?? ''))) : uri;
      final resp = await http.get(queryUri).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        debugPrint('[SyncManager] api op ${op['opId']} GET success');
        return;
      } else {
        throw Exception('api op GET HTTP ${resp.statusCode} body=${resp.body}');
      }
    } else {
      throw Exception('Unsupported API op method: $method');
    }
  }
}




