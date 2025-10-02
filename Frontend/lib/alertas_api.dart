// lib/services/alertas_api.dart
//
// API y Socket.IO exclusivos para ALERTAS.
// ✔ Compatible con Flutter Web (usa auth.token en el handshake)
// ✔ Mantiene extraHeaders para Android/iOS/Desktop
// ✔ Endpoints: crearSOS, aceptarAlerta, derivarAlerta, completarAlerta
//
// Uso:
//   AlertasApi.configure(baseUrl: Api.baseUrl, token: token);
//   await AlertasApi.initSocket();
//   final r = await AlertasApi.crearSOS(countdown: 30);
//   AlertasApi.joinAlerta(r['alertaId']);
//   AlertasApi.on('alerta_nueva', (d) { ... });

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class AlertasApi {
  // ===== Config =====
  static String _baseUrl =
      const String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:3000');
  static String? _token;

  /// Configura/actualiza baseUrl y token.
  static void configure({required String baseUrl, required String token}) {
    _baseUrl = baseUrl;
    _token = token;
  }

  // ===== HTTP helpers =====
  static Uri _uri(String path) {
    if (!path.startsWith('/')) path = '/$path';
    return Uri.parse('$_baseUrl$path');
  }

  static Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final t = _token;
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  static dynamic _parse(http.Response resp) {
    final body = resp.body;
    final data = body.isEmpty ? null : jsonDecode(body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return data;
    throw Exception((data is Map && data['error'] != null) ? data['error'] : 'HTTP ${resp.statusCode}');
  }

  // ===== Endpoints ALERTAS =====

  /// Adulto mayor crea una alerta SOS/CAIDA
  /// Respuesta: { ok, alertaId, countdown, firstAssigned }
  static Future<Map<String, dynamic>> crearSOS({
    int countdown = 30,
    String tipo = 'SOS',
    String? descripcion,
  }) async {
    final resp = await http.post(
      _uri('/api/alertas/sos'),
      headers: _headers(),
      body: jsonEncode({'tipo': tipo, 'descripcion': descripcion, 'countdown': countdown}),
    );
    final data = _parse(resp);
    return (data as Map).cast<String, dynamic>();
  }

  /// Cuidador: “Voy en camino”
  static Future<void> aceptarAlerta(String alertaId) async {
    final resp = await http.post(
      _uri('/api/alertas/$alertaId/aceptar'),
      headers: _headers(),
    );
    _parse(resp);
  }

  /// Cuidador: “Derivar”
  static Future<void> derivarAlerta(String alertaId) async {
    final resp = await http.post(
      _uri('/api/alertas/$alertaId/derivar'),
      headers: _headers(),
    );
    _parse(resp);
  }

  /// (Opcional) Completar/cerrar alerta
  static Future<void> completarAlerta(String alertaId) async {
    final resp = await http.post(
      _uri('/api/alertas/$alertaId/completar'),
      headers: _headers(),
    );
    _parse(resp);
  }

  // ===== Socket.IO SOLO para alertas =====
  static IO.Socket? _socket;
  static String? _socketJwt; // para evitar reconectar con el mismo token

  static String _socketOriginFromBase(String base) {
    final u = Uri.parse(base);
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}'; // ej: http://10.0.2.2:3000
  }

  /// Inicializa el socket con el token configurado. Llama después de `configure`.
  static Future<void> initSocket() async {
    final jwt = _token;
    if (jwt == null || jwt.isEmpty) return;

    if (_socket != null && _socket!.connected && _socketJwt == jwt) return;

    try { _socket?.dispose(); } catch (_) {}
    _socket = null;

    final origin = _socketOriginFromBase(_baseUrl);

    // ✅ CLAVE PARA WEB: enviar token en auth (handshake.auth.token)
    final builder = IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setAuth({'token': jwt});

    // Mantén también extraHeaders por compatibilidad con nativo/desktop
    builder.setExtraHeaders({'Authorization': 'Bearer $jwt'});

    final opts = builder.build();
    final s = IO.io(origin, opts);

    // (Opcionales) logs:
    // s.onConnect((_) => debugPrint('[alertas] socket connected'));
    // s.onDisconnect((_) => debugPrint('[alertas] socket disconnected'));
    // s.onError((e) => debugPrint('[alertas] socket error: $e'));

    s.connect();

    _socket = s;
    _socketJwt = jwt;
  }

  static bool get isSocketConnected => _socket?.connected == true;

  /// Unirse a la sala de una alerta (adulto mayor abre su pantalla SOS)
  static void joinAlerta(String alertaId) {
    if (_socket?.connected == true) {
      _socket!.emit('join_alerta', {'alertaId': alertaId});
    }
  }

  /// Listeners de eventos: 'alerta_nueva', 'cuidador_en_camino', 'derivada_siguiente', 'alerta_completada', 'alerta_emergencia'
  static void on(String event, void Function(dynamic) handler) => _socket?.on(event, handler);
  static void off(String event, [void Function(dynamic)? handler]) => _socket?.off(event, handler);

  /// Cierra el socket (por ejemplo, al cerrar sesión)
  static void dispose() {
    try { _socket?.dispose(); } catch (_) {}
    _socket = null;
    _socketJwt = null;
  }
}
