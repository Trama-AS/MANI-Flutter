/// Validaciones de correo y contraseña de los formularios de acceso. Son las
/// mismas reglas que aplica Core (contraseña de 8 caracteres como mínimo);
/// aquí solo adelantan el mensaje para no esperar el 400.
class CredencialesValidators {
  const CredencialesValidators._();

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static const minPassword = 8;

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

  /// Valida que la confirmación coincida con la contraseña escrita.
  static String? confirmacion(String? valor, String password) {
    if (valor == null || valor.isEmpty) return 'Confirma la contraseña';
    if (valor != password) return 'Las contraseñas no coinciden';
    return null;
  }
}
