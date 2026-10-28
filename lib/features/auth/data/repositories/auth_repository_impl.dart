import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mani/core/network/gateway_exception.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:mani/features/auth/domain/entities/user_entity.dart';
import 'package:mani/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mani/features/auth/data/models/user_model.dart';
import 'package:mani/features/auth/domain/entities/registro_cliente_empresa.dart';

/// Implementación del repositorio de autenticación.
///
/// Actúa como anti-corruption layer: captura excepciones específicas del
/// proveedor (Supabase [AuthException]) y las convierte en [AuthFailure]
/// de dominio para que las capas superiores (use cases, cubit) no dependan
/// del SDK de infraestructura. Los errores del API Gateway
/// ([GatewayException]) ya traen un mensaje legible y se propagan tal cual.
class AuthRepositoryImpl implements IAuthRepository {
  const AuthRepositoryImpl({required this.remoteDataSource});

  final IAuthRemoteDataSource remoteDataSource;

  @override
  Future<UserEntity> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final user = await remoteDataSource.signInWithEmail(
        email: email,
        password: password,
      );
      return UserModel.fromSupabase(user);
    } on AuthException catch (e) {
      throw AuthFailure(mensajeDeErrorDeLogin(e));
    } catch (_) {
      // Sin el texto de la excepción: puede traer detalles internos que no son para el usuario.
      throw const AuthFailure(mensajeLoginInesperado);
    }
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
    try {
      return await remoteDataSource.registrarClientePersonaNatural(
        email: email,
        password: password,
        nombreCompleto: nombreCompleto,
        tenantId: tenantId,
        telefono: telefono,
        direccionHogar: direccionHogar,
      );
    } on GatewayException catch (e) {
      throw AuthFailure(e.message);
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e.message));
    } catch (e) {
      throw AuthFailure('Error en registro de cliente: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> registrarClienteEmpresa(
    RegistroClienteEmpresa datos,
  ) async {
    try {
      return await remoteDataSource.registrarClienteEmpresa(datos);
    } on GatewayException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      throw AuthFailure('Error en registro de cliente empresa: $e');
    }
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
    try {
      return await remoteDataSource.registrarAliadoPersonaNatural(
        email: email,
        password: password,
        nombreCompleto: nombreCompleto,
        tenantId: tenantId,
        categoriaId: categoriaId,
        documentosKYC: documentosKYC,
      );
    } on GatewayException catch (e) {
      throw AuthFailure(e.message);
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e.message));
    } catch (e) {
      throw AuthFailure('Error en registro de aliado: $e');
    }
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
    try {
      return await remoteDataSource.registrarAliadoEmpresa(
        email: email,
        password: password,
        razonSocial: razonSocial,
        nit: nit,
        tenantId: tenantId,
        nombreRepresentante: nombreRepresentante,
        docRepresentante: docRepresentante,
        telefonoContacto: telefonoContacto,
        categoriaId: categoriaId,
        documentosKYC: documentosKYC,
      );
    } on GatewayException catch (e) {
      throw AuthFailure(e.message);
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e.message));
    } catch (e) {
      throw AuthFailure('Error en registro de empresa: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await remoteDataSource.signOut();
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthError(e.message));
    }
  }

  static const mensajeCredencialesInvalidas =
      'Correo o contraseña incorrectos.';
  static const mensajeSinConexion =
      'No pudimos conectar. Revisa tu conexión e inténtalo de nuevo.';
  static const mensajeDemasiadosIntentos =
      'Demasiados intentos. Espera un momento.';
  static const mensajeLoginInesperado =
      'No pudimos iniciar sesión. Inténtalo de nuevo.';

  /// Mensaje del inicio de sesión (SCRUM-1370, C2). Una credencial inválida,
  /// un correo que no existe y uno sin confirmar dan EL MISMO mensaje: así el
  /// login no revela si un correo está registrado. Solo se distinguen los
  /// fallos que no dicen nada de la cuenta: demasiados intentos y falta de red.
  static String mensajeDeErrorDeLogin(AuthException e) {
    if (e is AuthRetryableFetchException) return mensajeSinConexion;
    final texto = e.message.toLowerCase();
    if (e.statusCode == '429' ||
        texto.contains('too many requests') ||
        texto.contains('rate limit')) {
      return mensajeDemasiadosIntentos;
    }
    return mensajeCredencialesInvalidas;
  }

  /// Mapea mensajes de error de Supabase a mensajes legibles en español.
  ///
  /// Al estar en el repositorio (capa de datos), se mantiene el conocimiento
  /// de Supabase aislado de la presentación y el dominio.
  String _mapAuthError(String message) {
    if (message.contains('Invalid login credentials') ||
        message.contains('invalid_credentials')) {
      return 'Email o contraseña incorrectos.';
    }
    if (message.contains('Email not confirmed')) {
      return 'Por favor confirma tu email antes de ingresar.';
    }
    if (message.contains('Too many requests')) {
      return 'Demasiados intentos. Espera un momento.';
    }
    if (message.contains('already registered') ||
        message.contains('User already registered')) {
      return 'Ya existe una cuenta registrada con este correo.';
    }
    return message;
  }
}
