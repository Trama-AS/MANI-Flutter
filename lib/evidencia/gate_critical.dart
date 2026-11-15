// Evidencia de QA para SCRUM-1681 (QAS-45). NO FUSIONAR.
// La complejidad cognitiva de esta función es 20 (> 15): issue Critical dart:S3776.
// Tiene pruebas completas, así que el gate "Sonar way" pasa por cobertura y el
// único bloqueo debe venir del paso "Sin issues Blocker o Critical nuevos".

String clasificarGateCritical(int valor, bool urgente, bool premium) {
  if (valor < 0) {
    if (urgente) {
      if (premium) {
        return 'a';
      } else {
        return 'b';
      }
    } else {
      return 'c';
    }
  } else if (valor < 10) {
    if (urgente && premium) {
      return 'd';
    }
    if (urgente) {
      return 'e';
    }
    return 'f';
  } else {
    if (premium) {
      if (urgente) {
        return 'g';
      }
      return 'h';
    }
    return 'i';
  }
}
