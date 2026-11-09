import 'dart:convert';

double _d(Object? v) => v == null ? 0 : (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();

class Portion {
  final String name;
  final double grams;
  const Portion(this.name, this.grams);
  List<Object> toJson() => [name, grams];
  static Portion fromJson(Object? j) {
    final l = j as List;
    return Portion(l[0] as String, (l[1] as num).toDouble());
  }
}

/// Alimento; valores nutricionales por 100 g (o 100 ml si [liquid]).
class Food {
  int? id;
  String name;
  String? brand;
  String? barcode;
  String? category;
  double kcal, protein, carbs, fat;
  double? fiber, sugar, satFat, salt;
  bool liquid;
  List<Portion> portions;
  String source; // base | off | custom | recipe
  bool favorite;
  int useCount;
  String? recipe; // JSON de ingredientes si es receta

  Food({
    this.id,
    required this.name,
    this.brand,
    this.barcode,
    this.category,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber,
    this.sugar,
    this.satFat,
    this.salt,
    this.liquid = false,
    List<Portion>? portions,
    this.source = 'custom',
    this.favorite = false,
    this.useCount = 0,
    this.recipe,
  }) : portions = portions ?? [];

  String get unit => liquid ? 'ml' : 'g';

  String get sourceLabel => switch (source) {
        'base' => 'Genérico',
        'off' => 'Supermercado',
        'recipe' => 'Receta',
        _ => 'Mío',
      };

  Map<String, Object?> toMap({bool withId = false}) => {
        if (withId || id != null) 'id': id,
        'name': name,
        'name_norm': null, // se rellena en Db
        'brand': brand,
        'barcode': barcode,
        'category': category,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'sugar': sugar,
        'satfat': satFat,
        'salt': salt,
        'liquid': liquid ? 1 : 0,
        'portions': jsonEncode(portions.map((p) => p.toJson()).toList()),
        'source': source,
        'favorite': favorite ? 1 : 0,
        'use_count': useCount,
        'recipe': recipe,
      };

  factory Food.fromMap(Map<String, Object?> m) => Food(
        id: m['id'] as int?,
        name: m['name'] as String,
        brand: m['brand'] as String?,
        barcode: m['barcode'] as String?,
        category: m['category'] as String?,
        kcal: _d(m['kcal']),
        protein: _d(m['protein']),
        carbs: _d(m['carbs']),
        fat: _d(m['fat']),
        fiber: _dn(m['fiber']),
        sugar: _dn(m['sugar']),
        satFat: _dn(m['satfat']),
        salt: _dn(m['salt']),
        liquid: (m['liquid'] as int? ?? 0) == 1,
        portions: m['portions'] == null
            ? []
            : (jsonDecode(m['portions'] as String) as List).map(Portion.fromJson).toList(),
        source: m['source'] as String? ?? 'custom',
        favorite: (m['favorite'] as int? ?? 0) == 1,
        useCount: m['use_count'] as int? ?? 0,
        recipe: m['recipe'] as String?,
      );
}

const mealNames = ['Desayuno', 'Almuerzo', 'Comida', 'Merienda', 'Cena'];
const mealIcons = ['☕', '🥪', '🍽️', '🍎', '🌙'];

/// Comida por hora del día.
int mealForNow() {
  final h = DateTime.now().hour;
  if (h < 11) return 0;
  if (h < 13) return 1;
  if (h < 17) return 2;
  if (h < 20) return 3;
  return 4;
}

class Entry {
  int? id;
  String date;
  int meal;
  int? foodId;
  String name;
  String? brand;
  double amount; // cantidad en la unidad elegida
  String unit; // 'g', 'ml' o nombre de la ración
  double grams;
  double kcal, protein, carbs, fat;

  Entry({
    this.id,
    required this.date,
    required this.meal,
    this.foodId,
    required this.name,
    this.brand,
    required this.amount,
    required this.unit,
    required this.grams,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory Entry.fromFood(Food f, {required String date, required int meal, required double amount, required String unit, required double grams}) {
    final r = grams / 100;
    return Entry(
      date: date,
      meal: meal,
      foodId: f.id,
      name: f.name,
      brand: f.brand,
      amount: amount,
      unit: unit,
      grams: grams,
      kcal: f.kcal * r,
      protein: f.protein * r,
      carbs: f.carbs * r,
      fat: f.fat * r,
    );
  }

  Entry copyTo(String newDate, int newMeal) => Entry(
      date: newDate,
      meal: newMeal,
      foodId: foodId,
      name: name,
      brand: brand,
      amount: amount,
      unit: unit,
      grams: grams,
      kcal: kcal,
      protein: protein,
      carbs: carbs,
      fat: fat);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'meal': meal,
        'food_id': foodId,
        'name': name,
        'brand': brand,
        'amount': amount,
        'unit': unit,
        'grams': grams,
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int?,
        date: m['date'] as String,
        meal: m['meal'] as int,
        foodId: m['food_id'] as int?,
        name: m['name'] as String,
        brand: m['brand'] as String?,
        amount: _d(m['amount']),
        unit: m['unit'] as String,
        grams: _d(m['grams']),
        kcal: _d(m['kcal']),
        protein: _d(m['protein']),
        carbs: _d(m['carbs']),
        fat: _d(m['fat']),
      );

  String get amountLabel {
    String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
    if (unit == 'g' || unit == 'ml') return '${n(amount)} $unit';
    return '${n(amount)} × $unit (${n(grams)} g)';
  }
}

class ExerciseEntry {
  int? id;
  String date;
  String name;
  double minutes;
  double kcal;
  String source; // manual | hc | hc_steps
  String? extId;

  ExerciseEntry({this.id, required this.date, required this.name, required this.minutes, required this.kcal, this.source = 'manual', this.extId});

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'name': name,
        'minutes': minutes,
        'kcal': kcal,
        'source': source,
        'ext_id': extId,
      };

  factory ExerciseEntry.fromMap(Map<String, Object?> m) => ExerciseEntry(
        id: m['id'] as int?,
        date: m['date'] as String,
        name: m['name'] as String,
        minutes: _d(m['minutes']),
        kcal: _d(m['kcal']),
        source: m['source'] as String? ?? 'manual',
        extId: m['ext_id'] as String?,
      );
}

class Targets {
  final double kcal, protein, carbs, fat;
  const Targets(this.kcal, this.protein, this.carbs, this.fat);
  Map<String, Object?> toMap(String date) => {'date': date, 'kcal': kcal, 'protein': protein, 'carbs': carbs, 'fat': fat};
  factory Targets.fromMap(Map<String, Object?> m) => Targets(_d(m['kcal']), _d(m['protein']), _d(m['carbs']), _d(m['fat']));
}

/// Perfil y ajustes del usuario (guardado como JSON en preferencias).
class Profile {
  String sex; // 'h' hombre | 'm' mujer
  int age;
  double height;
  double weight;
  int activity; // 0..4
  String goal; // lose | recomp | maintain | gain
  int intensity; // 0 suave, 1 moderado, 2 intenso
  double? customKcal;
  double? adaptiveTdee;
  double? proteinPerKg;
  double fatPct;
  int exercisePct;
  int tolerancePct;
  int waterGoal;
  Map<String, String?> reminders;
  bool hcEnabled, hcSteps, hcWorkouts, hcWeight;
  int stepThreshold;

  Profile({
    this.sex = 'h',
    this.age = 30,
    this.height = 175,
    this.weight = 75,
    this.activity = 1,
    this.goal = 'recomp',
    this.intensity = 1,
    this.customKcal,
    this.adaptiveTdee,
    this.proteinPerKg,
    this.fatPct = 0.27,
    this.exercisePct = 50,
    this.tolerancePct = 10,
    this.waterGoal = 2500,
    Map<String, String?>? reminders,
    this.hcEnabled = false,
    this.hcSteps = true,
    this.hcWorkouts = true,
    this.hcWeight = true,
    this.stepThreshold = 7000,
  }) : reminders = reminders ?? Map.of(defaultReminders);

  static const defaultReminders = <String, String?>{
    'peso': '08:15',
    'desayuno': '10:00',
    'comida': '15:30',
    'cena': '22:00',
    'resumen': '22:45',
  };

  Map<String, Object?> toJson() => {
        'sex': sex,
        'age': age,
        'height': height,
        'weight': weight,
        'activity': activity,
        'goal': goal,
        'intensity': intensity,
        'customKcal': customKcal,
        'adaptiveTdee': adaptiveTdee,
        'proteinPerKg': proteinPerKg,
        'fatPct': fatPct,
        'exercisePct': exercisePct,
        'tolerancePct': tolerancePct,
        'waterGoal': waterGoal,
        'reminders': reminders,
        'hcEnabled': hcEnabled,
        'hcSteps': hcSteps,
        'hcWorkouts': hcWorkouts,
        'hcWeight': hcWeight,
        'stepThreshold': stepThreshold,
      };

  factory Profile.fromJson(Map<String, Object?> j) => Profile(
        sex: j['sex'] as String? ?? 'h',
        age: j['age'] as int? ?? 30,
        height: _d(j['height']),
        weight: _d(j['weight']),
        activity: j['activity'] as int? ?? 1,
        goal: j['goal'] as String? ?? 'recomp',
        intensity: j['intensity'] as int? ?? 1,
        customKcal: _dn(j['customKcal']),
        adaptiveTdee: _dn(j['adaptiveTdee']),
        proteinPerKg: _dn(j['proteinPerKg']),
        fatPct: _dn(j['fatPct']) ?? 0.27,
        exercisePct: j['exercisePct'] as int? ?? 50,
        tolerancePct: j['tolerancePct'] as int? ?? 10,
        waterGoal: j['waterGoal'] as int? ?? 2500,
        reminders: j['reminders'] == null
            ? null
            : (j['reminders'] as Map).map((k, v) => MapEntry(k as String, v as String?)),
        hcEnabled: j['hcEnabled'] as bool? ?? false,
        hcSteps: j['hcSteps'] as bool? ?? true,
        hcWorkouts: j['hcWorkouts'] as bool? ?? true,
        hcWeight: j['hcWeight'] as bool? ?? true,
        stepThreshold: j['stepThreshold'] as int? ?? 7000,
      );

  Profile clone() => Profile.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, Object?>);
}

/// Resumen de un día para el histórico.
class DaySummary {
  final DateTime day;
  final double kcal, protein, carbs, fat, exercise;
  final Targets target;
  final int exercisePct;
  final int tolerancePct;
  DaySummary(this.day, this.kcal, this.protein, this.carbs, this.fat, this.exercise, this.target, this.exercisePct, this.tolerancePct);

  bool get hasData => kcal > 0;
  double get exerciseCounted => exercise * exercisePct / 100;
  double get allowance => target.kcal + exerciseCounted;
  double get diff => kcal - allowance; // >0 pasado, <0 falta
  bool get proteinOk => protein >= target.protein * 0.9;

  DayStatus get status {
    if (!hasData) return DayStatus.none;
    final tol = allowance * tolerancePct / 100;
    if (diff > tol) return DayStatus.over;
    if (diff < -tol) return DayStatus.under;
    return DayStatus.ok;
  }
}

enum DayStatus { none, ok, over, under }
