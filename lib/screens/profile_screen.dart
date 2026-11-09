import 'package:flutter/material.dart';

import '../calc.dart';
import '../models.dart';
import '../notifications.dart';
import '../state.dart';
import '../util.dart';

class ProfileScreen extends StatefulWidget {
  final bool firstTime;
  const ProfileScreen({super.key, this.firstTime = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Profile p;
  late final TextEditingController age, height, weight;

  @override
  void initState() {
    super.initState();
    p = app.profile?.clone() ?? Profile();
    age = TextEditingController(text: widget.firstTime ? '' : '${p.age}');
    height = TextEditingController(text: widget.firstTime ? '' : fmtNum(p.height, 1));
    weight = TextEditingController(text: widget.firstTime ? '' : fmtNum(p.weight, 1));
  }

  @override
  void dispose() {
    age.dispose();
    height.dispose();
    weight.dispose();
    super.dispose();
  }

  bool get _valid {
    final a = int.tryParse(age.text.trim());
    final h = parseNum(height.text);
    final w = parseNum(weight.text);
    return a != null && a >= 14 && a <= 100 && h != null && h >= 120 && h <= 230 && w != null && w >= 35 && w <= 300;
  }

  void _read() {
    p.age = int.tryParse(age.text.trim()) ?? p.age;
    p.height = parseNum(height.text) ?? p.height;
    p.weight = parseNum(weight.text) ?? p.weight;
  }

  Future<void> _save() async {
    if (!_valid) {
      toast(context, 'Revisa edad (14-100), altura en cm y peso en kg');
      return;
    }
    _read();
    final first = widget.firstTime;
    final weightChanged = app.profile == null || (app.profile!.weight - p.weight).abs() > 0.01;
    await app.saveProfile(p);
    if (weightChanged) await app.addWeight(today(), p.weight);
    if (first) {
      try {
        await Notif.requestPermission();
        await Notif.scheduleReminders(p);
      } catch (_) {}
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Widget _section(String title, [String? help]) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (help != null) Text(help, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _option({required bool selected, required String title, String? subtitle, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: selected ? cs.primaryContainer : null,
      child: ListTile(
        title: Text(title, style: TextStyle(fontWeight: selected ? FontWeight.bold : null)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: selected ? Icon(Icons.check_circle, color: cs.primary) : const Icon(Icons.circle_outlined),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final canPreview = _valid;
    Targets? t;
    double? b, td;
    if (canPreview) {
      final tmp = p.clone();
      tmp.age = int.parse(age.text.trim());
      tmp.height = parseNum(height.text)!;
      tmp.weight = parseNum(weight.text)!;
      t = computeTargets(tmp);
      b = bmr(tmp);
      td = formulaTdee(tmp);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstTime ? 'Bienvenido a Balance' : 'Perfil y objetivo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (widget.firstTime)
            Text('Cuéntame un poco de ti y calculo las calorías y macros que necesitas.', style: ts.bodyLarge),
          _section('Sexo'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'h', label: Text('Hombre'), icon: Icon(Icons.male)),
              ButtonSegment(value: 'm', label: Text('Mujer'), icon: Icon(Icons.female)),
            ],
            selected: {p.sex},
            onSelectionChanged: (s) => setState(() => p.sex = s.first),
          ),
          _section('Datos'),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Edad', suffixText: 'años'),
                    onChanged: (_) => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: height,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Altura', suffixText: 'cm'),
                    onChanged: (_) => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Peso', suffixText: 'kg'),
                    onChanged: (_) => setState(() {}))),
          ]),
          _section('Actividad diaria', 'Sin contar los entrenamientos: esos los registras aparte y suman.'),
          for (var i = 0; i < activityLabels.length; i++)
            _option(
              selected: p.activity == i,
              title: activityLabels[i],
              subtitle: activityHelp[i],
              onTap: () => setState(() => p.activity = i),
            ),
          _section('¿Qué buscas?'),
          for (final g in goalLabels.keys)
            _option(
              selected: p.goal == g,
              title: goalLabels[g]!,
              subtitle: goalHelp[g],
              onTap: () => setState(() {
                p.goal = g;
                p.proteinPerKg = null;
              }),
            ),
          if (p.goal != 'maintain') ...[
            _section('Ritmo'),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (var i = 0; i < 3; i++)
                  ButtonSegment(value: i, label: Text(intensityLabels[p.goal]![i], textAlign: TextAlign.center)),
              ],
              selected: {p.intensity},
              onSelectionChanged: (s) => setState(() => p.intensity = s.first),
            ),
          ],
          if (t != null) ...[
            _section('Tu objetivo diario'),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${fmtNum(t.kcal)} kcal',
                      style: ts.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: 8),
                  Text('Proteína ${fmtNum(t.protein)} g · Hidratos ${fmtNum(t.carbs)} g · Grasa ${fmtNum(t.fat)} g'),
                  const SizedBox(height: 8),
                  Text(
                    'Metabolismo basal ${fmtNum(b!)} kcal · Gasto diario ${fmtNum(td!)} kcal'
                    '${p.adaptiveTdee != null ? ' (usando gasto real estimado: ${fmtNum(p.adaptiveTdee!)} kcal)' : ''}'
                    '${p.customKcal != null ? '\nObjetivo fijado a mano en Ajustes.' : ''}',
                    style: ts.bodySmall,
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(widget.firstTime ? 'Empezar' : 'Guardar'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}
