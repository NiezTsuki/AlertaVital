// lib/pages/mapa_alerta_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '/alertas_api.dart';

class MapaAlertaPage extends StatefulWidget {
  final String alertaId; // Hacemos que el ID sea requerido para esta vista
  final double lat; // posición inicial del adulto (snapshot al crear SOS)
  final double lon;

  const MapaAlertaPage({
    super.key,
    required this.lat,
    required this.lon,
    required this.alertaId,
  });

  @override
  State<MapaAlertaPage> createState() => _MapaAlertaPageState();
}

class _MapaAlertaPageState extends State<MapaAlertaPage> {
  final MapController _mapController = MapController();

  // Traza y últimos puntos
  List<LatLng> _adultoTrail = [];
  List<LatLng> _cuidadorTrail = [];
  LatLng? _adultoLast;
  LatLng? _cuidadorLast;

  @override
  void initState() {
    super.initState();
    _adultoLast = LatLng(widget.lat, widget.lon);
    
    // ✅ SOLUCIÓN: Reemplazamos el polling por una carga inicial + suscripción a tiempo real.
    _fetchInitialPositions(); // Carga el historial de posiciones al entrar
    _subscribeToPositionUpdates(); // Se suscribe para recibir nuevas posiciones
  }

  // Carga el historial de posiciones que ya existen en el servidor.
  Future<void> _fetchInitialPositions() async {
    try {
      final rows = await AlertasApi.getPosiciones(widget.alertaId);
      _processPositionRows(rows);
    } catch (_) {
      // Manejo de error silencioso, la UI simplemente no mostrará el historial
    }
  }

 // ✅ Se suscribe al canal de Pusher para recibir actualizaciones en tiempo real.
Future<void> _subscribeToPositionUpdates() async {
  try {
    final channel = await AlertasApi.subscribeToChannel('private-alerta-${widget.alertaId}');
    
    // ✅ SOLUCIÓN: Cambiar el tipo del parámetro a 'dynamic' y hacer un cast.
    channel.onEvent = (dynamic event) {
      // Hacemos una comprobación de tipo para seguridad.
      if (event is! PusherEvent) return;

      if (!mounted || event.eventName != 'posicion_actualizada' || event.data == null) {
        return;
      }
      // Procesa el nuevo punto que llega en tiempo real.
      _handleNewPosition(event.data!);
    };
  } catch (e) {
    print('Error al suscribirse a actualizaciones de posición: $e');
  }
}

  // ✅ Procesa una nueva posición recibida desde Pusher.
  void _handleNewPosition(String jsonData) {
    try {
      final data = jsonDecode(jsonData);
      final rol = data['rol'] as String?;
      final lat = (data['latitud'] as num?)?.toDouble();
      final lon = (data['longitud'] as num?)?.toDouble();

      if (rol == null || lat == null || lon == null) return;
      
      final newPoint = LatLng(lat, lon);
      
      setState(() {
        if (rol == 'ADULTO_MAYOR') {
          _adultoTrail.add(newPoint);
          _adultoLast = newPoint;
        } else if (rol == 'CUIDADOR') {
          _cuidadorTrail.add(newPoint);
          _cuidadorLast = newPoint;
        }
      });

    } catch (e) {
      print('Error al procesar nueva posición: $e');
    }
  }
  
