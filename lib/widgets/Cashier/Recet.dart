// // ----- SupermarketReceipt + ReceiptItem (للاستخدام مع CartItem) -----
// import 'package:flutter/material.dart';
//
// import '../../screens/cashier/cashier_screen.dart';
//
// // تأكد أن CartItem معرّف في نفس النطاق (كما في cashier_screen.dart).
// // هذا الـ Widget يأخذ List<CartItem> ويعرض الفاتورة بحساب ضريبة 15%.
// class SupermarketReceipt extends StatelessWidget {
//   final List<CartItem> items;
//
//   const SupermarketReceipt({super.key, required this.items});
//
//   double get _subtotal {
//     double s = 0.0;
//     for (final it in items) s += it.subtotal;
//     return s;
//   }
//
//   double get _tax => _subtotal * 0.15; // 15%
//   double get _total => _subtotal + _tax;
//
//   String _shortDate() {
//     final d = DateTime.now();
//     final two = (int n) => n.toString().padLeft(2, '0');
//     return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // غلاف Directionality لضبط المحاذاة العربية
//     return Directionality(
//       textDirection: TextDirection.rtl,
//       child: Padding(
//         padding: const EdgeInsets.all(12.0),
//         child: Container(
//           padding: const EdgeInsets.all(14),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(10),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.grey.withOpacity(0.4),
//                 spreadRadius: 1,
//                 blurRadius: 6,
//                 offset: const Offset(0, 3),
//               ),
//             ],
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               // Header
//               const Text(
//                 'سوبر ماركت الفرح',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
//               ),
//               const SizedBox(height: 6),
//               Text(
//                 'التاريخ: ${_shortDate()}',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(fontSize: 13, color: Colors.grey),
//               ),
//               const SizedBox(height: 12),
//               const Divider(color: Colors.black, thickness: 1),
//               const SizedBox(height: 8),
//
//               // Items
//               Column(
//                 children: items.map((it) => ReceiptItem(item: it)).toList(),
//               ),
//
//               const SizedBox(height: 8),
//               const Divider(color: Colors.black, thickness: 1),
//               const SizedBox(height: 8),
//
//               // Totals
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   const Text('المجموع الفرعي:', style: TextStyle(fontSize: 15)),
//                   Text(_subtotal.toStringAsFixed(2), style: TextStyle(fontSize: 15)),
//                 ],
//               ),
//               const SizedBox(height: 6),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   const Text('ضريبة القيمة المضافة (15%):', style: TextStyle(fontSize: 15)),
//                   Text(_tax.toStringAsFixed(2), style: TextStyle(fontSize: 15)),
//                 ],
//               ),
//               const SizedBox(height: 12),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   const Text('المجموع الكلي:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
//                   Text(_total.toStringAsFixed(2), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
//                 ],
//               ),
//               const SizedBox(height: 14),
//               const Text(
//                 'شكراً لزيارتكم!',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.green),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// // ----- سطر صنف فردي داخل الفاتورة -----
// class ReceiptItem extends StatelessWidget {
//   final CartItem item;
//   const ReceiptItem({super.key, required this.item});
//
//   @override
//   Widget build(BuildContext context) {
//     final name = item.product.name;
//     final qty = item.quantity;
//     final price = item.product.sellingPrice;
//     final lineTotal = item.subtotal;
//
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6.0),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               Expanded(
//                 child: Text(
//                   name,
//                   style: TextStyle(fontSize: 14),
//                   overflow: TextOverflow.ellipsis,
//                 ),
//               ),
//               const SizedBox(width: 8),
//               Text('$qty × ${price.toStringAsFixed(2)}', style: TextStyle(fontSize: 13)),
//               const SizedBox(width: 8),
//               Text(lineTotal.toStringAsFixed(2), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }
