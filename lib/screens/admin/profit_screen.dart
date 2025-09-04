import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/db/db_helper.dart';

class TopProductsChartPage extends StatefulWidget {
  const TopProductsChartPage({super.key});

  @override
  State<TopProductsChartPage> createState() => _TopProductsChartPageState();
}

class _TopProductsChartPageState extends State<TopProductsChartPage> {
  String _period = 'day';
  int _limit = 20; // 👈 عدد أكبر لأن الشارت هيتحرك أفقياً

  Future<List<Map<String, dynamic>>> _loadData() async {
    return await DBHelper.instance.getTopSellingProducts(period: _period, limit: _limit);
  }

  void _changePeriod(String p) {
    setState(() {
      _period = p;
    });
  }

  Widget _periodButton(String val, String label) {
    final active = _period == val;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Theme(
        data: Theme.of(context).copyWith(
          chipTheme: Theme.of(context).chipTheme.copyWith(
            checkmarkColor: AppColorsDark.mainColor,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom:30.0),
          child: ChoiceChip(
            disabledColor: AppColorsDark.bgColor,
            backgroundColor: AppColorsDark.bgColor,
            selectedColor: AppColorsDark.bgColor,

            side: BorderSide(color: AppColorsDark.mainColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            label: Text(label),
            selected: active,
            onSelected: (_) => _changePeriod(val),
            labelStyle: TextStyle(
              color: active ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  BarChartGroupData _makeGroup(int x, double value, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: value,
          width: 20,
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildBarChart(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const Center(child: Text('لا توجد بيانات لعرضها'));

    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.brown,
    ];

    final maxUnits = rows.map((r) => (r['units_sold'] as int)).fold<int>(0, (p, e) => e > p ? e : p);
    final groups = <BarChartGroupData>[];
    final labels = <String>[];

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final units = (r['units_sold'] as int).toDouble();
      groups.add(_makeGroup(i, units, colors[i % colors.length]));
      final name = (r['product_name'] as String?) ?? '';
      labels.add(name.length > 12 ? name.substring(0, 11) + '…' : name);
    }

    final double maxY = (maxUnits > 0) ? (maxUnits * 1.2) : 1.0;

    // 👇 العرض الكلي للشارت بناءً على عدد الأعمدة
    final chartWidth = groups.length * 60.0;

    return Column(
      children: [
        SizedBox(
          height: 280,
          child: Card(
            color: AppColorsDark.bgColor,
            elevation: 3,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColorsDark.mainColor)
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1400,
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      barGroups: groups,
                      gridData: FlGridData(show: true),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 0,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              final intVal = value.toInt();
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(intVal.toString(), style: const TextStyle(fontSize: 11,color: Colors.white)),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                              return SideTitleWidget(
                                meta: meta,
                                space: 6.0,
                                child: Text(
                                  labels[idx],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11,color: Colors.white),
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => Colors.white,
                          tooltipBorderRadius: BorderRadius.circular(6),
                          tooltipPadding: const EdgeInsets.all(8),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final r = rows[groupIndex];
                            return BarTooltipItem(
                              '${r['product_name']}\n${r['units_sold']} وحدة\n${(r['revenue'] as double).toStringAsFixed(2)} ج.م',
                              const TextStyle(color: Colors.white70),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (ctx, i) {
              final r = rows[i];
              return Padding(
                padding: EdgeInsetsGeometry.directional(bottom: 10),
                child: Card(
                  color: AppColorsDark.bgCardColor,
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors[i % colors.length],
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(r['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold,color: Colors.white)),
                      subtitle: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('${r['units_sold']} وحدة مباعة',style: TextStyle(color: Colors.white70,fontSize: 10),),
                      ),
                      trailing: Text(
                        '${(r['revenue'] as double).toStringAsFixed(2)} ج.م',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        _periodButton('day', 'اليوم'),
        _periodButton('week', 'الأسبوع'),
        _periodButton('month', 'الشهر'),
        _periodButton('year', 'السنة'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
          title:Text(
              'أكثر المنتجات مبيعًا',
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
            ),
          ),
        elevation: 0.0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        scrolledUnderElevation: 0.0,
        iconTheme: IconThemeData(
          color: Colors.white70
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildPeriodSelector(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('حدث خطأ: ${snapshot.error}'));
                }
                final rows = snapshot.data ?? [];
                return _buildBarChart(rows);
              },
            ),
          ),
        ],
      ),
    );
  }
}
