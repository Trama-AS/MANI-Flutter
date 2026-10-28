import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SCRUM-1380 (HU-M02-12) · ADR-0027 · transversal T6.
///
/// Interpretación aprobada por la PO el 27-oct: la app usa `supabase.auth` SOLO para iniciar sesión, renovar el token y
/// cerrar sesión. Leer o escribir datos de dominio con `.from()`, `.rpc()` o `.storage` está prohibido: todo eso va por
/// el Gateway. Esta prueba lo vigila sobre el código de `lib/` para que una regresión falle en el CI y no en QA.
///
/// Las dos excepciones que existen hoy están nombradas abajo, con su motivo. Si una se migra al Gateway, la prueba
/// obliga a quitarla de la lista; si aparece una nueva, la prueba falla.
class _Regla {
  const _Regla(this.nombre, this.patron, this.porQue);

  final String nombre;
  final RegExp patron;
  final String porQue;
}

final _reglas = <_Regla>[
  _Regla(
    'rpc',
    RegExp(r'\.rpc\('),
    'Las RPC de dominio van por el Gateway (T6).',
  ),
  _Regla(
    'storage',
    RegExp(r'\.storage\b'),
    'Los archivos van por el Gateway; Core firma las URL (T6).',
  ),
  _Regla(
    'functions',
    RegExp(r'\.functions\b'),
    'Las Edge Functions no son parte de la arquitectura de la app (T6).',
  ),
  _Regla(
    'realtime',
    RegExp(r'\.(realtime\b|channel\()'),
    'No hay Realtime: el chat consulta al servidor (SCRUM-881).',
  ),
  _Regla(
    'from-tabla',
    RegExp('\\.from\\(\\s*[\'"]'),
    'Las tablas de dominio no se leen ni se escriben desde la app (T1, T6).',
  ),
  _Regla(
    'userMetadata',
    RegExp(r'\buserMetadata\b'),
    'El tenant y el rol salen del token verificado, no de user_metadata, que el usuario puede editar (T4).',
  ),
];

/// Excepciones conocidas: archivo -> regla -> cuántas veces. Son deuda, no un permiso.
///
/// Vacía desde SCRUM-1380: la cobertura y las categorías del aliado ya salen por el Gateway. Una entrada nueva
/// necesita una decisión de Arquitectura y de la PO, no solo este archivo.
const _excepciones = <String, Map<String, int>>{};

/// Lo único que la app puede hacer con `supabase.auth`: sesión.
const _miembrosDeAuthPermitidos = {
  'currentUser',
  'currentSession',
  'onAuthStateChange',
  'signInWithPassword',
  'refreshSession',
  'signOut',
};

/// Quita los comentarios para no marcar lo que solo se menciona en un texto.
String _sinComentarios(String codigo) {
  final sinBloques = codigo.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return sinBloques
      .split('\n')
      .map((linea) {
        final i = linea.indexOf(RegExp(r'(?<!:)//'));
        return i < 0 ? linea : linea.substring(0, i);
      })
      .join('\n');
}

Map<String, int> _conteo(String codigo) {
  final limpio = _sinComentarios(codigo);
  return {
    for (final r in _reglas)
      if (r.patron.allMatches(limpio).isNotEmpty)
        r.nombre: r.patron.allMatches(limpio).length,
  };
}

Set<String> _miembrosDeAuth(String codigo) => RegExp(
  r'\bauth\.([A-Za-z_]+)',
).allMatches(_sinComentarios(codigo)).map((m) => m.group(1)!).toSet();

