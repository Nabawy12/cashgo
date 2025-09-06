// Copy of your PreviousSalesScreen with imports adjusted (day/month format 22/8, English digits)
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/Cashier/returndailog.dart';

class PreviousSalesScreen extends StatefulWidget {
  final String cashierUsername;
  final void Function(int originalSaleId, int returnSaleId)? onReturnProcessed;
  const PreviousSalesScreen({super.key, required this.cashierUsername, this.onReturnProcessed});

  @override
  State<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
}

class _PreviousSalesScreenState extends State<PreviousSalesScreen> {
  bool loading = true;
  List<Map<String, dynamic>> sales = [];
  Map<int, List<Map<String, dynamic>>> saleItems = {};

  DateTime selectedDate = DateTime.now(); // الفلتر الافتراضي: اليوم

  @override
  void initState() {
    super.initState();
    _loadSales(date: selectedDate);
  }

  Future<void> _loadSales({DateTime? date}) async {
    setState(() => loading = true);
    // نأخذ كل الفواتير من الداتا بيز ثم نقوم بالتصفية محليًا حسب التاريخ المطلوب
    final all = await DBHelper.instance.getAllSales();
    if (date != null) {
      sales = all.where((s) => _matchesDate(s['date'], date)).toList();
    } else {
      sales = all;
    }
    setState(() {
      loading = false;
    });
  }

  bool _matchesDate(dynamic rawDate, DateTime date) {
    if (rawDate == null) return false;
    // حاول تحويل النص إلى DateTime بطرق متعددة
    final s = rawDate.toString();
    DateTime? dt;
    try {
      dt = DateTime.parse(s);
    } catch (_) {
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (m != null) {
        final y = int.tryParse(m.group(1) ?? '0') ?? 0;
        final mo = int.tryParse(m.group(2) ?? '0') ?? 0;
        final d = int.tryParse(m.group(3) ?? '0') ?? 0;
        dt = DateTime(y, mo, d);
      } else {
        final parts = s.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
        if (parts.length >= 3) {
          // dd/mm/yyyy OR yyyy/mm/dd
          if (parts[0].length == 4) {
            final y = int.tryParse(parts[0]) ?? 0;
            final mo = int.tryParse(parts[1]) ?? 0;
            final d = int.tryParse(parts[2]) ?? 0;
            dt = DateTime(y, mo, d);
          } else {
            final d = int.tryParse(parts[0]) ?? 0;
            final mo = int.tryParse(parts[1]) ?? 0;
            final y = int.tryParse(parts[2]) ?? 0;
            dt = DateTime(y, mo, d);
          }
        }
      }
    }

    if (dt == null) return false;
    return dt.year == date.year && dt.month == date.month && dt.day == date.day;
  }

  Future<void> _ensureItems(int saleId) async {
    if (saleItems.containsKey(saleId)) return;
    final items = await DBHelper.instance.getSaleItemsBySaleId(saleId);
    saleItems[saleId] = items;
    setState(() {});
  }

