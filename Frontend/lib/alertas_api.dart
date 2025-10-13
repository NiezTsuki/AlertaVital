import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class AlertasApi {
  // ===== Configuración =====

  // Esta es la URL base para las peticiones HTTP de las alertas.
  // La función `configure` puede sobreescribirla, pero este
  // valor por defecto asegura que siempre apunte a Vercel.
  static String _baseUrl = const String.fromEnvironment('API_BASE',
      defaultValue: 'https://alerta-vital-nine.vercel.app');
  static String? _token;

  /// Configura/actualiza baseUrl y token.
  static void configure({required String baseUrl, required String token}) {
    _baseUrl = baseUrl;
    _token = token;
  }

  // ===== Ayudantes HTTP =====
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

  // ===== Endpoints de ALERTAS =====

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

  static Future<void> aceptarAlerta(String alertaId) async {
    final resp = await http.post(
      _uri('/api/alertas/$alertaId/aceptar'),
      headers: _headers(),
    );
    _parse(resp);
  }

  static Future<void> derivarAlerta(String alertaId) async {
    final resp = await http.post(
      _uri('/api/alertas/$alertaId/derivar'),
      headers: _headers(),
    );
    _parse(resp);
  }

  static Future<void> completarAlerta(String alertaId) async {
    final resp = await http.post(
      _uri('/api/alertas/$alertaId/completar'),
      headers: _headers(),
    );
    _parse(resp);
  }

  // ===== Ubicaciones (entrenamiento/proximidad) =====

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
  static String? _socketJwt;

  static String _socketOriginFromBase(String base) {
    final u = Uri.parse(base);
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
  }

  static Future<void> initSocket() async {
    final jwt = _token;

    // =====================================================================
    // LÍNEA DE DEPURACIÓN AÑADIDA:
    // Revisa la consola de depuración para ver este mensaje.
    // Te dirá si el token es nulo o válido antes de conectar.
    // =====================================================================
    print('💡 [SOCKET] Intentando conectar con el token: $jwt');

    if (jwt == null || jwt.isEmpty) {
      print('❌ [SOCKET] ERROR: El token es nulo o vacío. No se puede conectar.');
      return;
    }

    if (_socket != null && _socket!.connected && _socketJwt == jwt) return;

    try { _socket?.dispose(); } catch (_) {}
    _socket = null;

    final origin = _socketOriginFromBase(_baseUrl);

    final builder = IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setAuth({'token': jwt}); // <-- ¡Esto es vital!

    builder.setExtraHeaders({'Authorization': 'Bearer $jwt'});

    final opts = builder.build();
    final s = IO.io(origin, opts);
    s.connect();

    _socket = s;
    _socketJwt = jwt;
  }

  static bool get isSocketConnected => _socket?.connected == true;

  static void joinAlerta(String alertaId) {
    if (_socket?.connected == true) {
      _socket!.emit('join_alerta', {'alertaId': alertaId});
    }
  }

  static void on(String event, void Function(dynamic) handler) => _socket?.on(event, handler);
  static void off(String event, [void Function(dynamic)? handler]) => _socket?.off(event, handler);

  static void dispose() {
    try { _socket?.dispose(); } catch (_) {}
    _socket = null;
    _socketJwt = null;
  }
}