Map<String, String> _fuentes() => {
  for (final e in Directory('lib').listSync(recursive: true).whereType<File>())
    if (e.path.endsWith('.dart'))
      e.path.replaceAll(r'\', '/'): e.readAsStringSync(),
};

void main() {
  group('el escáner detecta lo que dice detectar', () {
    test('marca RPC, storage, functions, realtime, tablas y user_metadata', () {
      expect(_conteo("await client.rpc('fn');"), {'rpc': 1});
      expect(_conteo("client.storage.from('docs').upload(a, b);"), {
        'storage': 1,
        'from-tabla': 1,
      });
      expect(_conteo("await client.from('usuario').select();"), {
        'from-tabla': 1,
      });
      expect(_conteo('await client.functions.invoke(x);'), {'functions': 1});
      expect(_conteo("client.channel('chat').subscribe();"), {'realtime': 1});
      expect(_conteo("final t = user.userMetadata?['tenant_id'];"), {
        'userMetadata': 1,
      });
    });

    test('no marca código legítimo ni lo que solo aparece en comentarios', () {
      expect(
        _conteo(
          'final m = Map<String, dynamic>.from(e); final s = Set<String>.from(xs);',
        ),
        isEmpty,
      );
      expect(
        _conteo('// antes se llamaba client.rpc(fn) y .from("x")'),
        isEmpty,
      );
      expect(
        _conteo('/* userMetadata y .storage ya no se usan */ final a = 1;'),
        isEmpty,
      );
      expect(
        _conteo("final u = Uri.parse('https://api.mani.app/x');"),
        isEmpty,
      );
    });

    test('lee los miembros de auth y distingue los de sesión de los demás', () {
      expect(
        _miembrosDeAuth('client.auth.signInWithPassword(a); auth.signOut();'),
        {'signInWithPassword', 'signOut'},
      );
      expect(_miembrosDeAuth('// auth.uid() en el SQL'), isEmpty);
      expect(
        _miembrosDeAuth(
          'client.auth.admin.deleteUser(id);',
        ).difference(_miembrosDeAuthPermitidos),
        {'admin'},
      );
    });
  });

  group('la app respeta ADR-0027 y T6', () {
    final fuentes = _fuentes();

    test('hay código que revisar', () {
      expect(fuentes.length, greaterThan(100));
    });

    test(
      'C1: la app no lee ni escribe datos de dominio con el SDK de Supabase, salvo las excepciones nombradas',
      () {
        final nuevas = <String>[];
        for (final e in fuentes.entries) {
          final permitidas = _excepciones[e.key] ?? const <String, int>{};
          _conteo(e.value).forEach((regla, veces) {
            if (veces > (permitidas[regla] ?? 0)) {
              final r = _reglas.firstWhere((x) => x.nombre == regla);
              nuevas.add('${e.key}: "$regla" x$veces. ${r.porQue}');
            }
          });
        }
        expect(
          nuevas,
          isEmpty,
          reason:
              'Acceso directo a Supabase fuera del Gateway:\n${nuevas.join('\n')}',
        );
      },
    );

    test(
      'las excepciones nombradas siguen existiendo: si ya se migraron, hay que quitarlas de la lista',
      () {
        final obsoletas = <String>[];
        _excepciones.forEach((archivo, reglas) {
          final codigo = fuentes[archivo];
          if (codigo == null) {
            obsoletas.add('$archivo ya no existe');
            return;
          }
          final real = _conteo(codigo);
          reglas.forEach((regla, esperadas) {
            if ((real[regla] ?? 0) != esperadas) {
              obsoletas.add(
                '$archivo: se esperaban $esperadas "$regla" y hay ${real[regla] ?? 0}',
              );
            }
          });
        });
        expect(obsoletas, isEmpty, reason: obsoletas.join('\n'));
      },
    );

    test(
      'C1: supabase.auth solo se usa para iniciar, renovar y cerrar sesión (y leerla)',
      () {
        final fuera = <String>[];
        for (final e in fuentes.entries) {
          final no = _miembrosDeAuth(
            e.value,
          ).difference(_miembrosDeAuthPermitidos);
          if (no.isNotEmpty) fuera.add('${e.key}: auth.${no.join(', auth.')}');
        }
        expect(
          fuera,
          isEmpty,
          reason:
              'Uso de supabase.auth fuera de la sesión:\n${fuera.join('\n')}',
        );
      },
    );

    test('el cliente de Supabase se crea en un solo lugar, main.dart', () {
      final donde = [
        for (final e in fuentes.entries)
          if (_sinComentarios(e.value).contains('Supabase.initialize(')) e.key,
      ];
      expect(donde, ['lib/main.dart']);
    });

    test(
      'C3: el tenant y el rol no salen de user_metadata en ningún lugar del código',
      () {
        final usos = [
          for (final e in fuentes.entries)
            if (RegExp(r'\buserMetadata\b').hasMatch(_sinComentarios(e.value)))
              e.key,
        ];
        expect(usos, isEmpty);
      },
    );

    test(
      'C3: el único encabezado de tenant que envía la app es el slug previo al login (ADR-0018)',
      () {
        final encabezados = <String>{};
        for (final e in fuentes.entries) {
          for (final m in RegExp(
            '[\'"](X-Tenant[A-Za-z-]*)[\'"]',
          ).allMatches(_sinComentarios(e.value))) {
            encabezados.add(m.group(1)!);
          }
        }
        expect(encabezados, {
          'X-Tenant-Slug',
        }, reason: 'Nada de X-Tenant-Id ni de rol en encabezados');
      },
    );
  });
}
