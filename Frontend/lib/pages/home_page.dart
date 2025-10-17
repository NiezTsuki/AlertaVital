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
  // ===== Estado del flujo SOS (adulto) =====
  Timer? _sosTimer;
  Timer? _adultoTrailTimer;
  int _countdown = 0;
  String? _alertaId;
  String _estadoTexto = 'Listo para ayudar';

  // ===== Estado de cuidador: alertas entrantes =====
  final List<_IncomingAlert> _incoming = [];

  // ===== Heartbeat general de ubicación =====
  Timer? _hbTimer;

  // ===== Estados de Pusher =====
  bool _isPusherInitialized = false;

  // ===== Helpers de rol/credenciales =====
  bool get _esAdultoMayor => context.read<AuthState>().user?['rol'] == 'ADULTO_MAYOR';
  bool get _esCuidador => context.read<AuthState>().user?['rol'] == 'CUIDADOR';
  String? get _token => context.read<AuthState>().token;
  String? get _userId => context.read<AuthState>().user?['sub'];

  // ===== Ciclo de vida =====
  @override
  void initState() {
    super.initState();
    _startHeartbeatUbicacion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthState>();

    if (!_isPusherInitialized && auth.token != null && auth.user != null) {
      print("✅ AuthState confirmado. Se procederá a inicializar Pusher...");
      
      unawaited(AlertasApi.initPusher(
        // ⚠️ RECUERDA PONER TUS CLAVES DE PUSHER AQUÍ ⚠️
        apiKey: '67c27146be09c306d1f7', 
        cluster: 'us2',
      ).then((_) {
        if (mounted) _subscribeToUserChannel();
      }));
      
      setState(() {
        _isPusherInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _stopCountdown();
    _stopAdultoTrail();
    _stopHeartbeatUbicacion();
    AlertasApi.dispose();
    super.dispose();
  }

  // ===== Acciones de navegación =====
  void _goVincular() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VincularPage()));
  void _goMisVinculos() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MisVinculosPage()));

  Future<void> _logout() async {
    await context.read<AuthState>().logout();
    AlertasApi.dispose();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // ===== Lógica de Pusher =====
  Future<void> _subscribeToUserChannel() async {
    final token = _token;
    final userId = _userId;
    if (token == null || token.isEmpty || userId == null) return;
    
    AlertasApi.configure(baseUrl: Api.baseUrl, token: token);
    final userChannel = await AlertasApi.subscribeToChannel('private-user-$userId');

    // ✅ SOLUCIÓN DEFINITIVA: Asignar una función al callback onEvent
    userChannel.onEvent = (event) {
      if (!mounted) return;
      // Usamos un switch para manejar los diferentes eventos que llegan al canal del usuario
      switch (event.eventName) {
        case 'cuidador_en_camino':
          _onEnCamino(event);
          break;
        case 'alerta_completada':
          _onCompletada(event);
          break;
        case 'alerta_emergencia':
          _onEmergencia(event);
          break;
        case 'alerta_nueva':
          if (_esCuidador) _onAlertaNueva(event);
          break;
      }
    };
  }

  // ===== Heartbeat y GPS =====
  void _startHeartbeatUbicacion() {
    _hbTimer?.cancel();
    _hbTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final pos = await _getCurrentPosition();
      if (pos == null || !mounted) return;
      try {
        await AlertasApi.registrarUbicacion(pos.latitude, pos.longitude, precision: pos.accuracy);
      } catch (_) {}
    });
  }
  void _stopHeartbeatUbicacion() => _hbTimer?.cancel();
  
  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }

  // ===== Lógica de SOS y Handlers de Eventos =====
  Future<void> _onSosPressed() async {
    if (_token == null || _token!.isEmpty) return;
    try {
      AlertasApi.configure(baseUrl: Api.baseUrl, token: _token!);
      final pos = await _getCurrentPosition();

      final r = await AlertasApi.crearSOS(
        lat: pos?.latitude,
        lon: pos?.longitude,
        precision: pos?.accuracy,
      );
      final id = (r['alertaId'] ?? '').toString();
      if (id.isEmpty) throw Exception('No se pudo crear la alerta');
      
      final alertaChannel = await AlertasApi.subscribeToChannel('private-alerta-$id');
      
      // ✅ SOLUCIÓN DEFINITIVA: Asignar una función al callback onEvent
      alertaChannel.onEvent = (event) {
        if (mounted && event.eventName == 'derivada_siguiente') {
          _onDerivada(event);
        }
      };

      setState(() {
        _alertaId = id;
        _countdown = (r['countdown'] ?? 30) as int;
        _estadoTexto = 'Notificando al cuidador más cercano…';
      });
      _startCountdown();
      _startAdultoTrail();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alerta enviada.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _onAlertaNueva(PusherEvent event) {
    if (event.data == null) return;
    final data = jsonDecode(event.data!);
    final alertaId = (data['alertaId'] ?? '').toString();
    if (alertaId.isEmpty) return;

    final exists = _incoming.any((a) => a.alertaId == alertaId);
    if (!exists) {
      if (!mounted) return;
      setState(() {
        _incoming.insert(0, _IncomingAlert(
          alertaId: alertaId,
          orden: (data['orden'] as num?)?.toInt() ?? 1,
          lat: (data['latitud'] as num?)?.toDouble(),
          lon: (data['longitud'] as num?)?.toDouble(),
        ));
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nueva alerta SOS')));
    }
  }

  void _onEnCamino(PusherEvent? _) { if (mounted) setState(() => _estadoTexto = '¡Tu cuidador va en camino!'); }
  void _onDerivada(PusherEvent? _) { if (mounted) setState(() => _estadoTexto = 'Derivando al siguiente cuidador…'); }

  void _onCompletada(PusherEvent? _) {
    if (!mounted) return;
    setState(() => _estadoTexto = 'Alerta finalizada.');
    _stopCountdown();
    _stopAdultoTrail();
    if (_alertaId != null) AlertasApi.unsubscribeFromChannel('private-alerta-${_alertaId!}');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _alertaId = null);
    });
  }

  void _onEmergencia(PusherEvent? _) {
    if (!mounted) return;
    setState(() => _estadoTexto = 'Sin cuidadores. Llamado de emergencia realizado.');
    _stopCountdown();
    _stopAdultoTrail();
    if (_alertaId != null) AlertasApi.unsubscribeFromChannel('private-alerta-${_alertaId!}');
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _alertaId = null);
    });
  }

  // ===== Timers de Alerta Activa =====
  void _startCountdown() {
    _stopCountdown();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (t) {
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
      if (pos == null) return;
      try {
        await AlertasApi.registrarPosicionAlerta(_alertaId!, pos.latitude, pos.longitude, precision: pos.accuracy);
        await AlertasApi.registrarUbicacion(pos.latitude, pos.longitude, precision: pos.accuracy);
      } catch (_) {}
    });
  }
  void _stopAdultoTrail() => _adultoTrailTimer?.cancel();

  // ===== Método Build de la UI =====
  @override
  Widget build(BuildContext context) {
    final isAdulto = _esAdultoMayor;
    final isCuidador = _esCuidador;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdulto ? 'AlertaVital — Adulto Mayor' : 'AlertaVital — Cuidador'),
        actions: [
          if (isAdulto)
            IconButton(
              tooltip: 'Vincular cuidador',
              icon: const Icon(Icons.link),
              onPressed: _goVincular,
            ),
          IconButton(
            tooltip: 'Mis vínculos',
            icon: const Icon(Icons.group),
            onPressed: _goMisVinculos,
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.power_settings_new),
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: isAdulto
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SosBigButton(onPressed: _onSosPressed),
                    const SizedBox(height: 16),
                    if (_alertaId != null) ...[
                      _EstadoChip(text: _estadoTexto),
                      const SizedBox(height: 8),
                      _CountdownDisplay(value: _countdown),
                    ] else
                      const Text(
                        'Presiona el botón para pedir ayuda.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                  ],
                )
              : isCuidador
                  ? _CaregiverView(
                      items: _incoming,
                      onAccept: _acceptIncoming,
                      onDerive: _deriveIncoming,
                    )
                  : const Text(
                      'Rol no reconocido.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
        ),
      ),
    );
  }

  // ===== Acciones de la Vista del Cuidador =====
  Future<void> _acceptIncoming(_IncomingAlert item) async {
    try {
      await AlertasApi.aceptarAlerta(item.alertaId);
      if (!mounted) return;
      if (item.lat != null && item.lon != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MapaAlertaPage(
            lat: item.lat!, lon: item.lon!, alertaId: item.alertaId,
          ),
        ));
      }
      setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo aceptar: $e')));
    }
  }

  Future<void> _deriveIncoming(_IncomingAlert item) async {
    try {
      await AlertasApi.derivarAlerta(item.alertaId);
      if (!mounted) return;
      setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo derivar: $e')));
    }
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
  _IncomingAlert({
    required this.alertaId,
    required this.orden,
    this.lat,
    this.lon,
  });
}

