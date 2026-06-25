import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../db/db_helper.dart';

class ProductApi {
  static Future<void> initBoxes() async {
    if (!Hive.isBoxOpen('products')) await Hive.openBox('products');
    if (!Hive.isBoxOpen('ops')) await Hive.openBox('ops');
  }

  static Map<String, dynamic> _normalise(Map<String, dynamic> product) {
    final cartons = (product['quantity'] as num?)?.toInt() ??
        int.tryParse(product['quantity']?.toString() ?? '') ??
        0;
    final unitsInCarton = (product['units_in_carton'] as num?)?.toInt() ??
        int.tryParse(product['units_in_carton']?.toString() ?? '') ??
        1;
    final remainder = (product['units_remainder'] as num?)?.toInt() ??
        int.tryParse(product['units_remainder']?.toString() ?? '') ??
        0;
    return {
      ...product,
      'quantity': cartons,
      'units_in_carton': unitsInCarton,
      'units_remainder': remainder,
      'total_units':
          product['total_units'] ?? (cartons * unitsInCarton + remainder),
    };
  }

  static Future<List<Map<String, dynamic>>> getAllProducts({int? count}) async {
    final rows = await DBHelper.instance.getAllProducts();
    return rows.map((p) => _normalise(Map<String, dynamic>.from(p))).toList();
  }

  static Future<Map<String, dynamic>> getProductsPage({int page = 1}) async {
    const perPage = 50;

    final all = await getAllProducts();
    final total = all.length;

    final totalPages = (total / perPage).ceil();

    final start = (page - 1) * perPage;
    final end = min(start + perPage, total);

    final rows = start >= total
        ? <Map<String, dynamic>>[]
        : all.sublist(start, end);

    return {
      'meta': {
        'total': total,
        'total_pages': totalPages,
        'current_page': page,
        'per_page': perPage,
        'has_more': page < totalPages,
      },
      'rows': rows,
    };
  }

  static Future<Map<String, dynamic>?> getProductByBarcode(String code) async {
    final product = await DBHelper.instance.getProductByBarcode(code);
    return product == null
        ? null
        : _normalise(Map<String, dynamic>.from(product));
  }

  static Future<Map<String, dynamic>?> getProductById(int id) async {
    final product = await DBHelper.instance.getProductById(id);
    return product == null
        ? null
        : _normalise(Map<String, dynamic>.from(product));
  }

  static Future<bool> saveProduct(Map<String, dynamic> prod) async {
    final product = Map<String, dynamic>.from(prod);
    if (product['id'] != null &&
        (int.tryParse(product['id'].toString()) ?? 0) > 0) {
      await DBHelper.instance.updateProduct(product);
    } else {
      await DBHelper.instance.insertProduct(product);
    }
    return true;
  }

  static Future<bool> setProductProfitMarked(int id, bool marked) async {
    if (id <= 0) return false;
    await DBHelper.instance.setProductProfitMarked(id, marked);
    return true;
  }

  static Future<bool> deleteProduct(dynamic id) async {
    final parsed = id is int ? id : int.tryParse(id.toString()) ?? 0;
    if (parsed <= 0) return false;
    await DBHelper.instance.deleteProduct(parsed);
    return true;
  }

  static Future<void> removeIncompleteLocalProducts() async {}
}

class ApiDefaults {
  static const String defaultBaseUrl = 'local-sqlite';
}

class SyncManager {
  static bool _running = false;

  static Future<void> init() => ProductApi.initBoxes();

  static void start() {
    _running = true;
    debugPrint('[SyncManager] offline-only mode active; remote sync disabled.');
  }

  static Future<void> stop() async {
    _running = false;
  }

  static Future<void> flushOnce() async {
    if (!_running) return;
    debugPrint('[SyncManager] flush skipped because app is local SQLite only.');
  }
}
