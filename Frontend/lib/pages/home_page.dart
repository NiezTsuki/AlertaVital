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
import 'aceptar_vinculo_page.dart';

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
  bool _isRealTimeReady = false;

  // ===== Getters de conveniencia =====
  bool get _esAdultoMayor => context.read<AuthState>().user?['rol'] == 'ADULTO_MAYOR';
  bool get _esCuidador => context.read<AuthState>().user?['rol'] == 'CUIDADOR';

  // ===== Ciclo de Vida del Widget =====
  @override
  void initState() {
    super.initState();
    // ✅ CORRECCIÓN: La inicialización se dispara aquí, de forma segura,
    // después de que el widget se haya construido por primera vez.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthState>();
      final token = auth.token;
      // El 'user' y su 'id' vienen del flujo de autenticación anterior (RootPage).
      final userId = auth.user?['id'] as String?;

      if (token != null && userId != null) {
        _initializeAuthenticatedServices(token, userId);
      } else {
        // Fallback de seguridad: si por alguna razón llegamos aquí sin datos, deslogueamos.
        print("🔴 ERROR CRÍTICO: HomePage cargada sin datos de usuario. Forzando logout.");
        _logout();
      }
    });
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
  Future<void> _initializeAuthenticatedServices(String token, String userId) async {
    if (_isServicesInitialized) return;

    print("✅ Usuario autenticado ($userId). Inicializando servicios...");
    AlertasApi.configure(baseUrl: Api.baseUrl, token: token);

    await _sendLocationOnce(token);
    _startHeartbeatUbicacion(token);

    final success = await AlertasApi.initPusher(
      apiKey: '67c27146be09c306d1f7',
      cluster: 'us2',
    );

    if (mounted) {
      if (success) {
        print("✅ Conexión con Pusher exitosa. Suscribiendo a canales...");
        _subscribeToUserChannel(userId);
      } else {
        print("❌ Falló la conexión con Pusher.");
      }
      // Marcamos que la inicialización ha terminado y actualizamos la UI.
      setState(() {
        _isServicesInitialized = true;
        _isRealTimeReady = success;
      });
    }
  }

  Future<void> _subscribeToUserChannel(String userId) async {
    final channelName = 'private-user-$userId';
    final userChannel = await AlertasApi.subscribeToChannel(channelName);
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
  
  // ===== Timers y GPS =====
  void _startHeartbeatUbicacion(String token) { 
    _hbTimer?.cancel();
    _hbTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      await _sendLocationOnce(token);
    });
  }
  
  Future<void> _sendLocationOnce(String token) async {
    final pos = await _getCurrentPosition();
    if (pos != null) {
      try {
        await AlertasApi.registrarUbicacion(pos.latitude, pos.longitude, precision: pos.accuracy);
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
  
  void _goInvitar() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VincularPage()));
  void _goAceptarVinculo() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AceptarVinculoPage()));
  void _goMisVinculos() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MisVinculosPage()));
  
  Future<void> _logout() async {
    _hbTimer?.cancel();
    await context.read<AuthState>().logout();
    AlertasApi.dispose();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  // ===== Construcción de la UI (REDISEÑADA) =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_esAdultoMayor ? 'AlertaVital' : 'AlertaVital — Cuidador'),
        actions: [
          IconButton(tooltip: 'Enviar Invitación', icon: const Icon(Icons.link), onPressed: _goInvitar),
          IconButton(tooltip: 'Aceptar Invitación', icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: _goAceptarVinculo),
          IconButton(tooltip: 'Mis Vínculos', icon: const Icon(Icons.group_outlined), onPressed: _goMisVinculos),
          IconButton(tooltip: 'Cerrar Sesión', icon: const Icon(Icons.power_settings_new), onPressed: _logout),
        ],
      ),
      body: Center(
        // ✅ CORRECCIÓN DEFINITIVA: La UI ahora depende de _isServicesInitialized.
        // Mientras los servicios no se hayan inicializado, mostramos la rueda de carga.
        child: !_isServicesInitialized
            ? const CircularProgressIndicator()
            : (_esAdultoMayor ? _buildVistaAdultoMayor() : _buildVistaCuidador()),
      ),
    );
  }

  Widget _buildVistaAdultoMayor() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          SosBigButton(onPressed: _isRealTimeReady && _alertaId == null ? _onSosPressed : null),
          const SizedBox(height: 24),
          !_isRealTimeReady
              ? const _StatusChip(text: 'Conectando al servicio de alertas...', color: Colors.orange)
              : _alertaId != null 
                ? Column(children: [
                    _StatusChip(text: _estadoTexto, color: Theme.of(context).colorScheme.secondaryContainer),
                    const SizedBox(height: 8),
                    _CountdownDisplay(value: _countdown),
                  ])
                : const _StatusChip(text: 'Presiona el botón para pedir ayuda', color: Colors.transparent),
          const Spacer(flex: 3),
        ],
      ),
    );
  }

  Widget _buildVistaCuidador() {
    if (!_isRealTimeReady) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Card(
          color: Colors.amber.shade100,
          child: const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '⚠️ No se pudo conectar al servicio de alertas. No recibirás notificaciones.\n\nRevisa tu conexión a internet e intenta reiniciar la aplicación.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        ),
      );
    }
    return _CaregiverView(
      items: _incoming,
      onAccept: _acceptIncoming,
      onDerive: _deriveIncoming,
    );
  }
}


