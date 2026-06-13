import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/empty_state_card.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();
  final _money = NumberFormat.currency(locale: 'ar', symbol: 'جنيه ');
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;

  List<Map<String, dynamic>> get _filteredCustomers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _customers;
    return _customers.where((customer) {
      final name = (customer['name'] ?? '').toString().toLowerCase();
      final phone = (customer['phone'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await DBHelper.instance.getCustomersWithSummary();
      if (mounted) setState(() => _customers = rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('فشل تحميل العملاء: $e'),
        ),
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم العميل أو رقم الهاتف',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredCustomers.isEmpty
                        ? const EmptyStateCard(
                            icon: Icons.people_outline,
                            title: 'لا يوجد عملاء',
                            message:
                                'سيظهر العملاء هنا بعد تسجيلهم من شاشة الكاشير.',
                          )
                        : ListView.separated(
                            itemCount: _filteredCustomers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final customer = _filteredCustomers[index];
                              final balance =
                                  (customer['loyalty_balance'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                              final invoiceCount =
                                  (customer['invoice_count'] as num?)
                                          ?.toInt() ??
                                      0;
                              final totalPurchases =
                                  (customer['total_purchases'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                              return Card(
                                color: Theme.of(context).cardColor,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 26,
                                        backgroundColor: AppColorsDark.mainColor
                                            .withValues(alpha: 0.16),
                                        child: Icon(
                                          Icons.person,
                                          color:
                                              Theme.of(context).iconTheme.color,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (customer['name'] ?? '')
                                                  .toString(),
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              (customer['phone'] ?? '')
                                                  .toString(),
                                              textDirection: TextDirection.ltr,
                                              style:
                                                  TextStyle(color: textColor),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'عدد الفواتير: $invoiceCount  |  إجمالي المشتريات: ${_money.format(totalPurchases)}',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: balance >= 50
                                              ? Colors.green
                                                  .withValues(alpha: 0.16)
                                              : AppColorsDark.mainColor
                                                  .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'رصيد الخصم',
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${balance.toStringAsFixed(2)} جنيه',
                                              style: TextStyle(
                                                color: balance >= 50
                                                    ? Colors.green
                                                    : textColor,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
