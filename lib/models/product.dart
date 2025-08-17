// lib/models/product.dart
class Product {
  final int? id;
  final String barcode;
  final String name;
  final double purchasePrice; // سعر الكرتونة
  final double sellingPrice;  // سعر بيع القطعة
  final int quantity;         // عدد الكراتين (full cartons)
  final int unitsInCarton;    // عدد القطع داخل الكرتونة
  final int unitsRemainder;   // قطع متبقية (أقل من carton)

  // new fields
  final String? productionDate; // yyyy-mm-dd
  final String? expiryDate;     // yyyy-mm-dd
  final int? lowStockSeen;      // 0 or 1
  final int? expirySeen;        // 0 or 1

  Product({
    this.id,
    required this.barcode,
    required this.name,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.quantity,
    required this.unitsInCarton,
    this.unitsRemainder = 0,
    this.productionDate,
    this.expiryDate,
    this.lowStockSeen,
    this.expirySeen,
  });

  // total units available = full cartons * unitsInCarton + unitsRemainder
  int get totalUnits => quantity * unitsInCarton + unitsRemainder;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'quantity': quantity,
      'units_in_carton': unitsInCarton,
      'units_remainder': unitsRemainder,
      'production_date': productionDate ?? '',
      'expiry_date': expiryDate ?? '',
      'low_stock_seen': lowStockSeen ?? 0,
      'expiry_seen': expirySeen ?? 0,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    String? parseDate(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      if (s.isEmpty) return null;
      return s;
    }

    final unitsRemainder = map['units_remainder'] is int
        ? map['units_remainder'] as int
        : int.tryParse((map['units_remainder'] ?? '0').toString()) ?? 0;

    final unitsInCarton = (map['units_in_carton'] as num).toInt();
    final cartons = (map['quantity'] as num).toInt();

    return Product(
      id: map['id'] is int ? map['id'] as int : int.tryParse((map['id'] ?? '').toString()),
      barcode: (map['barcode'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      purchasePrice: (map['purchase_price'] as num).toDouble(),
      sellingPrice: (map['selling_price'] as num).toDouble(),
      quantity: cartons,
      unitsInCarton: unitsInCarton,
      unitsRemainder: unitsRemainder,
      productionDate: parseDate(map['production_date']),
      expiryDate: parseDate(map['expiry_date']),
      lowStockSeen: map['low_stock_seen'] is int ? map['low_stock_seen'] as int : int.tryParse((map['low_stock_seen'] ?? '').toString()) ?? 0,
      expirySeen: map['expiry_seen'] is int ? map['expiry_seen'] as int : int.tryParse((map['expiry_seen'] ?? '').toString()) ?? 0,
    );
  }
}
