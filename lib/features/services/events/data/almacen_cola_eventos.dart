import 'cola_eventos.dart';
import 'almacen_cola_eventos_web.dart'
    if (dart.library.io) 'almacen_cola_eventos_io.dart'
    as plataforma;

/// Almacén de la cola sin conexión para la plataforma actual: archivos en
/// Android e iOS; en web y escritorio no hay modo sin conexión (SCRUM-873).
AlmacenColaEventos crearAlmacenColaEventos() => plataforma.crearAlmacen();
