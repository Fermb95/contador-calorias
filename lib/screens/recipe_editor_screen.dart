import 'dart:convert';

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../util.dart';
import 'add_food_screen.dart';
import 'food_search_screen.dart';

class _Ing {
  final int? foodId;
  final String name;
  final double grams, kcal, protein, carbs, fat;
  _Ing(this.foodId, this.name, this.grams, this.kcal, this.protein, this.carbs, this.fat);

  factory _Ing.fromPicked(PickedFood p) {
    final r = p.grams / 100;
    final f = p.food;
    return _Ing(f.id, f.name, p.grams, f.kcal * r, f.protein * r, f.carbs * r, f.fat * r);
  }

  Map<String, Object?> toJson() =>
      {'food_id': foodId, 'name': name, 'grams': grams, 'kcal': kcal, 'protein': protein, 'carbs': carbs, 'fat': fat};

  factory _Ing.fromJson(Map<String, dynamic> j) => _Ing(
        j['food_id'] as int?,
        j['name'] as String,
        (j['grams'] as num).toDouble(),
        (j['kcal'] as num).toDouble(),
        (j['protein'] as num).toDouble(),
        (j['carbs'] as num).toDouble(),
        (j['fat'] as num).toDouble(),
      );
}

/// Recetas: suma ingredientes y guarda el resultado como alimento por 100 g con raciones.
class RecipeEditorScreen extends StatefulWidget {
  final Food? recipe;
  const RecipeEditorScreen({super.key, this.recipe});

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  final name = TextEditingController();
  final servings = TextEditingController(text: '2');
  final cookedWeight = TextEditingController();
  final List<_Ing> ings = [];

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    if (r != null && r.recipe != null) {
      name.text = r.name;
      final j = jsonDecode(r.recipe!) as Map<String, dynamic>;
      servings.text = '${j['servings'] ?? 1}';
      if (j['cooked'] != null) cookedWeight.text = fmtNum(j['cooked'] as num, 1).replaceAll('.', '');
      ings.addAll((j['items'] as List).map((e) => _Ing.fromJson(e as Map<String, dynamic>)));
    }
  }

  double get rawWeight => ings.fold(0.0, (s, i) => s + i.grams);
  double get totalWeight => parseNum(cookedWeight.text) ?? rawWeight;
  double get kcal => ings.fold(0.0, (s, i) => s + i.kcal);
  double get protein => ings.fold(0.0, (s, i) => s + i.protein);
  double get carbs => ings.fold(0.0, (s, i) => s + i.carbs);
  double get fat => ings.fold(0.0, (s, i) => s + i.fat);
  int get nServ => (int.tryParse(servings.text.trim()) ?? 1).clamp(1, 100);

  Future<void> _add() async {
    final p = await Navigator.push<PickedFood>(
        context, MaterialPageRoute(builder: (_) => const FoodSearchScreen(meal: 2, pickMode: true)));
    if (p != null) setState(() => ings.add(_Ing.fromPicked(p)));
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty || ings.isEmpty || totalWeight <= 0) {
      toast(context, 'Pon nombre y al menos un ingrediente');
      return;
    }
    final w = totalWeight;
    final f = widget.recipe ?? Food(name: '', kcal: 0, protein: 0, carbs: 0, fat: 0, source: 'recipe');
    f
      ..name = name.text.trim()
      ..source = 'recipe'
      ..kcal = kcal / w * 100
      ..protein = protein / w * 100
      ..carbs = carbs / w * 100
      ..fat = fat / w * 100
      ..portions = [
        Portion('ración (1/$nServ de la receta)', w / nServ),
        Portion('receta entera', w),
      ]
      ..recipe = jsonEncode({
        'servings': nServ,
        'cooked': parseNum(cookedWeight.text),
        'items': ings.map((i) => i.toJson()).toList(),
      });
    await Db.saveFood(f);
    if (mounted) Navigator.pop(context, f);
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final perServ = nServ > 0 ? kcal / nServ : 0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.recipe == null ? 'Nueva receta' : 'Editar receta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre de la receta'), textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: servings,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Raciones'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: cookedWeight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Peso final cocinado (opcional)', suffixText: 'g', hintText: fmtNum(rawWeight)),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Si pesas la olla/bandeja al terminar, el cálculo por gramos será exacto (el agua se evapora o se absorbe).',
                style: ts.bodySmall),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Ingredientes', style: ts.titleMedium)),
            FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Añadir')),
          ]),
          for (final i in ings)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(i.name),
              subtitle: Text('${fmtNum(i.grams, 1)} g · P ${fmtNum(i.protein)} · H ${fmtNum(i.carbs)} · G ${fmtNum(i.fat)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${fmtNum(i.kcal)} kcal'),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => ings.remove(i))),
              ]),
            ),
          if (ings.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total: ${fmtNum(kcal)} kcal · ${fmtNum(totalWeight)} g', style: ts.titleMedium),
                  Text('Por ración: ${fmtNum(perServ)} kcal · P ${fmtNum(protein / nServ)} g · H ${fmtNum(carbs / nServ)} g · G ${fmtNum(fat / nServ)} g'),
                  Text('Por 100 g: ${fmtNum(kcal / totalWeight * 100)} kcal', style: ts.bodySmall),
                ]),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Guardar receta'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}
