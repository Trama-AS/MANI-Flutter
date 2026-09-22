import 'dart:async';

import 'package:mani/core/platform/url_opener.dart';
import 'package:mani/features/profiles/verification/data/datasources/verificacion_remote_datasource.dart';
import 'package:mani/features/profiles/verification/domain/entities/decision_verificacion.dart';
import 'package:mani/features/profiles/verification/domain/entities/documento_kyc.dart';
import 'package:mani/features/profiles/verification/domain/entities/solicitud_aliado.dart';
import 'package:mani/features/profiles/verification/domain/failures/verificacion_failure.dart';
import 'package:mani/features/profiles/verification/domain/repositories/verificacion_aliados_repository.dart';
import 'package:mani/features/profiles/verification/domain/usecases/verificacion_usecases.dart';
import 'package:mani/features/profiles/verification/presentation/bloc/bandeja_verificacion_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- builders
DocumentoKyc doc(
  String id, {
  TipoDocumentoKyc tipo = TipoDocumentoKyc.cedulaCiudadania,
  String ruta = 'kyc/t1/cedula.pdf',
}) => DocumentoKyc(
  id: id,
  tipo: tipo,
  rutaStorage: ruta,
  estado: EstadoDocumentoKyc.pendiente,
);

SolicitudAliado aliado({
  String id = 'a1',
  String nombre = 'Carlos Mendoza',
  String email = 'carlos@correo.com',
  TipoAliado tipo = TipoAliado.personaNatural,
  EstadoVerificacion estado = EstadoVerificacion.pendiente,
  int diasEspera = 1,
  List<String> categorias = const ['Plomería'],
  List<DocumentoKyc>? documentos,
  String? motivoRechazo,
  DateTime? fechaVerificacion,
}) => SolicitudAliado(
  id: id,
  nombre: nombre,
  email: email,
  tipo: tipo,
  estado: estado,
  fechaRegistro: DateTime.now().subtract(Duration(days: diasEspera)),
  categorias: categorias,
  documentos: documentos ?? [doc('d-$id')],
  motivoRechazo: motivoRechazo,
  fechaVerificacion: fechaVerificacion,
);

// ------------------------------------------------ repositorio en memoria
/// Repositorio de dominio en memoria. Replica la regla del servidor de que
/// solo se resuelve una solicitud PENDIENTE (409 si no).
class FakeVerificacionRepository implements VerificacionAliadosRepository {
  FakeVerificacionRepository(List<SolicitudAliado> iniciales)
    : _datos = {for (final a in iniciales) a.id: a};

  final Map<String, SolicitudAliado> _datos;

  VerificacionFailure? fallarAlListar;
  VerificacionFailure? fallarAlDetalle;
  VerificacionFailure? fallarAlResolver;
  VerificacionFailure? fallarUrl;

  /// Si se asigna, `resolver` espera a que se complete (para ver "procesando").
  Completer<void>? pausaResolver;

  int llamadasListar = 0;
  int llamadasResolver = 0;
  DecisionVerificacion? ultimaDecision;

  SolicitudAliado? porId(String id) => _datos[id];

  /// Simula que otro administrador resolvió la solicitud en paralelo.
  void resueltoPorOtroAdmin(String id, EstadoVerificacion estado) {
    _datos[id] = _copiar(_datos[id]!, estado: estado);
  }

  void eliminar(String id) => _datos.remove(id);

  @override
  Future<List<SolicitudAliado>> listarSolicitudes() async {
    llamadasListar++;
    if (fallarAlListar != null) throw fallarAlListar!;
    return _datos.values.toList();
  }

  @override
  Future<SolicitudAliado> obtenerDetalle(String aliadoId) async {
    if (fallarAlDetalle != null) throw fallarAlDetalle!;
    return _datos[aliadoId] ??
        (throw const VerificacionFailure(VerificacionErrorTipo.noEncontrado));
  }

