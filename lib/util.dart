import 'package:flutter/material.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// Clave de fecha yyyy-mm-dd.
String dkey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

DateTime parseKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => dayOnly(DateTime.now());
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Lunes de la semana de [d].
DateTime weekStart(DateTime d) => dayOnly(d).subtract(Duration(days: d.weekday - 1));

const meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];
const mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const diasCortos = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String fmtDayTitle(DateTime d) {
  final t = today();
  if (sameDay(d, t)) return 'Hoy';
  if (sameDay(d, t.subtract(const Duration(days: 1)))) return 'Ayer';
  if (sameDay(d, t.add(const Duration(days: 1)))) return 'Mañana';
  return '${cap(dias[d.weekday - 1])} ${d.day} ${mesesCortos[d.month - 1]}';
}

String fmtLong(DateTime d) => '${cap(dias[d.weekday - 1])}, ${d.day} de ${meses[d.month - 1]} de ${d.year}';
String fmtShort(DateTime d) => '${d.day} ${mesesCortos[d.month - 1]}';

/// Número con separador de miles español y coma decimal.
String fmtNum(num v, [int dec = 0]) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(dec);
  final parts = s.split('.');
  final buf = StringBuffer();
  final ip = parts[0];
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) buf.write('.');
    buf.write(ip[i]);
  }
  var out = buf.toString();
  if (parts.length > 1 && dec > 0) {
    var frac = parts[1];
    while (frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    if (frac.isNotEmpty) out += ',$frac';
  }
  return neg ? '-$out' : out;
}

double? parseNum(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Minúsculas y sin tildes, para buscar.
String normalize(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final low = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in low.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

String hhmm(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';
TimeOfDay? parseHHMM(String? s) {
  if (s == null || !s.contains(':')) return null;
  final p = s.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

const okColor = Color(0xFF2E7D32);
const overColor = Color(0xFFC62828);
const underColor = Color(0xFFEF8F00);
const proteinColor = Color(0xFF1E88E5);
const carbsColor = Color(0xFFFFA000);
const fatColor = Color(0xFF8E24AA);
