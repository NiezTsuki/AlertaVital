// lib/alertas_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

class AlertasApi {
  // ===== Configuración =====
  static String _baseUrl = const String.fromEnvironment('API_BASE',
      defaultValue: 'https://alerta-vital-nine.vercel.app');
  static String? _token;

  static void configure({required String baseUrl, required String token}) {
    _baseUrl = baseUrl;
    _token = token;
  }

  // ===== Ayudantes HTTP =====
  static Uri _uri(String path, [Map<String, dynamic>? q]) {
    if (!path.startsWith('/')) path = '/$path';
    final uri = Uri.parse('$_baseUrl$path');
    if (q == null || q.isEmpty) return uri;
    return uri.replace(queryParameters: q.map((k, v) => MapEntry(k, v?.toString())));
  }

  static Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final t = _token;
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  static dynamic _parse(http.Response resp) {
    if (resp.body.isEmpty) {
       if (resp.statusCode >= 200 && resp.statusCode < 300) return null;
       throw Exception('HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return data;
    throw Exception(data['error'] ?? 'HTTP ${resp.statusCode}');
  }

  // ===== Endpoints de API REST =====
  static Future<Map<String, dynamic>> crearSOS({double? lat, double? lon, double? precision}) async {
    final body = <String, dynamic>{
      'tipo': 'SOS',
      'countdown': 30,
    };
    if (lat != null && lon != null) {
      body['latitud'] = lat;
      body['longitud'] = lon;
      if (precision != null) body['precision_metros'] = precision;
    }
    final resp = await http.post(_uri('/api/alertas/sos'), headers: _headers(), body: jsonEncode(body));
    return _parse(resp);
  }

  static Future<void> aceptarAlerta(String alertaId) async {
    await http.post(_uri('/api/alertas/$alertaId/aceptar'), headers: _headers());
  }

  static Future<void> derivarAlerta(String alertaId) async {
    await http.post(_uri('/api/alertas/$alertaId/derivar'), headers: _headers());
  }

  static Future<List<dynamic>> getPosiciones(String alertaId) async {
    final resp = await http.get(_uri('/api/alertas/$alertaId/posiciones'), headers: _headers());
    return _parse(resp) ?? [];
  }

  static Future<void> registrarPosicionAlerta(String alertaId, double lat, double lon, {double? precision}) async {
    await http.post(_uri('/api/alertas/$alertaId/posicion'), headers: _headers(), body: jsonEncode({'latitud': lat, 'longitud': lon, 'precision_metros': precision}));
  }
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

  // ===== Lógica de Pusher =====
  static final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();
  static bool _isPusherInitialized = false;

  static Future<void> initPusher({required String apiKey, required String cluster}) async {
    if (_isPusherInitialized) return;
    if (_token == null || _token!.isEmpty) return;

    try {
      await _pusher.init(
        apiKey: apiKey,
        cluster: cluster,
        onConnectionStateChange: (currentState, previousState) => print("🔌 [PUSHER] Estado: $currentState"),
        onError: (message, code, error) => print("❌ [PUSHER] Error: $message, code: $code, error: $error"),
        onAuthorizer: (channelName, socketId, options) async {
          final resp = await http.post(_uri('/auth/pusher/auth'), headers: _headers(), body: jsonEncode({'socket_id': socketId, 'channel_name': channelName}));
          return jsonDecode(resp.body);
        },
      );
      await _pusher.connect();
      _isPusherInitialized = true;
    } catch (e) {
      print('💥 [PUSHER] Excepción al inicializar: $e');
    }
  }

  static Future<PusherChannel> subscribeToChannel(String channelName) async {
    return await _pusher.subscribe(channelName: channelName);
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