import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/json.dart';
import '../../core/theme.dart';
import '../../resources/resources.dart';
import '../../services/farm_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../resource/resource_form_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _summary;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await FarmService.dashboardSummary();
      if (mounted) setState(() => _summary = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<FlSpot> _chartSpots(String key) {
    final raw = pick(_summary, [key]);
    if (raw is! List) return [];
    final points = raw.whereType<Map<String, dynamic>>().toList();
    return [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), pickNum(points[i], ['value']).toDouble()),
    ];
  }

  List<String> _chartLabels(String key) {
    final raw = pick(_summary, [key]);
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((p) => pickString(p, ['label']))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final session = context.watch<AppState>().session;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session?.farmName ?? 'Dashboard'),
            Text('Hi ${session?.username ?? ''} 👋',
                style: t.bodySmall?.copyWith(color: AppColors.inkMuted)),
          ],
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Iconsax.refresh)),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(TextTheme t) {
    if (_error != null) return ErrorRetry(message: _error!, onRetry: _load);
    if (_summary == null) return const Center(child: CircularProgressIndicator());
    final s = _summary!;
    final eggSpots = _chartSpots('eggChart');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              StatCard(
                label: 'Eggs today',
                value: '${pickNum(s, ['totalEggsToday'])}',
                icon: Iconsax.cake,
                color: AppColors.accent,
              ),
              StatCard(
                label: 'Feed today',
                value: '${pickNum(s, ['feedUsedTodayKg'])} kg',
                icon: Iconsax.milk,
                color: AppColors.success,
              ),
              StatCard(
                label: 'Sales today',
                value: fmtMoney(pickNum(s, ['salesToday'])),
                icon: Iconsax.shopping_cart,
                color: AppColors.primary,
              ),
              StatCard(
                label: 'Expenses today',
                value: fmtMoney(pickNum(s, ['expensesToday'])),
                icon: Iconsax.money_send,
                color: AppColors.danger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Iconsax.pet, color: AppColors.primary),
              ),
              title: Text('${pickNum(s, ['activeFlocks'])} active flocks',
                  style: t.titleMedium?.copyWith(fontSize: 15.5)),
              subtitle: const Text('Long-press any record in a list to delete it'),
            ),
          ),
          if (eggSpots.length > 1) ...[
            const SizedBox(height: 20),
            Text('Egg production trend', style: t.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                child: SizedBox(
                  height: 190,
                  child: _EggChart(spots: eggSpots, labels: _chartLabels('eggChart')),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Quick add', style: t.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              _QuickAction(spec: eggProductionSpec, label: 'Eggs', onDone: _load),
              const SizedBox(width: 10),
              _QuickAction(spec: feedUsageSpec, label: 'Feed', onDone: _load),
              const SizedBox(width: 10),
              _QuickAction(spec: salesSpec, label: 'Sale', onDone: _load),
              const SizedBox(width: 10),
              _QuickAction(spec: expensesSpec, label: 'Expense', onDone: _load),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final dynamic spec;
  final String label;
  final VoidCallback onDone;
  const _QuickAction({required this.spec, required this.label, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => ResourceFormScreen(spec: spec)),
            );
            if (changed == true) onDone();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(spec.icon, color: spec.color, size: 24),
                const SizedBox(height: 6),
                Text(label, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EggChart extends StatelessWidget {
  final List<FlSpot> spots;
  final List<String> labels;
  const _EggChart({required this.spots, required this.labels});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.black.withValues(alpha: 0.06), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: t.labelSmall?.copyWith(color: AppColors.inkMuted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (spots.length / 4).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i],
                      style: t.labelSmall?.copyWith(color: AppColors.inkMuted)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(handleBuiltInTouches: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
