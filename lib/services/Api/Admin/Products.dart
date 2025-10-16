// lib/services/Api/Admin/Products.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// عدّل هنا إلى رابط الـ API عندك
const String _BASE_URL = 'https://nabawisolution.com/products.php';

class ProductApi {
  /// جلب كل المنتجات
  /// جلب المنتجات صفحة بصفحة (count يبدأ من 1).
  /// ترجع قائمة المنتجات (rows) كما كانت سابقًا.
  static Future<List<Map<String, dynamic>>> getAllProducts({int count = 1}) async {
    try {
      if (count < 1) count = 1;
      final uri = Uri.parse('$_BASE_URL?action=get_all&count=${count}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        return [];
      }
      final body = jsonDecode(resp.body);
      // الآن السيرفر يرجع data كـ { meta: {...}, rows: [...] }
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map && data['rows'] is List) {
          final List rows = data['rows'];
          return rows
              .map<Map<String, dynamic>>(
                  (e) => _normalizeProductMap(Map<String, dynamic>.from(e)))
              .toList();
        }
        // backward-compat: لو رجع مباشرة لستة (نادر الآن)
        if (data is List) {
          return data
              .map<Map<String, dynamic>>(
                  (e) => _normalizeProductMap(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
      return [];
    } catch (e) {
      // debug print: print('getAllProducts error: $e');
      return [];
    }
  }
  /// جلب صفحة منتجات مع الـ meta
  /// يرجع Map يحتوي keys: 'meta' (Map) و 'rows' (List<Map>)
  static Future<Map<String, dynamic>?> getProductsPage({int count = 1}) async {
    try {
      if (count < 1) count = 1;
      final uri = Uri.parse('$_BASE_URL?action=get_all&count=${count}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true && body['data'] is Map) {
        final data = body['data'] as Map;
        final meta = data['meta'] ?? {};
        final List rowsRaw = data['rows'] is List ? data['rows'] : [];
        final rows = rowsRaw
            .map<Map<String, dynamic>>(
                (e) => _normalizeProductMap(Map<String, dynamic>.from(e)))
            .toList();
        return {
          'meta': Map<String, dynamic>.from(meta),
          'rows': rows,
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }


  /// جلب منتج بالباركود — يرجع null لو مش موجود
  static Future<Map<String, dynamic>?> getProductByBarcode(String code) async {
    try {
      // ملاحظة: الاسم المعتمد في الـ API هو "barcode"
      final uri = Uri.parse('$_BASE_URL?action=get_by_barcode&barcode=${Uri.encodeComponent(code)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true && body['data'] != null) {
        return _normalizeProductMap(Map<String, dynamic>.from(body['data']));
      }
      return null;
    } catch (e) {
      // print('getProductByBarcode error: $e');
      return null;
    }
  }

  /// جلب منتج بالـ id
  static Future<Map<String, dynamic>?> getProductById(int id) async {
    try {
      final uri = Uri.parse('$_BASE_URL?action=get&id=$id');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true && body['data'] != null) {
        return _normalizeProductMap(Map<String, dynamic>.from(body['data']));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// حفظ (insert / update).
  /// إذا prod يحتوي على 'id' و id>0 -> يقوم بتحديث (action=update)
  /// وإلا يقوم بإنشاء جديد (action=create).
  static Future<bool> saveProduct(Map<String, dynamic> prod) async {
    try {
      final bool isUpdate = prod.containsKey('id') && (prod['id'] is int ? prod['id'] > 0 : int.tryParse(prod['id']?.toString() ?? '0')! > 0);
      final action = isUpdate ? 'update' : 'create';

      // أضف action في body لأن السكربت يقرأها من GET أو من body
      final bodyMap = Map<String, dynamic>.from(prod);
      bodyMap['action'] = action;

      final uri = Uri.parse('$_BASE_URL'); // action في body
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(bodyMap),
      ).timeout(const Duration(seconds: 10));

      // قبول 200 أو 201 كنجاح
      if (!(resp.statusCode == 200 || resp.statusCode == 201)) return false;
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true) {
        return true;
      } else {
        // optional: print(body['message']);
        return false;
      }
    } catch (e) {
      // print('saveProduct error: $e');
      return false;
    }
  }

  /// حذف
  static Future<bool> deleteProduct(int id) async {
    try {
      final uri = Uri.parse('$_BASE_URL?action=delete');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body);
      if (body is Map && body['success'] == true) return true;
      return false;
    } catch (e) {
      // print('deleteProduct error: $e');
      return false;
    }
  }

  /* ----- مساعدة لتحويل الأنواع والتأكد من وجود total_units ----- */

  static Map<String, dynamic> _normalizeProductMap(Map<String, dynamic> raw) {
    final map = <String, dynamic>{};
    // محفوظات سلاسل أو null من السيرفر
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

    // إذا السيرفر رجع total_units استخدمه، وإلا احسبه هنا
    if (raw.containsKey('total_units') && raw['total_units'] != null) {
      map['total_units'] = _intFrom(raw['total_units']);
    } else {
      map['total_units'] =
          _computeTotalUnits(map['quantity'], map['units_in_carton'], map['units_remainder']);
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
      // لو units_in_carton = 0، اعتبر quantity وحدات مباشرة
      return q + rem;
    }
  }
}
