import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
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
  final MapController mapController = MapController(); // Para mover el mapa
  List<dynamic> spots = [];
  bool cargando = true;
  bool verRoca = true;
  bool verRocodromos = true;
  bool modoTopo = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosConCache();
  }

  // ESTRATEGIA 3G/OFFLINE
  Future<void> _cargarDatosConCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString('cache_spots');
    if (cache != null) {
      setState(() {
        spots = jsonDecode(cache);
        cargando = false;
      });
    }
    _leerDatosDeSupabase();
  }

  Future<void> _leerDatosDeSupabase() async {
    try {
      final data = await supabase.from('spots').select();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_spots', jsonEncode(data));
      setState(() { spots = data; cargando = false; });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => cargando = false);
    }
  }

  // FUNCIÓN PARA ELIMINAR FÍSICAMENTE EL PUNTO
  Future<void> _borrarPunto(String id) async {
    try {
      await supabase.from('spots').delete().eq('id', id);
      _leerDatosDeSupabase(); // Refrescar mapa
      if (!mounted) return;
      Navigator.pop(context); // Cerrar hoja de detalles
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sector eliminado correctamente'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      debugPrint('Error al borrar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escalada Map'),
        actions: [
          IconButton(
            icon: Icon(modoTopo ? Icons.map : Icons.terrain),
            onPressed: () => setState(() => modoTopo = !modoTopo),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _mostrarFiltros(context),
          ),
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
                markers: spots.where((s) {
                  if (s['tipo'] == 'sector_outdoor' && !verRoca) return false;
                  if (s['tipo'] == 'rocodromo' && !verRocodromos) return false;
                  return true;
                }).map((s) {
                  return Marker(
                    point: LatLng(s['latitud'], s['longitud']),
                    child: GestureDetector(
                      onTap: () {
                        // CENTRAR MAPA AUTOMÁTICAMENTE
                        mapController.move(LatLng(s['latitud'], s['longitud']), 13.0);
                        _mostrarDetalles(s);
                      },
                      child: Icon(
                        s['tipo'] == 'sector_outdoor' ? Icons.terrain : Icons.fitness_center,
                        color: s['tipo'] == 'sector_outdoor' ? Colors.brown : Colors.blue,
                        size: 35,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
    );
  }

  void _mostrarFormularioNuevo(LatLng punto) {
    String nombre = "";
    String tipo = "sector_outdoor";
    bool agua = false;
    bool mascotas = false;
    String internet = "no";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setStateForm) {
        return AlertDialog(
          title: const Text('Registrar Nuevo Sector'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: 'Nombre del lugar', border: OutlineInputBorder()),
                    onChanged: (v) => nombre = v,
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: tipo,
                    decoration: const InputDecoration(labelText: '¿Qué es?', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'sector_outdoor', child: Text('Sector Roca')),
                      DropdownMenuItem(value: 'rocodromo', child: Text('Rocódromo')),
                    ],
                    onChanged: (v) => tipo = v!,
                  ),
                  CheckboxListTile(
                    title: const Text('Agua Potable'),
                    value: agua,
                    onChanged: (v) => setStateForm(() => agua = v!),
                  ),
                  CheckboxListTile(
                    title: const Text('Mascotas'),
                    value: mascotas,
                    onChanged: (v) => setStateForm(() => mascotas = v!),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: internet,
                    decoration: const InputDecoration(labelText: 'Internet'),
                    items: const [
                      DropdownMenuItem(value: 'no', child: Text('No')),
                      DropdownMenuItem(value: 'gratis', child: Text('Gratis')),
                      DropdownMenuItem(value: 'pago', child: Text('Pago')),
                    ],
                    onChanged: (v) => setStateForm(() => internet = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nombre.isNotEmpty) {
                  await supabase.from('spots').insert({
                    'nombre': nombre, 'tipo': tipo, 'latitud': punto.latitude, 'longitud': punto.longitude,
                    'tiene_agua_potable': agua, 'pet_friendly': mascotas, 'internet_status': internet
                  });
                  _leerDatosDeSupabase();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              }, 
              child: const Text('Guardar')
            ),
          ],
        );
      }),
    );
  }

  void _mostrarDetalles(dynamic s) async {
    List<dynamic> comentarios = [];
    final res = await supabase.from('comentarios').select().eq('spot_id', s['id']).order('fecha', ascending: false);
    comentarios = res;
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final comController = TextEditingController();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(s['nombre'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                    // BOTÓN DE BORRAR (PROTEGIDO)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmarBorrado(s['id']),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (s['tiene_agua_potable'] == true) const Chip(label: Text('Agua'), avatar: Icon(Icons.water_drop, size: 14)),
                    if (s['pet_friendly'] == true) const Chip(label: Text('Mascotas'), avatar: Icon(Icons.pets, size: 14)),
                    if (s['internet_status'] != 'no') Chip(label: Text('Internet: ${s['internet_status']}'), avatar: const Icon(Icons.wifi, size: 14)),
                  ],
                ),
                const Divider(),
                const Text('COMENTARIOS / AYUDAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: comentarios.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(comentarios[i]['texto']),
                      subtitle: Text('Actualización: ${comentarios[i]['fecha'].toString().substring(0,16)}', 
                        style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 10)),
                    ),
                  ),
                ),
                TextField(
                  controller: comController,
                  decoration: InputDecoration(
                    hintText: 'Escribe algo útil...',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () async {
                        if (comController.text.isNotEmpty) {
                          await supabase.from('comentarios').insert({'spot_id': s['id'], 'texto': comController.text});
                          final n = await supabase.from('comentarios').select().eq('spot_id', s['id']).order('fecha', ascending: false);
                          setModalState(() { comentarios = n; comController.clear(); });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  // DIALOGO PARA PEDIR CLAVE DE BORRADO
  void _confirmarBorrado(String id) {
    String claveIntroducida = "";
    const String claveMaestra = "159357"; // CAMBIA ESTA CLAVE POR LA QUE QUIERAS

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Sector'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Introduce la clave de administrador para borrar este punto:'),
            const SizedBox(height: 15),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Clave Secreta', border: OutlineInputBorder()),
              onChanged: (v) => claveIntroducida = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              if (claveIntroducida == claveMaestra) {
                _borrarPunto(id);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clave incorrecta')));
              }
            }, 
            child: const Text('Confirmar Borrado')
          ),
        ],
      ),
    );
  }

  void _mostrarFiltros(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setMS) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(title: const Text('Ver Roca'), value: verRoca, onChanged: (v) { setState(()=>verRoca=v); setMS(()=>verRoca=v); }),
          SwitchListTile(title: const Text('Ver Rocódromos'), value: verRocodromos, onChanged: (v) { setState(()=>verRocodromos=v); setMS(()=>verRocodromos=v); }),
          const SizedBox(height: 20),
        ],
      )),
    );
  }
}