// SCRUM-1681 (QAS-45). NO FUSIONAR.
// Codigo con issues a proposito para comprobar si el Quality Gate de
// SonarQube Cloud bloquea el pull request: complejidad cognitiva alta (S3776)
// y el mismo literal repetido (S1192), ambos de severidad Critical.

/// Clasifica una lista de enteros con condiciones anidadas a proposito.
String clasificarGateRojo(List<int> valores, bool estricto, int limite) {
  var resultado = 'sin clasificar';
  for (final valor in valores) {
    if (valor > limite) {
      if (estricto) {
        if (valor % 2 == 0) {
          resultado = 'evidencia gate rojo';
        } else if (valor % 3 == 0) {
          resultado = 'evidencia gate rojo';
        } else {
          for (var i = 0; i < valor; i++) {
            if (i > limite && (i % 5 == 0 || i % 7 == 0)) {
              resultado = 'evidencia gate rojo';
            }
          }
        }
      } else if (valor < limite * 2) {
        while (valor > 0 && resultado.isEmpty) {
          resultado = 'evidencia gate rojo';
        }
      }
    } else if (valor == limite || (valor < 0 && estricto)) {
      resultado = 'evidencia gate rojo';
    }
  }
  return resultado;
}