  @override
  Future<SolicitudAliado> resolver(
    String aliadoId,
    DecisionVerificacion decision,
  ) async {
    llamadasResolver++;
    ultimaDecision = decision;
    if (pausaResolver != null) await pausaResolver!.future;
    if (fallarAlResolver != null) throw fallarAlResolver!;
    final actual =
        _datos[aliadoId] ??
        (throw const VerificacionFailure(VerificacionErrorTipo.noEncontrado));
    if (!actual.estaPendiente) {
      throw const VerificacionFailure(VerificacionErrorTipo.yaResuelta);
    }
    final nuevo = switch (decision) {
      Aprobacion() => _copiar(actual, estado: EstadoVerificacion.aprobado),
      Rechazo(:final motivo) => _copiar(
        actual,
        estado: EstadoVerificacion.rechazado,
        motivo: motivo,
      ),
    };
    _datos[aliadoId] = nuevo;
    return nuevo;
  }

  @override
  Future<Uri> urlDocumento(DocumentoKyc documento) async {
    if (fallarUrl != null) throw fallarUrl!;
    return Uri.parse('https://storage.test/${documento.rutaStorage}');
  }

  static SolicitudAliado _copiar(
    SolicitudAliado a, {
    required EstadoVerificacion estado,
    String? motivo,
  }) => SolicitudAliado(
    id: a.id,
    nombre: a.nombre,
    email: a.email,
    tipo: a.tipo,
    estado: estado,
    fechaRegistro: a.fechaRegistro,
    categorias: a.categorias,
    documentos: a.documentos,
    motivoRechazo: motivo,
    fechaVerificacion: DateTime.now(),
  );
}

class FakeUrlOpener implements UrlOpener {
  final List<Uri> abiertas = [];
  bool resultado = true;

  @override
  Future<bool> abrir(Uri url) async {
    abiertas.add(url);
    return resultado;
  }
}

BandejaVerificacionCubit crearCubit(
  VerificacionAliadosRepository repo, {
  UrlOpener? opener,
}) => BandejaVerificacionCubit(
  listar: ListarSolicitudesAliados(repo),
  obtenerDetalle: ObtenerDetalleAliado(repo),
  aprobar: AprobarAliado(repo),
  rechazar: RechazarAliado(repo),
  urlDocumento: ObtenerUrlDocumento(repo),
  urlOpener: opener ?? FakeUrlOpener(),
);

// -------------------------------------------- servidor Supabase simulado
/// Simula, a nivel JSON, las RPC de `002_verificacion_aliados.sql`: deriva
/// tenant y rol de la sesión, oculta aliados de otros tenants (404), bloquea
/// dobles decisiones (409) y valida decisión, motivo y documentos (422).
class ServidorVerificacionFake implements VerificacionRemoteDataSource {
  ServidorVerificacionFake({
    this.tenantSesion = 'tenant-a',
    this.rolSesion = 'ADMIN_TENANT',
    this.haySesion = true,
  });

  String tenantSesion;
  String rolSesion;
  bool haySesion;

  /// Filas "en BD": JSON de `_ver_aliado_json` + `tenant_id`.
  final List<Map<String, dynamic>> filas = [];

  /// Rutas que realmente existen en el bucket de Storage.
  final Set<String> archivosSubidos = {};
  final List<Map<String, dynamic>> notificaciones = [];
  Object? errorDeRed;

  void registrarAliado({
    required String id,
    required String tenantId,
    required String nombre,
    String tipo = 'PERSONA_NATURAL',
    String email = 'aliado@correo.com',
    List<String> categorias = const ['Plomería'],
    List<({String id, String tipo, String ruta})> documentos = const [],
    DateTime? fecha,
  }) {
    filas.add({
      'tenant_id': tenantId,
      'id': id,
      'tipo': tipo,
      'nombre': nombre,
      'email': email,
      'estado_verificacion': 'PENDIENTE',
      'fecha_registro': (fecha ?? DateTime.now()).toUtc().toIso8601String(),
      'motivo_rechazo': null,
      'fecha_verificacion': null,
      'categorias': categorias,
      'documentos': [
        for (final d in documentos)
          {
            'id': d.id,
            'tipo_documento': d.tipo,
            'ruta_storage': d.ruta,
            'estado': 'PENDIENTE',
            'fecha_carga': DateTime.now().toUtc().toIso8601String(),
          },
      ],
    });
  }

