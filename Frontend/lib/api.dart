import 'dart:convert';
import 'package:http/http.dart' as http;

class Api {
  static const String baseUrl = 'https://alertavital.xyz';

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

  // NUEVA FUNCIÓN AÑADIDA
  /// Envía el token de verificación del correo al backend.
  static Future<Map<String, dynamic>> verifyEmail(String verificationToken) async {
    final uri = Uri.parse('$baseUrl/api/verify-email');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': verificationToken}),
    );
    
    final body = jsonDecode(res.body);
    if (res.statusCode == 200) {
      return body; // Devuelve el mensaje de éxito del servidor, ej: {'message': '...'}
    } else {
      // Si el servidor responde con un error, lo lanzamos como una excepción.
      throw Exception(body['error'] ?? 'Error al verificar el correo (${res.statusCode})');
    }
  }

  // Reseteo de contraseña
  static Future<Map<String, dynamic>> requestPasswordReset(String correo) async {
    final uri = Uri.parse('$baseUrl/api/request-password-reset');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'correo': correo}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200) return body;
    throw Exception(body['error'] ?? 'Error al solicitar el reseteo');
  }


  /// ---------- VÍNCULOS (ADULTO MAYOR ↔ CUIDADOR) ----------

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static Future<Map<String, dynamic>> solicitarVinculo(
    String token, {
    required String? adultoCorreo,
    required String? cuidadorCorreo,
  }) async {
    final uri = Uri.parse('$baseUrl/api/cuidadores/solicitar');
    final res = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({
        'adultoCorreo': adultoCorreo,
        'cuidadorCorreo': cuidadorCorreo,
      }),
    );
    if (res.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }
    try {
      final errorBody = jsonDecode(res.body);
      throw Exception(errorBody['error'] ?? 'Error al solicitar vínculo (${res.statusCode})');
    } catch (_) {
      throw Exception('Error al solicitar vínculo (${res.statusCode})');
    }
  }

  /// Aceptar una vinculación usando el token de invitación.
  static Future<bool> aceptarVinculo(String token, String tokenDeVinculo) async {
    final uri = Uri.parse('$baseUrl/api/cuidadores/aceptar');
    final res = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({'token': tokenDeVinculo}),
    );
    if (res.statusCode == 201) {
      return true;
    }
    try {
      final errorBody = jsonDecode(res.body);
      throw Exception(errorBody['error'] ?? 'Error al aceptar el vínculo (${res.statusCode})');
    } catch (_) {
      throw Exception('Error al aceptar el vínculo (${res.statusCode})');
    }
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
