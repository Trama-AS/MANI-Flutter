import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Slug del tenant al que se asigna el cliente que se registra sin selector
/// (`TENANT_SLUG` del `.env`). Core resuelve el tenant por `X-Tenant-Slug`
/// (ADR-0018), así que este valor nunca puede ser el UUID del tenant: en PROD
/// la pantalla enviaba un UUID fijo y Core rechazaba el registro.
const tenantSlugPorDefecto = 'plomeria-express';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Devuelve el slug configurado o [tenantSlugPorDefecto]. Lanza [StateError]
/// si la configuración trae un UUID, para que el error aparezca en el build
/// y no como un registro rechazado en producción.
String tenantSlugRegistro({String? valor}) {
  final configurado = (valor ?? dotenv.maybeGet('TENANT_SLUG') ?? '').trim();
  if (configurado.isEmpty) return tenantSlugPorDefecto;
  if (_uuid.hasMatch(configurado)) {
    throw StateError(
      'TENANT_SLUG debe ser el slug del tenant, no su UUID ($configurado)',
    );
  }
  return configurado;
}
