// lib/widgets/Cashier/payment_controller.dart
import 'package:cashgo/models/login.dart';
import 'package:cashgo/utils/colors.dart';
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
  double _parsePaid() =>
      double.tryParse(widget.paidController.text.replaceAll(',', '')) ?? 0.0;

  // possible values: "cash", "wallet", "delayed"
  String? savingButton;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.paidController,
      builder: (context, _) {
        final paid = _parsePaid();
        final canPayFully = paid >= widget.total && widget.total > 0;
        final remaining = (paid >= widget.total)
            ? (paid - widget.total)
            : (widget.total - paid);
        final isLight = Theme.of(context).brightness == Brightness.light;
        final cardColor =
            isLight ? Theme.of(context).cardColor : AppColorsDark.bgCardColor;
        final borderColor =
            isLight ? Colors.grey.shade300 : AppColorsDark.strokColor;
        final textColor = Theme.of(context).textTheme.bodyMedium?.color ??
            (isLight ? Colors.black : Colors.white);

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.06 : 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              children: [
                _SummaryPill(
                  label: 'الإجمالي',
                  value: widget.total.toStringAsFixed(2),
                  color: textColor,
                ),
                const SizedBox(width: 12),
                _SummaryPill(
                  label: paid >= widget.total ? 'الباقي' : 'المتبقي',
                  value: remaining.toStringAsFixed(2),
                  color: paid >= widget.total ? Colors.green : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 12),
            CustomFormField(
              hint: 'المبلغ المدفوع',
              controller: widget.paidController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
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
                CustomButton(
                  text: 'دفع بالمحفظة',
                  onPressed: widget.total > 0 && savingButton == null
                      ? () {
                          setState(() => savingButton = "wallet");
                          widget.onSaveAsCard();
                          setState(() => savingButton = null);
                        }
                      : null,
                  isLoading: savingButton == "wallet",
                  infinity: false,
                ),
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
          ]),
        );
      },
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.grey.shade100
              : AppColorsDark.bgColor.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
