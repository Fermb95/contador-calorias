import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Valores leídos de una tabla nutricional (por 100 g/ml salvo que [perServing]).
class LabelValues {
  double? kcal, protein, carbs, sugar, fat, satFat, fiber, salt;
  bool perHundred = true;
  bool liquid = false;
  int get found => [kcal, protein, carbs, sugar, fat, satFat, fiber, salt].where((v) => v != null).length;

  @override
  String toString() =>
      'kcal=$kcal p=$protein c=$carbs az=$sugar g=$fat sat=$satFat fib=$fiber sal=$salt per100=$perHundred';
}

class _Line {
  final String text;
  final String norm;
  final Rect box;
  _Line(this.text, this.box) : norm = _normalize(text);
  double get cy => box.center.dy;
  double get h => box.height;
}

String _normalize(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Lee la etiqueta de una foto con ML Kit (en el propio móvil, sin internet).
class LabelOcr {
  static Future<LabelValues> readFile(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await recognizer.processImage(InputImage.fromFilePath(path));
      final lines = <_Line>[
        for (final b in res.blocks)
          for (final l in b.lines) _Line(l.text, l.boundingBox),
      ];
      return parse(lines.map((l) => (l.text, l.box)).toList());
    } finally {
      await recognizer.close();
    }
  }

  // Palabras clave por nutriente (normalizadas, sin tildes). Orden importante: los "de los cuales" primero.
  static const _keys = <String, List<String>>{
    'sugar': ['azucar', 'sugars', 'sucres'],
    'satFat': ['saturad', 'saturates', 'satures'],
    'fiber': ['fibra', 'fibre', 'fiber'],
    'salt': ['sal ', 'sal:', 'salt', 'sel '],
    'protein': ['proteina', 'protein', 'proteine'],
    'carbs': ['hidratos', 'carbohidrat', 'carbohydrate', 'glucides', 'h. de c', 'hc '],
    'fat': ['grasa', 'fat', 'lipid', 'matieres grasses'],
  };

  static final _num = RegExp(r'(<\s*)?(\d+(?:[.,]\d+)?)');

  static double? _firstNumber(String s) {
    for (final m in _num.allMatches(s)) {
      final rest = s.substring(m.end).trimLeft();
      if (rest.startsWith('%')) return null; // "azúcar (25%)" es de la lista de ingredientes
      final v = double.tryParse(m.group(2)!.replaceAll(',', '.'));
      if (v == null) continue;
      if (m.group(1) != null) return v / 2; // "<0,5 g" → aproximamos a la mitad
      return v;
    }
    return null;
  }

  /// [raw]: líneas reconocidas con su posición en la imagen.
  static LabelValues parse(List<(String, Rect)> raw) {
    final lines = raw.map((r) => _Line(r.$1, r.$2)).toList();
    final out = LabelValues();
    final all = lines.map((l) => l.norm).join('\n');
    out.liquid = RegExp(r'100\s*ml').hasMatch(all);
    // Si no aparece "100 g/ml" pero sí "ración"/"porción", avisamos de que puede ser por ración.
    out.perHundred = RegExp(r'100\s*(g|ml)').hasMatch(all) || !RegExp(r'racion|porcion|serving').hasMatch(all);

    // Texto a la derecha en la misma fila (las tablas se leen como columnas separadas).
    String rowText(_Line key, {required String afterKeyword}) {
      final same = lines
          .where((l) => l != key && (l.cy - key.cy).abs() < max(key.h, l.h) * 0.6 && l.box.left > key.box.left)
          .toList()
        ..sort((a, b) => a.box.left.compareTo(b.box.left));
      return '$afterKeyword ${same.map((l) => l.norm).join(' ')}';
    }

    // Energía: primer valor en kcal (o kJ / 4,184).
    final kcalRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*k\s*cal');
    final kjRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*k\s*j');
    for (final l in lines) {
      if (!(l.norm.contains('energ') || l.norm.contains('kcal') || l.norm.contains('valor') || l.norm.contains('kj'))) continue;
      final row = rowText(l, afterKeyword: l.norm);
      final m = kcalRe.firstMatch(row);
      if (m != null) {
        out.kcal = double.tryParse(m.group(1)!.replaceAll(',', '.'));
        break;
      }
      final j = kjRe.firstMatch(row);
      if (j != null && out.kcal == null) {
        final kj = double.tryParse(j.group(1)!.replaceAll(',', '.'));
        if (kj != null) out.kcal = kj / 4.184;
      }
    }
    if (out.kcal == null) {
      final m = kcalRe.firstMatch(all);
      if (m != null) out.kcal = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    }

    final used = <_Line>{};
    for (final entry in _keys.entries) {
      for (final l in lines) {
        if (used.contains(l)) continue;
        final n = '${l.norm} ';
        final idx = entry.value.map((k) => n.indexOf(k)).where((i) => i >= 0).fold<int>(-1, (a, b) => a < 0 ? b : min(a, b));
        if (idx < 0 || idx > 26) continue; // la palabra clave debe ir al principio (no en ingredientes)
        // Evitar que "grasas" capture la línea de "saturadas" y "hidratos" la de "azúcares".
        if (entry.key == 'fat' && (n.contains('saturad') || n.contains('saturat') || n.contains('satur'))) continue;
        if (entry.key == 'carbs' && n.contains('azucar')) continue;
        if (entry.key == 'salt' && (n.contains('saturad') || n.contains('sales'))) continue;
        final after = n.substring(idx);
        final v = _firstNumber(rowText(l, afterKeyword: after));
        if (v == null || v > 100) continue;
        used.add(l);
        switch (entry.key) {
          case 'sugar':
            out.sugar = v;
          case 'satFat':
            out.satFat = v;
          case 'fiber':
            out.fiber = v;
          case 'salt':
            out.salt = v;
          case 'protein':
            out.protein = v;
          case 'carbs':
            out.carbs = v;
          case 'fat':
            out.fat = v;
        }
        break;
      }
    }
    // Si no hay kcal pero sí macros, se estiman.
    if (out.kcal == null && (out.protein != null || out.carbs != null || out.fat != null)) {
      out.kcal = (out.protein ?? 0) * 4 + (out.carbs ?? 0) * 4 + (out.fat ?? 0) * 9 + (out.fiber ?? 0) * 2;
    }
    return out;
  }
}
