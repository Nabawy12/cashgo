import 'package:flutter/material.dart';

class ShiftReportWidget extends StatelessWidget {
  final String cashierUsername;
  final String fromDate;
  final String toDate;
  final Map<String, double> totals;
  final double width;


  // new fields
  final double drawerCurrent; // المبلغ الموجود في الدرج الآن (للفترة)
  final double cardForCashier; // المبلغ في المحفظه (card) للكاشير خلال الفترة
  final double creditOutstandingForCashier; // مستحقات العملاء (آجل) للكاشير خلال الفترة
  final double purchaseReceiptsOutstandingForUser; // مستحقات سندات الشراء (آجل) المسجلة بواسطة الكاشير

  const ShiftReportWidget({
    super.key,
    required this.cashierUsername,
    required this.fromDate,
    required this.toDate,
    required this.totals,
    this.width = 300,
    // required new fields:
    required this.drawerCurrent,
    required this.cardForCashier,
    required this.creditOutstandingForCashier,
    required this.purchaseReceiptsOutstandingForUser,
  });

  // داخل build() — اعرضهم في أعلى التقرير
  @override
  Widget build(BuildContext context) {
    String _dateOnly(String iso) => iso.split('T').first;
    Widget _solidDivider() => Container(height: 1, color: Colors.black, margin: const EdgeInsets.symmetric(vertical: 6));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        child: Container(
          width: width,
          padding: const EdgeInsets.all(10),
          color: Colors.white,
          child: SingleChildScrollView(
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.black, fontSize: 12, height: 1.25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Text('تقرير تقفيل شفت', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  const SizedBox(height: 8),
                  Text('الكاشير: $cashierUsername', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('في يوم: ${_dateOnly(fromDate)}', style: const TextStyle(fontWeight: FontWeight.w500)),
                  _solidDivider(),

                  // Here show the four requested numbers prominently
                  Text('المبلغ في الدرج الآن: ${drawerCurrent.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('المبلغ في المحفظة (بطاقات) للكاشير: ${cardForCashier.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('المبلغ المستحق (عملاء آجل) للكاشير: ${creditOutstandingForCashier.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('مستحقات سندات الشراء المسجلة بواسطة الكاشير: ${purchaseReceiptsOutstandingForUser.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  _solidDivider(),

                  // rest of existing report (summary, details...) ...
                  Text('ملـخـص الشفت', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('إجمالي المبيعات: ${ (totals['sales_total'] ?? 0.0).toStringAsFixed(2) }'),
                  Text('نقدي مستلم: ${ (totals['sales_paid_cash'] ?? 0.0).toStringAsFixed(2) }'),
                  Text('كارت مستلم: ${ (totals['sales_paid_card'] ?? 0.0).toStringAsFixed(2) }'),
                  Text('مشتريات مدفوعة: ${ (totals['purchases_paid'] ?? 0.0).toStringAsFixed(2) }'),
                  _solidDivider(),

                  // تفاصيل المبيعات و المشتريات كما في النسخة السابقة...
                  // (ابقِ باقي محتوى الودجت كما هو لديك، أو انسخ ما سبق)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
