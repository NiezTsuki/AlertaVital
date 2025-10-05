// lib/pages/mapa_alerta_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '/alertas_api.dart';

class MapaAlertaPage extends StatefulWidget {
  final String? alertaId;
  final double lat; // posición inicial del adulto (snapshot al crear SOS)
  final double lon;

  const MapaAlertaPage({
    super.key,
    required this.lat,
    required this.lon,
    this.alertaId,
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

  Timer? _pollTimer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Fallback inicial al snapshot
    _adultoLast = LatLng(widget.lat, widget.lon);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    // Poll inmediato
    _pollOnce();
    // Y cada 6 segundos
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (widget.alertaId == null || widget.alertaId!.isEmpty) return;
    if (_loading) return;
    _loading = true;
    try {
      final rows = await AlertasApi.getPosiciones(widget.alertaId!); // devuelve ambos roles si no pasamos ?rol
      // Estructura esperada: [{ rol: 'ADULTO_MAYOR'|'CUIDADOR', latitud, longitud, capturada_en, ... }, ...]
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

setState(() {
  _adultoTrail   = adultoOrdered.isNotEmpty   ? adultoOrdered   : _adultoTrail;
  _cuidadorTrail = cuidadorOrdered.isNotEmpty ? cuidadorOrdered : _cuidadorTrail;

  _adultoLast    = (adultoOrdered.isNotEmpty   ? adultoOrdered.last   : _adultoLast) ?? _adultoLast;
  _cuidadorLast  = (cuidadorOrdered.isNotEmpty ? cuidadorOrdered.last : _cuidadorLast);
});

      setState(() {
        _adultoTrail = adulto.isNotEmpty ? adulto : _adultoTrail;
        _cuidadorTrail = cuidador.isNotEmpty ? cuidador : _cuidadorTrail;
        _adultoLast = (adulto.isNotEmpty ? adulto.last : _adultoLast) ?? _adultoLast;
        _cuidadorLast = (cuidador.isNotEmpty ? cuidador.last : _cuidadorLast);
      });
    } catch (_) {
      // Silencioso: si falla, reintenta en el próximo tick
    } finally {
      _loading = false;
    }
  }

  // ---- Navegación externa
  Future<void> _abrirGoogleMaps() async {
    final LatLng dest = _adultoLast ?? LatLng(widget.lat, widget.lon);
    final web = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}');
    if (!await launchUrl(web, mode: LaunchMode.externalApplication)) {
      await launchUrl(web, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _abrirWaze() async {
    final LatLng dest = _adultoLast ?? LatLng(widget.lat, widget.lon);
    final deep = Uri.parse('waze://?ll=${dest.latitude},${dest.longitude}&navigate=yes');
    final web  = Uri.parse('https://waze.com/ul?ll=${dest.latitude},${dest.longitude}&navigate=yes');
    if (!await launchUrl(deep, mode: LaunchMode.externalApplication)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  // ---- Centrar mapa
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
        width: 54,
        height: 54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.location_pin, size: 44, color: Colors.red),
            Text('Adulto', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      // Cuidador (si hay)
      if (_cuidadorLast != null)
        Marker(
          point: _cuidadorLast!,
          width: 54,
          height: 54,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.person_pin_circle, size: 44, color: Colors.blue),
              Text('Tú', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Ubicación ${widget.alertaId != null ? widget.alertaId!.substring(0, 6) : ''}'),
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

// ---- Widgets auxiliares ----
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
