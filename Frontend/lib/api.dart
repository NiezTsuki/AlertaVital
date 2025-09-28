import 'dart:convert';
import 'package:http/http.dart' as http;

class Api {
  static const String baseUrl = 'http://localhost:3000'; 

  static Future<Map<String, dynamic>> login(String correo, String contrasena) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'correo': correo, 'contrasena': contrasena}),
    );
    return {'status': res.statusCode, 'body': jsonDecode(res.body)};
  }

  static Future<Map<String, dynamic>> register(String rol, String nombreCompleto, String correo, String telefono, String contrasena) async {
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
}
