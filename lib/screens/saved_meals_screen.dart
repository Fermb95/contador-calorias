import 'dart:convert';

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../state.dart';
import '../util.dart';

/// Comidas guardadas (plantillas de varios alimentos) para añadir de golpe.
class SavedMealsScreen extends StatefulWidget {
  final int meal;
  const SavedMealsScreen({super.key, required this.meal});

  @override
  State<SavedMealsScreen> createState() => _SavedMealsScreenState();
}

class _SavedMealsScreenState extends State<SavedMealsScreen> {
  List<Map<String, Object?>> meals = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await Db.savedMeals();
    if (mounted) setState(() => meals = m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Añadir a ${mealNames[widget.meal].toLowerCase()}')),
      body: meals.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No tienes comidas guardadas.\n\nEn el diario, abre el menú ⋮ de una comida y pulsa «Guardar como comida» '
                    'para reutilizar desayunos o tuppers habituales.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              children: [
                for (final m in meals)
                  Builder(builder: (context) {
                    final items = (jsonDecode(m['items'] as String) as List)
                        .map((e) => Entry.fromMap(Map<String, Object?>.from(e as Map)))
                        .toList();
                    final kcal = items.fold(0.0, (s, e) => s + e.kcal);
                    final prot = items.fold(0.0, (s, e) => s + e.protein);
                    return ListTile(
                      title: Text(m['name'] as String),
                      subtitle: Text('${items.map((e) => e.name).join(', ')}\n${fmtNum(kcal)} kcal · ${fmtNum(prot)} g proteína',
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await Db.deleteSavedMeal(m['id'] as int);
                          _load();
                        },
                      ),
                      onTap: () async {
                        await app.addSavedMeal(m, widget.meal);
                        if (context.mounted) {
                          toast(context, 'Añadida "${m['name']}"');
                          Navigator.pop(context);
                        }
                      },
                    );
                  }),
              ],
            ),
    );
  }
}
