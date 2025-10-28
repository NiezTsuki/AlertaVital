
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart'; 

class AsistenteApi {
  // Se requiere el token como tercer argumento.
  static Future<String> conversar(String texto, List<Map<String, dynamic>> historial, String token) async {
    final uri = Uri.parse('${Api.baseUrl}/api/asistente/conversar');
    
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token' // Envía el token real al backend
    };

    final body = jsonEncode({'texto': texto, 'historial': historial}); 

    final response = await http.post(uri, headers: headers, body: body);

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['respuesta'];
    } else if (response.statusCode == 401) {
      // Manejo específico para la expiración o falta de sesión
      throw Exception('Sesión expirada o no autorizada.');
    } else {
      // Manejo de otros errores (500, etc.)
      print('Error ${response.statusCode} en API: ${response.body}'); 
      throw Exception('Error al conectar con el asistente. Código: ${response.statusCode}');
    }
  }
}
