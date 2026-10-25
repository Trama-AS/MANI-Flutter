/// Validaciones del formulario de cliente empresa (HU-M02-07). Son las mismas
/// reglas que aplica Core en `POST /auth/register/client/company`; aquí solo
/// adelantan el mensaje para no esperar el 400.
class ClienteEmpresaValidators {
  const ClienteEmpresaValidators._();

  /// NIT colombiano: 9 o 10 dígitos y dígito de verificación opcional tras
  /// guion. Se permiten puntos y espacios al escribirlo (`900.123.456-7`).
  static final RegExp _nit = RegExp(r'^\d{9,10}(-\d)?$');
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static const minPassword = 8;

  /// Quita puntos y espacios, igual que Core antes de guardar el NIT.
  static String normalizarNit(String nit) =>
      nit.replaceAll(RegExp(r'[.\s]'), '');

  /// Devuelve [mensaje] si el campo está vacío.
  static String? obligatorio(String? valor, String mensaje) =>
      (valor == null || valor.trim().isEmpty) ? mensaje : null;

  static String? nit(String? valor) {
    if (valor == null || valor.trim().isEmpty) return 'El NIT es obligatorio';
    if (!_nit.hasMatch(normalizarNit(valor))) {
      return 'NIT inválido: 9 o 10 dígitos, con dígito de verificación opcional (900123456-7)';
    }
    return null;
  }

  static String? email(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'El correo es obligatorio';
    }
    if (!_email.hasMatch(valor.trim())) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  static String? password(String? valor) {
    if (valor == null || valor.isEmpty) return 'La contraseña es obligatoria';
    if (valor.length < minPassword) return 'Mínimo $minPassword caracteres';
    return null;
  }
}