  void _openSaleDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    await _ensureItems(saleId);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '#فاتورة رقم : $saleId',
              style: TextStyle(
                  fontSize: 19,
                  color: Colors.white
              ),
            ),
            const SizedBox(width: 8),
            if ((sale['is_return'] ?? 0) == 1) const Icon(Icons.cancel, color: Colors.red),
            if ((sale['return_note'] ?? '').toString().toLowerCase().contains('exchange')) const Icon(Icons.swap_horiz, color: Colors.green),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'الإجمالي: ${(sale['total'] as num?)?.toDouble() ?? 0.0}',
                style: TextStyle(
                    fontSize: 17,
                    color: Colors.white
                ),
              ),
              const SizedBox(height: 10),
              Text(
                  'المدفوع: ${(sale['paid_amount'] as num?)?.toDouble() ?? 0.0}',
                  style: TextStyle(
                      fontSize: 17,
                      color: Colors.white
                  )
              ),
              const SizedBox(height: 10),
              Text(
                  'الباقي: ${(sale['change_amount'] as num?)?.toDouble() ?? 0.0}',
                  style: TextStyle(
                      fontSize: 17,
                      color: Colors.white
                  )
              ),
              const SizedBox(height: 25),
              const Text(
                ':العناصر',
                style: TextStyle(
                    fontSize: 19,
                    color: Colors.white
                ),
              ),
              SizedBox(height: 25,),
              Builder(builder: (_) {
                final items = saleItems[saleId] ?? [];
                if (items.isEmpty) return const Text(
                  'لا توجد عناصر مسجلة لهذه الفاتورة',
                  style: TextStyle(
                      fontSize: 25,
                      color: Colors.white
                  ),
                );
                return SizedBox(
                  height: 250,
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final name = (it['product_name'] ?? 'Product') as String;
                      final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        title: Text(
                          name,
                          style: TextStyle(
                              fontSize: 17,
                              color: Colors.white
                          ),
                        ),
                        subtitle: Text(
                          'الكمية: $qty × ${price.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 15,
                              color: Colors.white
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgCardColor,
              ),
              onPressed: () => Navigator.pop(context), child: const Text(
            'إغلاق',
            style: TextStyle(
                color: Colors.white
            ),
          )
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: AppColorsDark.bgCardColor,
            ),
            onPressed: () async {
              Navigator.pop(context);
              final changed = await _openProcessReturnDialog(saleId);
              if (changed != null) {
                if (mounted) Navigator.pop(context, changed);
              }
            },
            child:Text(
              'معالجة مرتجع / بدل',
              style: TextStyle(
                  color: Colors.white
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// حاول استخراج يوم/شهر من قيمة التاريخ (يدعم ISO أو نص يحوي yyyy-mm-dd).
  /// يعيد سلسلة بصيغة "day/month" مثل "22/8".
  /// تم ضبطه ليعرض الأرقام بالإنجليزية.
  String _formatDayMonth(dynamic rawDate) {
    if (rawDate == null) return '';
    final s = rawDate.toString();

    int? day;
    int? month;

    // حاول التحليل كـ DateTime
    try {
      final dt = DateTime.parse(s);
      day = dt.day;
      month = dt.month;
    } catch (_) {
      // حاول استخراج yyyy-mm-dd عبر regex
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (m != null) {
        month = int.tryParse(m.group(2) ?? '');
        day = int.tryParse(m.group(3) ?? '');
      } else {
        // محاولة ثانية: ابحث عن أجزاء مفصولة ب slash أو space
        final parts = s.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
        // إن كانت الصيغة dd/mm/yyyy أو yyyy/mm/dd حاول استخراج ما يصلح
        if (parts.length >= 3) {
          // إذا الجزء الأول طوله 4 فالأرجح yyyy/mm/dd
          if (parts[0].length == 4) {
            month = int.tryParse(parts[1]);
            day = int.tryParse(parts[2]);
          } else {
            day = int.tryParse(parts[0]);
            month = int.tryParse(parts[1]);
          }
        }
      }
    }

    if (day == null || month == null) {
      // فشل التحليل — ارجع النص الأصلي قصيرًا (fallback)
      return s;
    }

    final useArabicDigits = false; // <-- English digits
    String dStr = day.toString();
    String mStr = month.toString();

    if (useArabicDigits) {
      dStr = _toArabicDigits(dStr);
      mStr = _toArabicDigits(mStr);
    }

    return '$dStr/$mStr';
  }

  /// يحول أرقام 0..9 إلى الأرقام العربية-الهندية (١٢٣) — تُركت للرجوع لو احتجت لاحقًا
  String _toArabicDigits(String input) {
    const western = ['0','1','2','3','4','5','6','7','8','9'];
    const arabic = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
    var out = StringBuffer();
    for (var ch in input.split('')) {
      final idx = western.indexOf(ch);
      if (idx != -1) out.write(arabic[idx]);
      else out.write(ch);
    }
    return out.toString();
  }

  Future<int?> _openProcessReturnDialog(int originalSaleId) async {
    // ensure items loaded
    await _ensureItems(originalSaleId);
    final items = saleItems[originalSaleId] ?? [];
    // open dialog passing items & cashier username
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => ProcessReturnDialog(
        originalSaleId: originalSaleId,
        items: items,
        cashierUsername: widget.cashierUsername,
        onDone: () async {
          // refresh
          await _loadSales(date: selectedDate);
          await _ensureItems(originalSaleId);
        },
      ),
    );

    return result; // saleId or null
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
      await _loadSales(date: selectedDate);
    }
  }

  String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: IconThemeData(color: Colors.white70),
        title: Text(
          'الفواتير السابقة',
          style: TextStyle(
              fontSize: 20,
              color: Colors.white
          ),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              // فتح بدون فلتر (يعرض كل الفواتير)
              setState(() {
                selectedDate = DateTime.now();
              });
              await _loadSales(date: selectedDate);
            },
            icon: Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'تحديث لليوم',
          ),

        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // التاريخ والفلتر — التاريخ بالمنتصف تحت الاب بار
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _pickDate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'التاريخ',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatSelectedDate(selectedDate),
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.calendar_today, size: 18, color: Colors.white70),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sales.isEmpty
                ? Center(
              child: Text(
                'لا توجد فواتير لهذا اليوم',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
                : ListView.builder(
              itemCount: sales.length,
              itemBuilder: (context, idx) {
                final s = sales[idx];
                final saleId = (s['id'] as num).toInt();
                final total = (s['total'] as num?)?.toDouble() ?? 0.0;
                final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                final isReturn = (s['is_return'] ?? 0) == 1;
                final note = (s['return_note'] ?? '').toString();

                final dayMonth = _formatDayMonth(s['date']);

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Card(
                    color: AppColorsDark.bgCardColor,
                    child: ListTile(
                      onTap: () => _openSaleDetails(s),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '#$saleId — $dayMonth', // يعرض مثل: #12 — 22/8
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (isReturn) const Icon(Icons.cancel, color: Colors.red),
                          if (note.toLowerCase().contains('exchange')) const Icon(Icons.swap_horiz, color: Colors.green),
                        ],
                      ),
                      subtitle: Text(
                        'الإجمالي: ${total.toStringAsFixed(2)} — المدفوع: ${paid.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white70,fontSize: 15),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
