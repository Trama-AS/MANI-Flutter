import 'cola_eventos.dart';

/// En la web no hay modo sin conexión (decisión del PO, SCRUM-873).
AlmacenColaEventos crearAlmacen() => AlmacenColaEnMemoria(disponible: false);
