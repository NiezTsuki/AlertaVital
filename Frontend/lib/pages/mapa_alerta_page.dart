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
  final String alertaId;
  final double lat; // posición inicial del adulto
  final double lon;

  const MapaAlertaPage({
    super.key,
    required this.alertaId,
    required this.lat,
    required this.lon,
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
    _fetchInitialPositions();
    _subscribeToPositionUpdates();
  }

  @override
  void dispose() {
    // Es una buena práctica desuscribirse del canal al salir de la pantalla
    AlertasApi.unsubscribeFromChannel('private-alerta-${widget.alertaId}');
    super.dispose();
  }

  // Carga el historial de posiciones que ya existen en el servidor.
  Future<void> _fetchInitialPositions() async {
    try {
      final rows = await AlertasApi.getPosiciones(widget.alertaId);
      _processPositionRows(rows);
    } catch (e) {
      print('Error al cargar la ruta inicial: $e');
    }
  }

  // Se suscribe al canal de Pusher para recibir actualizaciones en tiempo real.
  Future<void> _subscribeToPositionUpdates() async {
    try {
      final channel = await AlertasApi.subscribeToChannel('private-alerta-${widget.alertaId}');
      
      // Asigna una función al callback onEvent para manejar los eventos.
      channel.onEvent = (event) {
        if (!mounted || event.eventName != 'posicion_actualizada' || event.data == null) {
          return;
        }
        _handleNewPosition(event.data!);
      };
    } catch (e) {
      print('Error al suscribirse a actualizaciones de posición: $e');
    }
  }

  // Procesa una nueva posición recibida desde Pusher.
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

    final adultoOrdered = List<LatLng>.from(adulto.reversed);
    final cuidadorOrdered = List<LatLng>.from(cuidador.reversed);

    if (!mounted) return;
    setState(() {
      _adultoTrail = adultoOrdered;
      _cuidadorTrail = cuidadorOrdered;
      if (adultoOrdered.isNotEmpty) _adultoLast = adultoOrdered.last;
      if (cuidadorOrdered.isNotEmpty) _cuidadorLast = cuidadorOrdered.last;
    });
  }

  // ---- Navegación externa ----
  Future<void> _launchMapUrl(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir ${url.scheme}')));
    }
  }

  void _abrirGoogleMaps() {
    final dest = _adultoLast ?? LatLng(widget.lat, widget.lon);
    _launchMapUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${dest.latitude},${dest.longitude}'));
  }

  void _abrirWaze() {
    final dest = _adultoLast ?? LatLng(widget.lat, widget.lon);
    _launchMapUrl(Uri.parse('https://waze.com/ul?ll=${dest.latitude},${dest.longitude}&navigate=yes'));
  }

  // ---- Centrar mapa ----
  void _centrarAdulto() {
    final c = _adultoLast ?? LatLng(widget.lat, widget.lon);
    _mapController.move(c, _mapController.camera.zoom);
  }

  void _centrarCuidador() {
    if (_cuidadorLast != null) {
      _mapController.move(_cuidadorLast!, _mapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = LatLng(widget.lat, widget.lon);

    final polylines = <Polyline>[
      if (_adultoTrail.length >= 2) Polyline(points: _adultoTrail, strokeWidth: 5, color: Colors.red.withOpacity(0.85)),
      if (_cuidadorTrail.length >= 2) Polyline(points: _cuidadorTrail, strokeWidth: 5, color: Colors.blue.withOpacity(0.85)),
    ];

    final markers = <Marker>[
      Marker(
        point: _adultoLast ?? initialCenter,
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_pin, size: 44, color: Colors.red),
          _MarkerLabel(text: 'Adulto'),
        ]),
      ),
      if (_cuidadorLast != null)
        Marker(
          point: _cuidadorLast!,
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_pin_circle, size: 44, color: Colors.blue),
            _MarkerLabel(text: 'Tú'),
          ]),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Ubicación de Alerta')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: initialCenter, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            left: 12, top: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  _LegendDot(color: Colors.red, label: 'Adulto'),
                  SizedBox(width: 12),
                  _LegendDot(color: Colors.blue, label: 'Tú (cuidador)'),
                ]),
              ),
            ),
          ),
          Positioned(
            right: 12, top: 12,
            child: Column(children: [
              _RoundIconButton(icon: Icons.center_focus_strong, tooltip: 'Centrar en adulto', onTap: _centrarAdulto),
              const SizedBox(height: 10),
              _RoundIconButton(icon: Icons.my_location, tooltip: 'Centrar en cuidador', onTap: _centrarCuidador, disabled: _cuidadorLast == null),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _abrirWaze, icon: const Icon(Icons.directions_car), label: const Text('Waze'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(onPressed: _abrirGoogleMaps, icon: const Icon(Icons.map), label: const Text('Google Maps'))),
        ]),
      ),
    );
  }
}

// ---- Widgets auxiliares ----
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool disabled;
  const _RoundIconButton({required this.icon, required this.tooltip, required this.onTap, this.disabled = false});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: disabled ? Theme.of(context).disabledColor : Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 4,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: disabled ? null : onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 22, color: disabled ? Colors.grey[600] : Theme.of(context).iconTheme.color),
          ),
        ),
      ),
    );
  }
}

class _MarkerLabel extends StatelessWidget {
  final String text;
  const _MarkerLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black87)),
    );
  }
}