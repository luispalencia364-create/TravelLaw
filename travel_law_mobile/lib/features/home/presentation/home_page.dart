import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/rutas.dart';
import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/data/destino_activo_provider.dart';
import '../../destinos/data/destinos_repository.dart';
import '../../lugares/data/lugares_repository.dart';
import '../../notificaciones/data/notificaciones_repository.dart';
import '../../ubicacion/data/ubicacion_provider.dart';
import 'widgets/app_drawer.dart';
import 'widgets/home_map.dart';
import 'widgets/perfil_sheet.dart';

/// Pantalla principal: saludo y rol, buscador de destinos, mapa con ubicación
/// en tiempo real y destinos sugeridos.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  final _mapController = MapController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  late final UbicacionNotifier _ubicacion;

  bool _mapaListo = false;
  bool _centradoEnUsuario = false;
  Destino? _seleccionado;
  LugarPublico? _lugarSeleccionado;
  String _consulta = '';

  /// Controla cada cuánto se envía la ubicación al servidor para no saturar
  /// la red con cada actualización del GPS.
  DateTime? _ultimaSyncUbicacion;
  LatLng? _ultimaPosicionSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ubicacion = ref.read(ubicacionProvider.notifier);
    // Pide el permiso, empieza a seguir la ubicación y registra el contexto
    // inicial (destino y/o posición) para las notificaciones.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ubicacion.iniciar();
      _sincronizarContexto();
    });
  }

  /// Guarda en el servidor el destino activo y la última ubicación conocida.
  /// Así el viajero recibe alertas de su zona aunque no tenga la app abierta
  /// en ese momento.
  Future<void> _sincronizarContexto({int? idDestino, LatLng? posicion}) async {
    final client = ref.read(supabaseProvider);
    if (client.auth.currentUser?.id == null) return;

    final destino = idDestino ?? ref.read(destinoEfectivoProvider)?.id;
    final pos = posicion ?? ref.read(ubicacionProvider).posicion;
    if (destino == null && pos == null) return;

    try {
      await client.rpc(
        'actualizar_mi_contexto',
        params: {
          'p_id_destino': ?destino,
          'p_lat': ?pos?.latitude,
          'p_lng': ?pos?.longitude,
        },
      );
    } catch (e) {
      debugPrint('No se pudo sincronizar el contexto del viajero: $e');
    }
  }

  /// Envía la ubicación como máximo cada 2 minutos o si el viajero se movió
  /// más de 500 m desde el último envío.
  bool _debeSincronizarUbicacion(LatLng posicion) {
    final ahora = DateTime.now();
    final ultima = _ultimaSyncUbicacion;
    final anterior = _ultimaPosicionSync;

    if (ultima == null || anterior == null) {
      _ultimaSyncUbicacion = ahora;
      _ultimaPosicionSync = posicion;
      return true;
    }

    if (ahora.difference(ultima) >= const Duration(minutes: 2)) {
      _ultimaSyncUbicacion = ahora;
      _ultimaPosicionSync = posicion;
      return true;
    }

    final metros = Geolocator.distanceBetween(
      anterior.latitude,
      anterior.longitude,
      posicion.latitude,
      posicion.longitude,
    );
    if (metros >= 500) {
      _ultimaSyncUbicacion = ahora;
      _ultimaPosicionSync = posicion;
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ubicacion.detener(); // al cerrar sesión se deja de usar el GPS
    _mapController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Al volver de los ajustes del teléfono, se reintenta si faltaba GPS/permiso.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final estado = ref.read(ubicacionProvider).status;
    const reintentables = {
      UbicacionStatus.servicioApagado,
      UbicacionStatus.denegado,
      UbicacionStatus.denegadoSiempre,
      UbicacionStatus.error,
    };
    if (reintentables.contains(estado)) _ubicacion.iniciar();
  }

  void _moverMapa(LatLng punto, double zoom) {
    if (!_mapaListo) return;
    try {
      _mapController.move(punto, zoom);
    } catch (_) {
      // El mapa aún no está montado: se ignora.
    }
  }

  void _alMapaListo() {
    _mapaListo = true;
    final posicion = ref.read(ubicacionProvider).posicion;
    if (posicion != null && !_centradoEnUsuario) {
      _centradoEnUsuario = true;
      _moverMapa(posicion, 12);
    }
  }

  void _centrarEnUsuario() {
    final posicion = ref.read(ubicacionProvider).posicion;
    if (posicion != null) _moverMapa(posicion, 14);
  }

  void _seleccionar(Destino destino) {
    FocusScope.of(context).unfocus();
    setState(() {
      _seleccionado = destino;
      _lugarSeleccionado = null;
    });
    ref.read(destinoActivoProvider.notifier).seleccionar(destino.id);
    _moverMapa(destino.posicion, 13);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _seleccionarLugar(LugarPublico lugar) {
    FocusScope.of(context).unfocus();
    final destino = Destino(
      id: lugar.idDestino,
      nombre: lugar.destino,
      municipio: lugar.municipio,
      posicion: lugar.destinoPosicion,
    );
    setState(() {
      _seleccionado = destino;
      _lugarSeleccionado = lugar;
    });
    ref.read(destinoActivoProvider.notifier).seleccionar(destino.id);
    _moverMapa(lugar.posicion, 16);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _LugarSheet(lugar: lugar),
    );
  }

  List<LugarPublico> _filtrarLugares(List<LugarPublico> todos) {
    final q = normalizar(_consulta.trim());
    if (q.isEmpty) return const <LugarPublico>[];
    return todos
        .where(
          (l) => normalizar(
            '${l.nombre} ${l.categoria} ${l.destino} ${l.municipio}',
          ).contains(q),
        )
        .toList();
  }

  Widget _tarjetaLugar(LugarPublico l) {
    final horario = l.horario?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconoCategoria(l.categoria)),
        title: Text(l.nombre),
        subtitle: Text(
          '${l.categoria} · ${l.destino}'
          '${horario.isEmpty ? '' : ' · $horario'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _seleccionarLugar(l),
      ),
    );
  }

  void _mostrarPerfil() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const PerfilSheet(),
    );
  }

  double _distanciaA(Destino d, LatLng desde) {
    return Geolocator.distanceBetween(
      desde.latitude,
      desde.longitude,
      d.posicion.latitude,
      d.posicion.longitude,
    );
  }

  List<Destino> _filtrar(List<Destino> todos, LatLng? posicionUsuario) {
    final q = normalizar(_consulta.trim());
    final resultado = q.isEmpty
        ? List<Destino>.of(todos)
        : todos
              .where(
                (d) => normalizar('${d.nombre} ${d.municipio}').contains(q),
              )
              .toList();
    if (posicionUsuario != null) {
      resultado.sort(
        (a, b) => _distanciaA(
          a,
          posicionUsuario,
        ).compareTo(_distanciaA(b, posicionUsuario)),
      );
    }
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    // Primera posición recibida: centra el mapa en el usuario una sola vez.
    ref.listen<UbicacionState>(ubicacionProvider, (anterior, nuevo) {
      final posicion = nuevo.posicion;
      if (!_centradoEnUsuario && posicion != null) {
        _centradoEnUsuario = true;
        _moverMapa(posicion, 12);
      }
      if (posicion != null && _debeSincronizarUbicacion(posicion)) {
        _sincronizarContexto(posicion: posicion);
      }
    });

    // Si el destino efectivo cambia (selección manual o GPS), se guarda en
    // el servidor para segmentar las notificaciones.
    ref.listen<Destino?>(destinoEfectivoProvider, (anterior, nuevo) {
      if (nuevo != null && nuevo.id != anterior?.id) {
        _sincronizarContexto(idDestino: nuevo.id);
      }
    });

    final perfil = ref.watch(perfilProvider);
    final destinosAsync = ref.watch(destinosProvider);
    final ubicacion = ref.watch(ubicacionProvider);
    final todos = destinosAsync.maybeWhen(
      data: (lista) => lista,
      orElse: () => const <Destino>[],
    );

    final lugaresAsync = ref.watch(lugaresProvider);
    final lugares = lugaresAsync.maybeWhen(
      data: (lista) => lista,
      orElse: () => const <LugarPublico>[],
    );
    final lugaresVisibles = _filtrarLugares(lugares);

    return Scaffold(
      drawer: AppDrawer(onPerfil: _mostrarPerfil),
      appBar: AppBar(
        title: perfil.when(
          skipLoadingOnReload: true,
          data: (p) => Text(
            p == null ? 'Hola' : 'Hola, ${p.primerNombre}',
            overflow: TextOverflow.ellipsis,
          ),
          loading: () => const Text('Hola'),
          error: (_, _) => const Text('Hola'),
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final noLeidas = ref.watch(notificacionesNoLeidasProvider);
              return IconButton(
                tooltip: 'Notificaciones',
                onPressed: () => context.push(Rutas.notificaciones),
                icon: Badge(
                  isLabelVisible: noLeidas > 0,
                  label: Text(noLeidas > 99 ? '99+' : '$noLeidas'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            },
          ),
          perfil.maybeWhen(
            skipLoadingOnReload: true,
            data: (p) => p == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ActionChip(
                      avatar: const Icon(Icons.badge_outlined, size: 18),
                      label: Text(p.rolEtiqueta),
                      tooltip: 'Ver mi perfil',
                      onPressed: _mostrarPerfil,
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(destinosProvider);
          ref.invalidate(lugaresProvider);
          await Future.wait([
            ref.read(destinosProvider.future),
            ref.read(lugaresProvider.future),
          ]);
        },
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _consulta = v),
              decoration: InputDecoration(
                hintText: 'Buscar destinos o lugares (ej. Osaka)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _consulta.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _consulta = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
            const SizedBox(height: 12),
            HomeMap(
              controller: _mapController,
              destinos: todos,
              seleccionado: _seleccionado,
              lugarSeleccionado: _lugarSeleccionado,
              onSelect: _seleccionar,
              onMapReady: _alMapaListo,
              onCentrar: _centrarEnUsuario,
            ),
            const SizedBox(height: 20),
            Text(
              _consulta.trim().isEmpty ? 'Destinos sugeridos' : 'Resultados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (lugaresAsync.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No se pudieron cargar los lugares.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (_consulta.trim().isNotEmpty && lugaresVisibles.isNotEmpty) ...[
              Text('Lugares', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final l in lugaresVisibles) _tarjetaLugar(l),
              const SizedBox(height: 12),
            ],
            destinosAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'No se pudieron cargar los destinos. Revisa tu conexión.\n$e',
                ),
              ),
              data: (lista) {
                final visibles = _filtrar(lista, ubicacion.posicion);
                if (visibles.isEmpty) {
                  if (_consulta.trim().isNotEmpty &&
                      lugaresVisibles.isNotEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _consulta.trim().isEmpty
                          ? 'No hay destinos disponibles.'
                          : 'No encontramos destinos ni lugares para '
                                '"$_consulta".',
                    ),
                  );
                }
                return Column(
                  children: [
                    if (_consulta.trim().isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Destinos',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    for (final d in visibles)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          selected: d.id == _seleccionado?.id,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(d.nombre),
                          subtitle: Text(
                            ubicacion.posicion == null
                                ? d.municipio
                                : '${d.municipio}  ·  a '
                                      '${formatearDistancia(_distanciaA(d, ubicacion.posicion!))}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _seleccionar(d),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconoCategoria(String categoria) {
  return switch (normalizar(categoria)) {
    'restaurante' => Icons.restaurant_outlined,
    'alojamiento' => Icons.hotel_outlined,
    'atraccion' => Icons.attractions_outlined,
    'servicio' => Icons.build_outlined,
    'transporte' => Icons.directions_bus_outlined,
    _ => Icons.place_outlined,
  };
}

class _LugarSheet extends StatelessWidget {
  const _LugarSheet({required this.lugar});

  final LugarPublico lugar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final horario = lugar.horario?.trim() ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(_iconoCategoria(lugar.categoria)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lugar.nombre,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${lugar.categoria} · ${lugar.destino}',
                        style: TextStyle(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (horario.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(horario)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'El destino ${lugar.destino} quedó activo para el resto de '
              'los módulos.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
