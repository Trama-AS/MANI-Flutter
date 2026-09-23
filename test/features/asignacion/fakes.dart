import 'dart:async';

import 'package:mani/features/asignacion/data/datasources/asignacion_remote_datasource.dart';
import 'package:mani/features/asignacion/domain/entities/modalidad_servicio.dart';
import 'package:mani/features/asignacion/domain/entities/motivo_rechazo.dart';
import 'package:mani/features/asignacion/domain/entities/regla_sitio.dart';
import 'package:mani/features/asignacion/domain/entities/solicitud_entity.dart';
import 'package:mani/features/asignacion/domain/failures/asignacion_failure.dart';
import 'package:mani/features/asignacion/domain/repositories/i_asignacion_repository.dart';
import 'package:mani/features/asignacion/domain/usecases/asignacion_usecases.dart';
import 'package:mani/features/asignacion/presentation/bloc/solicitudes_aliado_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- builders
SolicitudEntity solicitud(
  String id, {
  EstadoSolicitud estado = EstadoSolicitud.pendiente,
  bool esMia = false,
  String categoria = 'Plomería',
  ModalidadServicio modalidad = ModalidadServicio.cotizacionPrevia,
  String zona = 'Roma Norte',
  String? zonaPadre = 'Cuauhtémoc',
  List<ReglaSitio> reglas = const [],
  String? direccion,
  int minutosAtras = 10,
  DateTime? fechaAsignacion,
}) => SolicitudEntity(
  id: id,
  estado: estado,
  esMia: esMia,
  categoria: categoria,
  modalidad: modalidad,
  zona: zona,
  zonaPadre: zonaPadre,
  reglasSitio: reglas,
  direccion: direccion,
  fechaCreacion: DateTime.now().subtract(Duration(minutes: minutosAtras)),
  fechaAsignacion: fechaAsignacion,
);

// ------------------------------------------------ repositorio en memoria
/// Repositorio de dominio en memoria para cubit y widgets. Replica las reglas
/// de la RPC: solo se asigna una solicitud PENDIENTE (409 si no) y el
/// reintento del mismo aliado es idempotente.
class FakeAsignacionRepository implements IAsignacionRepository {
  FakeAsignacionRepository([List<SolicitudEntity> iniciales = const []])
    : _datos = {for (final s in iniciales) s.id: s};

  final Map<String, SolicitudEntity> _datos;
  final Map<String, MotivoRechazo?> rechazadas = {};

  AsignacionFailure? fallarAlListar;
  AsignacionFailure? fallarAlAceptar;
  AsignacionFailure? fallarAlRechazar;

  /// Si se asigna, aceptar/rechazar esperan a que se complete.
  Completer<void>? pausa;

  int llamadasAceptar = 0;
  int llamadasRechazar = 0;

  SolicitudEntity? porId(String id) => _datos[id];

  /// Simula que otro aliado ganó la solicitud desde otro dispositivo.
  void tomadaPorOtroAliado(String id) {
    final s = _datos[id]!;
    _datos[id] = _copiar(s, estado: EstadoSolicitud.asignada, esMia: false);
  }

  @override
  Future<List<SolicitudEntity>> listar() async {
    if (fallarAlListar != null) {
      throw fallarAlListar!;
    }
    return _datos.values
        .where((s) => s.esMia || s.estado == EstadoSolicitud.pendiente)
        .where((s) => !rechazadas.containsKey(s.id))
        .toList();
  }

  @override
  Future<SolicitudEntity> aceptar(String solicitudId) async {
    llamadasAceptar++;
    if (pausa != null) {
      await pausa!.future;
    }
    if (fallarAlAceptar != null) {
      throw fallarAlAceptar!;
    }
    final actual = _datos[solicitudId];
    if (actual == null) {
      throw const AsignacionFailure(AsignacionErrorTipo.noEncontrada);
    }
    if (actual.esMia) {
      return actual;
    }
    if (actual.estado != EstadoSolicitud.pendiente) {
      throw const AsignacionFailure(AsignacionErrorTipo.yaNoDisponible);
    }
    final asignada = _copiar(
      actual,
      estado: EstadoSolicitud.asignada,
      esMia: true,
      direccion: 'Calle Colima 120, Apto 401',
      fechaAsignacion: DateTime.now(),
    );
    _datos[solicitudId] = asignada;
    return asignada;
  }