  String estadoDe(String id) =>
      filas.firstWhere((f) => f['id'] == id)['estado_verificacion'] as String;

  void _exigirAdmin() {
    if (errorDeRed != null) throw errorDeRed!;
    if (!haySesion) {
      throw const PostgrestException(message: 'MANI-VER-401: sesión requerida');
    }
    if (rolSesion != 'ADMIN_TENANT') {
      throw const PostgrestException(
        message: 'MANI-VER-403: solo el administrador del tenant',
      );
    }
  }

  Map<String, dynamic>? _filaDelTenant(String id) {
    for (final f in filas) {
      if (f['id'] == id && f['tenant_id'] == tenantSesion) return f;
    }
    return null;
  }

  static Map<String, dynamic> _publica(Map<String, dynamic> f) =>
      Map<String, dynamic>.from(f)..remove('tenant_id');

  @override
  Future<List<Map<String, dynamic>>> listarAliados() async {
    _exigirAdmin();
    return filas
        .where((f) => f['tenant_id'] == tenantSesion)
        .map(_publica)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> obtenerAliado(String aliadoId) async {
    _exigirAdmin();
    final f = _filaDelTenant(aliadoId);
    if (f == null) {
      throw const PostgrestException(
        message: 'MANI-VER-404: aliado no encontrado',
      );
    }
    return _publica(f);
  }

  @override
  Future<Map<String, dynamic>> resolver(
    String aliadoId,
    String decision,
    String? motivo,
  ) async {
    _exigirAdmin();
    final d = decision.trim().toUpperCase();
    final m = motivo?.trim() ?? '';
    if (d != 'VERIFICADO' && d != 'RECHAZADO') {
      throw PostgrestException(
        message: 'MANI-VER-422D: decisión inválida ($d)',
      );
    }
    if (d == 'RECHAZADO' && (m.length < 10 || m.length > 500)) {
      throw const PostgrestException(message: 'MANI-VER-422M: motivo inválido');
    }
    final f = _filaDelTenant(aliadoId);
    if (f == null) {
      throw const PostgrestException(
        message: 'MANI-VER-404: aliado no encontrado',
      );
    }
    if (f['estado_verificacion'] != 'PENDIENTE') {
      throw PostgrestException(
        message: 'MANI-VER-409: ya resuelta (${f['estado_verificacion']})',
      );
    }
    if (d == 'VERIFICADO' && (f['documentos'] as List).isEmpty) {
      throw const PostgrestException(message: 'MANI-VER-422K: sin documentos');
    }
    f['estado_verificacion'] = d;
    f['motivo_rechazo'] = d == 'RECHAZADO' ? m : null;
    f['fecha_verificacion'] = DateTime.now().toUtc().toIso8601String();
    for (final doc in (f['documentos'] as List).cast<Map<String, dynamic>>()) {
      if (doc['estado'] == 'PENDIENTE') doc['estado'] = d;
    }
    notificaciones.add({
      'aliado_id': aliadoId,
      'decision': d,
      'motivo': d == 'RECHAZADO' ? m : null,
    });
    return _publica(f);
  }

  @override
  Future<String> urlFirmada(String rutaStorage) async {
    if (errorDeRed != null) throw errorDeRed!;
    if (!archivosSubidos.contains(rutaStorage)) {
      throw const StorageException('Object not found', statusCode: '404');
    }
    return 'https://storage.test/sign/$rutaStorage?token=abc';
  }

  @override
  String? get tenantIdSesion => tenantSesion;
}
