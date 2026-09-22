import 'package:url_launcher/url_launcher.dart';

/// Puerto para abrir URLs fuera de la app (visor del navegador / sistema).
/// Se abstrae para que la presentación sea testeable sin plugins nativos.
abstract interface class UrlOpener {
  Future<bool> abrir(Uri url);
}

class UrlLauncherOpener implements UrlOpener {
  const UrlLauncherOpener();

  @override
  Future<bool> abrir(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
}
