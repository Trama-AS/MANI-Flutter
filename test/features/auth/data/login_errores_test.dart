import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mani/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mani/features/auth/domain/entities/auth_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException, User;

class _RemotoQueFalla implements IAuthRemoteDataSource {
  _RemotoQueFalla(this.error);

  final Object error;

  @override
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<String> _mensajeDeLogin(Object error) async {
  final repo = AuthRepositoryImpl(remoteDataSource: _RemotoQueFalla(error));
  try {
    await repo.signInWithEmail(email: 'ana@mani.app', password: 'Password123');
  } on AuthFailure catch (f) {
    return f.message;
  }
  fail('debía lanzar AuthFailure');
}

/// SCRUM-1370, C2: credenciales inválidas muestran un mensaje genérico, sin revelar si el correo existe.
void main() {
  const generico = 'Correo o contraseña incorrectos.';

  test(
    'C2: contraseña incorrecta, correo inexistente y correo sin confirmar dan el MISMO mensaje',
    () async {
      final mensajes = <String>{
        await _mensajeDeLogin(
          const AuthException('Invalid login credentials', statusCode: '400'),
        ),
        await _mensajeDeLogin(const AuthException('invalid_credentials')),
        await _mensajeDeLogin(
          const AuthException('User not found', statusCode: '400'),
        ),
        await _mensajeDeLogin(
          const AuthException('Email not confirmed', statusCode: '400'),
        ),
        await _mensajeDeLogin(const AuthException('User is banned')),
      };

      expect(
        mensajes,
        {generico},
        reason:
            'si cambiara según el caso, el login delataría qué correos existen',
      );
      expect(AuthRepositoryImpl.mensajeCredencialesInvalidas, generico);
    },
  );

  test(
    'C2: el mensaje no repite el texto crudo del servidor ni menciona el correo',
    () async {
      final m = await _mensajeDeLogin(
        const AuthException(
          'AuthApiException: user ana@mani.app locked, hook 0x3f',
        ),
      );
      expect(m, generico);
      expect(m.contains('ana@mani.app'), isFalse);
      expect(m.contains('hook'), isFalse);
    },
  );

  test(
    'demasiados intentos se distingue porque no dice nada de la cuenta',
    () async {
      expect(
        await _mensajeDeLogin(const AuthException('Too many requests')),
        AuthRepositoryImpl.mensajeDemasiadosIntentos,
      );
      expect(
        await _mensajeDeLogin(
          const AuthException('over_request_rate_limit', statusCode: '429'),
        ),
        AuthRepositoryImpl.mensajeDemasiadosIntentos,
      );
    },
  );

  test(
    'un fallo de red no se presenta como credenciales incorrectas',
    () async {
      final m = await _mensajeDeLogin(
        AuthRetryableFetchException(message: 'ClientException: sin red'),
      );
      expect(m, AuthRepositoryImpl.mensajeSinConexion);
      expect(m, isNot(generico));
    },
  );

  test('un error inesperado no expone la excepción al usuario', () async {
    final m = await _mensajeDeLogin(
      StateError('stacktrace interno con detalles'),
    );
    expect(m, AuthRepositoryImpl.mensajeLoginInesperado);
    expect(m.contains('stacktrace'), isFalse);
  });
}
