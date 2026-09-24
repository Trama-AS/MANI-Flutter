import 'package:equatable/equatable.dart';

/// Tipos de documento que el registro de aliados adjunta hoy
/// (US-02.1.1 persona natural y US-02.1.2 empresa). Un valor desconocido se
/// trata como [otro] en vez de romper la bandeja.
enum TipoDocumentoKyc {
  cedulaCiudadania('Cédula de ciudadanía'),
  rutCertificado('RUT / Certificación'),
  camaraComercio('Cámara de comercio'),
  rutEmpresa('RUT de la empresa'),
  cedulaRepresentante('Cédula del representante legal'),
  otro('Documento adicional');

  const TipoDocumentoKyc(this.etiqueta);

  final String etiqueta;

  static TipoDocumentoKyc desde(String valor) =>
      switch (valor.trim().toUpperCase()) {
        'CEDULA_CIUDADANIA' => cedulaCiudadania,
        'RUT_CERTIFICADO' => rutCertificado,
        'CAMARA_COMERCIO' => camaraComercio,
        'RUT_EMPRESA' => rutEmpresa,
        'CEDULA_REPRESENTANTE' => cedulaRepresentante,
        _ => otro,
      };
}

enum EstadoDocumentoKyc {
  pendiente,
  verificado,
  rechazado;

  static EstadoDocumentoKyc desde(String valor) =>
      switch (valor.trim().toUpperCase()) {
        'VERIFICADO' || 'APROBADO' => verificado,
        'RECHAZADO' => rechazado,
        _ => pendiente,
      };
}

/// Documento KYC adjuntado por el aliado al registrarse.
class DocumentoKyc extends Equatable {
  const DocumentoKyc({
    required this.id,
    required this.tipo,
    required this.rutaStorage,
    required this.estado,
    this.fechaCarga,
  });

  final String id;
  final TipoDocumentoKyc tipo;

  /// Ruta del archivo en Supabase Storage. No es una URL pública: para verlo
  /// se pide una URL firmada de vida corta.
  final String rutaStorage;
  final EstadoDocumentoKyc estado;
  final DateTime? fechaCarga;

  String get nombreArchivo {
    final partes = rutaStorage.split('/');
    return partes.isEmpty ? rutaStorage : partes.last;
  }

  bool get esImagen {
    final n = nombreArchivo.toLowerCase();
    return n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg');
  }

  @override
  List<Object?> get props => [id, tipo, rutaStorage, estado, fechaCarga];
}
