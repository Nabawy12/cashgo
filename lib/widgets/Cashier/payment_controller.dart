import 'package:flutter/material.dart';

class PaymentControls extends StatelessWidget {
  final TextEditingController paidController;
  final void Function(double) addQuickPaid;
  final void Function(double) setQuickPaid;
  final double total;
  final bool saving;
  final VoidCallback onPayAndSave;
  final VoidCallback onSaveAsCredit;

  const PaymentControls({
    super.key,
    required this.paidController,
    required this.addQuickPaid,
    required this.setQuickPaid,
    required this.total,
    required this.saving,
    required this.onPayAndSave,
    required this.onSaveAsCredit,
  });

  double _parsePaid() => double.tryParse(paidController.text.replaceAll(',', '')) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder listens to paidController (it's a Listenable) and rebuilds UI on changes
    return AnimatedBuilder(
      animation: paidController,
      builder: (context, _) {
        final paid = _parsePaid();
        final canPayFully = paid >= total && total > 0;
        final remaining = (paid >= total) ? (paid - total) : (total - paid);

        return Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('الإجمالي: ${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            // لو حابب تعرض عدد القطع هنا ضيف باراميتر لتمريره
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: paidController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ المدفوع', border: OutlineInputBorder()),
                // onChanged يمكن تركه أو استعماله لو تريد تعامل إضافي
                onChanged: (v) {
                  // لا حاجة لنداء setState في الـ parent — الـ AnimatedBuilder يحدث الواجهة هنا
                },
              ),
            ),
            const SizedBox(width: 8),
            Column(children: [
              Row(children: [
                ElevatedButton(onPressed: () => setQuickPaid(20), child: const Text('20')),
                const SizedBox(width: 6),
                ElevatedButton(onPressed: () => setQuickPaid(50), child: const Text('50')),
                const SizedBox(width: 6),
                ElevatedButton(onPressed: () => setQuickPaid(100), child: const Text('100')),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                ElevatedButton(onPressed: () => addQuickPaid(10), child: const Text('+10')),
                const SizedBox(width: 6),
                ElevatedButton(onPressed: () => addQuickPaid(20), child: const Text('+20')),
              ]),
            ]),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            // عرض المتبقي/الباقي realtime
            paid >= total
                ? Text('الباقي: ${remaining.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold))
                : Text('المتبقي: ${remaining.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
            Row(children: [
              ElevatedButton.icon(
                onPressed: (canPayFully && !saving) ? onPayAndSave : null,
                icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.payment),
                label: const Text('دفع وحفظ'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: (!saving && total > 0) ? onSaveAsCredit : null,
                icon: !saving ? const Icon(Icons.save) : const SizedBox.shrink(),
                label: const Text('حفظ كآجل'),
              ),
            ]),
          ]),
        ]);
      },
    );
  }
}
