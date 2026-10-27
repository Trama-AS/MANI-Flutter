import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/auth/domain/entities/enlace_recuperacion.dart';

void main() {
  Uri uri(String s) => Uri.parse(s);

  group('EnlaceRecuperacion.desde', () {
    test('lee el token del fragmento que deja Supabase', () {
      final e = EnlaceRecuperacion.desde(
        uri(
          'https://app.mani.co/reset-password#access_token=tok-1&refresh_token=r&type=recovery&expires_in=3600',
        ),
      );
      expect(e.accessToken, 'tok-1');
      expect(e.expirado, isFalse);
      expect(e.esValido, isTrue);
    });

    test('acepta el token en la consulta', () {
      final e = EnlaceRecuperacion.desde(
        uri('https://app.mani.co/reset-password?access_token=tok-2'),
      );
      expect(e.accessToken, 'tok-2');
      expect(e.esValido, isTrue);
    });

    test(
      'un enlace vencido (error_code en el fragmento) no es válido aunque traiga otros datos',
      () {
        final e = EnlaceRecuperacion.desde(
          uri(
            'https://app.mani.co/reset-password#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
          ),
        );
        expect(e.accessToken, isNull);
        expect(e.expirado, isTrue);
        expect(e.esValido, isFalse);
      },
    );

    test('un token de otro tipo (no recovery) se descarta', () {
      final e = EnlaceRecuperacion.desde(
        uri('https://app.mani.co/reset-password#access_token=tok&type=signup'),
      );
      expect(e.esValido, isFalse);
    });

    test(
      'sin parámetros, o con un fragmento que no es de parámetros, no hay token',
      () {
        for (final u in [
          'https://app.mani.co/reset-password',
          'https://app.mani.co/reset-password#seccion',
          'https://app.mani.co/reset-password#access_token=',
        ]) {
          expect(EnlaceRecuperacion.desde(uri(u)).esValido, isFalse, reason: u);
        }
      },
    );
  });

  group('EnlaceRecuperacion.resolver', () {
    test('prefiere el URI del router y cae al del navegador si no trae nada', () {
      final enRuta = uri(
        'https://app.mani.co/reset-password#access_token=ruta&type=recovery',
      );
      final enNavegador = uri(
        'https://app.mani.co/reset-password#access_token=navegador&type=recovery',
      );
      final vacio = uri('https://app.mani.co/reset-password');

      expect(
        EnlaceRecuperacion.resolver(enRuta, enNavegador).accessToken,
        'ruta',
      );
      expect(
        EnlaceRecuperacion.resolver(vacio, enNavegador).accessToken,
        'navegador',
      );
      expect(EnlaceRecuperacion.resolver(vacio, vacio).esValido, isFalse);
    });

    test('un enlace vencido en la ruta no se pisa con el del navegador', () {
      final vencido = uri(
        'https://app.mani.co/reset-password#error_code=otp_expired',
      );
      final otro = uri(
        'https://app.mani.co/reset-password#access_token=viejo&type=recovery',
      );
      expect(EnlaceRecuperacion.resolver(vencido, otro).esValido, isFalse);
    });
  });
}
