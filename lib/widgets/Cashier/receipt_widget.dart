// Receipt widget (stateless). Pass cart map, paid, cashierUsername, and width.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/cart.dart';

class ReceiptWidget extends StatelessWidget {
  final Map<int, CartItem> cart;
  final double paid;
  final String cashierUsername;
  final double width;
  final bool useCairo; // if font was loaded into engine

  const ReceiptWidget({
    super.key,
    required this.cart,
    required this.paid,
    required this.cashierUsername,
    required this.width,
    this.useCairo = false,
  });

  double get total {
    double t = 0;
    for (final c in cart.values) t += c.subtotal;
    return t;
  }

  String _shorten(String text, {int max = 18}) {
    final clean = text.replaceAll('\n', ' ');
    return clean.length > max ? clean.substring(0, max) + '...' : clean;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toLocal();
    final shortDate = DateFormat('dd/MM').format(now);
    final textStyle = TextStyle(fontFamily: useCairo ? 'Cairo' : null, fontSize: 12, color: Colors.black);
    final headerStyle = TextStyle(fontFamily: useCairo ? 'Cairo' : null, fontSize: 14, fontWeight: FontWeight.bold);

    return Material(
      color: Colors.white,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Image.asset("assets/icons/app_icon.png", width: 30, height: 30)),
            const SizedBox(height: 12),
            Center(child: Text('*** فاتورة بيع ***', style: headerStyle)),
            Text('${cashierUsername} :الكاشير', style: textStyle),
            Text('التاريخ: $shortDate', style: textStyle),
            const SizedBox(height: 6),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                SizedBox(width: 60, child: Text('المجموع', textAlign: TextAlign.center, style: textStyle)),
                SizedBox(width: 60, child: Text('سعر', textAlign: TextAlign.center, style: textStyle)),
                SizedBox(width: 40, child: Text('كم', textAlign: TextAlign.center, style: textStyle)),
                SizedBox(width: 60, child: Text('الصنف', textAlign: TextAlign.center, style: textStyle)),
              ]),
            ),
            const SizedBox(height: 4),
            ...cart.values.map((item) {
              final name = _shorten(item.product.name, max: 16);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(width: 60, child: Text(item.subtotal.toStringAsFixed(2), textAlign: TextAlign.center, style: textStyle)),
                    SizedBox(width: 60, child: Text(item.product.sellingPrice.toStringAsFixed(2), textAlign: TextAlign.center, style: textStyle)),
                    SizedBox(width: 40, child: Text(item.quantity.toString(), textAlign: TextAlign.center, style: textStyle)),
                    SizedBox(width: 60, child: Text(name, style: textStyle)),
                  ],
                ),
              );
            }).toList(),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(total.toStringAsFixed(2), style: headerStyle),
              Text(' :الإجمالي', style: headerStyle),
            ]),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(paid.toStringAsFixed(2), style: textStyle),
                Text(':المدفوع', style: textStyle),
              ]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text((paid >= total ? (paid - total) : (total - paid)).toStringAsFixed(2), style: textStyle),
                Text(paid >= total ? ':الباقي' : ':المتبقي', style: textStyle),
              ]),
            ),
            const SizedBox(height: 10),
            Center(child: Text('شكراً لزيارتكم', style: textStyle)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
