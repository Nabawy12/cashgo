import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

class ReceiptWidget extends StatelessWidget {
  final Map<String, dynamic> saleData;
  const ReceiptWidget({super.key, required this.saleData});

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '') ?? '') ?? 0.0;
  }

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _asText(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  List<Map<String, dynamic>> _items() {
    final raw =
        saleData['items'] ?? saleData['product_list'] ?? saleData['sale_items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _formattedDate() {
    final raw =
        saleData['date'] ?? saleData['created_at'] ?? saleData['updated_at'];
    if (raw == null)
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  Widget _line(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      color: Colors.black,
      fontSize: 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(value, style: style, textAlign: TextAlign.left)),
          const SizedBox(width: 8),
          Text(label, style: style, textAlign: TextAlign.right),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shopName = _asText(saleData['shop_name'], fallback: 'CashGo');
    final shopAddress = _asText(saleData['shop_address']);
    final shopPhone = _asText(saleData['shop_phone']);
    final cashierName = _asText(
      saleData['cashier_username'] ??
          saleData['cashier_name'] ??
          saleData['cashier'],
      fallback: '-',
    );
    final items = _items();
    final total = _asDouble(saleData['total'] ?? saleData['net_total']);
    final paid = _asDouble(saleData['paid_amount'] ?? saleData['paid']);
    final change = saleData.containsKey('change_amount')
        ? _asDouble(saleData['change_amount'])
        : (paid - total).clamp(0.0, double.infinity);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: 320,
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black, fontSize: 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                shopName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (shopAddress.isNotEmpty)
                Text(shopAddress, textAlign: TextAlign.center),
              if (shopPhone.isNotEmpty)
                Text(shopPhone, textAlign: TextAlign.center),
              const Divider(color: Colors.black),
              _line('التاريخ', _formattedDate()),
              _line('الكاشير', cashierName),
              const Divider(color: Colors.black),
              const Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: Text('الصنف',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: Text('كمية',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: Text('سعر',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: Text('إجمالي',
                          textAlign: TextAlign.left,
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              const Divider(color: Colors.black),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('لا توجد أصناف', textAlign: TextAlign.center),
                )
              else
                ...items.map((item) {
                  final name = _asText(
                    item['product_name'] ?? item['name'] ?? item['product'],
                    fallback: 'منتج',
                  );
                  final qty =
                      _asInt(item['qty'] ?? item['quantity'] ?? item['count']);
                  final price =
                      _asDouble(item['price'] ?? item['selling_price']);
                  final itemTotal =
                      item.containsKey('subtotal') || item.containsKey('total')
                          ? _asDouble(item['subtotal'] ?? item['total'])
                          : qty * price;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: Text(name)),
                        Expanded(
                            child: Text('$qty', textAlign: TextAlign.center)),
                        Expanded(
                            child: Text(price.toStringAsFixed(2),
                                textAlign: TextAlign.center)),
                        Expanded(
                            child: Text(itemTotal.toStringAsFixed(2),
                                textAlign: TextAlign.left)),
                      ],
                    ),
                  );
                }),
              const Divider(color: Colors.black),
              _line('الإجمالي', total.toStringAsFixed(2), bold: true),
              _line('المدفوع', paid.toStringAsFixed(2)),
              _line('الباقي', change.toStringAsFixed(2), bold: true),
            ],
          ),
        ),
      ),
    );
  }
}
