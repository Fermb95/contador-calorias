import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../state.dart';
import '../util.dart';
import 'food_editor_screen.dart';
import 'recipe_editor_screen.dart';

class PickedFood {
  final Food food;
  final double grams;
  final double amount;
  final String unit;
  PickedFood(this.food, this.grams, this.amount, this.unit);
}

class AddFoodScreen extends StatefulWidget {
  final Food food;
  final int meal;
  final Entry? existing;
  final bool pickMode;
  final double? initialGrams;
  const AddFoodScreen({super.key, required this.food, required this.meal, this.existing, this.pickMode = false, this.initialGrams});

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  late Food food = widget.food;
  late int meal = widget.meal;
  int unitIdx = -1; // -1 = gramos/ml; i = ración i
  final amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final i = food.portions.indexWhere((p) => p.name == e.unit);
      unitIdx = i;
      amount.text = fmtNum(i >= 0 ? e.amount : e.grams, 2);
    } else if (widget.initialGrams != null) {
      amount.text = fmtNum(widget.initialGrams!, 1);
    } else if (food.portions.isNotEmpty) {
      unitIdx = 0;
      amount.text = '1';
    } else {
      amount.text = '100';
    }
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  double get _amount => parseNum(amount.text) ?? 0;
  double get grams => unitIdx < 0 ? _amount : _amount * food.portions[unitIdx].grams;
  String get unitName => unitIdx < 0 ? food.unit : food.portions[unitIdx].name;

  Future<void> _save() async {
    if (grams <= 0) {
      toast(context, 'Indica una cantidad');
      return;
    }
    if (food.id == null) await Db.saveFood(food);
    final picked = PickedFood(food, grams, _amount, unitName);
    if (widget.pickMode) {
      if (mounted) Navigator.pop(context, picked);
      return;
    }
    final e = Entry.fromFood(food, date: dkey(app.date), meal: meal, amount: _amount, unit: unitName, grams: grams);
    if (widget.existing != null) {
      e.id = widget.existing!.id;
      e.date = widget.existing!.date;
      await app.updateEntry(e);
    } else {
      await app.addEntry(e);
    }
    if (mounted) Navigator.pop(context, picked);
  }

  Future<void> _toggleFav() async {
    if (food.id == null) await Db.saveFood(food);
    setState(() => food.favorite = !food.favorite);
    await Db.setFavorite(food.id!, food.favorite);
    if (mounted) toast(context, food.favorite ? 'Añadido a favoritos' : 'Quitado de favoritos');
  }

  Future<void> _edit() async {
    final f = await Navigator.push<Food>(
        context,
        MaterialPageRoute(
            builder: (_) => food.source == 'recipe' && food.recipe != null
                ? RecipeEditorScreen(recipe: food)
                : FoodEditorScreen(food: food)));
    if (f != null) {
      setState(() {
        food = f;
        if (unitIdx >= food.portions.length) unitIdx = -1;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar alimento'),
        content: Text('¿Eliminar "${food.name}" de tus alimentos? Los registros pasados se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && food.id != null) {
      await Db.deleteFood(food.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = grams / 100;
    final quick = unitIdx < 0 ? [50.0, 100.0, 150.0, 200.0, 250.0] : [0.5, 1.0, 1.5, 2.0, 3.0];
    Widget macro(String l, double v, Color c) => Expanded(
          child: Column(children: [
            Text('${fmtNum(v, 1)} g', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: c)),
            Text(l, style: ts.bodySmall),
          ]),
        );
    Widget row(String l, double? v, [String u = 'g']) => v == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [Expanded(child: Text(l)), Text('${fmtNum(v, 1)} $u')]),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? 'Editar' : (widget.pickMode ? 'Ingrediente' : 'Añadir')),
        actions: [
          IconButton(
              icon: Icon(food.favorite ? Icons.star : Icons.star_border, color: food.favorite ? Colors.amber : null),
              onPressed: _toggleFav),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? _edit() : _delete(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar valores del alimento')),
              if (food.id != null && food.source != 'base') const PopupMenuItem(value: 'delete', child: Text('Eliminar alimento')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(food.name, style: ts.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text([if (food.brand != null) food.brand!, food.sourceLabel, if (food.barcode != null) food.barcode!].join(' · '),
              style: ts.bodySmall),
          const SizedBox(height: 20),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cantidad'),
                style: ts.titleLarge,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('units-${food.portions.length}-$unitIdx'),
                initialValue: unitIdx,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Medida'),
                items: [
                  DropdownMenuItem(value: -1, child: Text('Gramos exactos (${food.unit})')),
                  for (var i = 0; i < food.portions.length; i++)
                    DropdownMenuItem(
                        value: i,
                        child: Text('${food.portions[i].name} (${fmtNum(food.portions[i].grams, 1)} ${food.unit})',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  final g = grams;
                  unitIdx = v ?? -1;
                  if (unitIdx < 0) {
                    amount.text = fmtNum(g > 0 ? g : 100, 1);
                  } else {
                    amount.text = '1';
                  }
                }),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [
            for (final q in quick)
              ActionChip(
                label: Text(unitIdx < 0 ? '${fmtNum(q)} ${food.unit}' : '× ${fmtNum(q, 1)}'),
                onPressed: () => setState(() => amount.text = fmtNum(q, 1)),
              ),
          ]),
          if (unitIdx >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('≈ ${fmtNum(grams, 1)} ${food.unit}', style: ts.bodyMedium),
            ),
          if (!widget.pickMode) ...[
            const SizedBox(height: 16),
            Text('Comida', style: ts.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (var m = 0; m < mealNames.length; m++)
                ChoiceChip(label: Text(mealNames[m]), selected: meal == m, onSelected: (_) => setState(() => meal = m)),
            ]),
          ],
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text('${fmtNum(food.kcal * r)} kcal',
                    style: ts.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
                const SizedBox(height: 10),
                Row(children: [
                  macro('Proteína', food.protein * r, proteinColor),
                  macro('Hidratos', food.carbs * r, carbsColor),
                  macro('Grasa', food.fat * r, fatColor),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('Por 100 ${food.unit}', style: ts.titleSmall),
          const SizedBox(height: 4),
          row('Energía', food.kcal, 'kcal'),
          row('Proteínas', food.protein),
          row('Hidratos de carbono', food.carbs),
          row('  de los cuales azúcares', food.sugar),
          row('Grasas', food.fat),
          row('  de las cuales saturadas', food.satFat),
          row('Fibra', food.fiber),
          row('Sal', food.salt),
          if (food.source == 'off')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Datos de Open Food Facts (colaborativos). Si algo no cuadra con la etiqueta, edítalo.',
                  style: ts.bodySmall),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: Icon(widget.existing != null ? Icons.check : Icons.add),
            label: Text(widget.existing != null
                ? 'Guardar cambios'
                : widget.pickMode
                    ? 'Añadir a la receta'
                    : 'Añadir a ${mealNames[meal].toLowerCase()}'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
    );
  }
}
