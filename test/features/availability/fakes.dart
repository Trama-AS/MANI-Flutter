import 'package:mani/features/availability/domain/entities/ausencia.dart';
import 'package:mani/features/availability/domain/failures/disponibilidad_failure.dart';
import 'package:mani/features/availability/domain/repositories/i_disponibilidad_repository.dart';
import 'package:mani/features/availability/presentation/bloc/disponibilidad_cubit.dart';

/// "Ahora" fijo de las pruebas: sábado 17 oct 2026, 10:00 hora local.
final ahoraFijo = DateTime(2026, 10, 17, 10);

final vacaciones = Ausencia(
  id: 'aus-1',
  inicio: DateTime(2026, 10, 20, 8),
  fin: DateTime(2026, 10, 25, 18),
  motivo: MotivoAusencia.vacaciones,
  nota: 'Viaje familiar',
);

/// Repositorio en memoria con las reglas de Core: sin solapamientos y
/// `disponibleAhora` según si alguna ausencia cubre [ahoraFijo].
class FakeDisponibilidadRepository implements IDisponibilidadRepository {
  FakeDisponibilidadRepository({
    List<Ausencia> ausencias = const [],
    this.fallaCarga,
    this.fallaGuardado,
  }) : ausencias = [...ausencias];

  List<Ausencia> ausencias;
  DisponibilidadFailure? fallaCarga;
  DisponibilidadFailure? fallaGuardado;
  int llamadasCarga = 0;
  int _secuencia = 100;

  bool _cruza(DateTime inicio, DateTime fin, String? excepto) => ausencias.any(
    (a) => a.id != excepto && a.inicio.isBefore(fin) && inicio.isBefore(a.fin),
  );

  Ausencia _desde(String id, BorradorAusencia b) => Ausencia(
    id: id,
    inicio: b.inicio,
    fin: b.fin,
    motivo: b.motivo,
    nota: b.nota,
    activa: !ahoraFijo.isBefore(b.inicio) && ahoraFijo.isBefore(b.fin),
  );

  @override
  Future<DisponibilidadAliado> obtener() async {
    llamadasCarga++;
    if (fallaCarga != null) throw fallaCarga!;
    final vigentes = ausencias.where((a) => a.fin.isAfter(ahoraFijo)).toList()
      ..sort((a, b) => a.inicio.compareTo(b.inicio));
    return DisponibilidadAliado(
      ausencias: vigentes,
      disponibleAhora: !vigentes.any(
        (a) => !ahoraFijo.isBefore(a.inicio) && ahoraFijo.isBefore(a.fin),
      ),
    );
  }

  @override
  Future<Ausencia> crear(BorradorAusencia borrador) async {
    if (fallaGuardado != null) throw fallaGuardado!;
    if (_cruza(borrador.inicio, borrador.fin, null)) {
      throw const DisponibilidadFailure(DisponibilidadErrorTipo.solapamiento);
    }
    final nueva = _desde('aus-${_secuencia++}', borrador);
    ausencias.add(nueva);
    return nueva;
  }

  @override
  Future<Ausencia> editar(String id, BorradorAusencia borrador) async {
    if (fallaGuardado != null) throw fallaGuardado!;
    final i = ausencias.indexWhere((a) => a.id == id);
    if (i < 0) {
      throw const DisponibilidadFailure(DisponibilidadErrorTipo.noEncontrada);
    }
    if (_cruza(borrador.inicio, borrador.fin, id)) {
      throw const DisponibilidadFailure(DisponibilidadErrorTipo.solapamiento);
    }
    return ausencias[i] = _desde(id, borrador);
  }

  @override
  Future<void> eliminar(String id) async {
    if (fallaGuardado != null) throw fallaGuardado!;
    final antes = ausencias.length;
    ausencias.removeWhere((a) => a.id == id);
    if (ausencias.length == antes) {
      throw const DisponibilidadFailure(DisponibilidadErrorTipo.noEncontrada);
    }
  }
}

DisponibilidadCubit cubitCon(FakeDisponibilidadRepository repo) =>
    DisponibilidadCubit(repository: repo, ahora: () => ahoraFijo);
