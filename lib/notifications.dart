import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'util.dart';

class Notif {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _ids = {'peso': 1, 'desayuno': 2, 'comida': 3, 'cena': 4};
  static const _summaryToday = 100;
  static const _summaryTomorrow = 101;

  static const reminderLabels = {
    'peso': 'Pesarte',
    'desayuno': 'Registrar el desayuno',
    'comida': 'Registrar la comida',
    'cena': 'Registrar la cena',
    'resumen': 'Resumen del día',
  };

  static const _texts = {
    'peso': ('⚖️ Hora de pesarte', 'En ayunas y tras ir al baño: así la tendencia es más fiable.'),
    'desayuno': ('☕ ¿Qué has desayunado?', 'Apúntalo ahora que lo tienes fresco.'),
    'comida': ('🍽️ ¿Has registrado la comida?', 'Un minuto ahora te ahorra adivinar luego.'),
    'cena': ('🌙 Registra la cena', 'Cierra el día con todo apuntado.'),
  };

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Madrid'));
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')));
    _ready = true;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'recordatorios',
      'Recordatorios',
      channelDescription: 'Recordatorios para registrar comidas, peso y resumen diario',
      importance: Importance.high,
      priority: Priority.high,
      color: okColor,
    ),
  );

  static tz.TZDateTime _next(int h, int m) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  static Future<void> _schedule(int id, String title, String body, tz.TZDateTime when, {bool daily = false}) =>
      _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: daily ? DateTimeComponents.time : null,
      );

  /// Programa los recordatorios diarios fijos según el perfil.
  static Future<void> scheduleReminders(Profile p) async {
    if (!_ready) return;
    for (final e in _ids.entries) {
      await _plugin.cancel(e.value);
      final t = parseHHMM(p.reminders[e.key]);
      if (t == null) continue;
      final txt = _texts[e.key]!;
      await _schedule(e.value, txt.$1, txt.$2, _next(t.hour, t.minute), daily: true);
    }
  }

  /// Resumen nocturno: el de hoy con datos reales y el de mañana genérico (se sustituye al abrir la app).
  static Future<void> scheduleSummary(Profile p, {required double eaten, required double allowance, required double protein, required double proteinTarget, required bool hasData}) async {
    if (!_ready) return;
    await _plugin.cancel(_summaryToday);
    await _plugin.cancel(_summaryTomorrow);
    final t = parseHHMM(p.reminders['resumen']);
    if (t == null) return;
    final now = tz.TZDateTime.now(tz.local);
    final todayAt = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    final String title;
    final String body;
    if (!hasData) {
      title = '📋 Hoy no has registrado nada';
      body = 'Si has comido, apúntalo para no romper la racha.';
    } else {
      final diff = allowance - eaten;
      final protLeft = proteinTarget - protein;
      if (diff >= 0) {
        title = '✅ Te quedan ${fmtNum(diff)} kcal';
      } else {
        title = '⚠️ Te has pasado ${fmtNum(-diff)} kcal';
      }
      body = 'Llevas ${fmtNum(eaten)} de ${fmtNum(allowance)} kcal.'
          '${protLeft > 5 ? ' Te faltan ${fmtNum(protLeft)} g de proteína.' : ' Proteína cumplida 💪'}';
    }
    if (todayAt.isAfter(now)) await _schedule(_summaryToday, title, body, todayAt);
    await _schedule(_summaryTomorrow, '📊 Revisa tu balance de hoy', '¿Lo tienes todo registrado? Mira cuánto te queda.',
        todayAt.add(const Duration(days: 1)));
  }

  static Future<void> cancelAll() => _plugin.cancelAll();
}
