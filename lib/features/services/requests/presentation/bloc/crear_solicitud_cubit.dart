import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mani/core/platform/selector_fotos.dart';
import 'package:mani/core/utils/generador_id.dart';

import '../../domain/entities/catalogo_solicitud.dart';
import '../../domain/entities/foto_adjunta.dart';
import '../../domain/entities/nueva_solicitud.dart';
import '../../domain/entities/solicitud_publicada.dart';
import '../../domain/failures/solicitud_failure.dart';
import '../../domain/usecases/solicitud_usecases.dart';

part 'crear_solicitud_state.dart';

/// Estado y acciones del asistente "Nueva solicitud" (US-04.1.1).
class CrearSolicitudCubit extends Cubit<CrearSolicitudState> {
  CrearSolicitudCubit({
    required CargarCatalogoSolicitud cargarCatalogo,
    required BuscarZonas buscarZonas,
    required PublicarSolicitud publicar,
    String Function() generarClave = nuevoUuid,
  }) : _cargarCatalogo = cargarCatalogo,
       _buscarZonas = buscarZonas,
       _publicar = publicar,
       _generarClave = generarClave,
       super(CrearSolicitudState(clave: generarClave()));

  final CargarCatalogoSolicitud _cargarCatalogo;
  final BuscarZonas _buscarZonas;
  final PublicarSolicitud _publicar;
  final String Function() _generarClave;
  int _secuenciaAvisos = 0;
  int _tokenZonas = 0;

  // ------------------------------------------------------------------ carga
  Future<void> cargar() async {
    emit(state.copyWith(carga: CargaFormulario.cargando, error: null));
    try {
      final catalogo = await _cargarCatalogo();
      if (isClosed) {
        return;
      }
      // Con direcciones guardadas, se propone la más reciente.
      final conSitios = catalogo.sitios.isNotEmpty;
      emit(
        state.copyWith(
          carga: CargaFormulario.listo,
          catalogo: catalogo,
          modo: conSitios
              ? ModoUbicacion.sitioGuardado
              : ModoUbicacion.nuevaDireccion,
          sitioId: conSitios ? catalogo.sitios.first.id : null,
        ),
      );
    } on SolicitudFailure catch (f) {
      if (!isClosed) {
        emit(state.copyWith(carga: CargaFormulario.error, error: f));
      }
    }
  }

  // ------------------------------------------------------------ navegación
  void siguiente() {
    if (!state.puedeAvanzar || state.paso == PasoSolicitud.revision) {
      return;
    }
    emit(state.copyWith(paso: PasoSolicitud.values[state.paso.index + 1]));
  }

  void anterior() {
    if (state.paso.index == 0 || state.publicando) {
      return;
    }
    emit(state.copyWith(paso: PasoSolicitud.values[state.paso.index - 1]));
  }

  /// Salta a un paso anterior (desde "Revisar" → "Editar").
  void irA(PasoSolicitud paso) {
    if (paso.index < state.paso.index && !state.publicando) {
      emit(state.copyWith(paso: paso));
    }
  }

  // ------------------------------------------------------------- categoría
  /// Elegir un servicio avanza solo al paso siguiente: un toque, sin botón.
  void elegirCategoria(String id) {
    emit(state.copyWith(categoriaId: id, paso: PasoSolicitud.detalle));
  }

  // --------------------------------------------------------------- detalle
  void actualizarDescripcion(String texto) =>
      emit(state.copyWith(descripcion: texto));

  /// Valida y agrega fotos; las que no cumplen se informan sin perder las
  /// demás.
  void agregarFotos(List<ArchivoLocal> archivos) {
    final fotos = [...state.fotos];
    SolicitudFailure? primerRechazo;
    var rechazadas = 0;
    for (final a in archivos) {
      if (fotos.length >= NuevaSolicitud.maxFotos) {
        primerRechazo ??= const SolicitudFailure(
          SolicitudErrorTipo.demasiadasFotos,
        );
        rechazadas++;
        continue;
      }
      try {
        fotos.add(FotoAdjunta.crear(nombre: a.nombre, bytes: a.bytes));
      } on SolicitudFailure catch (f) {
        primerRechazo ??= f;
        rechazadas++;
      }
    }
    emit(state.copyWith(fotos: fotos));
    if (primerRechazo != null) {
      _avisar(
        rechazadas == 1
            ? primerRechazo.mensajeUsuario
            : '$rechazadas fotos no se agregaron. ${primerRechazo.mensajeUsuario}',
        esError: true,
      );
    }
  }

