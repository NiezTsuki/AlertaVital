// lib/pages/home_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../auth_state.dart';
import '../api.dart';
import '../alertas_api.dart';

import 'vincular_page.dart';
import 'mis_vinculos_page.dart';
import 'login_page.dart';
import 'mapa_alerta_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ===== Estados de la UI y Flujo =====
  Timer? _sosTimer, _adultoTrailTimer, _hbTimer;
  int _countdown = 0;
  String? _alertaId;
  String _estadoTexto = 'Listo para ayudar';
  final List<_IncomingAlert> _incoming = [];
  bool _isServicesInitialized = false;
  
  // ✅ ESTADO PRINCIPAL: Controla si la conexión en tiempo real está lista.
  bool _isRealTimeReady = false;

  // ===== Getters de conveniencia =====
  bool get _esAdultoMayor => context.read<AuthState>().user?['rol'] == 'ADULTO_MAYOR';
  bool get _esCuidador => context.read<AuthState>().user?['rol'] == 'CUIDADOR';
  String? get _token => context.read<AuthState>().token;
  String? get _userId => context.read<AuthState>().user?['sub'];

  // ===== Ciclo de Vida del Widget =====
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthState>();
    // ✅ CORRECCIÓN: Nos aseguramos de inicializar todo solo una vez y cuando tengamos token.
    if (!_isServicesInitialized && auth.token != null && auth.user != null) {
      setState(() => _isServicesInitialized = true);
      _initializeAuthenticatedServices();
    }
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _adultoTrailTimer?.cancel();
    _hbTimer?.cancel();
    AlertasApi.dispose();
    super.dispose();
  }

  // ===== Lógica de Inicialización y Pusher =====
  void _initializeAuthenticatedServices() {
    print("✅ Usuario autenticado. Inicializando servicios...");
    if (_token == null) return;
    AlertasApi.configure(baseUrl: Api.baseUrl, token: _token!);

    // Inicia el envío de ubicación una vez y luego periódicamente.
    _sendLocationOnce();
    _startHeartbeatUbicacion();

    unawaited(AlertasApi.initPusher(
      apiKey: '67c27146be09c306d1f7',
      cluster: 'us2',
    ).then((success) {
      if (mounted) {
        setState(() => _isRealTimeReady = success);
        if (success) {
          _subscribeToUserChannel();
        }
      }
    }));
  }

  Future<void> _subscribeToUserChannel() async {
    if (_userId == null) return;
    final userChannel = await AlertasApi.subscribeToChannel('private-user-$_userId');

    userChannel.onEvent = (event) {
      if (!mounted) return;
      switch (event.eventName) {
        case 'cuidador_en_camino': _onEnCamino(event); break;
        case 'alerta_completada': _onCompletada(event); break;
        case 'alerta_emergencia': _onEmergencia(event); break;
        case 'alerta_nueva': if (_esCuidador) _onAlertaNueva(event); break;
      }
    };
  }

  // ===== Lógica de SOS y Handlers de Eventos =====
  Future<void> _onSosPressed() async {
    try {
      final pos = await _getCurrentPosition();
      final r = await AlertasApi.crearSOS(lat: pos?.latitude, lon: pos?.longitude, precision: pos?.accuracy);
      final id = r['alertaId']?.toString();
      if (id == null) throw Exception('No se pudo crear la alerta');

      final alertaChannel = await AlertasApi.subscribeToChannel('private-alerta-$id');
      alertaChannel.onEvent = (event) {
        if (mounted && event.eventName == 'derivada_siguiente') _onDerivada(event);
      };

      setState(() {
        _alertaId = id;
        _countdown = (r['countdown'] as int?) ?? 30;
        _estadoTexto = 'Notificando al cuidador más cercano…';
      });
      _startCountdown();
      _startAdultoTrail();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _onAlertaNueva(PusherEvent event) {
    if (event.data == null) return;
    final data = jsonDecode(event.data!);
    final alertaId = data['alertaId']?.toString();
    if (alertaId == null) return;
    if (!_incoming.any((a) => a.alertaId == alertaId)) {
      setState(() => _incoming.insert(0, _IncomingAlert.fromJson(data)));
    }
  }

  void _onEnCamino(PusherEvent? e) => setState(() => _estadoTexto = '¡Tu cuidador va en camino!');
  void _onDerivada(PusherEvent? e) => setState(() => _estadoTexto = 'Derivando al siguiente cuidador…');
  void _onCompletada(PusherEvent? e) => _resetAlerta('Alerta finalizada.');
  void _onEmergencia(PusherEvent? e) => _resetAlerta('Sin cuidadores. Llamado de emergencia.');

  void _resetAlerta(String finalState) {
    setState(() => _estadoTexto = finalState);
    _stopCountdown();
    _stopAdultoTrail();
    if (_alertaId != null) AlertasApi.unsubscribeFromChannel('private-alerta-${_alertaId!}');
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _alertaId = null);
    });
  }
  
  // ===== Timers y GPS =====
  void _startCountdown() {
    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _countdown > 0) setState(() => _countdown--);
    });
  }
  void _stopCountdown() => _sosTimer?.cancel();
  
  void _startAdultoTrail() {
    _stopAdultoTrail();
    if (_alertaId == null) return;
    _adultoTrailTimer = Timer.periodic(const Duration(seconds: 7), (_) async {
      if (_alertaId == null || !mounted) return;
      final pos = await _getCurrentPosition();
      if (pos != null) {
        try {
          await AlertasApi.registrarPosicionAlerta(_alertaId!, pos.latitude, pos.longitude, precision: pos.accuracy);
        } catch (_) {}
      }
    });
  }
  void _stopAdultoTrail() => _adultoTrailTimer?.cancel();

  void _startHeartbeatUbicacion() { 
    _hbTimer?.cancel();
    _hbTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_token == null || !mounted) return; // Verificación de seguridad
      await _sendLocationOnce();
    });
  }
  
  Future<void> _sendLocationOnce() async {
    final pos = await _getCurrentPosition();
    if (pos != null && _token != null) {
      try {
        await AlertasApi.registrarUbicacion(pos.latitude, pos.longitude, precision: pos.accuracy);
        print('📍 Ubicación enviada.');
      } catch (_) {}
    }
  }
  
  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }

  // ===== Acciones de UI y Navegación =====
  Future<void> _acceptIncoming(_IncomingAlert item) async {
    try {
      await AlertasApi.aceptarAlerta(item.alertaId);
      if (!mounted) return;
      setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
      if (item.lat != null && item.lon != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapaAlertaPage(alertaId: item.alertaId, lat: item.lat!, lon: item.lon!)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al aceptar: $e')));
    }
  }

  Future<void> _deriveIncoming(_IncomingAlert item) async {
    try {
      await AlertasApi.derivarAlerta(item.alertaId);
      if (mounted) setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al derivar: $e')));
    }
  }

  void _goVincular() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VincularPage()));
  void _goMisVinculos() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MisVinculosPage()));
  
  Future<void> _logout() async {
    _hbTimer?.cancel();
    await context.read<AuthState>().logout();
    AlertasApi.dispose();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  // ===== Construcción de la UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_esAdultoMayor ? 'AlertaVital' : 'AlertaVital — Cuidador'),
        actions: [
          if (_esAdultoMayor) IconButton(tooltip: 'Vincular cuidador', icon: const Icon(Icons.link), onPressed: _goVincular),
          IconButton(tooltip: 'Mis vínculos', icon: const Icon(Icons.group), onPressed: _goMisVinculos),
          IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.power_settings_new), onPressed: _logout),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _esAdultoMayor
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  SosBigButton(onPressed: _isRealTimeReady ? _onSosPressed : null),
                  const SizedBox(height: 16),
                  if (!_isRealTimeReady)
                    const Text('Conectando al servicio de alertas...')
                  else if (_alertaId != null) ...[
                    _EstadoChip(text: _estadoTexto),
                    const SizedBox(height: 8),
                    _CountdownDisplay(value: _countdown),
                  ] else
                    const Text('Presiona el botón para pedir ayuda.'),
                ])
              : _esCuidador
                  ? _CaregiverView(items: _incoming, onAccept: _acceptIncoming, onDerive: _deriveIncoming)
                  : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

