import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de Supabase con tus credenciales
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
      title: 'Escalada App',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
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
  List<dynamic> spots = [];
  bool cargando = true;

  // Variables de control: Filtros y Estilo de mapa
  bool verRoca = true;
  bool verRocodromos = true;
  bool modoTopo = false;

  @override
  void initState() {
    super.initState();
    _leerDatos();
  }

  // Traer los sectores y rocódromos de la base de datos
  Future<void> _leerDatos() async {
    try {
      final data = await supabase.from('spots').select();
      setState(() {
        spots = data;
        cargando = false;
      });
    } catch (e) {
      debugPrint('Error al leer datos: $e');
      setState(() => cargando = false);
    }
  }

  // Guardar un nuevo sector (invocado por el clic largo)
  Future<void> _guardarNuevoPunto(LatLng posicion, String nombre, String tipo) async {
    try {
      await supabase.from('spots').insert({
        'nombre': nombre,
        'tipo': tipo,
        'latitud': posicion.latitude,
        'longitud': posicion.longitude,
        'descripcion': 'Nuevo sector compartido por la comunidad.',
      });
      _leerDatos(); // Refrescar el mapa
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Punto agregado con éxito!')),
        );
      }
    } catch (e) {
      debugPrint('Error al guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escalada Map'),
        elevation: 2,
        actions: [
          // Botón para alternar Mapa Topográfico
          IconButton(
            icon: Icon(modoTopo ? Icons.map : Icons.terrain),
            onPressed: () => setState(() => modoTopo = !modoTopo),
            tooltip: 'Cambiar a Topográfico',
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
              options: MapOptions(
                initialCenter: const LatLng(-34.6037, -58.3816),
                initialZoom: 10.0,
                // Detectar clic largo para agregar nuevo sector
                onLongPress: (tapPos, point) => _mostrarFormularioNuevo(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: modoTopo
                      ? 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: modoTopo ? const ['a', 'b', 'c'] : const [],
                  userAgentPackageName: 'com.tuapp.escalada',
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
                        onTap: () => _mostrarDetalles(s),
                        child: Icon(
                          s['tipo'] == 'sector_outdoor'
                              ? Icons.terrain
                              : Icons.fitness_center,
                          color: s['tipo'] == 'sector_outdoor'
                              ? Colors.brown
                              : Colors.blue,
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

  // VENTANA PARA DETALLES Y COMENTARIOS
  void _mostrarDetalles(dynamic s) async {
    List<dynamic> comentarios = [];

    // Obtener comentarios de este sector específico
    final res = await supabase
        .from('comentarios')
        .select()
        .eq('spot_id', s['id'])
        .order('fecha', ascending: false);
    comentarios = res;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final TextEditingController _comController = TextEditingController();

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              top: 25,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['nombre'],
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green)),
                const SizedBox(height: 5),
                Text(s['descripcion'] ?? '',
                    style: const TextStyle(fontSize: 16, color: Colors.black87)),
                const Divider(height: 30),
                const Text('COMUNIDAD Y AYUDAS',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1)),
                const SizedBox(height: 10),

                // Lista de Comentarios
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: comentarios.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No hay avisos todavía.'))
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: comentarios.length,
                          itemBuilder: (context, i) {
                            String fechaRaw = comentarios[i]['fecha'].toString();
                            String fechaFormateada = fechaRaw.substring(0, 10) +
                                " " +
                                fechaRaw.substring(11, 16);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(comentarios[i]['texto'],
                                      style: const TextStyle(fontSize: 15)),
                                  const SizedBox(height: 6),
                                  // FECHA EN LETRA CHICA Y CURSIVA
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Text(
                                      'Última actualización: $fechaFormateada',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Input para nuevo comentario
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: TextField(
                    controller: _comController,
                    decoration: InputDecoration(
                      hintText: 'Añadir información...',
                      filled: true,
                      fillColor: Colors.green[50],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send, color: Colors.green),
                        onPressed: () async {
                          if (_comController.text.isNotEmpty) {
                            await supabase.from('comentarios').insert({
                              'spot_id': s['id'],
                              'texto': _comController.text,
                            });
                            final nuevosCom = await supabase
                                .from('comentarios')
                                .select()
                                .eq('spot_id', s['id'])
                                .order('fecha', ascending: false);
                            setModalState(() {
                              comentarios = nuevosCom;
                              _comController.clear();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }

  // DIALOGO PARA CREAR NUEVO PUNTO
  void _mostrarFormularioNuevo(LatLng punto) {
    String nombre = "";
    String tipo = "sector_outdoor";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Sector'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Nombre del lugar'),
              onChanged: (val) => nombre = val,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: tipo,
              items: const [
                DropdownMenuItem(
                    value: 'sector_outdoor', child: Text('Sector Roca')),
                DropdownMenuItem(value: 'rocodromo', child: Text('Rocódromo')),
              ],
              onChanged: (val) => tipo = val!,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (nombre.isNotEmpty) {
                _guardarNuevoPunto(punto, nombre, tipo);
                Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // MENU DE FILTROS
  void _mostrarFiltros(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filtros de Mapa',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text('Sectores de Roca'),
                secondary: const Icon(Icons.terrain, color: Colors.brown),
                value: verRoca,
                onChanged: (v) {
                  setState(() => verRoca = v);
                  setModalState(() => verRoca = v);
                },
              ),
              SwitchListTile(
                title: const Text('Rocódromos'),
                secondary: const Icon(Icons.fitness_center, color: Colors.blue),
                value: verRocodromos,
                onChanged: (v) {
                  setState(() => verRocodromos = v);
                  setModalState(() => verRocodromos = v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}