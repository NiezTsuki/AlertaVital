import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

class AlertasApi {
  // ===== Configuración (sin cambios) =====
  static String _baseUrl = const String.fromEnvironment('API_BASE',
      defaultValue: 'https://alerta-vital-nine.vercel.app');
  static String? _token;

  static void configure({required String baseUrl, required String token}) {
    _baseUrl = baseUrl;
    _token = token;
  }

  // ===== Ayudantes HTTP (sin cambios) =====
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

  // ===== Endpoints de ALERTAS (sin cambios) =====
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

  // ===== Ubicaciones (sin cambios) =====
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
  
  // ===== LÓGICA DE PUSHER =====
  static final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();
  static bool _isPusherInitialized = false;

  static Future<void> initPusher({
    required String apiKey,
    required String cluster,
  }) async {
    if (_isPusherInitialized) return;
    final token = _token;
    if (token == null || token.isEmpty) return;

    try {
      final authEndpoint = Uri.parse('$_baseUrl/auth/pusher/auth');
      await _pusher.init(
        apiKey: apiKey,
        cluster: cluster,
        onConnectionStateChange: (currentState, previousState) => print("🔌 [PUSHER] Estado: $currentState"),
        onError: (message, code, error) => print("❌ [PUSHER] Error: $message, code: $code, error: $error"),
        onAuthorizer: (channelName, socketId, options) async {
          final resp = await http.post(
            authEndpoint,
            headers: _headers(),
            body: jsonEncode({'socket_id': socketId, 'channel_name': channelName}),
          );
          return jsonDecode(resp.body);
        },
      );
      await _pusher.connect();
      _isPusherInitialized = true;
    } catch (e) {
      print('💥 [PUSHER] Excepción al inicializar: $e');
      _isPusherInitialized = false;
    }
  }

  static Future<PusherChannel> subscribeToChannel(String channelName) async {
    PusherChannel? channel = _pusher.getChannel(channelName);
    if (channel == null) {
      channel = await _pusher.subscribe(channelName: channelName);
    }
    return channel;
  }

  static void unsubscribeFromChannel(String channelName) {
    _pusher.unsubscribe(channelName: channelName);
  }

  static void dispose() {
    if (_isPusherInitialized) {
      _pusher.disconnect();
      _isPusherInitialized = false;
    }
  }
}