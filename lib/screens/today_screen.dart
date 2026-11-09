import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../state.dart';
import '../util.dart';
import '../widgets/charts.dart';
import 'add_food_screen.dart';
import 'exercise_screen.dart';
import 'food_search_screen.dart';
import 'saved_meals_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  Future<void> _pickDate(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: app.date,
      firstDate: DateTime(2020),
      lastDate: today().add(const Duration(days: 365)),
    );
    if (d != null) app.setDate(d);
  }

  Future<void> _copyDay(BuildContext context, DateTime from) async {
    final n = await app.copyDay(from);
    if (context.mounted) toast(context, n == 0 ? 'Ese día no tiene alimentos' : 'Copiados $n alimentos');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final d = app.date;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            leading: IconButton(
                icon: const Icon(Icons.chevron_left), onPressed: () => app.setDate(d.subtract(const Duration(days: 1)))),
            title: InkWell(
              onTap: () => _pickDate(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(fmtDayTitle(d)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down),
                ]),
              ),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => app.setDate(d.add(const Duration(days: 1)))),
              if (!sameDay(d, today()))
                IconButton(icon: const Icon(Icons.today), tooltip: 'Ir a hoy', onPressed: () => app.setDate(today())),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'yesterday') {
                    await _copyDay(context, d.subtract(const Duration(days: 1)));
                  } else if (v == 'other') {
                    final from = await showDatePicker(
                        context: context,
                        helpText: 'Copiar todo desde…',
                        initialDate: d.subtract(const Duration(days: 1)),
                        firstDate: DateTime(2020),
                        lastDate: today());
                    if (from != null && context.mounted) await _copyDay(context, from);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'yesterday', child: Text('Copiar todo el día de ayer')),
                  PopupMenuItem(value: 'other', child: Text('Copiar todo de otro día…')),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              if (app.profile?.hcEnabled ?? false) {
                final msg = await app.syncHealth();
                if (context.mounted) toast(context, msg);
              } else {
                await app.loadDay();
              }
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96, top: 4),
              children: [
                const _SummaryCard(),
                for (var m = 0; m < mealNames.length; m++) _MealCard(meal: m),
                const _ExerciseCard(),
                const _WaterCard(),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => FoodSearchScreen(meal: sameDay(d, today()) ? mealForNow() : 2))),
            icon: const Icon(Icons.add),
            label: const Text('Añadir'),
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final t = app.targets;
    final ts = Theme.of(context).textTheme;
    final rem = app.remaining;
    final over = rem < 0;
    Widget col(String v, String l) => Column(children: [
          Text(v, style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text(l, style: ts.bodySmall),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            CalorieRing(
              value: app.eaten,
              max: app.allowance,
              size: 140,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(fmtNum(rem.abs()),
                    style: ts.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: over ? overColor : null)),
                Text(over ? 'kcal de más' : 'kcal restantes', style: ts.bodySmall),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(over ? 'Te has pasado ${fmtNum(-rem)} kcal' : 'Te faltan ${fmtNum(rem)} kcal',
                    style: ts.titleMedium?.copyWith(color: over ? overColor : okColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  col(fmtNum(t.kcal), 'Objetivo'),
                  col(fmtNum(app.eaten), 'Comido'),
                  col('+${fmtNum(app.exerciseCounted)}', 'Ejercicio'),
                ]),
                if (app.exerciseKcal > 0 && (app.profile?.exercisePct ?? 100) < 100)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Cuenta el ${app.profile!.exercisePct}% de ${fmtNum(app.exerciseKcal)} kcal de ejercicio',
                        style: ts.bodySmall),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: MacroBar(label: 'Proteína', value: app.protein, target: t.protein, color: proteinColor)),
            const SizedBox(width: 12),
            Expanded(child: MacroBar(label: 'Hidratos', value: app.carbs, target: t.carbs, color: carbsColor)),
            const SizedBox(width: 12),
            Expanded(child: MacroBar(label: 'Grasa', value: app.fat, target: t.fat, color: fatColor)),
          ]),
        ]),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final int meal;
  const _MealCard({required this.meal});

  Future<void> _menu(BuildContext context, String v, List<Entry> items) async {
    switch (v) {
      case 'yesterday':
        final n = await app.copyMeal(from: app.date.subtract(const Duration(days: 1)), fromMeal: meal, toMeal: meal);
        if (context.mounted) toast(context, n == 0 ? 'Ayer no había nada en ${mealNames[meal]}' : 'Copiados $n alimentos');
      case 'other':
        final from = await showDatePicker(
            context: context,
            helpText: 'Copiar ${mealNames[meal]} desde…',
            initialDate: app.date.subtract(const Duration(days: 1)),
            firstDate: DateTime(2020),
            lastDate: today());
        if (from == null) return;
        final n = await app.copyMeal(from: from, fromMeal: meal, toMeal: meal);
        if (context.mounted) toast(context, n == 0 ? 'Ese día no había nada' : 'Copiados $n alimentos');
      case 'save':
        if (items.isEmpty) {
          toast(context, 'Añade alimentos primero');
          return;
        }
        final ctrl = TextEditingController(text: '${mealNames[meal]} habitual');
        final name = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Guardar como comida'),
            content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Guardar')),
            ],
          ),
        );
        if (name == null || name.isEmpty) return;
        await Db.saveMeal(name, items);
        if (context.mounted) toast(context, 'Guardada "$name"');
      case 'saved':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => SavedMealsScreen(meal: meal)));
      case 'clear':
        for (final e in items) {
          await app.deleteEntry(e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = app.mealEntries(meal);
    final kcal = items.fold(0.0, (s, e) => s + e.kcal);
    final prot = items.fold(0.0, (s, e) => s + e.protein);
    final ts = Theme.of(context).textTheme;
    return Card(
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          title: Text('${mealIcons[meal]}  ${mealNames[meal]}', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          subtitle: items.isEmpty ? null : Text('${fmtNum(kcal)} kcal · ${fmtNum(prot)} g proteína'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.add_circle),
              color: Theme.of(context).colorScheme.primary,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FoodSearchScreen(meal: meal))),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => _menu(context, v, items),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'yesterday', child: Text('Copiar de ayer')),
                const PopupMenuItem(value: 'other', child: Text('Copiar de otro día…')),
                const PopupMenuItem(value: 'saved', child: Text('Añadir comida guardada')),
                const PopupMenuItem(value: 'save', child: Text('Guardar como comida')),
                if (items.isNotEmpty) const PopupMenuItem(value: 'clear', child: Text('Vaciar')),
              ],
            ),
          ]),
        ),
        for (final e in items)
          Dismissible(
            key: ValueKey('e${e.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: overColor,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) async {
              final copy = Entry.fromMap(e.toMap());
              await app.deleteEntry(e);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text('Eliminado ${e.name}'),
                    action: SnackBarAction(label: 'Deshacer', onPressed: () => app.restoreEntry(copy)),
                  ));
              }
            },
            child: ListTile(
              dense: true,
              title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${e.brand != null ? '${e.brand} · ' : ''}${e.amountLabel}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${fmtNum(e.kcal)} kcal', style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text('P ${fmtNum(e.protein)} · H ${fmtNum(e.carbs)} · G ${fmtNum(e.fat)}', style: ts.bodySmall),
              ]),
              onTap: () => editEntry(context, e),
            ),
          ),
        if (items.isNotEmpty) const SizedBox(height: 6),
      ]),
    );
  }
}

