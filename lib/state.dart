import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calc.dart';
import 'db.dart';
import 'health_service.dart';
import 'models.dart';
import 'notifications.dart';
import 'util.dart';

final app = AppState();

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  Profile? profile;
  DateTime date = today();
  List<Entry> entries = [];
  List<ExerciseEntry> exercises = [];
  int water = 0;
  int tab = 0;
  bool syncing = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('profile');
    if (raw != null) profile = Profile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    await loadDay();
  }

  Targets get targets => computeTargets(profile!);

  double get eaten => entries.fold(0.0, (s, e) => s + e.kcal);
  double get protein => entries.fold(0.0, (s, e) => s + e.protein);
  double get carbs => entries.fold(0.0, (s, e) => s + e.carbs);
  double get fat => entries.fold(0.0, (s, e) => s + e.fat);
  double get exerciseKcal => exercises.fold(0.0, (s, e) => s + e.kcal);
  double get exerciseCounted => exerciseKcal * (profile?.exercisePct ?? 100) / 100;
  double get allowance => targets.kcal + exerciseCounted;
  double get remaining => allowance - eaten;

  List<Entry> mealEntries(int meal) => entries.where((e) => e.meal == meal).toList();

  Future<void> saveProfile(Profile p) async {
    profile = p;
    await _prefs.setString('profile', jsonEncode(p.toJson()));
    await Db.saveDayTargets(dkey(today()), targets);
    notifyListeners();
    _afterChange();
  }

  Future<void> setDate(DateTime d) async {
    date = dayOnly(d);
    await loadDay();
  }

  Future<void> loadDay() async {
    final k = dkey(date);
    entries = await Db.entries(k);
    exercises = await Db.exercises(k);
    water = await Db.water(k);
    notifyListeners();
  }

  /// Guarda el objetivo del día (hoy se actualiza; días pasados conservan el que tenían).
  Future<void> _snapshot(String k) async {
    if (profile == null) return;
    await Db.saveDayTargets(k, targets, overwrite: k == dkey(today()));
  }

  Future<void> _changed(String k) async {
    await _snapshot(k);
    if (k == dkey(date)) await loadDay();
    _afterChange();
  }

  void _afterChange() {
    _updateSummaryNotification();
  }

  Future<void> refreshSummary() => _updateSummaryNotification();

  Future<void> _updateSummaryNotification() async {
    final p = profile;
    if (p == null) return;
    try {
      final k = dkey(today());
      final es = k == dkey(date) ? entries : await Db.entries(k);
      final ex = k == dkey(date) ? exercises : await Db.exercises(k);
      final eatenT = es.fold(0.0, (s, e) => s + e.kcal);
      final protT = es.fold(0.0, (s, e) => s + e.protein);
      final exT = ex.fold(0.0, (s, e) => s + e.kcal) * p.exercisePct / 100;
      await Notif.scheduleSummary(p,
          eaten: eatenT,
          allowance: targets.kcal + exT,
          protein: protT,
          proteinTarget: targets.protein,
          hasData: es.isNotEmpty);
    } catch (e) {
      debugPrint('notif: $e');
    }
  }

  Future<void> addEntry(Entry e) async {
    await Db.insertEntry(e);
    if (e.foodId != null) await Db.bumpUse(e.foodId!);
    await _changed(e.date);
  }

  Future<void> updateEntry(Entry e) async {
    await Db.updateEntry(e);
    await _changed(e.date);
  }

  Future<void> deleteEntry(Entry e) async {
    entries.removeWhere((x) => x.id == e.id);
    notifyListeners();
    await Db.deleteEntry(e.id!);
    await _changed(e.date);
  }

  Future<void> restoreEntry(Entry e) async {
    e.id = null;
    await Db.insertEntry(e);
    await _changed(e.date);
  }

  Future<int> copyMeal({required DateTime from, required int fromMeal, required int toMeal}) async {
    final src = (await Db.entries(dkey(from))).where((e) => e.meal == fromMeal).toList();
    for (final e in src) {
      await Db.insertEntry(e.copyTo(dkey(date), toMeal));
    }
    await _changed(dkey(date));
    return src.length;
  }

  Future<int> copyDay(DateTime from) async {
    final src = await Db.entries(dkey(from));
    for (final e in src) {
      await Db.insertEntry(e.copyTo(dkey(date), e.meal));
    }
    await _changed(dkey(date));
    return src.length;
  }

  Future<void> addSavedMeal(Map<String, Object?> meal, int toMeal) async {
    final items = jsonDecode(meal['items'] as String) as List;
    for (final i in items) {
      final e = Entry.fromMap(Map<String, Object?>.from(i as Map));
      await Db.insertEntry(e.copyTo(dkey(date), toMeal));
    }
    await _changed(dkey(date));
  }

  Future<void> addExercise(ExerciseEntry e) async {
    await Db.insertExercise(e);
    await _changed(e.date);
  }

  Future<void> deleteExercise(ExerciseEntry e) async {
    exercises.removeWhere((x) => x.id == e.id);
    notifyListeners();
    if (e.extId != null) {
      await Db.markExtDeleted(e);
    } else {
      await Db.deleteExercise(e.id!);
    }
    await _changed(e.date);
  }

  Future<void> setWater(int ml) async {
    water = ml < 0 ? 0 : ml;
    await Db.setWater(dkey(date), water);
    notifyListeners();
  }

  Future<void> addWeight(DateTime d, double kg) async {
    await Db.setWeight(dkey(d), kg);
    await _syncProfileWeight();
  }

  Future<void> deleteWeight(String k) async {
    await Db.deleteWeight(k);
    await _syncProfileWeight();
  }

  /// El peso del perfil sigue a la última pesada registrada.
  Future<void> _syncProfileWeight() async {
    final w = await Db.weights();
    final p = profile;
    if (p != null && w.isNotEmpty && (p.weight - w.last.value).abs() > 0.01) {
      p.weight = w.last.value;
      await saveProfile(p);
    } else {
      notifyListeners();
    }
  }

  Future<String> syncHealth({DateTime? day}) async {
    final p = profile;
    if (p == null || !p.hcEnabled) return 'Health Connect desactivado';
    if (syncing) return 'Sincronizando…';
    syncing = true;
    notifyListeners();
    try {
      final msg = await HealthService.syncDay(day ?? date, p);
      await _syncProfileWeight();
      await _changed(dkey(day ?? date));
      return msg;
    } catch (e) {
      return 'No se pudo sincronizar: $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void goToDay(DateTime d) {
    tab = 0;
    setDate(d);
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  // ---------- Histórico ----------
  Future<List<DaySummary>> summaries(DateTime from, DateTime to) async {
    final f = dkey(from), t = dkey(to);
    final et = await Db.entryTotals(f, t);
    final xt = await Db.exerciseTotals(f, t);
    final tg = await Db.dayTargets(f, t);
    final cur = targets;
    final p = profile!;
    final out = <DaySummary>[];
    for (var d = dayOnly(from); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      final k = dkey(d);
      final e = et[k] ?? const [0.0, 0.0, 0.0, 0.0];
      out.add(DaySummary(d, e[0], e[1], e[2], e[3], xt[k] ?? 0, tg[k] ?? cur, p.exercisePct, p.tolerancePct));
    }
    return out;
  }

  /// Gasto real estimado a partir de lo comido y la tendencia de peso (últimos [days] días).
  Future<AdaptiveResult?> adaptiveTdee({int days = 21}) async {
    final end = today().subtract(const Duration(days: 1));
    final start = end.subtract(Duration(days: days - 1));
    final ws = await Db.weights();
    if (ws.length < 4) return null;
    // tendencia diaria interpolando pesadas
    final allTrend = trendWeights(ws.map((e) => e.value).toList());
    double? trendAt(DateTime d) {
      double? v;
      for (var i = 0; i < ws.length; i++) {
        if (!parseKey(ws[i].key).isAfter(d)) v = allTrend[i];
      }
      return v;
    }

    final t0 = trendAt(start), t1 = trendAt(end);
    if (t0 == null || t1 == null) return null;
    final sums = await summaries(start, end);
    final logged = sums.where((s) => s.kcal > 800).toList();
    if (logged.length < days * 0.6) return null;
    final avg = logged.fold(0.0, (s, e) => s + e.kcal) / logged.length;
    final change = t1 - t0;
    final tdee = avg - change * 7700 / days;
    return AdaptiveResult(tdee, days, logged.length, avg, change);
  }

  Future<void> afterImport() async {
    final raw = _prefs.getString('profile');
    if (raw != null) profile = Profile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    await loadDay();
  }
}
