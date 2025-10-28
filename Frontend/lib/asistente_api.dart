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
      // ********** DEBUGGING DE LA RESPUESTA **********
      final responseBody = response.body;
      print('[API_DEBUG] Body recibido: $responseBody');
      
      // Manejo de cuerpo de respuesta vacío (indicativo de falla de Gemini)
      if (responseBody == null || responseBody.isEmpty) {
        print('💥 [JSON_ERROR] Body está vacío a pesar del 200 OK.');
        throw Exception('El servidor respondió, pero la IA devolvió una respuesta vacía. (Clave API inválida)');
      }

      try {
        final decodedBody = jsonDecode(responseBody);
        
        // Verifica que la clave 'respuesta' exista
        if (decodedBody.containsKey('respuesta') && decodedBody['respuesta'] != null) {
          return decodedBody['respuesta'];
        } else {
          // Si el JSON es válido pero la clave 'respuesta' no existe o está vacía
          print('💥 [JSON_ERROR] Clave "respuesta" no encontrada o es nula: $decodedBody');
          throw Exception('Formato de respuesta incompleto de la IA.');
        }
      } catch (e) {
        // Se activa si response.body no es JSON válido
        print('💥 [JSON_ERROR] Falló la decodificación del JSON: $e');
        throw Exception('El servidor respondió, pero el formato JSON es inválido.');
      }
      // **********************************************
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