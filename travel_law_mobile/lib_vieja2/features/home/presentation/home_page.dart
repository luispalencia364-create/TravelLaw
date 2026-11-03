import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/data/destinos_repository.dart';
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
  String _consulta = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ubicacion = ref.read(ubicacionProvider.notifier);
    // Pide el permiso y empieza a seguir la ubicación al abrir la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ubicacion.iniciar());
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
    setState(() => _seleccionado = destino);
    _moverMapa(destino.posicion, 13);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
    });

    final perfil = ref.watch(perfilProvider);
    final destinosAsync = ref.watch(destinosProvider);
    final ubicacion = ref.watch(ubicacionProvider);
    final todos = destinosAsync.maybeWhen(
      data: (lista) => lista,
      orElse: () => const <Destino>[],
    );

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
          error: (_, __) => const Text('Hola'),
        ),
        actions: [
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
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _consulta = v),
            decoration: InputDecoration(
              hintText: 'Buscar destinos (ej. Lorica)',
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
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No encontramos destinos para "$_consulta".'),
                );
              }
              return Column(
                children: [
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
    );
  }
}
