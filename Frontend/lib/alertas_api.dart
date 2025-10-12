// lib/services/alertas_api.dart
//
// API y Socket.IO exclusivos para ALERTAS.
// ✔ Compatible con Flutter Web (usa auth.token en el handshake)
// ✔ Mantiene extraHeaders para Android/iOS/Desktop
// ✔ Endpoints: crearSOS, aceptarAlerta, derivarAlerta, completarAlerta
// ✔ Ubicaciones: registrarUbicacion(), registrarPosicionAlerta(), getPosiciones()
//
// Uso típico:
//   AlertasApi.configure(baseUrl: Api.baseUrl, token: token);
//   await AlertasApi.initSocket();
//   final r = await AlertasApi.crearSOS(countdown: 30, lat: ..., lon: ...);
//   AlertasApi.joinAlerta(r['alertaId']);
//   // Tracking:
//   await AlertasApi.registrarPosicionAlerta(r['alertaId'], lat, lon, precision);

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class AlertasApi {
  // ===== Config =====
  static String _baseUrl = const String.fromEnvironment('API_BASE',
    defaultValue: 'https://alerta-vital-nine.vercel.app'); // <-- TU URL DE VERCEL AQUÍ
  static String? _token;

  /// Configura/actualiza baseUrl y token.
  static void configure({required String baseUrl, required String token}) {
    _baseUrl = baseUrl;
    _token = token;
  }

  // ===== HTTP helpers =====
  static Uri _uri(String path, [Map<String, dynamic>? q]) {
    if (!path.startsWith('/')) path = '/$path';
    final uri = Uri.parse('$_baseUrl$path');
    if (q == null || q.isEmpty) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      ...q.map((k, v) => MapEntry(k, v?.toString())),
    });
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
    double? lat,
    double? lon,
    double? precision,
  }) async {
    final body = <String, dynamic>{
      'tipo': tipo,
      'descripcion': descripcion,
      'countdown': countdown,
    };
    if (lat != null && lon != null) {
      body['latitud'] = lat;
      body['longitud'] = lon;
      if (precision != null) body['precision_metros'] = precision;
    }

    final resp = await http.post(
      _uri('/api/alertas/sos'),
      headers: _headers(),
      body: jsonEncode(body),
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

  // ===== Ubicaciones (entrenamiento/proximidad) =====

  /// Registrar ubicación actual del usuario (cuidadores/adultos) para cercanía y ML
  static Future<void> registrarUbicacion(double lat, double lon, {double? precision}) async {
    final resp = await http.post(
      _uri('/api/ubicaciones'),
      headers: _headers(),
      body: jsonEncode({
        'latitud': lat,
        'longitud': lon,
        if (precision != null) 'precision_metros': precision,
      }),
    );
    _parse(resp);
  }

  /// Guardar punto de traza asociado a una alerta (rol del token: ADULTO_MAYOR/CUIDADOR)
  static Future<void> registrarPosicionAlerta(
    String alertaId,
    double lat,
    double lon, {
    double? precision,
  }) async {
    final resp = await http.post(
      _uri('/api/alertas/$alertaId/posicion'),
      headers: _headers(),
      body: jsonEncode({
        'latitud': lat,
        'longitud': lon,
        if (precision != null) 'precision_metros': precision,
      }),
    );
    _parse(resp);
  }

  /// Obtener últimos puntos de una alerta (para pintar rutas) – opcional
  static Future<List<dynamic>> getPosiciones(String alertaId, {String? rol}) async {
    final resp = await http.get(
      _uri('/api/alertas/$alertaId/posiciones', {if (rol != null) 'rol': rol}),
      headers: _headers(),
    );
    final data = _parse(resp);
    if (data == null) return <dynamic>[];
    return (data as List).cast<dynamic>();
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
    s.connect();

    _socket = s;
    _socketJwt = jwt;
  }

  static bool get isSocketConnected => _socket?.connected == true;

  /// Unirse a la sala de la alerta (adulto mayor abre su pantalla SOS)
  static void joinAlerta(String alertaId) {
    if (_socket?.connected == true) {
      _socket!.emit('join_alerta', {'alertaId': alertaId});
    }
  }

  /// Listeners de eventos:
  /// 'alerta_nueva', 'cuidador_en_camino', 'derivada_siguiente',
  /// 'alerta_completada', 'alerta_emergencia'
  static void on(String event, void Function(dynamic) handler) => _socket?.on(event, handler);
  static void off(String event, [void Function(dynamic)? handler]) => _socket?.off(event, handler);

  /// Cierra el socket (por ejemplo, al cerrar sesión)
  static void dispose() {
    try { _socket?.dispose(); } catch (_) {}
    _socket = null;
    _socketJwt = null;
  }
}