  @override
  Future<void> rechazar(String solicitudId, {MotivoRechazo? motivo}) async {
    llamadasRechazar++;
    if (pausa != null) {
      await pausa!.future;
    }
    if (fallarAlRechazar != null) {
      throw fallarAlRechazar!;
    }
    rechazadas[solicitudId] = motivo;
  }

  static SolicitudEntity _copiar(
    SolicitudEntity s, {
    required EstadoSolicitud estado,
    required bool esMia,
    String? direccion,
    DateTime? fechaAsignacion,
  }) => SolicitudEntity(
    id: s.id,
    estado: estado,
    esMia: esMia,
    categoria: s.categoria,
    modalidad: s.modalidad,
    zona: s.zona,
    zonaPadre: s.zonaPadre,
    reglasSitio: s.reglasSitio,
    direccion: direccion,
    fechaCreacion: s.fechaCreacion,
    fechaAsignacion: fechaAsignacion,
  );
}

SolicitudesAliadoCubit crearCubit(IAsignacionRepository repo) =>
    SolicitudesAliadoCubit(
      listar: ListarSolicitudesAliado(repo),
      aceptar: AceptarSolicitud(repo),
      rechazar: RechazarSolicitud(repo),
    );

// -------------------------------------------- servidor Supabase simulado
/// Perfil de un aliado en el servidor simulado.
class AliadoFake {
  AliadoFake({
    required this.tenantId,
    this.verificado = true,
    this.categorias = const {'Plomería'},
    this.zonas = const {'Cuauhtémoc'},
  });

  final String tenantId;
  bool verificado;
  final Set<String> categorias;

  /// Zonas declaradas. Una zona cubre sus descendientes (ADR-0011): declarar
  /// "Cuauhtémoc" cubre "Roma Norte".
  final Set<String> zonas;
}

/// Simula, a nivel JSON, las RPC de `005_aceptar_rechazar_solicitud.sql`
/// para VARIOS aliados a la vez. Cada aliado usa su propia sesión
/// ([sesion]); todas comparten la misma "BD".
///
/// La asignación es un check-and-set síncrono tras la latencia de red, como
/// el UPDATE condicional de PostgreSQL: si dos aceptaciones compiten, ambas
/// se suspenden en el `await` y la segunda encuentra la fila ya asignada.
class ServidorAsignacionFake {
  ServidorAsignacionFake({this.latencia = Duration.zero});

  final Duration latencia;
  final Map<String, AliadoFake> aliados = {};
  final List<Map<String, dynamic>> solicitudes = [];
  final Map<(String, String), String?> rechazos = {};
  final List<Map<String, dynamic>> eventos = [];
  final List<Map<String, dynamic>> notificaciones = [];

  void registrarAliado(String id, AliadoFake aliado) => aliados[id] = aliado;

  void publicar({
    required String id,
    required String tenantId,
    String categoria = 'Plomería',
    String flujo = 'COTIZACION_PREVIA',
    String zona = 'Roma Norte',
    String? zonaPadre = 'Cuauhtémoc',
    Map<String, dynamic> reglas = const {},
    String direccion = 'Calle Colima 120, Apto 401',
    int minutosAtras = 10,
  }) {
    final creada = DateTime.now()
        .subtract(Duration(minutes: minutosAtras))
        .toUtc()
        .toIso8601String();
    solicitudes.add({
      'id': id,
      'tenant_id': tenantId,
      'categoria': categoria,
      'flujo_operativo': flujo,
      'zona': zona,
      'zona_padre': zonaPadre,
      'reglas_sitio': reglas,
      'direccion': direccion,
      'estado': 'PENDIENTE',
      'aliado_id': null,
      'created_at': creada,
      'updated_at': creada,
    });
  }

  Map<String, dynamic> fila(String id) =>
      solicitudes.firstWhere((s) => s['id'] == id);

  /// Datasource autenticado como [aliadoId] (`null` = sin sesión).
  AsignacionRemoteDataSource sesion(String? aliadoId) =>
      _SesionAliado(this, aliadoId);
}

class _SesionAliado implements AsignacionRemoteDataSource {
  _SesionAliado(this._srv, this._aliadoId);

  final ServidorAsignacionFake _srv;
  final String? _aliadoId;

