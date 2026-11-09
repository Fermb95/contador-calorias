import 'package:flutter/material.dart';

import '../calc.dart';
import '../db.dart';
import '../exercise_data.dart';
import '../models.dart';
import '../state.dart';
import '../util.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  String q = '';
  List<ExerciseEntry> recent = [];

  @override
  void initState() {
    super.initState();
    Db.recentExercises().then((r) {
      if (mounted) setState(() => recent = r);
    });
  }

  Future<void> _log({required String name, double? met, double? minutes, double? kcalPerMin}) async {
    final kg = app.profile!.weight;
    final nameC = TextEditingController(text: name);
    final minC = TextEditingController(text: fmtNum(minutes ?? 60));
    final kcalC = TextEditingController();
    bool manualKcal = met == null && kcalPerMin == null;

    double estimate() {
      final m = parseNum(minC.text) ?? 0;
      if (met != null) return metKcal(met, kg, m);
      if (kcalPerMin != null) return kcalPerMin * m;
      return 0;
    }

    if (!manualKcal) kcalC.text = fmtNum(estimate()).replaceAll('.', '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        return AlertDialog(
          title: const Text('Registrar ejercicio'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Nombre', helperText: 'Puedes personalizarlo: «Pesas – Push»')),
              const SizedBox(height: 12),
              TextField(
                controller: minC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Duración', suffixText: 'min'),
                onChanged: (_) {
                  if (!manualKcal) kcalC.text = fmtNum(estimate()).replaceAll('.', '');
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kcalC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Calorías quemadas',
                  suffixText: 'kcal',
                  helperText: manualKcal ? 'Valor manual (p. ej. de tu reloj)' : 'Estimado para ${fmtNum(kg, 1)} kg',
                ),
                onChanged: (_) => manualKcal = true,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Añadir')),
          ],
        );
      }),
    );
    if (ok != true) return;
    final kcal = parseNum(kcalC.text) ?? 0;
    final mins = parseNum(minC.text) ?? 0;
    if (kcal <= 0 && mins <= 0) return;
    await app.addExercise(ExerciseEntry(
      date: dkey(app.date),
      name: nameC.text.trim().isEmpty ? name : nameC.text.trim(),
      minutes: mins,
      kcal: kcal.roundToDouble(),
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final nq = normalize(q);
    final list = activities.where((a) => nq.isEmpty || normalize('${a.name} ${a.group}').contains(nq)).toList();
    final groups = <String, List<Activity>>{};
    for (final a in list) {
      groups.putIfAbsent(a.group, () => []).add(a);
    }
    final ts = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: false,
          decoration: const InputDecoration(hintText: 'Buscar actividad…', border: InputBorder.none),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Calorías manuales'),
            subtitle: const Text('Si tu reloj o la máquina te dicen las kcal'),
            onTap: () => _log(name: q.isEmpty ? 'Ejercicio' : q),
          ),
          if (recent.isNotEmpty && q.isEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Recientes', style: ts.titleSmall)),
            for (final r in recent)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(r.name),
                subtitle: Text('${fmtNum(r.minutes)} min · ${fmtNum(r.kcal)} kcal'),
                onTap: () => _log(
                    name: r.name, minutes: r.minutes, kcalPerMin: r.minutes > 0 ? r.kcal / r.minutes : null),
              ),
          ],
          for (final g in groups.entries) ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(g.key, style: ts.titleSmall)),
            for (final a in g.value)
              ListTile(
                dense: true,
                title: Text(a.name),
                trailing: Text('≈ ${fmtNum(metKcal(a.met, app.profile!.weight, 60))} kcal/h', style: ts.bodySmall),
                onTap: () => _log(name: a.name, met: a.met, minutes: a.group == 'Gimnasio' ? 60 : 45),
              ),
          ],
        ],
      ),
    );
  }
}