  void quitarFoto(int indice) {
    if (indice < 0 || indice >= state.fotos.length) {
      return;
    }
    emit(state.copyWith(fotos: [...state.fotos]..removeAt(indice)));
  }

  // ------------------------------------------------------------- ubicación
  void elegirSitio(String id) =>
      emit(state.copyWith(modo: ModoUbicacion.sitioGuardado, sitioId: id));

  void usarNuevaDireccion() =>
      emit(state.copyWith(modo: ModoUbicacion.nuevaDireccion));

  void actualizarDireccion(String texto) =>
      emit(state.copyWith(direccion: texto));

  /// Busca zonas descartando respuestas viejas si el usuario sigue escribiendo.
  Future<void> buscarZonas(String texto) async {
    final token = ++_tokenZonas;
    if (texto.trim().length < BuscarZonas.minimo) {
      emit(state.copyWith(zonasEncontradas: const [], buscandoZonas: false));
      return;
    }
    emit(state.copyWith(buscandoZonas: true));
    try {
      final zonas = await _buscarZonas(texto);
      if (isClosed || token != _tokenZonas) {
        return;
      }
      emit(state.copyWith(zonasEncontradas: zonas, buscandoZonas: false));
    } on SolicitudFailure catch (f) {
      if (isClosed || token != _tokenZonas) {
        return;
      }
      emit(state.copyWith(buscandoZonas: false));
      _avisar(f.mensajeUsuario, esError: true);
    }
  }

  void elegirZona(ZonaOpcion zona) {
    _tokenZonas++;
    emit(
      state.copyWith(
        zona: zona,
        zonasEncontradas: const [],
        buscandoZonas: false,
      ),
    );
  }

  void quitarZona() => emit(state.copyWith(zona: null));

  // -------------------------------------------------------------- publicar
  /// Devuelve `true` si la solicitud quedó publicada. Ante error conserva
  /// todo lo escrito y la misma clave, así reintentar no duplica.
  Future<bool> publicar() async {
    if (state.publicando || !state.completo(PasoSolicitud.revision)) {
      return false;
    }
    final NuevaSolicitud nueva;
    try {
      nueva = NuevaSolicitud.crear(
        categoria: state.categoria,
        descripcion: state.descripcion,
        fotos: state.fotos,
        ubicacion: switch (state.modo) {
          ModoUbicacion.sitioGuardado => SitioExistente(state.sitio!),
          ModoUbicacion.nuevaDireccion => NuevaDireccion.crear(
            direccion: state.direccion,
            zona: state.zona,
          ),
        },
        claveIdempotencia: state.clave,
      );
    } on SolicitudFailure catch (f) {
      emit(state.copyWith(errorEnvio: f));
      return false;
    }

    emit(state.copyWith(publicando: true, errorEnvio: null));
    try {
      final publicada = await _publicar(nueva);
      if (!isClosed) {
        emit(state.copyWith(publicando: false, publicada: publicada));
      }
      return true;
    } on SolicitudFailure catch (f) {
      if (isClosed) {
        return false;
      }
      emit(
        state.copyWith(
          publicando: false,
          errorEnvio: f,
          paso: _pasoDelError(f) ?? state.paso,
        ),
      );
      _avisar(f.mensajeUsuario, esError: true);
      return false;
    }
  }

  /// Lleva al paso donde se corrige el error, si corresponde a uno.
  PasoSolicitud? _pasoDelError(SolicitudFailure f) => switch (f.tipo) {
    SolicitudErrorTipo.categoriaInvalida => PasoSolicitud.categoria,
    SolicitudErrorTipo.descripcionInvalida => PasoSolicitud.detalle,
    SolicitudErrorTipo.ubicacionInvalida ||
    SolicitudErrorTipo.zonaInvalida => PasoSolicitud.ubicacion,
    _ => null,
  };

  /// Empieza otra solicitud desde cero con una clave nueva. Recarga el
  /// catálogo: la dirección recién creada aparece entre las guardadas.
  Future<void> nuevaSolicitud() async {
    emit(CrearSolicitudState(clave: _generarClave()));
    await cargar();
  }

  void _avisar(String mensaje, {bool esError = false}) {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        aviso: AvisoSolicitud(++_secuenciaAvisos, mensaje, esError: esError),
      ),
    );
  }
}
