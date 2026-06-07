// Receipt widget (stateless). Pass cart map, paid, cashierUsername, width.
// Optional: discountType ('percent' or 'fixed') and discountValue (e.g. 10.0 for 10% or 5.0 for EGP 5).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/cart.dart';

class ReceiptWidget extends StatelessWidget {
  final Map<int, CartItem> cart;
  final double paid;
  final String cashierUsername;
  final double width;
  final bool useCairo; // if font was loaded into engine

  // New optional discount fields
  // discountType: 'percent' or 'fixed' (any other / null -> no discount)
  final String? discountType;
  final double discountValue;

  const ReceiptWidget({
    super.key,
    required this.cart,
    required this.paid,
    required this.cashierUsername,
    required this.width,
    this.useCairo = false,
    this.discountType,
    this.discountValue = 0.0,
  });

  double get subtotal {
    double t = 0;
    for (final c in cart.values) t += c.subtotal;
    return t;
  }

  /// حساب قيمة الخصم بناءً على النوع والقيمة
  double get _discountAmount {
    if (discountType == null) return 0.0;
    final dType = discountType!.toLowerCase();
    final v = discountValue.isFinite
        ? discountValue.clamp(0.0, double.infinity)
        : 0.0;
    if (dType == 'percent' && v > 0) {
      final pct = v.clamp(0.0, 100.0);
      return (subtotal * (pct / 100.0));
    } else if (dType == 'fixed' && v > 0) {
      return v > subtotal ? subtotal : v;
    }
    return 0.0;
  }

  double get totalAfterDiscount {
    final t = (subtotal - _discountAmount).clamp(0.0, double.infinity);
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
    final textStyle = TextStyle(
        fontFamily: useCairo ? 'Cairo' : null,
        fontSize: 12,
        color: Colors.black);
    final headerStyle = TextStyle(
        fontFamily: useCairo ? 'Cairo' : null,
        fontSize: 14,
        fontWeight: FontWeight.bold);

    final discountAmt = _discountAmount;
    final hasDiscount = discountAmt > 0.000001;

    // determine change/remaining relative to totalAfterDiscount
    final paidRounded = paid;
    final totalAfter = totalAfterDiscount;
    final isPaidEnough = paidRounded >= totalAfter;
    final changeOrRemaining =
        (isPaidEnough ? (paidRounded - totalAfter) : (totalAfter - paidRounded))
            .abs();

    String discountLabel = '';
    if (hasDiscount) {
      if ((discountType ?? '').toLowerCase() == 'percent') {
        discountLabel = '${discountValue.toStringAsFixed(0)}%';
      } else {
        discountLabel = '${discountAmt.toStringAsFixed(2)}';
      }
    }

    return Material(
      color: Colors.white,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 12),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
                child: Image.asset("assets/images/logo.png",
                    width: 100, height: 100)),
            const SizedBox(height: 8),
            Center(child: Text('*** فاتورة بيع ***', style: headerStyle)),
            const SizedBox(height: 8),
            Text('${cashierUsername} :الكاشير', style: textStyle),
            Text('التاريخ: $shortDate', style: textStyle),
            const SizedBox(height: 6),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                        width: 40,
                        child: Text('سعر',
                            textAlign: TextAlign.center, style: textStyle)),
                    SizedBox(
                        width: 60,
                        child: Text('كم',
                            textAlign: TextAlign.center, style: textStyle)),
                    SizedBox(
                        width: 40,
                        child: Text('الصنف',
                            textAlign: TextAlign.center, style: textStyle)),
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
                    SizedBox(
                        width: 40,
                        child: Text(
                            item.product.sellingPrice.toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            style: textStyle)),
                    SizedBox(
                        width: 60,
                        child: Text(item.quantity.toString(),
                            textAlign: TextAlign.center, style: textStyle)),
                    SizedBox(
                        width: 40,
                        child: Text(name,
                            textAlign: TextAlign.center, style: textStyle)),
                  ],
                ),
              );
            }).toList(),
            const Divider(),
            // Subtotal (before discount)
            if (hasDiscount) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(subtotal.toStringAsFixed(2), style: headerStyle),
                      Text(' :الإجمالي قبل الخصم', style: headerStyle),
                    ]),
              ),
            ],
            if (!hasDiscount) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(subtotal.toStringAsFixed(2), style: headerStyle),
                      Text(' :الإجمالي', style: headerStyle),
                    ]),
              ),
            ],

            // Discount line (if any)
            if (hasDiscount) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${discountAmt.toStringAsFixed(2)}',
                          style: textStyle),
                      Text('${discountLabel} :خصم ', style: textStyle),
                    ]),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(totalAfter.toStringAsFixed(2), style: headerStyle),
                      Text(' :الإجمالي بعد الخصم', style: headerStyle),
                    ]),
              ),
            ],
            if (!hasDiscount) const SizedBox(height: 6),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(paidRounded.toStringAsFixed(2), style: textStyle),
                    Text(':المدفوع', style: textStyle),
                  ]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(changeOrRemaining.toStringAsFixed(2),
                        style: textStyle),
                    Text(isPaidEnough ? ':الباقي' : ':المتبقي',
                        style: textStyle),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
