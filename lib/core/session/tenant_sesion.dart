import 'package:mani/core/session/rol_usuario.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show GoTrueClient;

/// Tenant de la sesión abierta, para trazas (SCRUM-1380, C3). Sale del claim
/// del access token y, si no está, de `app_metadata` (que solo escribe el
/// servidor). **Nunca** de `user_metadata`, que el usuario puede editar. No
/// autoriza nada: Core toma el tenant del JWT verificado.
String? tenantIdDeSesion(GoTrueClient auth) =>
    tenantDesdeAccessToken(auth.currentSession?.accessToken) ??
    auth.currentUser?.appMetadata['tenant_id'] as String?;
