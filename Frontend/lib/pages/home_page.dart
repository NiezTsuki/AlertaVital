// lib/pages/home_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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
  // ... (código existente) ...

  Future<void> _initializeAuthenticatedServices(String token, String userId) async {
    if (_isServicesInitialized) return;

    print("✅ Usuario autenticado ($userId). Inicializando servicios...");
    AlertasApi.configure(baseUrl: Api.baseUrl, token: token);

    await _initNotifications();
    
    if (_esCuidador) {
      await _fetchPendingAlerts();
    }

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
      setState(() {
        _isServicesInitialized = true;
        _isRealTimeReady = success;
      });
    }
  }

  Future<void> _initNotifications() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    try {
      final fcmToken = await messaging.getToken();
      if (fcmToken != null) {
        print('📱 Firebase Messaging Token: $fcmToken');
        await AlertasApi.registrarFcmToken(fcmToken);
      }
    } catch (e) {
      print('🚨 Error al obtener o registrar el token FCM: $e');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // ✅ SINTAXIS CORREGIDA
      print('🔔 Notificación recibida en primer plano!');
      if (message.notification != null) {
        print('Mensaje: ${message.notification!.body}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.notification!.title ?? 'Nueva Notificación'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );

        if (_esCuidador) {
          _fetchPendingAlerts();
        }
      }
    });
  }

  // ... (el resto del archivo no necesita cambios)
  // ...
  // ... (el resto del archivo no necesita cambios)
  // ...

  bool get _esAdultoMayor => context.read<AuthState>().user?['rol'] == 'ADULTO_MAYOR';
  bool get _esCuidador => context.read<AuthState>().user?['rol'] == 'CUIDADOR';

  // ===== Ciclo de Vida del Widget =====
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthState>();
      final token = auth.token;
      final userId = auth.user?['id'] as String?;

      if (token != null && userId != null) {
        _initializeAuthenticatedServices(token, userId);
      } else {
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
  Timer? _sosTimer, _adultoTrailTimer, _hbTimer;
  int _countdown = 0;
  String? _alertaId;
  String _estadoTexto = 'Listo para ayudar';
  final List<_IncomingAlert> _incoming = [];
  bool _isServicesInitialized = false;
  bool _isRealTimeReady = false;

  Future<void> _fetchPendingAlerts() async {
    try {
      print("[HomePage] Buscando alertas pendientes...");
      final pending = await AlertasApi.getAlertasPendientes();
      if (pending.isNotEmpty) {
        print("[HomePage] Se encontraron ${pending.length} alertas pendientes. Actualizando UI...");
        final newAlerts = pending
            .map((data) => _IncomingAlert.fromJson(data as Map<String, dynamic>))
            .toList();

        if (mounted) {
          setState(() {
            _incoming.clear();
            _incoming.addAll(newAlerts);
          });
        }
      } else {
        print("[HomePage] No hay alertas pendientes.");
      }
    } catch (e) {
      print("🚨 Error al buscar alertas pendientes: $e");
    }
  }

  Future<void> _subscribeToUserChannel(String userId) async {
    final channelName = 'private-user-$userId';
    final userChannel = await AlertasApi.subscribeToChannel(channelName);
    userChannel.onEvent = (event) {
      print('<<<<< [PUSHER EVENT RECIBIDO] Evento: ${event.eventName}, Datos: ${event.data} >>>>>');
      if (!mounted) return;
      
      switch (event.eventName) {
        case 'cuidador_en_camino': _onEnCamino(event); break;
        case 'alerta_completada': _onCompletada(event); break;
        case 'alerta_emergencia': _onEmergencia(event); break;
        case 'asignacion_expirada': _onAsignacionExpirada(event); break;
        case 'alerta_nueva': 
          if (_esCuidador) {
            _onAlertaNueva(event); 
          }
          break;
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

  void _onAsignacionExpirada(PusherEvent event) {
    try {
      final data = jsonDecode(event.data!);
      final alertaId = data['alertaId'] as String?;
      if (alertaId == null) return;

      final index = _incoming.indexWhere((a) => a.alertaId == alertaId);
      if (index != -1) {
        print('[HomePage] Marcando alerta $alertaId como expirada.');
        setState(() {
          _incoming[index].isExpired = true;
        });
      }
    } catch (e) {
      print('Error al procesar asignacion_expirada: $e');
    }
  }

  void _onAlertaNueva(PusherEvent event) {
    try {
      if (event.data == null) return;
      final data = jsonDecode(event.data!);
      final alertaId = data['alertaId']?.toString();
      if (alertaId == null) return;

      if (!_incoming.any((a) => a.alertaId == alertaId)) {
        setState(() {
          _incoming.insert(0, _IncomingAlert.fromJson(data));
        });
      }
    } catch (e) {
      print('💥💥💥 [onAlertaNueva] ERROR CRÍTICO al procesar el evento: $e 💥💥💥');
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

  // ===== Construcción de la UI =====
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

class _IncomingAlert {
  final String alertaId;
  final int orden;
  final double? lat;
  final double? lon;
  bool isExpired;

  _IncomingAlert({
    required this.alertaId,
    required this.orden,
    this.lat,
    this.lon,
    this.isExpired = false,
  });

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
    final bool isExpired = item.isExpired;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      color: isExpired ? Colors.grey.shade200 : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isExpired ? 'Alerta Expirada' : 'Alerta SOS Recibida',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isExpired ? Colors.grey.shade600 : null,
                    decoration: isExpired ? TextDecoration.lineThrough : null,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _InfoChip(icon: Icons.vpn_key_outlined, text: item.alertaId.substring(0, 6)),
                const SizedBox(width: 8),
                if (item.lat != null) const _InfoChip(icon: Icons.location_on_outlined, text: 'GPS Disponible'),
              ],
            ),
            const SizedBox(height: 16),
            if (isExpired)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Tiempo agotado. La alerta fue derivada a otro cuidador.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              )
            else
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: onDerive, child: const Text('Derivar'))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: onAccept, child: const Text('Voy en Camino'))),
              ]),
          ],
        ),
      ),
    );
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