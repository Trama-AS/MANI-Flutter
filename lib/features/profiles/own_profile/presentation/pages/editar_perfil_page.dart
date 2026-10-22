import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mani/features/profiles/own_profile/data/datasources/perfil_propio_remote_datasource.dart';
import 'package:mani/features/profiles/own_profile/domain/entities/perfil_propio.dart';
import 'package:mani/features/profiles/own_profile/presentation/widgets/foto_perfil_selector_widget.dart';

/// US-02.3.1 (SCRUM-854 / SCRUM-1029 / SCRUM-1030):
/// Formulario donde el usuario (Cliente o Aliado) ve sus datos actuales y puede
/// modificar su nombre, teléfono, dirección y foto de perfil, manteniendo rol y
/// estado como atributos protegidos de solo lectura.
class EditarPerfilPage extends StatefulWidget {
  const EditarPerfilPage({
    super.key,
    required this.dataSource,
    this.selectorImagen,
  });

  final PerfilPropioRemoteDataSource dataSource;
  final SelectorArchivoImagen? selectorImagen;

  @override
  State<EditarPerfilPage> createState() => _EditarPerfilPageState();
}

class _EditarPerfilPageState extends State<EditarPerfilPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();

  static final _phoneRegex = RegExp(r'^\+?[0-9\s()-]{7,20}$');

  PerfilPropio? _perfil;
  bool _cargando = true;
  bool _guardando = false;
  bool _subiendoFoto = false;
  String? _mensajeError;
  String? _mensajeExito;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  Future<void> _cargarPerfil() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });
    try {
      final perfil = await widget.dataSource.obtenerPerfilPropio();
      _aplicarPerfilEnFormulario(perfil);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mensajeError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  void _aplicarPerfilEnFormulario(PerfilPropio perfil) {
    _perfil = perfil;
    _nombreController.text = perfil.fullName;
    _telefonoController.text = perfil.phone ?? '';
    _direccionController.text = perfil.address ?? '';
  }

  Future<void> _subirFoto(String nombreArchivo, Uint8List bytes) async {
    setState(() {
      _subiendoFoto = true;
      _mensajeError = null;
      _mensajeExito = null;
    });
    try {
      final actualizado = await widget.dataSource.subirFotoPerfil(
        nombreArchivo: nombreArchivo,
        bytes: bytes,
      );
      if (mounted) {
        setState(() {
          _perfil = actualizado;
          _mensajeExito = 'Foto de perfil actualizada correctamente';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mensajeError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _subiendoFoto = false;
        });
      }
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _mensajeError = null;
      _mensajeExito = null;
    });
    try {
      final actualizado = await widget.dataSource.actualizarPerfilPropio(
        fullName: _nombreController.text,
        phone: _telefonoController.text,
        address: _direccionController.text,
      );
      if (mounted) {
        setState(() {
          _aplicarPerfilEnFormulario(actualizado);
          _mensajeExito = 'Perfil actualizado exitosamente';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mensajeError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar mi perfil')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_perfil != null) ...[
                      FotoPerfilSelectorWidget(
                        fullName: _perfil!.fullName,
                        photoUrl: _perfil!.photoUrl,
                        subiendo: _subiendoFoto,
                        onFotoSeleccionada: _subirFoto,
                        selectorImagen: widget.selectorImagen,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Chip(
                            key: const Key('chip-rol-solo-lectura'),
                            label: Text('Rol: ${_perfil!.role}'),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            key: const Key('chip-estado-solo-lectura'),
                            label: Text('Estado: ${_perfil!.status}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_mensajeError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _mensajeError!,
                          key: const Key('banner-error-perfil'),
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (_mensajeExito != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _mensajeExito!,
                          key: const Key('banner-exito-perfil'),
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    TextFormField(
                      key: const Key('input-nombre-perfil'),
                      controller: _nombreController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo o razón social',
                      ),
                      validator: (v) {
                        final clean = v?.trim() ?? '';
                        if (clean.length < 2) {
                          return 'El nombre debe tener al menos 2 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('input-telefono-perfil'),
                      controller: _telefonoController,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono de contacto',
                      ),
                      validator: (v) {
                        final clean = v?.trim() ?? '';
                        if (clean.isEmpty || !_phoneRegex.hasMatch(clean)) {
                          return 'Ingresa un teléfono válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('input-direccion-perfil'),
                      controller: _direccionController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección principal',
                      ),
                      validator: (v) {
                        final clean = v?.trim() ?? '';
                        if (clean.length < 5) {
                          return 'La dirección no puede estar vacía (mínimo 5 caracteres)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      key: const Key('btn-guardar-perfil'),
                      onPressed: _guardando ? null : _guardarCambios,
                      child: Text(
                        _guardando ? 'Guardando...' : 'Guardar cambios',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
