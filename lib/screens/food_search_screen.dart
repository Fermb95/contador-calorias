import 'dart:async';

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../off_api.dart';
import '../util.dart';
import 'add_food_screen.dart';
import 'food_editor_screen.dart';
import 'recipe_editor_screen.dart';
import 'scanner_screen.dart';

/// Buscador de alimentos. Si [pickMode] es true devuelve un [PickedFood] en vez de registrar.
class FoodSearchScreen extends StatefulWidget {
  final int meal;
  final bool pickMode;
  const FoodSearchScreen({super.key, required this.meal, this.pickMode = false});

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> with SingleTickerProviderStateMixin {
  final _q = TextEditingController();
  late final TabController _tabs = TabController(length: 4, vsync: this);
  Timer? _debounce;
  List<Food> _local = [];
  List<Food> _favs = [];
  List<Food> _recents = [];
  List<Food> _mine = [];
  List<Food>? _online;
  bool _loadingOnline = false;
  String? _onlineError;
  String _onlineQuery = '';
  StoreFilter _store = storeFilters.first;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    final f = await Db.favorites();
    final r = await Db.recents();
    final m = await Db.myFoods();
    if (!mounted) return;
    setState(() {
      _favs = f;
      _recents = r;
      _mine = m;
    });
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final res = await Db.searchFoods(v);
      if (mounted) setState(() => _local = res);
    });
    if (_tabs.index != 0) _tabs.animateTo(0);
    setState(() {});
  }

  Future<void> _searchOnline() async {
    final q = _q.text.trim();
    if (q.length < 2) {
      toast(context, 'Escribe al menos 2 letras');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loadingOnline = true;
      _onlineError = null;
      _onlineQuery = q;
    });
    try {
      final res = await OffApi.search(q, _store);
      if (mounted) setState(() => _online = res);
    } catch (e) {
      if (mounted) setState(() => _onlineError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingOnline = false);
    }
  }

  Future<void> _open(Food f) async {
    final res = await Navigator.push<PickedFood>(
      context,
      MaterialPageRoute(builder: (_) => AddFoodScreen(food: f, meal: widget.meal, pickMode: widget.pickMode)),
    );
    if (!mounted) return;
    if (widget.pickMode && res != null) {
      Navigator.pop(context, res);
      return;
    }
    if (res != null) {
      // Registrado: volvemos al diario.
      Navigator.pop(context);
    } else {
      _loadLists();
    }
  }

  Future<void> _toggleFav(Food f) async {
    if (f.id == null) await Db.saveFood(f);
    f.favorite = !f.favorite;
    await Db.setFavorite(f.id!, f.favorite);
    await _loadLists();
    if (_q.text.isNotEmpty) _local = await Db.searchFoods(_q.text);
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code == null || !mounted) return;
    var food = await Db.foodByBarcode(code);
    if (food == null) {
      if (!mounted) return;
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
              content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Buscando producto…')])));
      try {
        food = await OffApi.byBarcode(code);
      } catch (e) {
        food = null;
      }
      if (mounted) Navigator.pop(context);
    }
    if (!mounted) return;
    if (food != null) {
      await _open(food);
      return;
    }
    final create = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Producto no encontrado'),
        content: Text('El código $code no está en la base de datos. ¿Lo creas haciendo una foto a la tabla nutricional? '
            'Quedará guardado para la próxima vez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leer etiqueta')),
        ],
      ),
    );
    if (create == true && mounted) {
      final f = await Navigator.push<Food>(
          context,
          MaterialPageRoute(
              builder: (_) => FoodEditorScreen(
                  food: Food(name: '', kcal: 0, protein: 0, carbs: 0, fat: 0, barcode: code), autoOcr: true)));
      if (f != null && mounted) await _open(f);
    }
  }

  Future<void> _create() async {
    final f = await Navigator.push<Food>(
        context, MaterialPageRoute(builder: (_) => FoodEditorScreen(food: Food(name: _q.text.trim(), kcal: 0, protein: 0, carbs: 0, fat: 0))));
    if (f != null && mounted) await _open(f);
  }

  Future<void> _createFromLabel() async {
    final f = await Navigator.push<Food>(
        context,
        MaterialPageRoute(
            builder: (_) => FoodEditorScreen(food: Food(name: _q.text.trim(), kcal: 0, protein: 0, carbs: 0, fat: 0), autoOcr: true)));
    if (f != null && mounted) await _open(f);
  }

  Future<void> _createRecipe() async {
    final f = await Navigator.push<Food>(context, MaterialPageRoute(builder: (_) => const RecipeEditorScreen()));
    if (f != null && mounted) await _open(f);
  }

  Widget _list(List<Food> foods, String empty) {
    if (foods.isEmpty) {
      return Center(
          child: Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: foods.length,
      itemBuilder: (_, i) => FoodTile(food: foods[i], onTap: () => _open(foods[i]), onFav: () => _toggleFav(foods[i])),
    );
  }

  Widget _searchTab() {
    final q = _q.text.trim();
    final cs = Theme.of(context).colorScheme;
    if (q.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Escribe para buscar entre los alimentos genéricos, tus favoritos y los productos que ya hayas usado.\n\n'
            'Pulsa la lupa del teclado o «Buscar en supermercados» para buscar productos de Mercadona, Carrefour, Alcampo, Lidl, Dia…'),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Escanear código de barras')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _createFromLabel, icon: const Icon(Icons.document_scanner), label: const Text('Crear desde foto de la etiqueta')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _create, icon: const Icon(Icons.edit_note), label: const Text('Crear alimento a mano')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _createRecipe, icon: const Icon(Icons.menu_book), label: const Text('Crear receta')),
      ]);
    }
    return ListView(padding: const EdgeInsets.only(bottom: 80), children: [
      if (_local.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('Nada en tus alimentos. Prueba en supermercados ↓')),
      for (final f in _local) FoodTile(food: f, onTap: () => _open(f), onFav: () => _toggleFav(f)),
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Supermercados (Open Food Facts)', style: Theme.of(context).textTheme.titleSmall),
      ),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final s in storeFilters)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s.label),
                  selected: _store == s,
                  onSelected: (_) {
                    setState(() => _store = s);
                    if (_online != null) _searchOnline();
                  },
                ),
              ),
          ],
        ),
      ),
      if (_loadingOnline)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_onlineError != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(_onlineError!, style: TextStyle(color: cs.error)))
      else if (_online == null || _onlineQuery != q)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: FilledButton.tonalIcon(
              onPressed: _searchOnline, icon: const Icon(Icons.storefront), label: Text('Buscar «$q» en supermercados')),
        )
      else if (_online!.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('Sin resultados. Prueba otra palabra o escanea el código.'))
      else
        for (final f in _online!) FoodTile(food: f, onTap: () => _open(f), onFav: () => _toggleFav(f)),
      const SizedBox(height: 12),
      Center(child: TextButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Crear alimento nuevo'))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (_) => _searchOnline(),
          decoration: InputDecoration(
            hintText: widget.pickMode ? 'Buscar ingrediente…' : 'Buscar en ${mealNames[widget.meal].toLowerCase()}…',
            border: InputBorder.none,
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _q.clear();
                      _onChanged('');
                    }),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Escanear', onPressed: _scan),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'label' => _createFromLabel(),
              'food' => _create(),
              _ => _createRecipe(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'label', child: Text('Crear desde foto de la etiqueta')),
              PopupMenuItem(value: 'food', child: Text('Crear alimento a mano')),
              PopupMenuItem(value: 'recipe', child: Text('Crear receta')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: false,
          tabs: const [Tab(text: 'Buscar'), Tab(text: 'Favoritos'), Tab(text: 'Recientes'), Tab(text: 'Míos')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _searchTab(),
        _list(_favs, 'Aún no tienes favoritos.\nPulsa la ⭐ de cualquier alimento para añadirlo.'),
        _list(_recents, 'Aquí aparecerán los alimentos que vayas registrando.'),
        _list(_mine, 'Aquí aparecen tus alimentos creados, recetas y productos de supermercado que hayas usado.'),
      ]),
    );
  }
}

class FoodTile extends StatelessWidget {
  final Food food;
  final VoidCallback onTap;
  final VoidCallback? onFav;
  const FoodTile({super.key, required this.food, required this.onTap, this.onFav});

  @override
  Widget build(BuildContext context) {
    final f = food;
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sub = [
      if (f.brand != null) f.brand!,
      '${fmtNum(f.kcal)} kcal/100 ${f.unit}',
      'P ${fmtNum(f.protein, 1)} · H ${fmtNum(f.carbs, 1)} · G ${fmtNum(f.fat, 1)}',
    ].join(' · ');
    return ListTile(
      title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, style: ts.bodySmall),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: cs.secondaryContainer,
        child: Icon(
          switch (f.source) {
            'off' => Icons.storefront,
            'recipe' => Icons.menu_book,
            'custom' => Icons.person,
            _ => Icons.eco,
          },
          size: 18,
          color: cs.onSecondaryContainer,
        ),
      ),
      trailing: onFav == null
          ? null
          : IconButton(
              icon: Icon(f.favorite ? Icons.star : Icons.star_border, color: f.favorite ? Colors.amber : null),
              onPressed: onFav,
            ),
      onTap: onTap,
    );
  }
}