  AliadoFake _aliadoActual() {
    final id = _aliadoId;
    if (id == null) {
      throw const PostgrestException(message: 'MANI-SOL-401: sesión requerida');
    }
    final a = _srv.aliados[id];
    if (a == null) {
      throw const PostgrestException(message: 'MANI-SOL-403: no es aliado');
    }
    return a;
  }

  void _exigirVerificado(AliadoFake a) {
    if (!a.verificado) {
      throw const PostgrestException(message: 'MANI-SOL-403V: no verificado');
    }
  }

  bool _elegible(AliadoFake a, Map<String, dynamic> s) =>
      a.categorias.contains(s['categoria']) &&
      (a.zonas.contains(s['zona']) || a.zonas.contains(s['zona_padre']));

  Map<String, dynamic>? _delTenant(AliadoFake a, String id) {
    for (final s in _srv.solicitudes) {
      if (s['id'] == id && s['tenant_id'] == a.tenantId) {
        return s;
      }
    }
    return null;
  }

  /// Proyección de `_sol_json`: la dirección solo si es mía.
  Map<String, dynamic> _json(Map<String, dynamic> s) {
    final mia = s['aliado_id'] == _aliadoId;
    return {
      'id': s['id'],
      'estado': s['estado'],
      'es_mia': mia,
      'categoria': s['categoria'],
      'flujo_operativo': s['flujo_operativo'],
      'zona': s['zona'],
      'zona_padre': s['zona_padre'],
      'reglas_sitio': s['reglas_sitio'],
      'direccion': mia ? s['direccion'] : null,
      'created_at': s['created_at'],
      'asignada_at': mia ? s['updated_at'] : null,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    final a = _aliadoActual();
    _exigirVerificado(a);
    return _srv.solicitudes
        .where((s) => s['tenant_id'] == a.tenantId)
        .where(
          (s) =>
              s['aliado_id'] == _aliadoId ||
              (s['estado'] == 'PENDIENTE' &&
                  s['aliado_id'] == null &&
                  _elegible(a, s) &&
                  !_srv.rechazos.containsKey((s['id'] as String, _aliadoId!))),
        )
        .map(_json)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> aceptar(String solicitudId) async {
    final a = _aliadoActual();
    _exigirVerificado(a);
    await Future<void>.delayed(_srv.latencia);

    final s = _delTenant(a, solicitudId);
    if (s == null) {
      throw const PostgrestException(message: 'MANI-SOL-404: no encontrada');
    }
    if (s['aliado_id'] == _aliadoId) {
      return _json(s); // reintento idempotente
    }
    if (!_elegible(a, s)) {
      throw const PostgrestException(message: 'MANI-SOL-403E: no elegible');
    }
    // UPDATE ... WHERE estado = 'PENDIENTE' AND aliado_id IS NULL (atómico).
    if (s['estado'] != 'PENDIENTE' || s['aliado_id'] != null) {
      throw const PostgrestException(message: 'MANI-SOL-409: ya_no_disponible');
    }
    s['aliado_id'] = _aliadoId;
    s['estado'] = 'ASIGNADA';
    s['updated_at'] = DateTime.now().toUtc().toIso8601String();
    _srv.eventos.add({
      'solicitud_id': solicitudId,
      'tipo_evento': 'SOLICITUD_ASIGNADA',
      'actor': _aliadoId,
    });
    _srv.notificaciones.add({
      'solicitud_id': solicitudId,
      'tipo': 'SOLICITUD_ASIGNADA',
    });
    return _json(s);
  }

  @override
  Future<void> rechazar(String solicitudId, String? motivo) async {
    final a = _aliadoActual();
    await Future<void>.delayed(_srv.latencia);
    const validos = {
      'FUERA_DE_ZONA',
      'SIN_DISPONIBILIDAD',
      'NO_ES_MI_ESPECIALIDAD',
      'OTRO',
    };
    if (motivo != null && !validos.contains(motivo)) {
      throw PostgrestException(message: 'MANI-SOL-422M: motivo ($motivo)');
    }
    final s = _delTenant(a, solicitudId);
    if (s == null) {
      throw const PostgrestException(message: 'MANI-SOL-404: no encontrada');
    }
    if (s['aliado_id'] == _aliadoId) {
      throw const PostgrestException(message: 'MANI-SOL-409A: ya es tuya');
    }
    _srv.rechazos.putIfAbsent((solicitudId, _aliadoId!), () => motivo);
  }

  @override
  String? get tenantIdSesion => _srv.aliados[_aliadoId]?.tenantId;
}
