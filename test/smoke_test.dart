import 'package:balance/calc.dart';
import 'package:balance/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('objetivo calórico razonable', () {
    final p = Profile(sex: 'h', age: 31, height: 178, weight: 80, activity: 1, goal: 'lose', intensity: 1);
    final t = computeTargets(p);
    expect(t.kcal, greaterThan(1500));
    expect(t.kcal, lessThan(2600));
    expect(t.protein, 160);
  });
}
