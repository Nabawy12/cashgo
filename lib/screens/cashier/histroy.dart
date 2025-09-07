// PreviousSalesGroupedByCashier.dart
import 'package:cashgo/screens/cashier/cashier_screen.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  Map<String, List<Map<String, dynamic>>> groupedSales = {};

  DateTime selectedDate = DateTime.now(); // الفلتر الافتراضي: اليوم

  @override
  void initState() {
    super.initState();
    _loadSales(date: selectedDate);
  }

  Future<void> _loadSales({DateTime? date}) async {
    setState(() => loading = true);
    final all = await DBHelper.instance.getAllSales();

    // تطبيق فلتر التاريخ محليًا كما في كودك
    List<Map<String, dynamic>> filtered;
    if (date != null) {
      filtered = all.where((s) => _matchesDate(s['date'], date)).toList();
    } else {
      filtered = all;
    }

    // تجميع حسب اسم الكاشير — نحاول عدة مفاتيح محتملة
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (final s in filtered) {
      final cashierName = (s['cashier_username'] ?? s['username'] ?? s['cashier'] ?? s['user'] ?? 'Unknown').toString();
      map.putIfAbsent(cashierName, () => []);
      map[cashierName]!.add(s);
    }

    if (!mounted) return;
    setState(() {
      sales = filtered;
      groupedSales = map;
      loading = false;
    });
  }

  bool _matchesDate(dynamic rawDate, DateTime date) {
    if (rawDate == null) return false;
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
    try {
      final items = await DBHelper.instance.getSaleItemsBySaleId(saleId);
      saleItems[saleId] = items;
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('Error in _ensureItems: $e\n$st');
      rethrow;
    }
  }

  void _openSaleDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    try {
      await _ensureItems(saleId);
    } catch (e, st) {
      debugPrint('Failed preloading items before opening details: $e\n$st');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('خطأ في تحميل العناصر'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
        ),
      );
      return;
    }

    final cashierName = (sale['cashier_username'] ?? sale['username'] ?? sale['cashier'] ?? sale['user'] ?? widget.cashierUsername).toString();

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
              style: TextStyle(fontSize: 19, color: Colors.white),
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
            children: [
              Text('الإجمالي: ${(sale['total'] as num?)?.toDouble() ?? 0.0}', style: TextStyle(fontSize: 17, color: Colors.white)),
              const SizedBox(height: 10),
              Text('المدفوع: ${(sale['paid_amount'] as num?)?.toDouble() ?? 0.0}', style: TextStyle(fontSize: 17, color: Colors.white)),
              const SizedBox(height: 10),
              Text('الباقي: ${(sale['change_amount'] as num?)?.toDouble() ?? 0.0}', style: TextStyle(fontSize: 17, color: Colors.white)),
              const SizedBox(height: 25),
              const Text(':العناصر', style: TextStyle(fontSize: 19, color: Colors.white)),
              SizedBox(height: 25),
              Builder(builder: (_) {
                final items = saleItems[saleId] ?? [];
                if (items.isEmpty) return const Text('لا توجد عناصر مسجلة لهذه الفاتورة', style: TextStyle(fontSize: 25, color: Colors.white));
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
                        title: Text(name, style: TextStyle(fontSize: 17, color: Colors.white)),
                        subtitle: Text('الكمية: $qty × ${price.toStringAsFixed(2)}', style: TextStyle(fontSize: 15, color: Colors.white)),
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
            style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
            onPressed: () async {
              // --- تعديل: تحويل التعامل مع الـ async ليكون متسلسلاً وبـ try/catch
              // نغلق نافذة التفاصيل أولاً
              if (Navigator.canPop(context)) Navigator.pop(context);

              // نظهر Loading dialog بطريقة آمنة (rootNavigator) لتجنّب مشاكل مع Stack الخاص بالـ dialogs خصوصاً على Windows
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator()),
                useRootNavigator: true,
              );

              // نحاول تحميل العناصر (إن لم تكن محمّلة) ثم نغلق الـ loading ونفتح شاشة المعالجة
              try {
                await _ensureItems(saleId);
              } catch (e, st) {
                debugPrint('Error loading sale items before return: $e\n$st');
                // أغلق الـ loading إذا كان ظاهرًا
                try {
                  if (Navigator.canPop(context)) Navigator.of(context, rootNavigator: true).pop();
                } catch (_) {}

                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('خطأ في تحميل البيانات'),
                    content: SingleChildScrollView(child: Text(e.toString())),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
                  ),
                );
                return;
              }

              // أغلق الـ loading بأمان
              try {
                if (Navigator.canPop(context)) Navigator.of(context, rootNavigator: true).pop();
              } catch (_) {}

              // ننتظر إطارًا صغيرًا ليكون الـ UI جاهزًا
              await Future.delayed(const Duration(milliseconds: 50));

              if (!mounted) return;

              try {
                final changed = await _openProcessReturnDialog(saleId, cashierName);
                if (changed != null) {
                  if (mounted) Navigator.pop(context, changed);
                }
              } catch (e, st) {
                debugPrint('Error while opening return screen: $e\n$st');
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('حدث خطأ'),
                    content: SingleChildScrollView(child: Text('$e\n\n${st.toString().split("\n").take(10).join("\n")}')),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
                  ),
                );
              }
            },
            child: Text('معالجة مرتجع / بدل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// نفس دالتك لعرض day/month
  String _formatDayMonth(dynamic rawDate) {
    if (rawDate == null) return '';
    final s = rawDate.toString();
    int? day;
    int? month;
    try {
      final dt = DateTime.parse(s);
      day = dt.day;
      month = dt.month;
    } catch (_) {
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (m != null) {
        month = int.tryParse(m.group(2) ?? '');
        day = int.tryParse(m.group(3) ?? '');
      } else {
        final parts = s.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
        if (parts.length >= 3) {
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
    if (day == null || month == null) return s;
    return '${day.toString()}/${month.toString()}';
  }

  Future<int?> _openProcessReturnDialog(int originalSaleId, String cashierName) async {
    // نتأكد من وجود العناصر محمّلة
    await _ensureItems(originalSaleId);
    final items = saleItems[originalSaleId] ?? [];

    // على Windows أحيانًا يحدث خطأ لأن بعض Widgets (مثل Expanded) متوقعة أن تكون داخل Flex
    // وDialog يضيف حدود/محاذاة قد تجعل Expanded يتلقى BoxParentData — بالتالي نفتح شاشة كاملة بدلاً من AlertDialog
    final result = await Navigator.of(context).push<int?>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColorsDark.bgColor,
          appBar: AppBar(
            title: Text('معالجة مرتجع / بدل', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white70),
          ),
          body: SafeArea(
            child: ProcessReturnDialog(
              originalSaleId: originalSaleId,
              items: items,
              cashierUsername: cashierName,
              onDone: () async {
                await _loadSales(date: selectedDate);
                await _ensureItems(originalSaleId);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  CashierScreen.routName,
                      (Route<dynamic> route) => false, // يحذف كل الشاشات السابقة
                );
              },
            ),
          ),
        ),
        fullscreenDialog: true,
      ),
    );

    return result;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) {
      setState(() => selectedDate = picked);
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
        title: Text('الفواتير السابقة', style: TextStyle(fontSize: 20, color: Colors.white)),
        actions: [
          IconButton(
            onPressed: () async {
              setState(() => selectedDate = DateTime.now());
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: GestureDetector(
              onTap: _pickDate,
              child: Column(
                children: [
                  Text('التاريخ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_formatSelectedDate(selectedDate), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Icon(Icons.calendar_today, size: 18, color: Colors.white70),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: groupedSales.isEmpty
                ? Center(child: Text('لا توجد فواتير لهذا اليوم', style: TextStyle(color: Colors.white70, fontSize: 16)))
                : ListView(
              scrollDirection: Axis.vertical,
              children: groupedSales.entries.map((entry) {
                final cashierName = entry.key;
                final list = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  child: Card(
                    color: AppColorsDark.bgCardColor,
                    child: ExpansionTile(
                      collapsedIconColor: Colors.white70,
                      iconColor: Colors.white,
                      tilePadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      title: Text(
                        '$cashierName (${list.length})',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      children: list.map((s) {
                        final saleId = (s['id'] as num).toInt();
                        final total = (s['total'] as num?)?.toDouble() ?? 0.0;
                        final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                        final isReturn = (s['is_return'] ?? 0) == 1;
                        final note = (s['return_note'] ?? '').toString();
                        final dayMonth = _formatDayMonth(s['date']);
                        return ListTile(
                          onTap: () => _openSaleDetails(s),
                          title: Row(
                            children: [
                              Expanded(child: Text('#$saleId — $dayMonth', style: const TextStyle(fontSize: 16, color: Colors.white))),
                              if (isReturn) const Icon(Icons.cancel, color: Colors.red),
                              if (note.toLowerCase().contains('exchange')) const Icon(Icons.swap_horiz, color: Colors.green),
                            ],
                          ),
                          subtitle: Text('الإجمالي: ${total.toStringAsFixed(2)} — المدفوع: ${paid.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
                        );
                      }).toList(),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
