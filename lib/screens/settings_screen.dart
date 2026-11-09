import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../calc.dart';
import '../db.dart';
import '../health_service.dart';
import '../models.dart';
import '../notifications.dart';
import '../state.dart';
import '../util.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _save(Profile p, {bool reschedule = false}) async {
    await app.saveProfile(p);
    if (reschedule) {
      try {
        await Notif.scheduleReminders(p);
      } catch (_) {}
    }
  }

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(t,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      );

  Future<void> _customKcal(BuildContext context, Profile p) async {
    final ctrl = TextEditingController(text: p.customKcal == null ? '' : fmtNum(p.customKcal!).replaceAll('.', ''));
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Calorías objetivo fijas'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Déjalo vacío para que se calcule automáticamente con tu perfil.'),
          const SizedBox(height: 12),
          TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'kcal/día', hintText: 'Automático')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (res == null) return;
    final v = parseNum(res);
    p.customKcal = (v != null && v >= 800) ? v : null;
    await _save(p);
  }

  Future<void> _pickTime(BuildContext context, Profile p, String key) async {
    final cur = parseHHMM(p.reminders[key] ?? Profile.defaultReminders[key]) ?? const TimeOfDay(hour: 9, minute: 0);
    final t = await showTimePicker(context: context, initialTime: cur);
    if (t == null) return;
    p.reminders[key] = hhmm(t);
    await _save(p, reschedule: true);
  }

  Future<void> _toggleHealth(BuildContext context, Profile p, bool on) async {
    if (!on) {
      p.hcEnabled = false;
      await _save(p);
      return;
    }
    try {
      final problem = await HealthService.availabilityProblem();
      if (problem != null) {
        if (context.mounted) toast(context, '$problem Te llevo a instalarlo.');
        await HealthService.install();
        return;
      }
      final ok = await HealthService.connect();
      if (!ok) {
        if (context.mounted) toast(context, 'No se concedieron los permisos de Health Connect');
        return;
      }
      p.hcEnabled = true;
      await _save(p);
      final msg = await app.syncHealth(day: today());
      if (context.mounted) toast(context, 'Conectado. Hoy: $msg');
    } catch (e) {
      if (context.mounted) toast(context, 'Error con Health Connect: $e');
    }
  }

  Future<void> _syncWeek(BuildContext context) async {
    for (var i = 6; i >= 0; i--) {
      await app.syncHealth(day: today().subtract(Duration(days: i)));
    }
    if (context.mounted) toast(context, 'Últimos 7 días sincronizados');
  }

  Future<void> _export(BuildContext context) async {
    try {
      final data = {
        'app': 'balance',
        'version': 1,
        'exported': DateTime.now().toIso8601String(),
        'profile': app.profile?.toJson(),
        'db': await Db.exportAll(),
      };
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/balance-copia-${dkey(today())}.json');
      await file.writeAsString(jsonEncode(data));
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Copia de seguridad de Balance ${fmtLong(today())}'));
    } catch (e) {
      if (context.mounted) toast(context, 'No se pudo exportar: $e');
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final data = jsonDecode(utf8.decode(await files.first.readAsBytes())) as Map<String, dynamic>;
      if (data['app'] != 'balance' || data['db'] is! Map) {
        if (context.mounted) toast(context, 'Ese archivo no es una copia de Balance');
        return;
      }
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Restaurar copia'),
          content: Text('Se reemplazarán TODOS los datos actuales por los de la copia del ${data['exported'] ?? '?'}. ¿Seguir?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurar')),
          ],
        ),
      );
      if (ok != true) return;
      await Db.importAll(Map<String, dynamic>.from(data['db'] as Map));
      if (data['profile'] is Map) {
        await app.saveProfile(Profile.fromJson(Map<String, Object?>.from(data['profile'] as Map)));
      }
      await app.afterImport();
      if (context.mounted) toast(context, 'Copia restaurada');
    } catch (e) {
      if (context.mounted) toast(context, 'No se pudo importar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.profile;
        if (p == null) return const SizedBox.shrink();
        final t = app.targets;
        final ts = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Ajustes')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _header(context, 'Perfil y objetivo'),
              ListTile(
                leading: const Icon(Icons.person),
                title: Text('${p.sex == 'h' ? 'Hombre' : 'Mujer'}, ${p.age} años, ${fmtNum(p.height)} cm, ${fmtNum(p.weight, 1)} kg'),
                subtitle: Text('${goalLabels[p.goal]} · actividad ${activityLabels[p.activity].toLowerCase()}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.local_fire_department),
                title: Text('${fmtNum(t.kcal)} kcal/día${p.customKcal != null ? ' (fijado a mano)' : ''}'),
                subtitle: Text('P ${fmtNum(t.protein)} g · H ${fmtNum(t.carbs)} g · G ${fmtNum(t.fat)} g'),
                trailing: const Icon(Icons.edit),
                onTap: () => _customKcal(context, p),
              ),
              ListTile(
                title: Text('Proteína: ${fmtNum(p.proteinPerKg ?? defaultProtein(p.goal), 1)} g por kg'),
                subtitle: Slider(
                  value: (p.proteinPerKg ?? defaultProtein(p.goal)).clamp(1.0, 3.0),
                  min: 1.0,
                  max: 3.0,
                  divisions: 20,
                  label: fmtNum(p.proteinPerKg ?? defaultProtein(p.goal), 1),
                  onChanged: (v) => _save(p..proteinPerKg = v),
                ),
              ),
              ListTile(
                title: Text('Grasa: ${(p.fatPct * 100).round()}% de las calorías'),
                subtitle: Slider(
                  value: p.fatPct.clamp(0.15, 0.45),
                  min: 0.15,
                  max: 0.45,
                  divisions: 30,
                  onChanged: (v) => _save(p..fatPct = v),
                ),
              ),
              _header(context, 'Cálculo del día'),
              ListTile(
                title: Text('Calorías de ejercicio que suman: ${p.exercisePct}%'),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Slider(
                    value: p.exercisePct.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 10,
                    label: '${p.exercisePct}%',
                    onChanged: (v) => _save(p..exercisePct = v.round()),
                  ),
                  Text('Los relojes y las tablas suelen sobreestimar el gasto. Con un 50% vas sobre seguro.', style: ts.bodySmall),
                ]),
              ),
              ListTile(
                title: Text('Margen para «objetivo cumplido»: ±${p.tolerancePct}%'),
                subtitle: Slider(
                  value: p.tolerancePct.toDouble(),
                  min: 3,
                  max: 20,
                  divisions: 17,
                  onChanged: (v) => _save(p..tolerancePct = v.round()),
                ),
              ),
              ListTile(
                title: Text('Agua diaria: ${fmtNum(p.waterGoal / 1000, 2)} L'),
                subtitle: Slider(
                  value: p.waterGoal.toDouble().clamp(1000, 5000),
                  min: 1000,
                  max: 5000,
                  divisions: 16,
                  onChanged: (v) => _save(p..waterGoal = v.round()),
                ),
              ),
              _header(context, 'Notificaciones'),
              for (final k in Notif.reminderLabels.keys)
                SwitchListTile(
                  title: Text(Notif.reminderLabels[k]!),
                  subtitle: Text(p.reminders[k] == null
                      ? 'Desactivado'
                      : k == 'resumen'
                          ? '${p.reminders[k]} · te dice cuánto te queda o cuánto te has pasado'
                          : 'Cada día a las ${p.reminders[k]} · toca para cambiar la hora'),
                  value: p.reminders[k] != null,
                  onChanged: (on) async {
                    if (on) {
                      await Notif.requestPermission();
                      p.reminders[k] = Profile.defaultReminders[k];
                    } else {
                      p.reminders[k] = null;
                    }
                    await _save(p, reschedule: true);
                    await app.refreshSummary();
                  },
                  secondary: IconButton(
                    icon: const Icon(Icons.schedule),
                    onPressed: p.reminders[k] == null
                        ? null
                        : () async {
                            await _pickTime(context, p, k);
                            await app.refreshSummary();
                          },
                  ),
                ),
              _header(context, 'Health Connect (reloj, pulsera, móvil)'),
              SwitchListTile(
                secondary: const Icon(Icons.favorite),
                title: const Text('Conectar con Health Connect'),
                subtitle: const Text('Importa pasos, entrenamientos y peso de Samsung Health, Google Fit, Zepp, Garmin…'),
                value: p.hcEnabled,
                onChanged: (v) => _toggleHealth(context, p, v),
              ),
              if (p.hcEnabled) ...[
                SwitchListTile(
                  title: const Text('Entrenamientos'),
                  subtitle: const Text('Se restan las kcal basales para no contarlas dos veces'),
                  value: p.hcWorkouts,
                  onChanged: (v) => _save(p..hcWorkouts = v),
                ),
                SwitchListTile(
                  title: const Text('Peso (báscula inteligente)'),
                  value: p.hcWeight,
                  onChanged: (v) => _save(p..hcWeight = v),
                ),
                SwitchListTile(
                  title: const Text('Pasos extra'),
                  subtitle: Text('Suman kcal solo los pasos por encima de ${fmtNum(p.stepThreshold)} '
                      '(los normales ya van en tu nivel de actividad)'),
                  value: p.hcSteps,
                  onChanged: (v) => _save(p..hcSteps = v),
                ),
                if (p.hcSteps)
                  ListTile(
                    title: Text('Umbral de pasos: ${fmtNum(p.stepThreshold)}'),
                    subtitle: Slider(
                      value: p.stepThreshold.toDouble().clamp(2000, 15000),
                      min: 2000,
                      max: 15000,
                      divisions: 26,
                      onChanged: (v) => _save(p..stepThreshold = v.round()),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sincronizar últimos 7 días'),
                  onTap: () => _syncWeek(context),
                ),
              ],
              _header(context, 'Copia de seguridad'),
              const ListTile(
                dense: true,
                title: Text('Tus datos solo están en este móvil. Haz copias de vez en cuando (Drive, correo…), '
                    'sobre todo antes de cambiar de teléfono.'),
              ),
              ListTile(leading: const Icon(Icons.upload_file), title: const Text('Exportar copia'), onTap: () => _export(context)),
              ListTile(leading: const Icon(Icons.download), title: const Text('Restaurar copia'), onTap: () => _import(context)),
              _header(context, 'Acerca de'),
              const ListTile(
                dense: true,
                title: Text('Balance 1.0 · uso personal'),
                subtitle: Text('Productos de supermercado: Open Food Facts (base colaborativa, licencia ODbL). '
                    'Alimentos genéricos: valores medios de tablas de composición. '
                    'Gasto de ejercicio: Compendium of Physical Activities. '
                    'Las cifras son estimaciones, no consejo médico.'),
              ),
            ],
          ),
        );
      },
    );
  }
}
