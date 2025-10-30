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
import 'asistente_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _sosTimer, _adultoTrailTimer, _hbTimer;
  int _countdown = 0;
  String? _alertaId;
  String _estadoTexto = 'Listo para ayudar';
  final List<_IncomingAlert> _incoming = [];
  bool _isServicesInitialized = false;
  bool _isRealTimeReady = false;

  bool get _esAdultoMayor => context.read<AuthState>().user?['rol'] == 'ADULTO_MAYOR';
  bool get _esCuidador => context.read<AuthState>().user?['rol'] == 'CUIDADOR';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthState>();
      if (auth.token != null && auth.user?['id'] != null) {
        _initializeAuthenticatedServices(auth.token!, auth.user!['id']);
      } else {
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

  Future<void> _initializeAuthenticatedServices(String token, String userId) async {
    if (_isServicesInitialized) return;
    AlertasApi.configure(baseUrl: Api.baseUrl, token: token);
    await _requestEssentialPermissions();
    if (_esCuidador) await _fetchPendingAlerts();
    await _sendLocationOnce(token);
    _startHeartbeatUbicacion(token);
    final success = await AlertasApi.initPusher(apiKey: '67c27146be09c306d1f7', cluster: 'us2');
    if (mounted) {
      if (success) _subscribeToUserChannel(userId);
      setState(() { _isServicesInitialized = true; _isRealTimeReady = success; });
    }
  }

  Future<void> _requestEssentialPermissions() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El permiso de ubicación fue negado permanentemente.')));
    }
    await _initNotifications(messaging);
  }

  Future<void> _initNotifications(FirebaseMessaging messaging) async {
    try {
      final fcmToken = await messaging.getToken();
      if (fcmToken != null) await AlertasApi.registrarFcmToken(fcmToken);
    } catch (e) { print('🚨 Error al obtener o registrar el token FCM: $e'); }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data.isNotEmpty && _esAdultoMayor && message.data['tipo'] == 'ALERTA_ACEPTADA') {
        final textoMensaje = message.data['mensaje'] as String?;
        if (mounted) setState(() { _estadoTexto = textoMensaje ?? '¡Un cuidador va en camino!'; _stopCountdown(); });
      }
      if (message.notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.notification!.title ?? 'Nueva Notificación')));
        if (_esCuidador) _fetchPendingAlerts();
      }
    });
  }

  Future<void> _fetchPendingAlerts() async {
    try {
      final pending = await AlertasApi.getAlertasPendientes();
      if (pending.isNotEmpty && mounted) {
        final newAlerts = pending.map((data) => _IncomingAlert.fromJson(data as Map<String, dynamic>)).toList();
        setState(() { _incoming.clear(); _incoming.addAll(newAlerts); });
      } else if (mounted) {
        setState(() { _incoming.clear(); });
      }
    } catch (e) { print("🚨 Error al buscar alertas pendientes: $e"); }
  }

  Future<void> _subscribeToUserChannel(String userId) async {
    final channelName = 'private-user-$userId';
    final userChannel = await AlertasApi.subscribeToChannel(channelName);
    userChannel.onEvent = (event) {
      if (!mounted) return;
      switch (event.eventName) {
        case 'asignacion_expirada': _onAsignacionExpirada(event); break;
        case 'alerta_nueva': if (_esCuidador) _onAlertaNueva(event); break;
      }
    };
  }
  
  Future<void> _onSosPressed() async {
    try {
      final pos = await _getCurrentPosition();
      if (pos == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo obtener la ubicación. Activa el GPS y concede los permisos.')));
        return;
      }
      final r = await AlertasApi.crearSOS(lat: pos.latitude, lon: pos.longitude, precision: pos.accuracy);
      final id = r['alertaId']?.toString();
      if (id == null) throw Exception('No se pudo crear la alerta');
      
      final alertaChannel = await AlertasApi.subscribeToChannel('private-alerta-$id');
      alertaChannel.onEvent = (event) {
        if (!mounted) return;
        switch (event.eventName) {
          case 'derivada_siguiente': _onDerivada(event); break;
          case 'cuidador_en_camino': _onEnCamino(event); break;
          case 'alerta_completada': _onCompletada(event); break;
        }
      };

      setState(() {
        _alertaId = id;
        _countdown = (r['countdown'] as int?) ?? 90;
        _estadoTexto = 'Notificando al cuidador más cercano…';
      });
      _startCountdown();
      _startAdultoTrail();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al crear alerta: $e')));
    }
  }

  void _onAsignacionExpirada(PusherEvent event) {
    try {
      final data = jsonDecode(event.data!);
      final alertaId = data['alertaId'] as String?;
      if (alertaId != null) {
        final index = _incoming.indexWhere((a) => a.alertaId == alertaId);
        if (index != -1 && mounted) {
          setState(() => _incoming[index].isExpired = true);
        }
      }
    } catch (e) { print('Error procesando asignacion_expirada: $e'); }
  }

  void _onAlertaNueva(PusherEvent event) {
    try {
      if (event.data == null) return;
      final data = jsonDecode(event.data!);
      final alertaId = data['alertaId']?.toString();
      if (alertaId != null && !_incoming.any((a) => a.alertaId == alertaId) && mounted) {
        setState(() => _incoming.insert(0, _IncomingAlert.fromJson(data)));
      }
    } catch (e) { print('💥 ERROR procesando alerta_nueva: $e'); }
  }

  void _onEnCamino(PusherEvent? e) {
    if (mounted) setState(() { _estadoTexto = '¡Tu cuidador va en camino!'; _stopCountdown(); });
  }

  void _onDerivada(PusherEvent? e) { if(mounted) setState(() => _estadoTexto = 'Derivando al siguiente cuidador…'); }
  void _onCompletada(PusherEvent? e) => _resetAlerta('Alerta finalizada.');
  
  void _resetAlerta(String finalState) {
    if (!mounted) return;
    setState(() => _estadoTexto = finalState);
    _stopCountdown();
    _stopAdultoTrail();
    if (_alertaId != null) AlertasApi.unsubscribeFromChannel('private-alerta-${_alertaId!}');
    Future.delayed(const Duration(seconds: 4), () { if (mounted) setState(() => _alertaId = null); });
  }
  
  void _startCountdown() { _sosTimer?.cancel(); _sosTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && _countdown > 0) setState(() => _countdown--); }); }
  void _stopCountdown() { _sosTimer?.cancel(); if (mounted) setState(() {}); }
  
  void _startAdultoTrail() {
    _stopAdultoTrail();
    if (_alertaId == null) return;
    _adultoTrailTimer = Timer.periodic(const Duration(seconds: 7), (_) async {
      if (_alertaId == null || !mounted) return;
      final pos = await _getCurrentPosition();
      if (pos != null) {
        try { await AlertasApi.registrarPosicionAlerta(_alertaId!, pos.latitude, pos.longitude, precision: pos.accuracy); } catch (_) {}
      }
    });
  }
  void _stopAdultoTrail() => _adultoTrailTimer?.cancel();
  
  void _startHeartbeatUbicacion(String token) { 
    _hbTimer?.cancel();
    _hbTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (mounted) await _sendLocationOnce(token);
    });
  }
  
  Future<void> _sendLocationOnce(String token) async {
    final pos = await _getCurrentPosition();
    if (pos != null) {
      try { await AlertasApi.registrarUbicacion(pos.latitude, pos.longitude, precision: pos.accuracy); } catch (_) {}
    }
  }
  
  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      print("Error obteniendo posición: $e");
      return null;
    }
  }

  // ===== ACCIONES DE UI (CORREGIDAS Y CON LOGS) =====
  Future<void> _acceptIncoming(_IncomingAlert item) async {
    print("📲 Botón 'Aceptar' presionado para alerta: ${item.alertaId}");
    try {
      await AlertasApi.aceptarAlerta(item.alertaId);
      print("✅ API 'aceptarAlerta' exitosa. Actualizando UI...");
      if (!mounted) return;
      
      setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
      
      if (item.lat != null && item.lon != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapaAlertaPage(alertaId: item.alertaId, lat: item.lat!, lon: item.lon!)));
      }
    } catch (e) {
      print("❌ Error al aceptar alerta: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al aceptar la alerta: $e')));
    }
  }

  Future<void> _deriveIncoming(_IncomingAlert item) async {
    print("📲 Botón 'Derivar' presionado para alerta: ${item.alertaId}");
    try {
      await AlertasApi.derivarAlerta(item.alertaId);
      print("✅ API 'derivarAlerta' exitosa. Actualizando UI...");
      if (mounted) {
        // ✅ CORRECCIÓN: La actualización del estado ahora está dentro del 'if (mounted)'
        setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
      }
    } catch (e) {
      print("❌ Error al derivar alerta: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al derivar la alerta: $e')));
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_esAdultoMayor ? 'AlertaVital' : 'AlertaVital — Cuidador'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'invitar': _goInvitar(); break;
                case 'aceptar': _goAceptarVinculo(); break;
                case 'vinculos': _goMisVinculos(); break;
                case 'logout': _logout(); break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'invitar', child: ListTile(leading: Icon(Icons.link), title: Text('Enviar Invitación'))),
              const PopupMenuItem<String>(value: 'aceptar', child: ListTile(leading: Icon(Icons.person_add_alt_1), title: Text('Aceptar Invitación'))),
              const PopupMenuItem<String>(value: 'vinculos', child: ListTile(leading: Icon(Icons.group_outlined), title: Text('Mis Vínculos'))),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'logout', child: ListTile(leading: Icon(Icons.power_settings_new), title: Text('Cerrar Sesión'))),
            ],
          ),
        ],
      ),
      body: Center(
        child: !_isServicesInitialized
            ? const CircularProgressIndicator()
            : (_esAdultoMayor ? _buildVistaAdultoMayor() : _buildVistaCuidador()),
      ),
      floatingActionButton: _esAdultoMayor
        ? FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AsistentePage()));
            },
            tooltip: 'Asistente de Compañía',
            child: const Icon(Icons.support_agent),
          )
        : null,
    );
  }

  Widget _buildVistaAdultoMayor() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
          const Spacer(flex: 2),
          SosBigButton(onPressed: _isRealTimeReady && _alertaId == null ? _onSosPressed : null),
          const SizedBox(height: 24),
          !_isRealTimeReady
              ? const _StatusChip(text: 'Conectando...', color: Colors.orange)
              : _alertaId != null 
                ? Column(children: [
                    _StatusChip(text: _estadoTexto, color: Theme.of(context).colorScheme.secondaryContainer),
                    const SizedBox(height: 8),
                    if (_sosTimer?.isActive ?? false) _CountdownDisplay(value: _countdown),
                  ])
                : const _StatusChip(text: 'Presiona para pedir ayuda', color: Colors.transparent),
          const Spacer(flex: 3),
        ],
      ),
    );
  }

  Widget _buildVistaCuidador() {
    return _CaregiverView(
      isReady: _isRealTimeReady,
      items: _incoming,
      onAccept: _acceptIncoming,
      onDerive: _deriveIncoming,
    );
  }
}

