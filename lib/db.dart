import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'util.dart';

class Db {
  static late Database db;

  static Future<void> init() async {
    final dir = await getDatabasesPath();
    db = await openDatabase(
      p.join(dir, 'balance.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''CREATE TABLE foods(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, name_norm TEXT, brand TEXT, barcode TEXT,
          category TEXT, kcal REAL, protein REAL, carbs REAL, fat REAL, fiber REAL, sugar REAL, satfat REAL,
          salt REAL, liquid INTEGER DEFAULT 0, portions TEXT, source TEXT, favorite INTEGER DEFAULT 0,
          use_count INTEGER DEFAULT 0, recipe TEXT)''');
        await d.execute('CREATE INDEX idx_foods_barcode ON foods(barcode)');
        await d.execute('''CREATE TABLE entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, meal INTEGER, food_id INTEGER, name TEXT,
          brand TEXT, amount REAL, unit TEXT, grams REAL, kcal REAL, protein REAL, carbs REAL, fat REAL)''');
        await d.execute('CREATE INDEX idx_entries_date ON entries(date)');
        await d.execute('''CREATE TABLE exercises(
          id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, name TEXT, minutes REAL, kcal REAL,
          source TEXT, ext_id TEXT)''');
        await d.execute('CREATE INDEX idx_ex_date ON exercises(date)');
        await d.execute('CREATE TABLE weights(date TEXT PRIMARY KEY, kg REAL)');
        await d.execute('CREATE TABLE water(date TEXT PRIMARY KEY, ml INTEGER)');
        await d.execute('CREATE TABLE days(date TEXT PRIMARY KEY, kcal REAL, protein REAL, carbs REAL, fat REAL)');
        await d.execute('CREATE TABLE saved_meals(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, items TEXT)');
        await _seed(d);
      },
    );
  }

  static Future<void> _seed(Database d) async {
    final raw = await rootBundle.loadString('assets/foods_es.json');
    final list = jsonDecode(raw) as List;
    final b = d.batch();
    for (final o in list) {
      final m = o as Map<String, dynamic>;
      final f = Food(
        name: m['n'] as String,
        category: m['c'] as String,
        kcal: (m['k'] as num).toDouble(),
        protein: (m['p'] as num).toDouble(),
        carbs: (m['h'] as num).toDouble(),
        fat: (m['g'] as num).toDouble(),
        fiber: (m['f'] as num).toDouble(),
        liquid: m['l'] == 1,
        portions: (m['u'] as List).map(Portion.fromJson).toList(),
        source: 'base',
      );
      b.insert('foods', _foodRow(f));
    }
    await b.commit(noResult: true);
  }

  static Map<String, Object?> _foodRow(Food f, {bool withId = false}) {
    final m = f.toMap(withId: withId);
    m['name_norm'] = normalize('${f.name} ${f.brand ?? ''}');
    return m;
  }

  // ---------- Alimentos ----------
  static Future<List<Food>> searchFoods(String q, {int limit = 80}) async {
    final words = normalize(q).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    final where = words.map((_) => 'name_norm LIKE ?').join(' AND ');
    final rows = await db.query('foods',
        where: where,
        whereArgs: words.map((w) => '%$w%').toList(),
        orderBy: 'favorite DESC, use_count DESC, length(name) ASC',
        limit: limit);
    return rows.map(Food.fromMap).toList();
  }

  static Future<List<Food>> favorites() async =>
      (await db.query('foods', where: 'favorite = 1', orderBy: 'use_count DESC, name')).map(Food.fromMap).toList();

  static Future<List<Food>> myFoods() async => (await db.query('foods',
          where: "source IN ('custom','recipe','off')", orderBy: 'use_count DESC, name'))
      .map(Food.fromMap)
      .toList();

  static Future<List<Food>> recents({int limit = 60}) async {
    final rows = await db.rawQuery('''SELECT f.* FROM foods f JOIN
        (SELECT food_id, MAX(id) AS last FROM entries WHERE food_id IS NOT NULL GROUP BY food_id) e
        ON e.food_id = f.id ORDER BY e.last DESC LIMIT ?''', [limit]);
    return rows.map(Food.fromMap).toList();
  }

  static Future<Food?> foodById(int id) async {
    final r = await db.query('foods', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Food.fromMap(r.first);
  }

  static Future<Food?> foodByBarcode(String code) async {
    final r = await db.query('foods', where: 'barcode = ?', whereArgs: [code], limit: 1);
    return r.isEmpty ? null : Food.fromMap(r.first);
  }

  /// Inserta o actualiza. Devuelve el id.
  static Future<int> saveFood(Food f) async {
    if (f.id != null) {
      await db.update('foods', _foodRow(f), where: 'id = ?', whereArgs: [f.id]);
      return f.id!;
    }
    if (f.barcode != null && f.barcode!.isNotEmpty) {
      final ex = await foodByBarcode(f.barcode!);
      if (ex != null) {
        f.id = ex.id;
        f.favorite = f.favorite || ex.favorite;
        f.useCount = ex.useCount;
        await db.update('foods', _foodRow(f), where: 'id = ?', whereArgs: [f.id]);
        return f.id!;
      }
    }
    f.id = await db.insert('foods', _foodRow(f));
    return f.id!;
  }

  static Future<void> setFavorite(int id, bool fav) =>
      db.update('foods', {'favorite': fav ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  static Future<void> bumpUse(int id) => db.rawUpdate('UPDATE foods SET use_count = use_count + 1 WHERE id = ?', [id]);

  static Future<void> deleteFood(int id) => db.delete('foods', where: 'id = ?', whereArgs: [id]);

  // ---------- Registros ----------
  static Future<List<Entry>> entries(String date) async =>
      (await db.query('entries', where: 'date = ?', whereArgs: [date], orderBy: 'meal, id')).map(Entry.fromMap).toList();

  static Future<int> insertEntry(Entry e) => db.insert('entries', e.toMap());
  static Future<void> updateEntry(Entry e) => db.update('entries', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  static Future<void> deleteEntry(int id) => db.delete('entries', where: 'id = ?', whereArgs: [id]);

  static Future<List<ExerciseEntry>> exercises(String date) async =>
      (await db.query('exercises', where: 'date = ?', whereArgs: [date], orderBy: 'id')).map(ExerciseEntry.fromMap).toList();

  static Future<int> insertExercise(ExerciseEntry e) => db.insert('exercises', e.toMap());
  static Future<void> deleteExercise(int id) => db.delete('exercises', where: 'id = ?', whereArgs: [id]);

  static Future<void> upsertExerciseExt(ExerciseEntry e) async {
    final r = await db.query('exercises', where: 'ext_id = ?', whereArgs: [e.extId], limit: 1);
    if (r.isEmpty) {
      await db.insert('exercises', e.toMap());
    } else {
      final m = e.toMap()..remove('id');
      await db.update('exercises', m, where: 'id = ?', whereArgs: [r.first['id']]);
    }
  }

  static Future<bool> extExerciseDeleted(String extId) async {
    final r = await db.query('exercises', where: 'ext_id = ?', whereArgs: ['deleted:$extId'], limit: 1);
    return r.isNotEmpty;
  }

  /// Recuerda que el usuario borró un ejercicio importado para no volver a importarlo.
  static Future<void> markExtDeleted(ExerciseEntry e) async {
    await db.update('exercises', {'ext_id': 'deleted:${e.extId}', 'kcal': 0, 'minutes': 0, 'date': 'deleted'},
        where: 'id = ?', whereArgs: [e.id]);
  }

  /// Ejercicios recientes distintos (para añadir rápido).
  static Future<List<ExerciseEntry>> recentExercises() async {
    final rows = await db.rawQuery('''SELECT * FROM exercises WHERE id IN
        (SELECT MAX(id) FROM exercises WHERE source = 'manual' GROUP BY name) ORDER BY id DESC LIMIT 15''');
    return rows.map(ExerciseEntry.fromMap).toList();
  }

  // ---------- Agua, peso, objetivos del día ----------
  static Future<int> water(String date) async {
    final r = await db.query('water', where: 'date = ?', whereArgs: [date]);
    return r.isEmpty ? 0 : (r.first['ml'] as int);
  }

  static Future<void> setWater(String date, int ml) =>
      db.insert('water', {'date': date, 'ml': ml}, conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<List<MapEntry<String, double>>> weights() async {
    final r = await db.query('weights', orderBy: 'date');
    return r.map((m) => MapEntry(m['date'] as String, (m['kg'] as num).toDouble())).toList();
  }

  static Future<void> setWeight(String date, double kg) =>
      db.insert('weights', {'date': date, 'kg': kg}, conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<void> deleteWeight(String date) => db.delete('weights', where: 'date = ?', whereArgs: [date]);

  static Future<void> saveDayTargets(String date, Targets t, {bool overwrite = true}) => db.insert('days', t.toMap(date),
      conflictAlgorithm: overwrite ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore);

  static Future<Map<String, Targets>> dayTargets(String from, String to) async {
    final r = await db.query('days', where: 'date BETWEEN ? AND ?', whereArgs: [from, to]);
    return {for (final m in r) m['date'] as String: Targets.fromMap(m)};
  }

  static Future<Map<String, List<double>>> entryTotals(String from, String to) async {
    final r = await db.rawQuery('''SELECT date, SUM(kcal) k, SUM(protein) p, SUM(carbs) c, SUM(fat) f
        FROM entries WHERE date BETWEEN ? AND ? GROUP BY date''', [from, to]);
    return {
      for (final m in r)
        m['date'] as String: [
          (m['k'] as num? ?? 0).toDouble(),
          (m['p'] as num? ?? 0).toDouble(),
          (m['c'] as num? ?? 0).toDouble(),
          (m['f'] as num? ?? 0).toDouble(),
        ]
    };
  }

  static Future<Map<String, double>> exerciseTotals(String from, String to) async {
    final r = await db.rawQuery(
        'SELECT date, SUM(kcal) k FROM exercises WHERE date BETWEEN ? AND ? GROUP BY date', [from, to]);
    return {for (final m in r) m['date'] as String: (m['k'] as num? ?? 0).toDouble()};
  }

  static Future<String?> firstEntryDate() async {
    final r = await db.rawQuery('SELECT MIN(date) d FROM entries');
    return r.isEmpty ? null : r.first['d'] as String?;
  }

  // ---------- Comidas guardadas ----------
  static Future<List<Map<String, Object?>>> savedMeals() => db.query('saved_meals', orderBy: 'name');

  static Future<void> saveMeal(String name, List<Entry> items) => db.insert('saved_meals', {
        'name': name,
        'items': jsonEncode(items.map((e) => e.toMap()..remove('id')).toList()),
      });

  static Future<void> deleteSavedMeal(int id) => db.delete('saved_meals', where: 'id = ?', whereArgs: [id]);

  // ---------- Copia de seguridad ----------
  static const _tables = ['foods', 'entries', 'exercises', 'weights', 'water', 'days', 'saved_meals'];

  static Future<Map<String, Object?>> exportAll() async {
    final out = <String, Object?>{};
    for (final t in _tables) {
      out[t] = await db.query(t);
    }
    return out;
  }

  static Future<void> importAll(Map<String, dynamic> data) async {
    await db.transaction((txn) async {
      for (final t in _tables) {
        final rows = data[t];
        if (rows is! List) continue;
        await txn.delete(t);
        final b = txn.batch();
        for (final r in rows) {
          b.insert(t, Map<String, Object?>.from(r as Map));
        }
        await b.commit(noResult: true);
      }
    });
  }
}