// ============================================================================
// WIDGETS Y CLASES AUXILIARES
// ============================================================================
class _IncomingAlert {
  final String alertaId;
  final int orden;
  final double? lat;
  final double? lon;
  _IncomingAlert({required this.alertaId, required this.orden, this.lat, this.lon});

  factory _IncomingAlert.fromJson(Map<String, dynamic> json) {
    return _IncomingAlert(
      alertaId: json['alertaId'] as String,
      orden: (json['orden'] as num?)?.toInt() ?? 1,
      lat: (json['latitud'] as num?)?.toDouble(),
      lon: (json['longitud'] as num?)?.toDouble(),
    );
  }
}

class _CaregiverView extends StatelessWidget {
  final List<_IncomingAlert> items;
  final Future<void> Function(_IncomingAlert) onAccept;
  final Future<void> Function(_IncomingAlert) onDerive;
  const _CaregiverView({required this.items, required this.onAccept, required this.onDerive});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Sin emergencias por ahora.\nMantén la app abierta para recibir alertas.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _IncomingCard(item: items[i], onAccept: () => onAccept(items[i]), onDerive: () => onDerive(items[i])),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  final _IncomingAlert item;
  final VoidCallback onAccept;
  final VoidCallback onDerive;
  const _IncomingCard({required this.item, required this.onAccept, required this.onDerive});

  @override
  Widget build(BuildContext context) {
    final ts = TimeOfDay.now();
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Alerta SOS', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _InfoChip(label: 'ID', value: item.alertaId.substring(0, 6)),
            _InfoChip(label: 'Orden', value: '${item.orden}'),
            _InfoChip(label: 'Hora', value: '$hh:$mm'),
            if (item.lat != null) _InfoChip(label: 'GPS', value: 'Disponible'),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: onDerive, icon: const Icon(Icons.redo), label: const Text('Derivar'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: onAccept, icon: const Icon(Icons.directions_walk), label: const Text('Voy en camino'))),
          ]),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class SosBigButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const SosBigButton({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null;
    final size = MediaQuery.of(context).size;
    final diameter = (size.width * 0.65).clamp(200.0, 380.0);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(diameter / 2),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isEnabled
                ? [const Color(0xFFFF6B6B), const Color(0xFFFF2E2E)]
                : [Colors.grey.shade500, Colors.grey.shade700],
          ),
          boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 8)) ],
        ),
        alignment: Alignment.center,
        child: const Text('SOS', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 6)),
      ),
    );
  }
}

class _CountdownDisplay extends StatelessWidget {
  final int value;
  const _CountdownDisplay({required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
      child: Text('Derivación en: ${value.clamp(0, 999)} s', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final String text;
  const _EstadoChip({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSecondaryContainer)),
    );
  }
}