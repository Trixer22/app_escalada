import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // Librería de GPS
import 'package:url_launcher/url_launcher.dart'; // Librería para abrir webs

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://rnfxpqnxpxtpcbbzyqrv.supabase.co',
    anonKey: 'sb_publishable_0g_V286Jbw-WM3ulM5rw6g_FZ0K-yep',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final supabase = Supabase.instance.client;
  final MapController mapController = MapController(); 
  List<dynamic> spots = [];
  List<dynamic> spotsFiltrados = [];
  bool cargando = true;
  
  // Variables para filtros y búsqueda
  String busqueda = "";
  bool verRoca = true;
  bool verRocodromos = true;
  bool modoTopo = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString('cache_spots');
    if (cache != null) {
      setState(() {
        spots = jsonDecode(cache);
        spotsFiltrados = spots;
        cargando = false;
      });
    }
    _leerDeSupabase();
  }

  Future<void> _leerDeSupabase() async {
    try {
      final data = await supabase.from('spots').select();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_spots', jsonEncode(data));
      setState(() { 
        spots = data; 
        _filtrar();
        cargando = false; 
      });
    } catch (e) {
      debugPrint('Error Supabase: $e');
      setState(() => cargando = false);
    }
  }

  void _filtrar() {
    setState(() {
      spotsFiltrados = spots.where((s) {
        final matchesBusqueda = s['nombre'].toString().toLowerCase().contains(busqueda.toLowerCase()) ||
                               (s['provincia'] ?? "").toString().toLowerCase().contains(busqueda.toLowerCase());
        final matchesTipo = (s['tipo'] == 'sector_outdoor' && verRoca) || (s['tipo'] == 'rocodromo' && verRocodromos);
        return matchesBusqueda && matchesTipo;
      }).toList();
    });
  }

  // FUNCIÓN GPS
  Future<void> _irAMiUbicacion() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      Position pos = await Geolocator.getCurrentPosition();
      mapController.move(LatLng(pos.latitude, pos.longitude), 14.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Buscar por nombre o provincia...',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: (v) {
            busqueda = v;
            _filtrar();
          },
        ),
        actions: [
          IconButton(icon: Icon(modoTopo ? Icons.map : Icons.terrain), onPressed: () => setState(() => modoTopo = !modoTopo)),
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () => _mostrarFiltros()),
        ],
      ),
      body: cargando 
        ? const Center(child: CircularProgressIndicator()) 
        : FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(-34.6037, -58.3816),
              initialZoom: 10.0,
              onTap: (tapPos, point) => _mostrarFormularioNuevo(point),
            ),
            children: [
              TileLayer(
                urlTemplate: modoTopo 
                  ? 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              MarkerLayer(
                markers: spotsFiltrados.map((s) {
                  return Marker(
                    point: LatLng(s['latitud'], s['longitud']),
                    child: GestureDetector(
                      onTap: () {
                        mapController.move(LatLng(s['latitud'], s['longitud']), 16.0);
                        _mostrarDetalles(s);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: Icon(
                          s['tipo'] == 'sector_outdoor' ? Icons.terrain : Icons.fitness_center,
                          color: s['tipo'] == 'sector_outdoor' ? const Color(0xFF795548) : const Color(0xFF1976D2),
                          size: 28,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: _irAMiUbicacion,
        child: const Icon(Icons.my_location),
      ),
    );
  }

  void _mostrarFormularioNuevo(LatLng punto) {
    String nombre = "";
    String tipo = "sector_outdoor";
    String pais = "";
    String provincia = "";
    String url = "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setStateForm) {
        return AlertDialog(
          title: const Text('Nuevo Punto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(decoration: const InputDecoration(labelText: 'Nombre'), onChanged: (v) => nombre = v),
                TextField(decoration: const InputDecoration(labelText: 'País'), onChanged: (v) => pais = v),
                TextField(decoration: const InputDecoration(labelText: 'Provincia'), onChanged: (v) => provincia = v),
                TextField(decoration: const InputDecoration(labelText: 'URL TheCrag'), onChanged: (v) => url = v),
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  items: const [
                    DropdownMenuItem(value: 'sector_outdoor', child: Text('Roca')),
                    DropdownMenuItem(value: 'rocodromo', child: Text('Rocódromo')),
                  ],
                  onChanged: (v) => tipo = v!,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nombre.isNotEmpty) {
                  await supabase.from('spots').insert({
                    'nombre': nombre, 'tipo': tipo, 'latitud': punto.latitude, 'longitud': punto.longitude,
                    'pais': pais, 'provincia': provincia, 'thecrag_url': url
                  });
                  _leerDeSupabase();
                  if (context.mounted) Navigator.pop(context);
                }
              }, 
              child: const Text('Guardar')
            ),
          ],
        );
      }),
    );
  }

  void _mostrarDetalles(dynamic s) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s['nombre'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text('${s['provincia'] ?? 'Provincia'}, ${s['pais'] ?? 'País'}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 15),
            if (s['thecrag_url'] != null && s['thecrag_url'] != "")
              ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse(s['thecrag_url'])),
                icon: const Icon(Icons.link),
                label: const Text('Ver en TheCrag'),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _mostrarFiltros() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(title: const Text('Roca'), value: verRoca, onChanged: (v) { setState(()=>verRoca=v); _filtrar(); Navigator.pop(context); }),
          SwitchListTile(title: const Text('Indoor'), value: verRocodromos, onChanged: (v) { setState(()=>verRocodromos=v); _filtrar(); Navigator.pop(context); }),
        ],
      ),
    );
  }
}