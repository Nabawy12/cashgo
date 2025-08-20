// import 'package:flutter/material.dart';
//
// import '../../../../services/db/db_helper.dart';
// import '../../../../utils/colors.dart';
// import '../../../custom_button.dart';
// import '../../../custom_form.dart';
//
// class AddEditProductDialog extends StatefulWidget {
//   final Map<String, dynamic>? existing;
//   final String? prefillBarcode;
//   const AddEditProductDialog({super.key, this.existing, this.prefillBarcode});
//
//   @override
//   State<AddEditProductDialog> createState() => _AddEditProductDialogState();
// }
//
// class _AddEditProductDialogState extends State<AddEditProductDialog> {
//   final _formKey = GlobalKey<FormState>();
//   late TextEditingController barcodeController;
//   final nameController = TextEditingController();
//   final purchaseController = TextEditingController();
//   final sellingController = TextEditingController();
//   final unitsInCartonController = TextEditingController();
//   final qtyController = TextEditingController();
//   final unitsRemainderController = TextEditingController();
//   final productionDateController = TextEditingController();
//   final expiryDateController = TextEditingController();
//
//   bool isEdit = false;
//   bool isIndividualSale = false;  // حقل لتحديد بيع السجائر فردية أو علبة
//
//   @override
//   void initState() {
//     super.initState();
//     isEdit = widget.existing != null;
//     barcodeController = TextEditingController(
//         text: widget.existing != null
//             ? widget.existing!['barcode']?.toString() ?? ''
//             : (widget.prefillBarcode ?? ''));
//     nameController.text = widget.existing != null ? widget.existing!['name'] ?? '' : '';
//     purchaseController.text =
//     widget.existing != null ? (widget.existing!['purchase_price']?.toString() ?? '') : '';
//     sellingController.text =
//     widget.existing != null ? (widget.existing!['selling_price']?.toString() ?? '') : '';
//     unitsInCartonController.text =
//     widget.existing != null ? (widget.existing!['units_in_carton']?.toString() ?? '') : '';
//     qtyController.text = widget.existing != null ? (widget.existing!['quantity']?.toString() ?? '') : '';
//     unitsRemainderController.text = widget.existing != null ? (widget.existing!['units_remainder']?.toString() ?? '0') : '0';
//     productionDateController.text = widget.existing?['production_date'] ?? '';
//     expiryDateController.text = widget.existing?['expiry_date'] ?? '';
//
//     // تحديث حالة البيع الفردي إذا كانت موجودة في البيانات
//     isIndividualSale = widget.existing != null ? (widget.existing!['is_individual_sale'] == 1) : false;
//   }
//
//   Future<void> save() async {
//     if (!_formKey.currentState!.validate()) return;
//     final prod = {
//       'id': isEdit ? widget.existing!['id'] : null,
//       'barcode': barcodeController.text.trim(),
//       'name': nameController.text.trim(),
//       'purchase_price': double.tryParse(purchaseController.text.trim()) ?? 0.0,
//       'selling_price': double.tryParse(sellingController.text.trim()) ?? 0.0,
//       'units_in_carton': int.tryParse(unitsInCartonController.text.trim()) ?? 0,
//       'quantity': int.tryParse(qtyController.text.trim()) ?? 0,
//       'units_remainder': int.tryParse(unitsRemainderController.text.trim()) ?? 0,
//       'production_date': productionDateController.text.trim(),
//       'expiry_date': expiryDateController.text.trim(),
//       'is_individual_sale': isIndividualSale ? 1 : 0,  // إضافة حالة البيع الفردي
//     };
//
//     if (isEdit) {
//       await DBHelper.instance.updateProduct(prod);
//     } else {
//       await DBHelper.instance.insertProduct(prod);
//     }
//     Navigator.pop(context, true);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final focusNode = FocusNode();
//
//     return AlertDialog(
//       backgroundColor: AppColorsDark.bgColor,
//       title: Center(
//         child: Text(
//           isEdit ? 'تعديل المنتج' : 'اضافه منتج جديد',
//           style: const TextStyle(color: Colors.white),
//         ),
//       ),
//       content: SingleChildScrollView(
//         child: SizedBox(
//           width: 560,
//           child: Form(
//             key: _formKey,
//             child: Column(
//               children: [
//                 CustomFormField(
//                   controller: barcodeController,
//                   hint: 'الرمز التعريفي الخاص بالمنتج',
//                   autoFocus: true,
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: nameController,
//                   hint: 'اسم المنتج',
//                   validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter name' : null,
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: purchaseController,
//                   hint: 'سعر شراء الجمله',
//                   validator: (v) => (v?.trim().isEmpty ?? true) ? 'ادخل السعر' : null,
//                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: sellingController,
//                   hint: 'سعر بيع القطعه',
//                   keyboardType: const TextInputType.numberWithOptions(decimal: true),
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: unitsInCartonController,
//                   hint: 'كام قطعه في الكرتونه',
//                   keyboardType: TextInputType.number,
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: qtyController,
//                   hint: 'كام كرتونه عندك',
//                   keyboardType: TextInputType.number,
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: unitsRemainderController,
//                   hint: 'عدد السجائر المتبقية',
//                   keyboardType: TextInputType.number,
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: productionDateController,
//                   hint: 'تاريخ الإنتاج',
//                   readOnly: true,
//                   onTap: () async {
//                     DateTime? picked = await showDatePicker(
//                       context: context,
//                       initialDate: DateTime.now(),
//                       firstDate: DateTime(2000),
//                       lastDate: DateTime(2100),
//                     );
//                     if (picked != null) {
//                       productionDateController.text = picked.toIso8601String().split('T').first;
//                     }
//                   },
//                 ),
//                 const SizedBox(height: 10),
//                 CustomFormField(
//                   controller: expiryDateController,
//                   hint: 'تاريخ الانتهاء',
//                   readOnly: true,
//                   onTap: () async {
//                     DateTime? picked = await showDatePicker(
//                       context: context,
//                       initialDate: DateTime.now(),
//                       firstDate: DateTime(2000),
//                       lastDate: DateTime(2100),
//                     );
//                     if (picked != null) {
//                       expiryDateController.text = picked.toIso8601String().split('T').first;
//                     }
//                   },
//                 ),
//                 const SizedBox(height: 12),
//                 Container(
//                   child: Column(
//                     children: [
//                       Text("هل يتم بيع السجائر بشكل فردي؟"),
//                        Switch(
//                         value: isIndividualSale,
//                         onChanged: (val) {
//                           setState(() {
//                             isIndividualSale = val;
//                           });
//                         },
//                       ),
//                     ],
//                   ),
//
//                 ),
//                 const SizedBox(height: 12),
//                 Column(
//                   mainAxisAlignment: MainAxisAlignment.end,
//                   children: [
//                     TextButton(
//                       onPressed: () => Navigator.pop(context, false),
//                       child: SizedBox(
//                         width: double.infinity,
//                         height: 30,
//                         child: Center(
//                           child: Text(
//                             'إلغاء',
//                             style: const TextStyle(color: Colors.white),
//                             textAlign: TextAlign.center,
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 15),
//                     CustomButton(
//                       onPressed: save,
//                       text: isEdit ? 'حفظ' : 'اضافه',
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
