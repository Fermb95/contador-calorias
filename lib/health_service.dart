import 'dart:math';

import 'package:health/health.dart';

import 'calc.dart';
import 'db.dart';
import 'models.dart';
import 'util.dart';

/// Lectura de pasos, entrenamientos y peso desde Health Connect.
class HealthService {
  static final Health _h = Health();
  static bool _configured = false;

  static const types = [
    HealthDataType.STEPS,
    HealthDataType.WORKOUT,
    HealthDataType.WEIGHT,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
  ];

  static Future<void> _cfg() async {
    if (_configured) return;
    await _h.configure();
    _configured = true;
  }

  /// null si está disponible; si no, un mensaje explicando el problema.
  static Future<String?> availabilityProblem() async {
    await _cfg();
    final st = await _h.getHealthConnectSdkStatus();
    if (st == HealthConnectSdkStatus.sdkAvailable) return null;
    if (st == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
      return 'Health Connect necesita actualizarse.';
    }
    return 'Health Connect no está instalado.';
  }

  static Future<void> install() async {
    await _cfg();
    await _h.installHealthConnect();
  }

  static Future<bool> connect() async {
    await _cfg();
    final perms = types.map((_) => HealthDataAccess.READ).toList();
    return _h.requestAuthorization(types, permissions: perms);
  }

  static String _workoutName(String type) {
    final t = type.toUpperCase();
    const map = {
      'RUNNING': 'Correr',
      'WALKING': 'Caminar',
      'HIKING': 'Senderismo',
      'BIKING': 'Bicicleta',
      'SWIMMING': 'Natación',
      'STRENGTH': 'Fuerza',
      'WEIGHTLIFTING': 'Pesas',
      'YOGA': 'Yoga',
      'PILATES': 'Pilates',
      'ELLIPTICAL': 'Elíptica',
      'ROWING': 'Remo',
      'HIGH_INTENSITY': 'HIIT',
      'SOCCER': 'Fútbol',
      'BASKETBALL': 'Baloncesto',
      'TENNIS': 'Tenis',
      'PADEL': 'Pádel',
      'DANCING': 'Baile',
      'MARTIAL': 'Artes marciales',
      'BOXING': 'Boxeo',
      'STAIR': 'Escaleras',
    };
    for (final e in map.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return 'Entrenamiento';
  }

  static double _workoutMet(String type) {
    final t = type.toUpperCase();
    if (t.contains('RUNNING')) return 9.8;
    if (t.contains('WALKING')) return 3.5;
    if (t.contains('HIKING')) return 6.0;
    if (t.contains('BIKING')) return 6.8;
    if (t.contains('SWIMMING')) return 7.0;
    if (t.contains('STRENGTH') || t.contains('WEIGHT')) return 3.5;
    if (t.contains('YOGA') || t.contains('PILATES')) return 3.0;
    if (t.contains('HIGH_INTENSITY')) return 8.0;
    return 5.0;
  }

  /// Sincroniza un día. Devuelve un texto resumen.
  static Future<String> syncDay(DateTime day, Profile p) async {
    await _cfg();
    final start = dayOnly(day);
    final end = start.add(const Duration(days: 1));
    final now = DateTime.now();
    final until = end.isAfter(now) ? now : end;
    final date = dkey(start);
    final parts = <String>[];

    if (p.hcSteps) {
      final steps = await _h.getTotalStepsInInterval(start, until) ?? 0;
      final extra = max(0, steps - p.stepThreshold);
      final kcal = extra * 0.0005 * p.weight;
      final id = 'steps-$date';
      if (!await Db.extExerciseDeleted(id)) {
        await Db.upsertExerciseExt(ExerciseEntry(
          date: date,
          name: 'Pasos: ${fmtNum(steps)} (extra sobre ${fmtNum(p.stepThreshold)})',
          minutes: 0,
          kcal: kcal.roundToDouble(),
          source: 'hc_steps',
          extId: id,
        ));
      }
      parts.add('${fmtNum(steps)} pasos');
    }

    if (p.hcWorkouts) {
      final pts = await _h.getHealthDataFromTypes(types: [HealthDataType.WORKOUT], startTime: start, endTime: until);
      var n = 0;
      final bmrPerMin = bmr(p) / 1440;
      for (final pt in pts) {
        final v = pt.value;
        if (v is! WorkoutHealthValue) continue;
        final minutes = pt.dateTo.difference(pt.dateFrom).inSeconds / 60;
        final typeName = v.workoutActivityType.name;
        final gross = v.totalEnergyBurned;
        double kcal;
        if (gross != null && gross > 0) {
          kcal = max(0, gross - bmrPerMin * minutes);
        } else {
          kcal = metKcal(_workoutMet(typeName), p.weight, minutes);
        }
        final id = 'hc-${pt.uuid}';
        if (await Db.extExerciseDeleted(id)) continue;
        await Db.upsertExerciseExt(ExerciseEntry(
          date: date,
          name: '${_workoutName(typeName)} (Health Connect)',
          minutes: minutes.roundToDouble(),
          kcal: kcal.roundToDouble(),
          source: 'hc',
          extId: id,
        ));
        n++;
      }
      if (n > 0) parts.add('$n entrenamiento${n == 1 ? '' : 's'}');
    }

    if (p.hcWeight) {
      final pts = await _h.getHealthDataFromTypes(types: [HealthDataType.WEIGHT], startTime: start, endTime: until);
      if (pts.isNotEmpty) {
        pts.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
        final v = pts.last.value;
        if (v is NumericHealthValue) {
          await Db.setWeight(date, v.numericValue.toDouble());
          parts.add('peso ${fmtNum(v.numericValue, 1)} kg');
        }
      }
    }
    return parts.isEmpty ? 'Sin datos nuevos' : parts.join(' · ');
  }
}