  // Procesa la lista completa de posiciones (usado para la carga inicial).
  void _processPositionRows(List<dynamic> rows) {
    // Estructura esperada: [{ rol: '...', latitud: ..., longitud: ... }, ...]
    final adulto = <LatLng>[];
    final cuidador = <LatLng>[];

    for (final x in rows) {
      final rol = '${x['rol'] ?? ''}';
      final lat = (x['latitud'] as num?)?.toDouble();
      final lon = (x['longitud'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      
      if (rol == 'ADULTO_MAYOR') {
        adulto.add(LatLng(lat, lon));
      } else if (rol == 'CUIDADOR') {
        cuidador.add(LatLng(lat, lon));
      }
    }

    // El backend trae orden DESC; invertimos para que la polyline vaya en orden temporal
    final adultoOrdered   = List<LatLng>.from(adulto.reversed);
    final cuidadorOrdered = List<LatLng>.from(cuidador.reversed);

    if (!mounted) return;
    setState(() {
      _adultoTrail   = adultoOrdered.isNotEmpty   ? adultoOrdered   : _adultoTrail;
      _cuidadorTrail = cuidadorOrdered.isNotEmpty ? cuidadorOrdered : _cuidadorTrail;

      _adultoLast    = adultoOrdered.isNotEmpty   ? adultoOrdered.last   : _adultoLast;
      _cuidadorLast  = cuidadorOrdered.isNotEmpty ? cuidadorOrdered.last : _cuidadorLast;
    });
  }


  // ---- Navegación externa (sin cambios)
  Future<void> _abrirGoogleMaps() async {
    final LatLng dest = _adultoLast ?? LatLng(widget.lat, widget.lon);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${dest.latitude},${dest.longitude}');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir Google Maps')));
    }
  }

  Future<void> _abrirWaze() async {
    final LatLng dest = _adultoLast ?? LatLng(widget.lat, widget.lon);
    final url = Uri.parse('https://waze.com/ul?ll=${dest.latitude},${dest.longitude}&navigate=yes');
     if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir Waze')));
    }
  }

  // ---- Centrar mapa (sin cambios)
  void _centrarAdulto() {
    final LatLng c = _adultoLast ?? LatLng(widget.lat, widget.lon);
    _mapController.move(c, _mapController.camera.zoom);
  }

  void _centrarCuidador() {
    if (_cuidadorLast == null) return;
    _mapController.move(_cuidadorLast!, _mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final LatLng initialCenter = LatLng(widget.lat, widget.lon);

    // Construcción de capas
    final polylines = <Polyline>[
      if (_adultoTrail.length >= 2)
        Polyline(points: _adultoTrail, strokeWidth: 5, color: Colors.red.withOpacity(0.85)),
      if (_cuidadorTrail.length >= 2)
        Polyline(points: _cuidadorTrail, strokeWidth: 5, color: Colors.blue.withOpacity(0.85)),
    ];

    final markers = <Marker>[
      // Adulto (último punto o snapshot inicial)
      Marker(
        point: _adultoLast ?? initialCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.location_pin, size: 44, color: Colors.red),
            Text('Adulto', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, backgroundColor: Colors.white)),
          ],
        ),
      ),
      // Cuidador (si hay)
      if (_cuidadorLast != null)
        Marker(
          point: _cuidadorLast!,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.person_pin_circle, size: 44, color: Colors.blue),
              Text('Tú', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, backgroundColor: Colors.white)),
            ],
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Ubicación ${widget.alertaId.substring(0, 6)}'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.alerta.vital',
              ),
              if (polylines.isNotEmpty)
                PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),

          // Leyenda simple (arriba a la izquierda)
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  _LegendDot(color: Colors.red, label: 'Adulto'),
                  SizedBox(width: 12),
                  _LegendDot(color: Colors.blue, label: 'Tú (cuidador)'),
                ],
              ),
            ),
          ),

          // Botones de centrar (arriba a la derecha)
          Positioned(
            right: 12,
            top: 12,
            child: Column(
              children: [
                _RoundIconButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Centrar en adulto',
                  onTap: _centrarAdulto,
                ),
                const SizedBox(height: 10),
                _RoundIconButton(
                  icon: Icons.my_location,
                  tooltip: 'Centrar en cuidador',
                  onTap: _centrarCuidador,
                  disabled: _cuidadorLast == null,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _abrirWaze,
                icon: const Icon(Icons.directions_car),
                label: const Text('Abrir en Waze'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _abrirGoogleMaps,
                icon: const Icon(Icons.map),
                label: const Text('Abrir en Google Maps'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Widgets auxiliares (sin cambios) ----
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool disabled;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: disabled ? Colors.grey.shade300 : Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: disabled ? null : onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: disabled ? Colors.grey : Colors.black87),
        ),
      ),
    );
  }
}