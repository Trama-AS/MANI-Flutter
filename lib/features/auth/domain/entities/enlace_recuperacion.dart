/// Lo que trae el enlace del correo de recuperación (HU-M02-10).
///
/// Supabase redirige a la pantalla de restablecimiento con el token en el
/// fragmento de la URL (`#access_token=…&type=recovery`) y, si el enlace ya
/// no sirve, con `#error_code=otp_expired`. Se acepta también en la consulta
/// (`?access_token=…`) por si el proveedor cambia de flujo.
class EnlaceRecuperacion {
  const EnlaceRecuperacion({this.accessToken, this.expirado = false});

  /// Token para enviar a Core; `null` si el enlace no trae uno utilizable.
  final String? accessToken;

  /// El proveedor avisó que el enlace venció o ya se usó.
  final bool expirado;

  bool get esValido => accessToken != null && !expirado;

  /// Lee el enlace del URI que entrega el router y, si no trae nada, de la
  /// URL del navegador: según cómo arranque la app, el fragmento solo está
  /// en uno de los dos.
  factory EnlaceRecuperacion.resolver(Uri deRuta, Uri delNavegador) {
    final enRuta = EnlaceRecuperacion.desde(deRuta);
    if (enRuta.accessToken != null || enRuta.expirado) return enRuta;
    return EnlaceRecuperacion.desde(delNavegador);
  }

  factory EnlaceRecuperacion.desde(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    if (uri.fragment.contains('=')) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } on FormatException {
        // Fragmento de otra cosa (una ruta, un ancla): no aporta parámetros.
      }
    }
    final token = params['access_token']?.trim();
    final tipo = params['type'];
    final error = params['error_code'] ?? params['error'];
    return EnlaceRecuperacion(
      accessToken: (token == null || token.isEmpty) ? null : token,
      expirado: error != null || (tipo != null && tipo != 'recovery'),
    );
  }
}