class _CaregiverView extends StatelessWidget {
  final List<_IncomingAlert> items;
  final Future<void> Function(_IncomingAlert) onAccept;
  final Future<void> Function(_IncomingAlert) onDerive;

  const _CaregiverView({
    required this.items,
    required this.onAccept,
    required this.onDerive,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'Sin emergencias por ahora.\nMantén la app abierta para recibir alertas.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final a = items[i];
        return _IncomingCard(
          alertaId: a.alertaId,
          orden: a.orden,
          lat: a.lat,
          lon: a.lon,
          receivedAt: DateTime.now(),
          onAccept: () => onAccept(a),
          onDerive: () => onDerive(a),
        );
      },
    );
  }
}

class _IncomingCard extends StatelessWidget {
  final String alertaId;
  final int orden;
  final double? lat;
  final double? lon;
  final DateTime receivedAt;
  final VoidCallback onAccept;
  final VoidCallback onDerive;

  const _IncomingCard({
    required this.alertaId,
    required this.orden,
    this.lat,
    this.lon,
    required this.receivedAt,
    required this.onAccept,
    required this.onDerive,
  });

  @override
  Widget build(BuildContext context) {
    final ts = TimeOfDay.fromDateTime(receivedAt);
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alerta SOS', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: 'ID', value: alertaId.substring(0, alertaId.length >= 6 ? 6 : alertaId.length)),
                _InfoChip(label: 'Orden', value: '$orden'),
                _InfoChip(label: 'Hora', value: '$hh:$mm'),
                if (lat != null && lon != null)
                  _InfoChip(label: 'GPS', value: '${lat!.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDerive,
                    icon: const Icon(Icons.redo),
                    label: const Text('Derivar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Voy en camino'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class SosBigButton extends StatelessWidget {
  final VoidCallback onPressed;
  const SosBigButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final diameter = (size.width * 0.65).clamp(200.0, 380.0);

    return Semantics(
      label: 'Botón de emergencia SOS',
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(diameter / 2),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6B6B), Color(0xFFFF2E2E)],
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'SOS',
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 6,
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownDisplay extends StatelessWidget {
  final int value;
  const _CountdownDisplay({required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 999);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Derivación en: $v s',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSecondaryContainer),
      ),
    );
  }
}