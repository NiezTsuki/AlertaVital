import 'dart:convert';
import 'package:http/http.dart' as http;

class Api {
  static const String baseUrl = 'http://localhost:3000'; // ajusta si usas emulador/dispositivo real

  /// ---------- AUTENTICACIÓN ----------
  static Future<Map<String, dynamic>> login(String correo, String contrasena) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'correo': correo, 'contrasena': contrasena}),
    );
    return {'status': res.statusCode, 'body': jsonDecode(res.body)};
  }

  static Future<Map<String, dynamic>> register(
    String rol,
    String nombreCompleto,
    String correo,
    String telefono,
    String contrasena,
  ) async {
    final uri = Uri.parse('$baseUrl/auth/register');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'rol': rol,
        'nombre_completo': nombreCompleto,
        'correo': correo,
        'telefono': telefono,
        'contrasena': contrasena,
      }),
    );
    return {'status': res.statusCode, 'body': jsonDecode(res.body)};
  }

  static Future<Map<String, dynamic>> me(String token) async {
    final uri = Uri.parse('$baseUrl/auth/me');
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    return {'status': res.statusCode, 'body': jsonDecode(res.body)};
  }

  /// ---------- VÍNCULOS (ADULTO MAYOR ↔ CUIDADOR) ----------

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Buscar un usuario por correo
  static Future<Map<String, dynamic>?> buscarUsuarioPorCorreo(String token, String correo) async {
    final uri = Uri.parse('$baseUrl/api/usuarios/por-correo?correo=${Uri.encodeQueryComponent(correo)}');
    final res = await http.get(uri, headers: _headers(token));
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }
    if (res.statusCode == 404) return null;
    throw Exception('Error buscando usuario (${res.statusCode})');
  }

  /// Vincular adulto con cuidador (directo)
  static Future<bool> vincularAdultoCuidador(
    String token, {
    required String adultoId,
    required String cuidadorId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/cuidadores/vincular');
    final res = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({'adultoId': adultoId, 'cuidadorId': cuidadorId}),
    );
    return res.statusCode == 200 || res.statusCode == 201;
  }

  /// Listar cuidadores de un adulto
  static Future<List<Map<String, dynamic>>> listarCuidadoresDeAdulto(String token, String adultoId) async {
    final uri = Uri.parse('$baseUrl/api/cuidadores/de-adulto/$adultoId');
    final res = await http.get(uri, headers: _headers(token));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as List;
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    throw Exception('Error listando cuidadores (${res.statusCode})');
  }

  /// Listar adultos de un cuidador
  static Future<List<Map<String, dynamic>>> listarAdultosDeCuidador(String token, String cuidadorId) async {
    final uri = Uri.parse('$baseUrl/api/cuidadores/de-cuidador/$cuidadorId');
    final res = await http.get(uri, headers: _headers(token));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as List;
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    throw Exception('Error listando adultos (${res.statusCode})');
  }

  /// Desvincular adulto ↔ cuidador
  static Future<bool> desvincular(
    String token, {
    required String adultoId,
    required String cuidadorId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/cuidadores/$adultoId/$cuidadorId');
    final res = await http.delete(uri, headers: _headers(token));
    return res.statusCode == 200;
  }
}
