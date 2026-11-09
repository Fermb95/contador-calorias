import 'dart:math';

import 'models.dart';

const activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];
const activityLabels = ['Sedentaria', 'Ligera', 'Moderada', 'Alta', 'Muy alta'];
const activityHelp = [
  'Trabajo de oficina, apenas caminas (<5.000 pasos).',
  'Caminas algo a diario o trabajo de pie a ratos (5.000-7.500 pasos).',
  'Trabajo de pie o caminas bastante (7.500-10.000 pasos).',
  'Trabajo físico o muy activo durante el día (>10.000 pasos).',
  'Trabajo físico muy duro todo el día.',
];

const goalLabels = {
  'lose': 'Perder grasa',
  'recomp': 'Perder grasa y ganar músculo',
  'maintain': 'Mantener peso',
  'gain': 'Ganar músculo',
};
const goalHelp = {
  'lose': 'Déficit calórico con proteína alta para conservar músculo.',
  'recomp': 'Recomposición: déficit ligero, proteína alta y entrenamiento de fuerza.',
  'maintain': 'Comer lo que gastas.',
  'gain': 'Superávit moderado para ganar músculo minimizando grasa.',
};
const intensityLabels = {
  'lose': ['Suave (-10%)', 'Moderado (-20%)', 'Agresivo (-25%)'],
  'recomp': ['Mantenimiento', 'Ligero (-5%)', 'Moderado (-10%)'],
  'maintain': ['-', '-', '-'],
  'gain': ['Limpio (+5%)', 'Moderado (+10%)', 'Rápido (+15%)'],
};

double goalAdjust(String goal, int intensity) {
  final i = intensity.clamp(0, 2);
  return switch (goal) {
    'lose' => const [-0.10, -0.20, -0.25][i],
    'recomp' => const [0.0, -0.05, -0.10][i],
    'gain' => const [0.05, 0.10, 0.15][i],
    _ => 0.0,
  };
}

double defaultProtein(String goal) => switch (goal) {
      'lose' => 2.0,
      'recomp' => 2.0,
      'gain' => 1.8,
      _ => 1.6,
    };

/// Mifflin-St Jeor.
double bmr(Profile p) => 10 * p.weight + 6.25 * p.height - 5 * p.age + (p.sex == 'h' ? 5 : -161);

double formulaTdee(Profile p) => bmr(p) * activityFactors[p.activity.clamp(0, 4)];

double baseTdee(Profile p) => p.adaptiveTdee ?? formulaTdee(p);

Targets computeTargets(Profile p) {
  var kcal = p.customKcal ?? baseTdee(p) * (1 + goalAdjust(p.goal, p.intensity));
  if (p.customKcal == null) {
    final floor = p.sex == 'h' ? 1500.0 : 1200.0;
    kcal = max(kcal, floor);
    kcal = (kcal / 10).roundToDouble() * 10;
  }
  final protein = (p.proteinPerKg ?? defaultProtein(p.goal)) * p.weight;
  final fat = max(kcal * p.fatPct / 9, 0.6 * p.weight);
  final carbs = max(0.0, (kcal - protein * 4 - fat * 9) / 4);
  return Targets(kcal.roundToDouble(), protein.roundToDouble(), carbs.roundToDouble(), fat.roundToDouble());
}

/// kcal netas de una actividad: (MET - 1) × kg × horas (resta lo que ya gastarías en reposo).
double metKcal(double met, double kg, double minutes) => max(0, (met - 1)) * kg * minutes / 60;

/// Peso de tendencia (media móvil exponencial) a partir de pesadas ordenadas por fecha.
List<double> trendWeights(List<double> weights, {double alpha = 0.15}) {
  final out = <double>[];
  for (final w in weights) {
    out.add(out.isEmpty ? w : out.last + alpha * (w - out.last));
  }
  return out;
}

class AdaptiveResult {
  final double tdee;
  final int days;
  final int loggedDays;
  final double avgIntake;
  final double trendChangeKg;
  AdaptiveResult(this.tdee, this.days, this.loggedDays, this.avgIntake, this.trendChangeKg);
}
