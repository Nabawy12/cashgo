// lib/widgets/Cashier/payment_controller.dart
import 'package:cashgo/models/login.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';

class PaymentControls extends StatefulWidget {
  final TextEditingController paidController;
  final void Function(double) addQuickPaid;
  final void Function(double) setQuickPaid;
  final double total;
  final bool saving;
  final VoidCallback onPayAndSave;
  final VoidCallback onSaveAsLater;
  final VoidCallback onSaveAsCard;

  const PaymentControls({
    super.key,
    required this.paidController,
    required this.addQuickPaid,
    required this.setQuickPaid,
    required this.total,
    required this.saving,
    required this.onPayAndSave,
    required this.onSaveAsLater,
    required this.onSaveAsCard,
  });

  @override
  State<PaymentControls> createState() => _PaymentControlsState();
}

class _PaymentControlsState extends State<PaymentControls> {
  double _parsePaid() => double.tryParse(widget.paidController.text.replaceAll(',', '')) ?? 0.0;

  // possible values: "cash", "wallet" (was "credit"), "delayed"
  String? savingButton;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.paidController,
      builder: (context, _) {
        final paid = _parsePaid();
        final canPayFully = paid >= widget.total && widget.total > 0;
        final remaining = (paid >= widget.total) ? (paid - widget.total) : (widget.total - paid);

        return Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('الإجمالي: ${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            // لو حابب تعرض عدد القطع هنا ضيف باراميتر لتمريره
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CustomFormField(
                  hint: 'المبلغ المدفوع',
                  controller: widget.paidController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ✅ الجزء بتاع النصوص (الباقي/المتبقي) ياخد مساحة على اليسار
              paid >= widget.total
                  ? Text(
                'الباقي: ${remaining.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              )
                  : Text(
                'المتبقي: ${remaining.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 17,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),

              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomButton(
                        text: 'دفع نقدي',
                        onPressed: canPayFully && savingButton == null
                            ? () {
                          setState(() => savingButton = "cash");
                          widget.onPayAndSave();
                          setState(() => savingButton = null);
                        }
                            : null,
                        isLoading: savingButton == "cash",
                        infinity: false,
                      ),
                      SizedBox(width: 10),
                      CustomButton(
                        // changed label to reflect wallet behaviour
                        text: 'دفع بالمحفظة',
                        onPressed: widget.total > 0 && savingButton == null
                            ? () {
                          setState(() => savingButton = "wallet"); // use "wallet" key
                          widget.onSaveAsCard(); // caller should pass wallet behavior
                          setState(() => savingButton = null);
                        }
                            : null,
                        isLoading: savingButton == "wallet",
                        infinity: false,
                      ),
                      SizedBox(width: 10),
                      Visibility(
                        visible: Session.pay_credit,
                        child: CustomButton(
                          text: 'حفظ كآجل',
                          onPressed: widget.total > 0 && savingButton == null
                              ? () {
                            setState(() => savingButton = "delayed");
                            widget.onSaveAsLater();
                            setState(() => savingButton = null);
                          }
                              : null,
                          isLoading: savingButton == "delayed",
                          infinity: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        ]);
      },
    );
  }
}
