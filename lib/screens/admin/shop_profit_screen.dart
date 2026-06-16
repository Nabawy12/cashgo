import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/empty_state_card.dart';

class ShopProfitScreen extends StatefulWidget {
  const ShopProfitScreen({super.key});

  @override
  State<ShopProfitScreen> createState() => _ShopProfitScreenState();
}

class _ShopProfitScreenState extends State<ShopProfitScreen> {
  final _money = NumberFormat.currency(locale: 'ar', symbol: 'EGP ');
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  List<Map<String, dynamic>> _dailyRows = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _paidPurchases = [];
  double _totalLoyaltyDiscounts = 0.0;

  double get _totalProfit => _dailyRows.fold<double>(
        0.0,
        (sum, row) => sum + ((row['profit'] as num?)?.toDouble() ?? 0.0),
      );

  double get _totalExternalExpenses => _expenses.fold<double>(
        0.0,
        (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0.0),
      );

  double get _totalPaidPurchases => _paidPurchases.fold<double>(

        0.0,
        (sum, row) => sum + ((row['paid_total'] as num?)?.toDouble() ?? 0.0),
      );

  double get _totalExpenses => _totalExternalExpenses + _totalPaidPurchases;

  double get _netProfit => _totalProfit - _totalExpenses - _totalLoyaltyDiscounts;

  DateTime get _monthStart =>
      DateTime(_selectedMonth.year, _selectedMonth.month, 1);

