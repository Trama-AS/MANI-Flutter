import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/profiles/coverage/domain/entities/seleccion_cobertura.dart';

import 'fakes.dart';

void main() {
  group('SeleccionCobertura (regla jerárquica ADR-0011)', () {
    test('agregar barrios independientes', () {
      final s = SeleccionCobertura.vacia().agregar(chico).agregar(niza);
      expect(s.ids, {'chi', 'niz'});
      expect(s.cubre(rosales), isFalse);
    });

    test('agregar la localidad absorbe sus barrios ya seleccionados', () {
      var s = SeleccionCobertura.vacia()
          .agregar(chico)
          .agregar(rosales)
          .agregar(niza);
      expect(s.cantidadAbsorbidaPor(chapinero), 2);
      s = s.agregar(chapinero);
      expect(s.ids, {'cha', 'niz'});
      expect(s.cubre(chico), isTrue);
      expect(s.estaCubiertaPorAncestro(rosales), isTrue);
      expect(s.ancestroSeleccionado(rosales), chapinero);
    });

    test('agregar un barrio ya cubierto por su localidad no cambia nada', () {
      final s = SeleccionCobertura.vacia().agregar(chapinero);
      expect(identical(s.agregar(chico), s), isTrue);
    });

    test('quitar solo aplica a zonas seleccionadas directamente', () {
      final s = SeleccionCobertura.vacia().agregar(chapinero);
      expect(s.quitar(chico).ids, {'cha'});
      expect(s.quitar(chapinero).estaVacia, isTrue);
    });

    test('ciudad completa absorbe todo', () {
      final s = SeleccionCobertura.vacia()
          .agregar(chapinero)
          .agregar(niza)
          .agregar(bogota);
      expect(s.ids, {'bog'});
      expect(s.cubre(rosales), isTrue);
    });

    test('desde() normaliza una lista con zona y ancestro', () {
      final s = SeleccionCobertura.desde([chico, chapinero, niza]);
      expect(s.ids, {'cha', 'niz'});
    });

    test('tieneDescendienteSeleccionada para checkbox parcial', () {
      final s = SeleccionCobertura.vacia().agregar(chico);
      expect(s.tieneDescendienteSeleccionada(chapinero), isTrue);
      expect(s.tieneDescendienteSeleccionada(suba), isFalse);
    });

    test('mismoContenidoQue ignora el orden', () {
      final a = SeleccionCobertura.vacia().agregar(chico).agregar(niza);
      final b = SeleccionCobertura.vacia().agregar(niza).agregar(chico);
      expect(a.mismoContenidoQue(b), isTrue);
      expect(a.mismoContenidoQue(b.quitar(niza)), isFalse);
    });

    test('desactivadas y sinDesactivadas', () {
      final s = SeleccionCobertura.desde([chico, nizaDesactivada]);
      expect(s.desactivadas.map((z) => z.id), ['niz']);
      expect(s.sinDesactivadas().ids, {'chi'});
    });
  });
}