// ============================================================================
// WIDGETS Y CLASES AUXILIARES
// ============================================================================

class _IncomingAlert {
  final String alertaId;
  final String adultoNombre;
  final int orden;
  final double? lat;
  final double? lon;
  bool isExpired;

  _IncomingAlert({ required this.alertaId, required this.adultoNombre, required this.orden, this.lat, this.lon, this.isExpired = false });

  factory _IncomingAlert.fromJson(Map<String, dynamic> json) => _IncomingAlert(
      alertaId: json['alertaId'] as String,
      adultoNombre: json['adultoNombre'] as String? ?? 'Nombre no disponible',
      orden: (json['orden'] as num?)?.toInt() ?? 1,
      lat: (json['latitud'] as num?)?.toDouble(),
      lon: (json['longitud'] as num?)?.toDouble(),
    );
}

class _CaregiverView extends StatelessWidget {
  final bool isReady;
  final List<_IncomingAlert> items;
  final Future<void> Function(_IncomingAlert) onAccept;
  final Future<void> Function(_IncomingAlert) onDerive;
  const _CaregiverView({required this.isReady, required this.items, required this.onAccept, required this.onDerive});

  @override
  Widget build(BuildContext context) {
    if (!isReady) return const _ErrorCard(message: '⚠️ No se pudo conectar al servicio de alertas. No recibirás notificaciones.');
    if (items.isEmpty) return Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.notifications_active_outlined, size: 80, color: Colors.grey.shade400), const SizedBox(height: 16), Text('Sin emergencias por ahora', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8), Text('Mantén la app abierta para recibir alertas.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)), ], );
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
    final theme = Theme.of(context);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      color: isExpired ? Colors.grey.shade200 : theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isExpired ? 'Alerta Expirada' : '¡Alerta de Emergencia!',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: isExpired ? Colors.grey.shade600 : theme.colorScheme.error),
            ),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.person_outline, label: 'Adulto Mayor:', value: item.adultoNombre),
            const SizedBox(height: 8),
            _InfoRow(icon: Icons.location_on_outlined, label: 'Ubicación:', value: item.lat != null ? 'GPS Disponible' : 'No disponible'),
            const Divider(height: 24),
            if (isExpired)
              const Center(child: Text('Tiempo agotado. La alerta fue derivada.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)))
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.redo_outlined),
                    label: const Text('Derivar'),
                    onPressed: onDerive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.directions_run),
                    label: const Text('Voy en Camino'),
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      foregroundColor: theme.colorScheme.onPrimary,
                      backgroundColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
        Icon(icon, color: Theme.of(context).textTheme.bodySmall?.color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
      ],
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
class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding( padding: const EdgeInsets.all(32.0), child: Card( color: Colors.amber.shade100, child: Padding( padding: const EdgeInsets.all(16.0), child: Text( message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w500, height: 1.4), ), ), ), );
  }
}