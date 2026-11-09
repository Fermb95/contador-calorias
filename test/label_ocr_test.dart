import 'dart:ui';

import 'package:balance/label_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

(String, Rect) l(String t, double x, double y, [double w = 150]) => (t, Rect.fromLTWH(x, y, w, 20));

void main() {
  test('tabla en columnas (etiqueta típica española)', () {
    final r = LabelOcr.parse([
      l('Ingredientes: harina de trigo, azúcar (25%), grasa de palma, sal.', 0, 0, 600),
      l('Información nutricional', 0, 60),
      l('Por 100 g', 220, 60),
      l('Por ración (30 g)', 360, 60),
      l('Valor energético', 0, 100),
      l('1858 kJ / 443 kcal', 220, 100),
      l('557 kJ / 133 kcal', 360, 100),
      l('Grasas', 0, 130),
      l('17 g', 220, 130),
      l('5,1 g', 360, 130),
      l('de las cuales saturadas', 0, 160),
      l('7,8 g', 220, 160),
      l('Hidratos de carbono', 0, 190),
      l('64 g', 220, 190),
      l('de los cuales azúcares', 0, 220),
      l('24 g', 220, 220),
      l('Fibra alimentaria', 0, 250),
      l('3,2 g', 220, 250),
      l('Proteínas', 0, 280),
      l('6,5 g', 220, 280),
      l('Sal', 0, 310),
      l('0,63 g', 220, 310),
    ]);
    expect(r.kcal, 443);
    expect(r.fat, 17);
    expect(r.satFat, 7.8);
    expect(r.carbs, 64);
    expect(r.sugar, 24);
    expect(r.fiber, 3.2);
    expect(r.protein, 6.5);
    expect(r.salt, 0.63);
    expect(r.perHundred, true);
  });

  test('texto en una línea por nutriente y bebida', () {
    final r = LabelOcr.parse([
      l('Valores medios por 100 ml', 0, 0, 400),
      l('Energía 180 kJ/43 kcal', 0, 30, 400),
      l('Grasas 1,5 g', 0, 60, 400),
      l('- de las cuales saturadas 1,0 g', 0, 90, 400),
      l('Hidratos de carbono 4,7 g', 0, 120, 400),
      l('- de los cuales azúcares 4,7 g', 0, 150, 400),
      l('Proteínas 3,1 g', 0, 180, 400),
      l('Sal 0,13 g', 0, 210, 400),
    ]);
    expect(r.kcal, 43);
    expect(r.fat, 1.5);
    expect(r.satFat, 1.0);
    expect(r.carbs, 4.7);
    expect(r.sugar, 4.7);
    expect(r.protein, 3.1);
    expect(r.salt, 0.13);
    expect(r.liquid, true);
  });
}