  DateTime get _monthEnd =>
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await DBHelper.instance.getDailyShopProfitReport(
        year: _selectedMonth.year,
        month: _selectedMonth.month,
      );
      final expenses = await DBHelper.instance.getShopExternalExpenses(
        from: _monthStart,
        to: _monthEnd,
      );
      final paidPurchases = await DBHelper.instance.getShopPaidPurchases(
        from: _monthStart,
        to: _monthEnd,
      );
      final loyaltyDiscounts = await DBHelper.instance.getTotalLoyaltyDiscounts(
        from: _monthStart,
        to: _monthEnd,
      );
      if (!mounted) return;
      setState(() {
        _dailyRows = rows;
        _expenses = expenses;
        _paidPurchases = paidPurchases;
        _totalLoyaltyDiscounts = loyaltyDiscounts;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'اختر أي يوم داخل الشهر المطلوب',
    );
    if (picked == null) return;
    setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    await _load();
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    await _load();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(message),
        ),
      ),
    );
  }

  Future<void> _showAddExpenseDialog() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    DateTime expenseDate = DateTime.now();
    if (expenseDate.year != _selectedMonth.year ||
        expenseDate.month != _selectedMonth.month) {
      expenseDate = _monthStart;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogTextColor = Theme.of(ctx).brightness == Brightness.light
            ? Colors.black87
            : Colors.white;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(
                  'إضافة مصروف خارجي',
                  style: TextStyle(color: dialogTextColor),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        labelText: 'المصروف يخص إيه؟',
                        hintText: 'مثال: إيجار، كهرباء، صيانة',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'قيمة المصروف',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: expenseDate,
                          firstDate: _monthStart,
                          lastDate: _monthEnd,
                        );
                        if (picked == null) return;
                        setDialogState(() => expenseDate = picked);
                      },
                      icon: Icon(Icons.calendar_today,
                          color: Theme.of(ctx).iconTheme.color),
                      label: Text(
                        DateFormat('yyyy-MM-dd').format(expenseDate),
                        style: TextStyle(color: dialogTextColor),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child:
                        Text('إلغاء', style: TextStyle(color: dialogTextColor)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final title = titleController.text.trim();
                      final amount = double.tryParse(amountController.text
                              .replaceAll(',', '')
                              .trim()) ??
                          0.0;
                      if (title.isEmpty || amount <= 0) {
                        _showSnack('اكتب اسم المصروف وقيمته بشكل صحيح');
                        return;
                      }
                      await DBHelper.instance.addShopExternalExpense(
                        title: title,
                        amount: amount,
                        date: expenseDate,
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    amountController.dispose();

    if (saved == true) {
      _showSnack('تم حفظ المصروف');
      await _load();
    }
  }

  Future<void> _deleteExpense(int id) async {
    await DBHelper.instance.deleteShopExternalExpense(id);
    _showSnack('تم حذف المصروف');
    await _load();
  }

  Widget _summaryCard(String title, double value, Color color) {
    return Expanded(
      child: Card(
        color: AppColorsDark.bgCardColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColorsDark.mainTextLight)),
              const SizedBox(height: 8),
              Text(
                _money.format(value),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dailyProfitList() {
    final activeRows = _dailyRows.where((row) {
      final profit = (row['profit'] as num?)?.toDouble() ?? 0.0;
      final expenses = (row['external_expenses'] as num?)?.toDouble() ?? 0.0;
      final paidPurchases = (row['paid_purchases'] as num?)?.toDouble() ?? 0.0;
      return profit != 0 || expenses != 0 || paidPurchases != 0;
    }).toList();

    if (activeRows.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.trending_up,
        title: 'لا توجد أرباح أو مصروفات',
        message: 'اختر شهر آخر أو أضف مصروف خارجي لهذا الشهر.',
      );
    }

    return ListView.separated(
      itemCount: activeRows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final row = activeRows[index];
        final date = (row['date'] ?? '').toString();
        final profit = (row['profit'] as num?)?.toDouble() ?? 0.0;
        final expenses = (row['external_expenses'] as num?)?.toDouble() ?? 0.0;
        final paidPurchases =
            (row['paid_purchases'] as num?)?.toDouble() ?? 0.0;
        final net = (row['net_profit'] as num?)?.toDouble() ?? 0.0;
        return Card(
          color: AppColorsDark.bgCardColor,
          child: ListTile(
            title:
                Text(date, style: TextStyle(color: AppColorsDark.mainTextDark)),
            subtitle: Text(
              'ربح اليوم: ${_money.format(profit)} | مصروفات خارجية: ${_money.format(expenses)} | مشتريات مدفوعة: ${_money.format(paidPurchases)}',
              style: TextStyle(color: AppColorsDark.mainTextLight),
            ),
            trailing: Text(
              _money.format(net),
              style: TextStyle(
                color: net >= 0 ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _expensesList() {
    if (_expenses.isEmpty) {
      return Text(
        'لا توجد مصروفات خارجية لهذا الشهر',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColorsDark.mainTextLight),
      );
    }

    return Column(
      children: _expenses.map((expense) {
        final id = (expense['id'] as num?)?.toInt() ?? 0;
        final title = (expense['title'] ?? '').toString();
        final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
        final date =
            (expense['expense_date'] ?? '').toString().split('T').first;
        return Card(
          color: AppColorsDark.bgCardColor,
          child: ListTile(
            title: Text(title,
                style: TextStyle(color: AppColorsDark.mainTextDark)),
            subtitle: Text(date,
                style: TextStyle(color: AppColorsDark.mainTextLight)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _money.format(amount),
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  tooltip: 'حذف المصروف',
                  onPressed: id <= 0 ? null : () => _deleteExpense(id),
                  icon: Icon(Icons.delete_outline,
                      color: Theme.of(context).iconTheme.color),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _paidPurchasesList() {
    if (_paidPurchases.isEmpty) {
      return Text(
        'لا توجد مشتريات مدفوعة لهذا الشهر',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColorsDark.mainTextLight),
      );
    }

    return Column(
      children: _paidPurchases.map((purchase) {
        final productName = (purchase['product_name'] ?? 'مشتريات').toString();
        final paidTotal = (purchase['paid_total'] as num?)?.toDouble() ?? 0.0;
        final paymentType = (purchase['payment_type'] ?? '').toString();
        final date = (purchase['created_at'] ?? '').toString().split('T').first;
        return Card(
          color: AppColorsDark.bgCardColor,
          child: ListTile(
            title: Text(productName,
                style: TextStyle(color: AppColorsDark.mainTextDark)),
            subtitle: Text(
              '$date | طريقة الدفع: ${paymentType.isEmpty ? 'غير محدد' : paymentType}',
              style: TextStyle(color: AppColorsDark.mainTextLight),
            ),
            trailing: Text(
              _money.format(paidTotal),
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'ar').format(_selectedMonth);

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text('أرباح المحل',
            style: TextStyle(color: AppColorsDark.mainTextDark)),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddExpenseDialog,
        icon: const Icon(Icons.add),
        label: const Text('إضافة مصروف'),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                color: AppColorsDark.bgCardColor,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => _changeMonth(-1),
                        icon: Icon(Icons.chevron_right,
                            color: Theme.of(context).iconTheme.color),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _pickMonth,
                          icon: Icon(Icons.calendar_month,
                              color: Theme.of(context).iconTheme.color),
                          label: Text(
                            monthLabel,
                            style: TextStyle(
                              color: AppColorsDark.mainTextDark,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _changeMonth(1),
                        icon: Icon(Icons.chevron_left,
                            color: Theme.of(context).iconTheme.color),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _summaryCard(
                      'مجمل الأرباح', _totalProfit, Colors.greenAccent),
                  const SizedBox(width: 8),
                  _summaryCard(
                      'مجمل المصاريف', _totalExpenses, Colors.redAccent),
                  const SizedBox(width: 8),
                  _summaryCard(
                      'خصومات العملاء', _totalLoyaltyDiscounts, Colors.orangeAccent),
                  const SizedBox(width: 8),
                  _summaryCard(
                    'الصافي',
                    _netProfit,
                    _netProfit >= 0 ? Colors.greenAccent : Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _dailyProfitList()),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'المصروفات الخارجية',
                                    style: TextStyle(
                                      color: AppColorsDark.mainTextDark,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _expensesList(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'المشتريات المدفوعة',
                                    style: TextStyle(
                                      color: AppColorsDark.mainTextDark,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _paidPurchasesList(),
                                  const SizedBox(height: 80),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
