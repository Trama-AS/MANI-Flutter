import 'package:flutter_test/flutter_test.dart';
import 'package:mani/evidencia/gate_critical.dart';

void main() {
  test('cubre todas las ramas de clasificarGateCritical', () {
    expect(clasificarGateCritical(-1, true, true), 'a');
    expect(clasificarGateCritical(-1, true, false), 'b');
    expect(clasificarGateCritical(-1, false, false), 'c');
    expect(clasificarGateCritical(5, true, true), 'd');
    expect(clasificarGateCritical(5, true, false), 'e');
    expect(clasificarGateCritical(5, false, false), 'f');
    expect(clasificarGateCritical(20, true, true), 'g');
    expect(clasificarGateCritical(20, false, true), 'h');
    expect(clasificarGateCritical(20, false, false), 'i');
  });
}
