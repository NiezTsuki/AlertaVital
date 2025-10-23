import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart'; // Asumiendo que aquí está la configuración base

class AsistenteApi {
  static Future<String> conversar(String texto, List<Map<String, dynamic>> historial) async {
    final uri = Uri.parse('${Api.baseUrl}/api/asistente/conversar');
    final token =
        ""; // token del usuario desde tu AuthState
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
    final body = jsonEncode({'texto': texto, 'historial': historial});

    final response = await http.post(uri, headers: headers, body: body);

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['respuesta'];
    } else {
      throw Exception('Error al conectar con el asistente.');
    }
  }
}