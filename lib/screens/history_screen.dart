import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../util.dart';
import '../widgets/charts.dart';

enum _Mode { day, week, month }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Mode mode = _Mode.week;
  DateTime anchor = today();
  List<DaySummary> data = [];
  int streak = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    app.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    app.removeListener(_reload);
    super.dispose();
  }

  (DateTime, DateTime) get _range {
    switch (mode) {
      case _Mode.day:
        final end = anchor;
        return (end.subtract(const Duration(days: 59)), end);
      case _Mode.week:
        final s = weekStart(anchor);
        return (s, s.add(const Duration(days: 6)));
      case _Mode.month:
        final s = DateTime(anchor.year, anchor.month, 1);
        return (s, DateTime(anchor.year, anchor.month + 1, 0));
    }
  }

  Future<void> _reload() async {
    if (app.profile == null) return;
    final (a, b) = _range;
    final d = await app.summaries(a, b);
    final s = await _streak();
    if (!mounted) return;
    setState(() {
      data = d;
      streak = s;
      loading = false;
    });
  }

  Future<int> _streak() async {
    final t = today();
    final list = await app.summaries(t.subtract(const Duration(days: 365)), t);
    var n = 0;
    for (var i = list.length - 1; i >= 0; i--) {
      final s = list[i];
      if (i == list.length - 1 && s.status != DayStatus.ok) continue; // hoy aún en curso
      if (s.status == DayStatus.ok) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  void _shift(int dir) {
    setState(() {
      switch (mode) {
        case _Mode.day:
          anchor = anchor.add(Duration(days: 60 * dir));
        case _Mode.week:
          anchor = anchor.add(Duration(days: 7 * dir));
        case _Mode.month:
          anchor = DateTime(anchor.year, anchor.month + dir, 1);
      }
      if (anchor.isAfter(today())) anchor = today();
    });
    _reload();
  }

  String get _title {
    final (a, b) = _range;
    switch (mode) {
      case _Mode.day:
        return 'Últimos 60 días hasta ${fmtShort(b)}';
      case _Mode.week:
        return 'Semana del ${fmtShort(a)} al ${fmtShort(b)}';
      case _Mode.month:
        return '${cap(meses[a.month - 1])} ${a.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.day, label: Text('Diario')),
                ButtonSegment(value: _Mode.week, label: Text('Semanal')),
                ButtonSegment(value: _Mode.month, label: Text('Mensual')),
              ],
              selected: {mode},
              onSelectionChanged: (s) {
                setState(() {
                  mode = s.first;
                  anchor = today();
                });
                _reload();
              },
            ),
          ),
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
            Expanded(child: Text(_title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _range.$2.isBefore(today()) ? () => _shift(1) : null),
          ]),
          if (loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else ...[
            _StatsCard(data: data, streak: streak),
            if (mode == _Mode.month) _MonthGrid(data: data, month: _range.$1),
            if (mode == _Mode.week) _WeekChart(data: data),
            if (mode != _Mode.month) ...[
              for (final s in data.reversed)
                if (mode == _Mode.week || s.hasData) _DayTile(s: s),
              if (mode == _Mode.day && data.every((s) => !s.hasData))
                const Padding(padding: EdgeInsets.all(24), child: Text('Sin registros en este periodo.')),
            ],
            const _Legend(),
          ],
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final List<DaySummary> data;
  final int streak;
  const _StatsCard({required this.data, required this.streak});

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final t = today();
    final logged = data.where((s) => s.hasData && !s.day.isAfter(t)).toList();
    final closed = logged.where((s) => s.day.isBefore(t)).toList(); // días terminados
    final ok = logged.where((s) => s.status == DayStatus.ok).length;
    final over = logged.where((s) => s.status == DayStatus.over).length;
    final under = logged.where((s) => s.status == DayStatus.under).length;
    final protOk = logged.where((s) => s.proteinOk).length;
    final avgK = logged.isEmpty ? 0.0 : logged.fold(0.0, (a, s) => a + s.kcal) / logged.length;
    final avgP = logged.isEmpty ? 0.0 : logged.fold(0.0, (a, s) => a + s.protein) / logged.length;
    final avgT = logged.isEmpty ? 0.0 : logged.fold(0.0, (a, s) => a + s.allowance) / logged.length;
    final balance = closed.fold(0.0, (a, s) => a + s.diff);
    Widget stat(String v, String l, [Color? c]) => Expanded(
          child: Column(children: [
            Text(v, style: ts.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: c)),
            Text(l, style: ts.bodySmall, textAlign: TextAlign.center),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            stat('$ok/${logged.length}', 'días en\nobjetivo', okColor),
            stat('$over', 'días\npasado', overColor),
            stat('$under', 'días\npor debajo', underColor),
            stat('🔥 $streak', 'racha\nactual'),
          ]),
          const Divider(height: 24),
          Row(children: [
            stat(fmtNum(avgK), 'kcal media\n(obj. ${fmtNum(avgT)})'),
            stat('${fmtNum(avgP)} g', 'proteína\nmedia'),
            stat('$protOk/${logged.length}', 'días con\nproteína'),
          ]),
          if (closed.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              balance <= 0
                  ? 'Balance: ${fmtNum(balance)} kcal respecto a tu objetivo (≈ ${fmtNum(balance / 7700, 2)} kg)'
                  : 'Balance: +${fmtNum(balance)} kcal por encima de tu objetivo (≈ +${fmtNum(balance / 7700, 2)} kg)',
              textAlign: TextAlign.center,
              style: ts.bodyMedium,
            ),
          ],
        ]),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  final List<DaySummary> data;
  const _WeekChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Calorías por día (la raya es tu objetivo)', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          BarChartSimple(
            values: data.map((s) => s.kcal).toList(),
            targets: data.map<double?>((s) => s.allowance).toList(),
            labels: data.map((s) => diasCortos[s.day.weekday - 1]).toList(),
            colors: data.map((s) => statusColor(s.status, cs)).toList(),
            onTap: (i) => app.goToDay(data[i].day),
          ),
        ]),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final List<DaySummary> data;
  final DateTime month;
  const _MonthGrid({required this.data, required this.month});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final offset = month.weekday - 1;
    final cells = <Widget>[
      for (final d in diasCortos) Center(child: Text(d, style: ts.labelSmall)),
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (final s in data)
        InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () => app.goToDay(s.day),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.hasData ? statusColor(s.status, cs) : null,
              border: sameDay(s.day, today()) ? Border.all(color: cs.primary, width: 2) : null,
            ),
            child: Stack(alignment: Alignment.center, children: [
              Text('${s.day.day}',
                  style: TextStyle(color: s.hasData ? Colors.white : cs.onSurface, fontWeight: FontWeight.w600)),
              if (s.hasData && s.proteinOk)
                const Positioned(bottom: 4, child: Icon(Icons.circle, size: 5, color: Colors.white)),
            ]),
          ),
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  final DaySummary s;
  const _DayTile({required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final diff = s.diff;
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: statusColor(s.status, cs),
        child: Text('${s.day.day}', style: TextStyle(fontSize: 12, color: s.hasData ? Colors.white : cs.onSurface)),
      ),
      title: Text('${cap(dias[s.day.weekday - 1])} ${fmtShort(s.day)}'),
      subtitle: Text(s.hasData
          ? '${fmtNum(s.kcal)} / ${fmtNum(s.allowance)} kcal · P ${fmtNum(s.protein)}/${fmtNum(s.target.protein)} g ${s.proteinOk ? '✓' : ''}'
          : 'Sin registro'),
      trailing: s.hasData
          ? Text(diff > 0 ? '+${fmtNum(diff)}' : fmtNum(diff),
              style: TextStyle(color: statusColor(s.status, cs), fontWeight: FontWeight.bold))
          : null,
      onTap: () => app.goToDay(s.day),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tol = app.profile?.tolerancePct ?? 10;
    Widget item(DayStatus st) => Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 6, backgroundColor: statusColor(st, cs)),
          const SizedBox(width: 4),
          Text(statusLabel(st), style: Theme.of(context).textTheme.bodySmall),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center, children: [
          item(DayStatus.ok),
          item(DayStatus.over),
          item(DayStatus.under),
        ]),
        const SizedBox(height: 6),
        Text('Cumplido = dentro de ±$tol% de tu objetivo (ajustable en Ajustes). El punto blanco indica proteína cumplida.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