// ============================================================================
// WIDGETS Y CLASES AUXILIARES (Sin cambios)
// ============================================================================
class _IncomingAlert {
  final String alertaId;
  final int orden;
  final double? lat;
  final double? lon;
  _IncomingAlert({required this.alertaId, required this.orden, this.lat, this.lon});
  factory _IncomingAlert.fromJson(Map<String, dynamic> json) => _IncomingAlert(
      alertaId: json['alertaId'] as String,
      orden: (json['orden'] as num?)?.toInt() ?? 1,
      lat: (json['latitud'] as num?)?.toDouble(),
      lon: (json['longitud'] as num?)?.toDouble(),
    );
}

class _CaregiverView extends StatelessWidget {
  final List<_IncomingAlert> items;
  final Future<void> Function(_IncomingAlert) onAccept;
  final Future<void> Function(_IncomingAlert) onDerive;
  const _CaregiverView({required this.items, required this.onAccept, required this.onDerive});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.notifications_active_outlined, size: 80, color: Colors.grey.shade400), const SizedBox(height: 16), Text('Sin emergencias por ahora', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8), Text('Mantén la app abierta para recibir alertas.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)), ], );
    }
    return ListView.builder( padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, i) => _IncomingCard(item: items[i], onAccept: () => onAccept(items[i]), onDerive: () => onDerive(items[i])), );
  }
}

class _IncomingCard extends StatelessWidget {
  final _IncomingAlert item;
  final VoidCallback onAccept;
  final VoidCallback onDerive;
  const _IncomingCard({required this.item, required this.onAccept, required this.onDerive});

  @override
  Widget build(BuildContext context) {
    return Card( elevation: 4, margin: const EdgeInsets.only(bottom: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding( padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Alerta SOS Recibida', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 12), Row( children: [ _InfoChip(icon: Icons.vpn_key_outlined, text: item.alertaId.substring(0, 6)), const SizedBox(width: 8), if (item.lat != null) const _InfoChip(icon: Icons.location_on_outlined, text: 'GPS Disponible'), ], ), const SizedBox(height: 16), Row(children: [ Expanded(child: OutlinedButton(onPressed: onDerive, child: const Text('Derivar'))), const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: onAccept, child: const Text('Voy en Camino'))), ]), ]), ), );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [ Icon(icon, size: 16, color: Colors.grey.shade700), const SizedBox(width: 6), Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade800)), ]), );
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
    return InkWell( onTap: onPressed, borderRadius: BorderRadius.circular(diameter / 2), child: Container( width: diameter, height: diameter, decoration: BoxDecoration( shape: BoxShape.circle, color: isEnabled ? Colors.red : Colors.grey.shade400, boxShadow: isEnabled ? [ BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 25, spreadRadius: 5) ] : [], ), alignment: Alignment.center, child: const Text('SOS', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 6)), ), );
  }
}

class _CountdownDisplay extends StatelessWidget {
  final int value;
  const _CountdownDisplay({required this.value});
  @override
  Widget build(BuildContext context) => Text('Derivación en: ${value.clamp(0, 999)} s', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700));
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container( padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)), child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSecondaryContainer)), );
  }
}