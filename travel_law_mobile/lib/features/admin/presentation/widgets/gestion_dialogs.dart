import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/text_utils.dart';
import '../../data/contenido_repository.dart';

// ─────────────────────────────────────────────────────────────
// Utilidades
// ─────────────────────────────────────────────────────────────

Future<bool> mostrarDialogoDestino(
  BuildContext context, {
  DestinoAdmin? destino,
}) async =>
    (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DestinoDialog(destino: destino),
    )) ??
    false;

Future<bool> mostrarDialogoLugar(BuildContext context, {LugarAdmin? lugar}) async =>
    (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LugarDialog(lugar: lugar),
    )) ??
    false;

Future<bool> mostrarDialogoNorma(BuildContext context, {NormaAdmin? norma}) async =>
    (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NormaDialog(norma: norma),
    )) ??
    false;

Future<bool> mostrarDialogoAlerta(
  BuildContext context, {
  AlertaAdmin? alerta,
}) async =>
    (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AlertaDialog(alerta: alerta),
    )) ??
    false;

Future<bool> mostrarDialogoContacto(
  BuildContext context, {
  ContactoAdmin? contacto,
}) async =>
    (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContactoDialog(contacto: contacto),
    )) ??
    false;

String? _obligatorio(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

String? _coordenada(String? v, {required bool lat}) {
  if (v == null || v.trim().isEmpty) return null;
  final valor = parseCoordenada(v);
  if (valor == null) return 'Número no válido';
  final min = lat ? -90.0 : -180.0;
  final max = lat ? 90.0 : 180.0;
  if (valor < min || valor > max) return 'Fuera de rango';
  return null;
}

// ─────────────────────────────────────────────────────────────
// Destinos
// ─────────────────────────────────────────────────────────────

class _DestinoDialog extends ConsumerStatefulWidget {
  const _DestinoDialog({this.destino});

  final DestinoAdmin? destino;

  @override
  ConsumerState<_DestinoDialog> createState() => _DestinoDialogState();
}

class _DestinoDialogState extends ConsumerState<_DestinoDialog> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.destino?.nombre);
  late final _municipio = TextEditingController(text: widget.destino?.municipio);
  late final _lat = TextEditingController(
    text: widget.destino?.posicion.$1.toString() ?? '',
  );
  late final _lng = TextEditingController(
    text: widget.destino?.posicion.$2.toString() ?? '',
  );
  late bool _activo = widget.destino?.activo ?? true;
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      final lat = parseCoordenada(_lat.text)!;
      final lng = parseCoordenada(_lng.text)!;
      if (widget.destino == null) {
        await repo.crearDestino(
          nombre: _nombre.text.trim(),
          municipio: _municipio.text.trim(),
          lat: lat,
          lng: lng,
        );
      } else {
        await repo.actualizarDestino(
          id: widget.destino!.id,
          nombre: _nombre.text.trim(),
          municipio: _municipio.text.trim(),
          lat: lat,
          lng: lng,
          activo: _activo,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = mensajeErrorContenido(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _municipio.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.destino == null ? 'Nuevo destino' : 'Editar destino'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del destino',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  validator: _obligatorio,
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _municipio,
                  decoration: const InputDecoration(
                    labelText: 'Municipio / departamento',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  validator: _obligatorio,
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lat,
                        decoration: const InputDecoration(labelText: 'Latitud'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) => _obligatorio(v) ?? _coordenada(v, lat: true),
                        enabled: !_guardando,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lng,
                        decoration: const InputDecoration(labelText: 'Longitud'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) => _obligatorio(v) ?? _coordenada(v, lat: false),
                        enabled: !_guardando,
                      ),
                    ),
                  ],
                ),
                if (widget.destino != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Destino activo (visible en el mapa)'),
                    value: _activo,
                    onChanged: _guardando ? null : (v) => setState(() => _activo = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(widget.destino == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Lugares
// ─────────────────────────────────────────────────────────────

class _LugarDialog extends ConsumerStatefulWidget {
  const _LugarDialog({this.lugar});

  final LugarAdmin? lugar;

  @override
  ConsumerState<_LugarDialog> createState() => _LugarDialogState();
}

class _LugarDialogState extends ConsumerState<_LugarDialog> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.lugar?.nombre);
  late final _horario = TextEditingController(text: widget.lugar?.horario);
  late final _lat = TextEditingController(
    text: widget.lugar?.posicion.$1.toString() ?? '',
  );
  late final _lng = TextEditingController(
    text: widget.lugar?.posicion.$2.toString() ?? '',
  );
  late int _idDestino = widget.lugar?.idDestino ?? 0;
  late int _idCategoria = widget.lugar?.idCategoria ?? 0;
  late bool _activo = widget.lugar?.activo ?? true;
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      final lat = parseCoordenada(_lat.text)!;
      final lng = parseCoordenada(_lng.text)!;
      if (widget.lugar == null) {
        await repo.crearLugar(
          idDestino: _idDestino,
          idCategoria: _idCategoria,
          nombre: _nombre.text.trim(),
          horario: _horario.text.trim(),
          lat: lat,
          lng: lng,
        );
      } else {
        await repo.actualizarLugar(
          id: widget.lugar!.id,
          idDestino: _idDestino,
          idCategoria: _idCategoria,
          nombre: _nombre.text.trim(),
          horario: _horario.text.trim(),
          lat: lat,
          lng: lng,
          activo: _activo,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = mensajeErrorContenido(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _horario.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destinos =
        ref.watch(destinosAdminProvider).value ?? const <DestinoAdmin>[];
    final categorias =
        ref.watch(categoriasLugarProvider).value ?? const <CategoriaLugar>[];

    return AlertDialog(
      title: Text(widget.lugar == null ? 'Nuevo lugar' : 'Editar lugar'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue:
                      destinos.any((d) => d.id == _idDestino) ? _idDestino : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Destino',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  items: destinos
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          enabled: d.activo,
                          child: Text(d.etiqueta, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _idDestino = v ?? 0),
                  validator: (v) =>
                      v == null ? 'Selecciona una opción' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue:
                      categorias.any((c) => c.id == _idCategoria)
                          ? _idCategoria
                          : null,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: categorias
                      .map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.nombre)),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _idCategoria = v ?? 0),
                  validator: (v) =>
                      v == null ? 'Selecciona una opción' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del lugar',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  validator: _obligatorio,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _horario,
                  decoration: const InputDecoration(
                    labelText: 'Horario (opcional)',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lat,
                        decoration: const InputDecoration(labelText: 'Latitud'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) =>
                            _obligatorio(v) ?? _coordenada(v, lat: true),
                        enabled: !_guardando,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lng,
                        decoration: const InputDecoration(labelText: 'Longitud'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) =>
                            _obligatorio(v) ?? _coordenada(v, lat: false),
                        enabled: !_guardando,
                      ),
                    ),
                  ],
                ),
                if (widget.lugar != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lugar activo (visible en la app)'),
                    value: _activo,
                    onChanged: _guardando ? null : (v) => setState(() => _activo = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(widget.lugar == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Normas
// ─────────────────────────────────────────────────────────────

class _NormaDialog extends ConsumerStatefulWidget {
  const _NormaDialog({this.norma});

  final NormaAdmin? norma;

  @override
  ConsumerState<_NormaDialog> createState() => _NormaDialogState();
}

class _NormaDialogState extends ConsumerState<_NormaDialog> {
  final _form = GlobalKey<FormState>();
  late final _tituloEs = TextEditingController(text: widget.norma?.tituloEs);
  late final _tituloEn = TextEditingController(text: widget.norma?.tituloEn);
  late final _contenidoEs =
      TextEditingController(text: widget.norma?.contenidoEs);
  late final _contenidoEn =
      TextEditingController(text: widget.norma?.contenidoEn);
  late final _fuente = TextEditingController(text: widget.norma?.fuente);
  late String _tipo = widget.norma?.tipo ?? 'legal';
  late int _idDestino = widget.norma?.idDestino ?? 0;
  late bool _vigente = widget.norma?.vigente ?? true;
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      if (widget.norma == null) {
        await repo.crearNorma(
          idDestino: _idDestino,
          tipo: _tipo,
          tituloEs: _tituloEs.text.trim(),
          contenidoEs: _contenidoEs.text.trim(),
          tituloEn: _tituloEn.text.trim(),
          contenidoEn: _contenidoEn.text.trim(),
          fuente: _fuente.text.trim(),
        );
      } else {
        await repo.actualizarNorma(
          id: widget.norma!.id,
          tipo: _tipo,
          tituloEs: _tituloEs.text.trim(),
          contenidoEs: _contenidoEs.text.trim(),
          tituloEn: _tituloEn.text.trim(),
          contenidoEn: _contenidoEn.text.trim(),
          fuente: _fuente.text.trim(),
          vigente: _vigente,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = mensajeErrorContenido(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _tituloEs.dispose();
    _tituloEn.dispose();
    _contenidoEs.dispose();
    _contenidoEn.dispose();
    _fuente.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destinos =
        ref.watch(destinosAdminProvider).value ?? const <DestinoAdmin>[];

    return AlertDialog(
      title: Text(widget.norma == null ? 'Nueva norma' : 'Editar norma'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue:
                      destinos.any((d) => d.id == _idDestino) ? _idDestino : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Destino',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  items: destinos
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.nombre, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _idDestino = v ?? 0),
                  validator: (v) =>
                      v == null ? 'Selecciona una opción' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de norma',
                    prefixIcon: Icon(Icons.gavel_outlined),
                  ),
                  items: NormaAdmin.tipos.entries
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t.key, child: Text(t.value)),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _tipo = v ?? 'legal'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tituloEs,
                  decoration:
                      const InputDecoration(labelText: 'Título (español)'),
                  validator: _obligatorio,
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tituloEn,
                  decoration: const InputDecoration(
                    labelText: 'Título (inglés, opcional)',
                  ),
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contenidoEs,
                  decoration: const InputDecoration(
                    labelText: 'Contenido (español)',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  validator: _obligatorio,
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contenidoEn,
                  decoration: const InputDecoration(
                    labelText: 'Contenido (inglés, opcional)',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fuente,
                  decoration: const InputDecoration(
                    labelText: 'Fuente oficial (opcional)',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                  enabled: !_guardando,
                ),
                if (widget.norma != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Norma vigente (se muestra en Legal y normativa)',
                    ),
                    value: _vigente,
                    onChanged: _guardando ? null : (v) => setState(() => _vigente = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(widget.norma == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Alertas oficiales
// ─────────────────────────────────────────────────────────────

class _AlertaDialog extends ConsumerStatefulWidget {
  const _AlertaDialog({this.alerta});

  final AlertaAdmin? alerta;

  @override
  ConsumerState<_AlertaDialog> createState() => _AlertaDialogState();
}

class _AlertaDialogState extends ConsumerState<_AlertaDialog> {
  final _form = GlobalKey<FormState>();
  late final _descripcion =
      TextEditingController(text: widget.alerta?.descripcion);
  late final _lat = TextEditingController();
  late final _lng = TextEditingController();
  late String _tipo = widget.alerta?.tipo ?? 'riesgo';
  late String _estado = widget.alerta?.estado ?? 'verificada';
  late int _idDestino = widget.alerta?.idDestino ?? 0;
  late DateTime _fechaEvento = widget.alerta?.fechaEvento ?? DateTime.now();
  bool _guardando = false;
  String? _error;

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaEvento,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fechaEvento),
    );
    if (!mounted) return;
    setState(() {
      _fechaEvento = hora == null
          ? fecha
          : DateTime(
              fecha.year,
              fecha.month,
              fecha.day,
              hora.hour,
              hora.minute,
            );
    });
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      if (widget.alerta == null) {
        await repo.crearAlerta(
          idDestino: _idDestino,
          tipo: _tipo,
          descripcion: _descripcion.text.trim(),
          fechaEvento: _fechaEvento,
          lat: parseCoordenada(_lat.text),
          lng: parseCoordenada(_lng.text),
          estado: _estado,
        );
      } else {
        await repo.actualizarAlerta(
          id: widget.alerta!.id,
          tipo: _tipo,
          descripcion: _descripcion.text.trim(),
          fechaEvento: _fechaEvento,
          estado: _estado,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = mensajeErrorContenido(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destinos =
        ref.watch(destinosAdminProvider).value ?? const <DestinoAdmin>[];
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(
        widget.alerta == null ? 'Nueva alerta oficial' : 'Editar alerta',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue:
                      destinos.any((d) => d.id == _idDestino) ? _idDestino : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Destino',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  items: destinos
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.nombre, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _idDestino = v ?? 0),
                  validator: (v) =>
                      v == null ? 'Selecciona una opción' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de alerta',
                    prefixIcon: Icon(Icons.warning_amber_outlined),
                  ),
                  items: AlertaAdmin.tipos.entries
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t.key, child: Text(t.value)),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _tipo = v ?? 'riesgo'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _estado,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    prefixIcon: Icon(Icons.rule_outlined),
                  ),
                  items: AlertaAdmin.estados.entries
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t.key, child: Text(t.value)),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _estado = v ?? 'verificada'),
                ),
                const SizedBox(height: 12),
                Card.outlined(
                  child: ListTile(
                    onTap: _guardando ? null : _elegirFecha,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Fecha del evento'),
                    subtitle: Text(formatearFecha(_fechaEvento)),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcion,
                  decoration: const InputDecoration(
                    labelText: 'Descripción de la alerta',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  validator: _obligatorio,
                  enabled: !_guardando,
                ),
                if (widget.alerta == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Ubicación (opcional; si se deja vacía se usa la del destino)',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _lat,
                          decoration:
                              const InputDecoration(labelText: 'Latitud'),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          validator: (v) => _coordenada(v, lat: true),
                          enabled: !_guardando,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lng,
                          decoration:
                              const InputDecoration(labelText: 'Longitud'),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          validator: (v) => _coordenada(v, lat: false),
                          enabled: !_guardando,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(widget.alerta == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Contactos SOS
// ─────────────────────────────────────────────────────────────

class _ContactoDialog extends ConsumerStatefulWidget {
  const _ContactoDialog({this.contacto});

  final ContactoAdmin? contacto;

  @override
  ConsumerState<_ContactoDialog> createState() => _ContactoDialogState();
}

class _ContactoDialogState extends ConsumerState<_ContactoDialog> {
  final _form = GlobalKey<FormState>();
  late final _entidad = TextEditingController(text: widget.contacto?.entidad);
  late final _telefono = TextEditingController(text: widget.contacto?.telefono);
  late final _direccion =
      TextEditingController(text: widget.contacto?.direccion);
  late final _fuente = TextEditingController(text: widget.contacto?.fuente);
  late int _idDestino = widget.contacto?.idDestino ?? 0;
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      if (widget.contacto == null) {
        await repo.crearContacto(
          idDestino: _idDestino,
          entidad: _entidad.text.trim(),
          telefono: _telefono.text.trim(),
          direccion: _direccion.text.trim(),
          fuente: _fuente.text.trim(),
        );
      } else {
        await repo.actualizarContacto(
          id: widget.contacto!.id,
          idDestino: _idDestino,
          entidad: _entidad.text.trim(),
          telefono: _telefono.text.trim(),
          direccion: _direccion.text.trim(),
          fuente: _fuente.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = mensajeErrorContenido(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _entidad.dispose();
    _telefono.dispose();
    _direccion.dispose();
    _fuente.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destinos =
        ref.watch(destinosAdminProvider).value ?? const <DestinoAdmin>[];

    return AlertDialog(
      title: Text(
        widget.contacto == null ? 'Nuevo contacto SOS' : 'Editar contacto SOS',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue:
                      destinos.any((d) => d.id == _idDestino) ? _idDestino : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Destino',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  items: destinos
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.nombre, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _idDestino = v ?? 0),
                  validator: (v) =>
                      v == null ? 'Selecciona una opción' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _entidad,
                  decoration: const InputDecoration(
                    labelText: 'Entidad (policía, bomberos...)',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                  validator: _obligatorio,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: _obligatorio,
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _direccion,
                  decoration: const InputDecoration(
                    labelText: 'Dirección (opcional)',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  enabled: !_guardando,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fuente,
                  decoration: const InputDecoration(
                    labelText: 'Fuente oficial (opcional)',
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                  enabled: !_guardando,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(widget.contacto == null ? 'Crear' : 'Guardar'),
        ),
      ],
    );
  }
}
