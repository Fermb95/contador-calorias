import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../state.dart';
import '../util.dart';
import '../widgets/charts.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<MapEntry<String, double>> weights = [];
  AdaptiveResult? adaptive;
  int range = 90;

  @override
  void initState() {
    super.initState();
    app.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    app.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (app.profile == null) return;
    final w = await Db.weights();
    final a = await app.adaptiveTdee();
    if (mounted) {
      setState(() {
        weights = w;
        adaptive = a;
      });
    }
  }

  Future<void> _addWeight() async {
    var d = today();
    final ctrl = TextEditingController(text: weights.isEmpty ? '' : fmtNum(weights.last.value, 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Registrar peso'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Peso', suffixText: 'kg'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.event),
              label: Text(fmtLong(d)),
              onPressed: () async {
                final x = await showDatePicker(context: c, initialDate: d, firstDate: DateTime(2020), lastDate: today());
                if (x != null) setD(() => d = x);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final kg = parseNum(ctrl.text);
    if (ok == true && kg != null && kg > 30 && kg < 300) {
      await app.addWeight(d, kg);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = app.profile;
    final cutoff = range == 0 ? DateTime(2000) : today().subtract(Duration(days: range));
    final allTrend = trendWeights(weights.map((e) => e.value).toList());
    final idx = [for (var i = 0; i < weights.length; i++) if (!parseKey(weights[i].key).isBefore(cutoff)) i];
    final dates = idx.map((i) => parseKey(weights[i].key)).toList();
    final ws = idx.map((i) => weights[i].value).toList();
    final tr = idx.map((i) => allTrend[i]).toList();

    double? trendChange(int days) {
      if (weights.length < 2) return null;
      final last = parseKey(weights.last.key);
      final from = last.subtract(Duration(days: days));
      int? j;
      for (var i = 0; i < weights.length; i++) {
        if (!parseKey(weights[i].key).isAfter(from)) j = i;
      }
      if (j == null) return null;
      return allTrend.last - allTrend[j];
    }

    final c7 = trendChange(7), c30 = trendChange(30);
    Widget stat(String v, String l) => Expanded(
          child: Column(children: [
            Text(v, style: ts.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(l, style: ts.bodySmall, textAlign: TextAlign.center),
          ]),
        );
    String sign(double? v) => v == null ? '—' : '${v > 0 ? '+' : ''}${fmtNum(v, 1)} kg';

    return Scaffold(
      appBar: AppBar(title: const Text('Peso y progreso')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _addWeight, icon: const Icon(Icons.monitor_weight), label: const Text('Registrar peso')),
      body: p == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        stat(weights.isEmpty ? '—' : '${fmtNum(weights.last.value, 1)} kg', 'última\npesada'),
                        stat(allTrend.isEmpty ? '—' : '${fmtNum(allTrend.last, 1)} kg', 'peso\ntendencia'),
                        stat(sign(c7), 'últimos\n7 días'),
                        stat(sign(c30), 'últimos\n30 días'),
                      ]),
                      const SizedBox(height: 16),
                      if (ws.length >= 2)
                        WeightChart(dates: dates, weights: ws, trend: tr)
                      else
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Pésate varias veces por semana (mejor a diario, en ayunas) para ver la tendencia.',
                              textAlign: TextAlign.center),
                        ),
                      Wrap(spacing: 6, children: [
                        for (final r in const [30, 90, 365, 0])
                          ChoiceChip(
                            label: Text(r == 0 ? 'Todo' : r == 365 ? '1 año' : '$r días'),
                            selected: range == r,
                            onSelected: (_) => setState(() => range = r),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text('Los puntos son tus pesadas; la línea, la tendencia que filtra el agua y la sal.',
                          style: ts.bodySmall, textAlign: TextAlign.center),
                    ]),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Gasto real estimado', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      if (adaptive == null)
                        Text(
                          'Cuando lleves unas 3 semanas registrando la comida casi todos los días y pesándote, '
                          'calcularé cuánto gastas de verdad comparando lo que comes con cómo cambia tu peso. '
                          'Ahora uso la fórmula: ${fmtNum(formulaTdee(p))} kcal/día.',
                          style: ts.bodyMedium,
                        )
                      else ...[
                        Text('${fmtNum(adaptive!.tdee)} kcal/día',
                            style: ts.headlineSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                        Text(
                          'Últimos ${adaptive!.days} días: comiste de media ${fmtNum(adaptive!.avgIntake)} kcal '
                          '(${adaptive!.loggedDays} días registrados) y tu tendencia cambió ${sign(adaptive!.trendChangeKg)}. '
                          'La fórmula decía ${fmtNum(formulaTdee(p))} kcal.',
                          style: ts.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, children: [
                          FilledButton.tonal(
                            onPressed: () async {
                              p.adaptiveTdee = (adaptive!.tdee / 10).roundToDouble() * 10;
                              await app.saveProfile(p);
                              if (context.mounted) toast(context, 'Objetivo ajustado: ${fmtNum(app.targets.kcal)} kcal');
                            },
                            child: const Text('Ajustar mi objetivo con este gasto'),
                          ),
                        ]),
                      ],
                      if (p.adaptiveTdee != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Expanded(child: Text('Usando gasto ajustado: ${fmtNum(p.adaptiveTdee!)} kcal', style: ts.bodySmall)),
                            TextButton(
                              onPressed: () async {
                                p.adaptiveTdee = null;
                                await app.saveProfile(p);
                              },
                              child: const Text('Volver a la fórmula'),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                if (weights.isNotEmpty)
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Pesadas', style: ts.titleSmall)),
                for (final w in weights.reversed.take(60))
                  Dismissible(
                    key: ValueKey('w${w.key}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                        color: overColor,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white)),
                    onDismissed: (_) async {
                      setState(() => weights.removeWhere((x) => x.key == w.key));
                      await app.deleteWeight(w.key);
                    },
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.monitor_weight_outlined),
                      title: Text('${fmtNum(w.value, 1)} kg'),
                      subtitle: Text(fmtLong(parseKey(w.key))),
                    ),
                  ),
              ],
            ),
    );
  }
}