Future<void> editEntry(BuildContext context, Entry e) async {
  final food = e.foodId == null ? null : await Db.foodById(e.foodId!);
  if (!context.mounted) return;
  if (food != null) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddFoodScreen(food: food, meal: e.meal, existing: e)));
    return;
  }
  // Alimento ya no existe: permitir cambiar los gramos proporcionalmente.
  final ctrl = TextEditingController(text: fmtNum(e.grams, 1));
  final g = await showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(e.name),
      content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Cantidad', suffixText: 'g')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, parseNum(ctrl.text)), child: const Text('Guardar')),
      ],
    ),
  );
  if (g == null || g <= 0 || e.grams <= 0) return;
  final r = g / e.grams;
  e
    ..kcal *= r
    ..protein *= r
    ..carbs *= r
    ..fat *= r
    ..grams = g
    ..amount = g
    ..unit = 'g';
  await app.updateEntry(e);
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard();

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final hc = app.profile?.hcEnabled ?? false;
    return Card(
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          title: Text('🏋️  Ejercicio', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          subtitle: app.exercises.isEmpty ? null : Text('${fmtNum(app.exerciseKcal)} kcal quemadas'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (hc)
              app.syncing
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      icon: const Icon(Icons.sync),
                      tooltip: 'Sincronizar Health Connect',
                      onPressed: () async {
                        final msg = await app.syncHealth();
                        if (context.mounted) toast(context, msg);
                      }),
            IconButton(
              icon: const Icon(Icons.add_circle),
              color: Theme.of(context).colorScheme.primary,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExerciseScreen())),
            ),
          ]),
        ),
        for (final e in app.exercises)
          Dismissible(
            key: ValueKey('x${e.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: overColor,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => app.deleteExercise(e),
            child: ListTile(
              dense: true,
              leading: Icon(e.source == 'manual' ? Icons.fitness_center : Icons.watch, size: 20),
              title: Text(e.name),
              subtitle: e.minutes > 0 ? Text('${fmtNum(e.minutes)} min') : null,
              trailing: Text('${fmtNum(e.kcal)} kcal', style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
        if (app.exercises.isNotEmpty) const SizedBox(height: 6),
      ]),
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard();

  @override
  Widget build(BuildContext context) {
    final goal = app.profile?.waterGoal ?? 2500;
    final ts = Theme.of(context).textTheme;
    final glasses = (app.water / 250).floor();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          const Text('💧', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Agua', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: (app.water / goal).clamp(0.0, 1.0), minHeight: 8, color: Colors.lightBlue),
              ),
              const SizedBox(height: 4),
              Text('${fmtNum(app.water / 1000, 2)} / ${fmtNum(goal / 1000, 1)} L · $glasses vasos', style: ts.bodySmall),
            ]),
          ),
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => app.setWater(app.water - 250)),
          IconButton(icon: const Icon(Icons.add_circle, color: Colors.lightBlue), onPressed: () => app.setWater(app.water + 250)),
        ]),
      ),
    );
  }
}
