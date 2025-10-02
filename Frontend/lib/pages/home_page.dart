// lib/pages/home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_state.dart';                 // expone: token (String?), user (Map?)
import '../api.dart';                        // para Api.baseUrl
import '../alertas_api.dart';       // API de alertas (HTTP + Socket)

import 'vincular_page.dart';
import 'mis_vinculos_page.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ===== Estado del flujo SOS (adulto) =====
  Timer? _sosTimer;
  int _countdown = 0;
  String? _alertaId;
  String _estadoTexto = 'Listo para ayudar';

  // ===== Estado de cuidador: alertas entrantes =====
  final List<_IncomingAlert> _incoming = [];

  // ===== Helpers de rol/credenciales =====
  bool get _esAdultoMayor {
    final auth = context.read<AuthState>();
    final me = auth.user ?? {};
    return (me['rol'] == 'ADULTO_MAYOR');
  }

  bool get _esCuidador {
    final auth = context.read<AuthState>();
    final me = auth.user ?? {};
    return (me['rol'] == 'CUIDADOR');
  }

  String? get _token => context.read<AuthState>().token;

  // ===== Ciclo de vida =====
  @override
  void initState() {
    super.initState();
    // Conecta socket si hay sesión y cablea listener para cuidadores
    unawaited(_wireCaregiverSocket());
  }

  @override
  void dispose() {
    _stopCountdown();
    super.dispose();
  }

  // ===== Acciones de navegación =====
  void _goVincular() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VincularPage()));
  }

  void _goMisVinculos() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MisVinculosPage()));
  }

  Future<void> _logout() async {
    final auth = context.read<AuthState>();
    try {
      // Si tu AuthState tiene logout(), úsalo:
      await (auth as dynamic).logout?.call();
    } catch (_) {}
    AlertasApi.dispose();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // ===== Socket para cuidador =====
  Future<void> _wireCaregiverSocket() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    // Conecta socket de alertas (idempotente)
    AlertasApi.configure(baseUrl: Api.baseUrl, token: token);
    await AlertasApi.initSocket();

    if (_esCuidador) {
      // Evita duplicados en hot-reload
      AlertasApi.off('alerta_nueva');
      AlertasApi.on('alerta_nueva', (data) {
        final alertaId = (data?['alertaId'] ?? '').toString();
        final orden = (data?['orden'] ?? 1) as int;
        if (alertaId.isEmpty || !mounted) return;

        // Si ya está en la lista, no la duplicamos
        final exists = _incoming.any((a) => a.alertaId == alertaId);
        if (!exists) {
          setState(() {
            _incoming.insert(0, _IncomingAlert(alertaId: alertaId, orden: orden));
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nueva alerta SOS')),
        );
      });
    }
  }

  // ===== Flujo SOS (adulto mayor) =====
  Future<void> _initAlertSocketIfNeeded() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    AlertasApi.configure(baseUrl: Api.baseUrl, token: token);
    await AlertasApi.initSocket();
  }

  Future<void> _onSosPressed() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión no válida. Inicia sesión nuevamente.')),
      );
      return;
    }

    try {
      await _initAlertSocketIfNeeded();

      // 1) Crear alerta
      final r = await AlertasApi.crearSOS(countdown: 30, tipo: 'SOS');
      final id = (r['alertaId'] ?? '').toString();
      if (id.isEmpty) throw Exception('No se pudo crear la alerta');

      setState(() {
        _alertaId = id;
        _countdown = (r['countdown'] ?? 30) as int;
        _estadoTexto = 'Notificando al cuidador más cercano…';
      });

      // 2) Unirse a la sala de la alerta
      AlertasApi.joinAlerta(id);

      // 3) Listeners
      AlertasApi.on('cuidador_en_camino', _onEnCamino);
      AlertasApi.on('derivada_siguiente', _onDerivada);
      AlertasApi.on('alerta_completada', _onCompletada);
      AlertasApi.on('alerta_emergencia', _onEmergencia);

      // 4) Countdown visual
      _startCountdown();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alerta enviada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _onEnCamino(dynamic _) {
    if (!mounted) return;
    setState(() => _estadoTexto = '¡Tu cuidador va en camino!');
  }

  void _onDerivada(dynamic _) {
    if (!mounted) return;
    setState(() {
      _estadoTexto = 'Derivando al siguiente cuidador…';
      _countdown = 30; // visual; el backend reinicia el real
    });
  }

  void _onCompletada(dynamic _) {
    if (!mounted) return;
    setState(() => _estadoTexto = 'Alerta finalizada.');
    _stopCountdown();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _alertaId = null);
    });
  }

  void _onEmergencia(dynamic _) {
    if (!mounted) return;
    setState(() => _estadoTexto = 'Sin cuidadores disponibles.\nLlamado de emergencia realizado.');
    _stopCountdown();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _alertaId = null);
    });
  }

  void _startCountdown() {
    _stopCountdown();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdown > 0) setState(() => _countdown--);
    });
  }

  void _stopCountdown() {
    _sosTimer?.cancel();
    _sosTimer = null;
  }

  // ===== UI =====
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

  // ===== Acciones de la vista del cuidador =====
  Future<void> _acceptIncoming(_IncomingAlert item) async {
    try {
      await AlertasApi.aceptarAlerta(item.alertaId);
      if (!mounted) return;
      setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Vas en camino!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aceptar: $e')),
      );
    }
  }

  Future<void> _deriveIncoming(_IncomingAlert item) async {
    try {
      await AlertasApi.derivarAlerta(item.alertaId);
      if (!mounted) return;
      setState(() => _incoming.removeWhere((e) => e.alertaId == item.alertaId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Derivaste la alerta')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo derivar: $e')),
      );
    }
  }
}

// ====== MODELO SIMPLE PARA LA VISTA DEL CUIDADOR ======
class _IncomingAlert {
  final String alertaId;
  final int orden;
  final DateTime receivedAt;
  _IncomingAlert({
    required this.alertaId,
    required this.orden,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();
}

// ====== WIDGET: LISTA DE ALERTAS PARA EL CUIDADOR ======
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final a = items[i];
          return _IncomingCard(
            alertaId: a.alertaId,
            orden: a.orden,
            receivedAt: a.receivedAt,
            onAccept: () => onAccept(a),
            onDerive: () => onDerive(a),
          );
        },
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  final String alertaId;
  final int orden;
  final DateTime receivedAt;
  final VoidCallback onAccept;
  final VoidCallback onDerive;

  const _IncomingCard({
    required this.alertaId,
    required this.orden,
    required this.receivedAt,
    required this.onAccept,
    required this.onDerive,
  });

  @override
  Widget build(BuildContext context) {
    final ts = TimeOfDay.fromDateTime(receivedAt);
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alerta SOS', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(
              children: [
                _InfoChip(label: 'ID', value: alertaId.substring(0, alertaId.length >= 6 ? 6 : alertaId.length)),
                const SizedBox(width: 8),
                _InfoChip(label: 'Orden', value: '$orden'),
                const SizedBox(width: 8),
                _InfoChip(label: 'Hora', value: '$hh:$mm'),
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
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ================== Botón SOS grande y circular ==================
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
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8)),
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

// ================== Widgets auxiliares (adulto) ==================
class _CountdownDisplay extends StatelessWidget {
  final int value;
  const _CountdownDisplay({required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 999);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
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
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}
