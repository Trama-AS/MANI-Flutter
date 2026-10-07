import 'dart:convert';

import 'package:mani/core/network/gateway_client.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class IAuthRemoteDataSource {
  Future<User> signInWithEmail({
    required String email,
    required String password,
  });

  Future<Map<String, dynamic>> registrarClientePersonaNatural({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    String? telefono,
    String? direccionHogar,
  });

  Future<Map<String, dynamic>> registrarAliadoPersonaNatural({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    required String categoriaId,
    required List<Map<String, String>> documentosKYC,
  });

  Future<Map<String, dynamic>> registrarAliadoEmpresa({
    required String email,
    required String password,
    required String razonSocial,
    required String nit,
    required String tenantId,
    required String nombreRepresentante,
    String? docRepresentante,
    String? telefonoContacto,
    String? categoriaId,
    required List<Map<String, String>> documentosKYC,
  });

  Future<void> signOut();
}

class AuthRemoteDataSource implements IAuthRemoteDataSource {
  final SupabaseClient client;
  final GatewayClient gateway;

  AuthRemoteDataSource({required this.client, required this.gateway});

  /// Registro de aliado empresa en Core Node, a través del Gateway
  /// (US-02.1.2-M2). Contrato provisional hasta que CFG-16 lo publique.
  static const rutaRegistroEmpresa = '/api/v1/core/aliados/empresa';

  /// Registro de aliado persona natural en Core Node, a través del Gateway
  /// (US-02.1.1-M2). Ruta y nombres de campo definidos por el contrato
  /// OpenAPI de CFG-16 (MANI-APIGateway/docs/openapi/core.yaml).
  static const rutaRegistroPersonaNatural = '/api/v1/core/auth/register/ally';

  /// Registro de cliente persona natural en Core Node, a través del Gateway
  /// (US-02.2.1-M2). Reutiliza el MISMO [GatewayClient] (sin crear un
  /// segundo cliente HTTP) y el endpoint de identidad que Core ya expone
  /// para Aliado (mismo authIdentityService del lado del servicio).
  static const rutaRegistroClientePersonaNatural =
      '/api/v1/core/auth/register/client';

  /// Resuelve el tenant antes de autenticarse (ADR-0018). No autoriza nada:
  /// Core toma el tenant definitivo del JWT que emite tras el registro.
  static const headerTenantSlug = 'X-Tenant-Slug';

  @override
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.user == null) {
      throw const AuthException('No user returned');
    }
    return response.user!;
  }

  @override
  Future<Map<String, dynamic>> registrarClientePersonaNatural({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    String? telefono,
    String? direccionHogar,
  }) async {
    // US-02.2.1-M2: migrado de Supabase directo (auth.signUp + .rpc()/.from()
    // de respaldo) al camino Gateway -> Core Node, igual que el registro de
    // Aliado (US-02.1.1-M2). Mismo GatewayClient (gateway), mismo endpoint
    // de identidad del lado de Core (CA-2): no se crea un segundo cliente
    // HTTP ni una segunda implementación de autenticación.
    //
    // direccionHogar queda sin enviar: la creación del `sitio` inicial
    // (hogar) que hacía la función PL/pgSQL legacy todavía no tiene
    // equivalente en Core Node (fuera del alcance de esta subtarea,
    // enfocada en reutilizar identidad/HTTP, no en portar `sitio`/`zona`).
    final campos = <String, dynamic>{
      'email': email.trim(),
      'password': password,
      'fullName': nombreCompleto.trim(),
      if (telefono != null && telefono.trim().isNotEmpty)
        'phone': telefono.trim(),
    };

    final respuesta = await gateway.postJson(
      rutaRegistroClientePersonaNatural,
      campos,
      headers: {headerTenantSlug: tenantId},
    );

    return {
      ...respuesta,
      'success': true,
      'usuario_id': respuesta['profile']?['id'],
      'rol': respuesta['profile']?['role'],
      'estado': respuesta['profile']?['status'],
      'mensaje': 'Cuenta de cliente creada exitosamente.',
    };
  }

  @override
  Future<Map<String, dynamic>> registrarAliadoPersonaNatural({
    required String email,
    required String password,
    required String nombreCompleto,
    required String tenantId,
    required String categoriaId,
    required List<Map<String, String>> documentosKYC,
  }) async {
    // Tenant solo en X-Tenant-Slug y rutas de Storage construidas por Core
    // (ADR-0013, ADR-0018). Nombres de campo en camelCase: así los define el contrato
    // OpenAPI de CFG-16 (fullName/categoriaId), no snake_case español.
    final campos = <String, String>{
      'email': email.trim(),
      'password': password,
      'fullName': nombreCompleto.trim(),
      'categoriaId': categoriaId.trim(),
    };

    final respuesta = await gateway.postMultipart(
      rutaRegistroPersonaNatural,
      campos: campos,
      archivos: [for (final doc in documentosKYC) _archivo(doc)],
      headers: {headerTenantSlug: tenantId},
    );

    return {
      ...respuesta,
      'success': true,
      'estado_verificacion': respuesta['estado_verificacion'] ?? 'PENDIENTE',
    };
  }

  @override
  Future<Map<String, dynamic>> registrarAliadoEmpresa({
    required String email,
    required String password,
    required String razonSocial,
    required String nit,
    required String tenantId,
    required String nombreRepresentante,
    String? docRepresentante,
    String? telefonoContacto,
    String? categoriaId,
    required List<Map<String, String>> documentosKYC,
  }) async {
    // El tenant va solo en X-Tenant-Slug (ADR-0018), nunca en el cuerpo, y la ruta del
    // documento en Storage la construye Core (tenant_id/aliado_id/documento,
    // ADR-0013): el cliente no envía rutas.
    final campos = <String, String>{
      'email': email.trim(),
      'password': password,
      'razon_social': razonSocial.trim(),
      'nit': nit.trim(),
      'nombre_representante': nombreRepresentante.trim(),
      'doc_representante': ?_texto(docRepresentante),
      'telefono_contacto': ?_texto(telefonoContacto),
      'categoria_id': ?_texto(categoriaId),
    };

    final respuesta = await gateway.postMultipart(
      rutaRegistroEmpresa,
      campos: campos,
      archivos: [for (final doc in documentosKYC) _archivo(doc)],
      headers: {headerTenantSlug: tenantId},
    );

    return {
      ...respuesta,
      'success': true,
      'estado_verificacion': respuesta['estado_verificacion'] ?? 'PENDIENTE',
    };
  }

  /// Convierte un documento KYC (`tipo_documento`, `nombre_archivo`,
  /// `contenido_base64`) en una parte multipart cuyo campo es el tipo en
  /// minúsculas, p. ej. `camara_comercio`.
  ArchivoMultipart _archivo(Map<String, String> doc) {
    final tipo = doc['tipo_documento'] ?? '';
    final contenido = doc['contenido_base64'];
    if (tipo.isEmpty || contenido == null || contenido.isEmpty) {
      throw GatewayException(
        message:
            'No se pudo leer el documento ${tipo.isEmpty ? '' : '$tipo '}'
            'adjunto. Vuelve a seleccionarlo.',
      );
    }
    return ArchivoMultipart(
      campo: tipo.toLowerCase(),
      nombre: doc['nombre_archivo'] ?? tipo.toLowerCase(),
      bytes: base64Decode(contenido),
    );
  }

  String? _texto(String? valor) {
    final limpio = valor?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
  }
}
