import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart'; 

class AsistenteApi {
  static Future<String> conversar(String texto, List<Map<String, dynamic>> historial, String token) async {
    final uri = Uri.parse('${Api.baseUrl}/api/asistente/conversar');
    
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };

    final body = jsonEncode({'texto': texto, 'historial': historial}); 

    final response = await http.post(uri, headers: headers, body: body);

    if (response.statusCode == 200) {
      final responseBody = response.body;
      print('[API_DEBUG] Body recibido: $responseBody');
      
      if (responseBody.isEmpty) {
        print('💥 [JSON_ERROR] Body está vacío a pesar del 200 OK.');
        throw Exception('El servidor respondió, pero la IA devolvió una respuesta vacía.');
      }

      try {
        final decodedBody = jsonDecode(responseBody);
        
        // --- MANEJO DE RESPUESTA MEJORADO ---
        // Verifica si la respuesta es exitosa y contiene el texto
        if (decodedBody.containsKey('respuesta') && decodedBody['respuesta'] != null) {
          return decodedBody['respuesta'];
        } 
        // Verifica si el backend devolvió un error específico
        else if (decodedBody.containsKey('error') && decodedBody['error'] != null) {
           throw Exception('Error del servidor: ${decodedBody['error']}');
        }
        // Si el JSON es válido pero no tiene el formato esperado
        else {
          print('💥 [JSON_ERROR] Clave "respuesta" o "error" no encontrada: $decodedBody');
          throw Exception('Formato de respuesta inesperado del servidor.');
        }
      } catch (e) {
        print('💥 [JSON_ERROR] Falló la decodificación del JSON: $e');
        throw Exception('El servidor respondió, pero el formato JSON es inválido.');
      }
    } else if (response.statusCode == 401) {
      throw Exception('Sesión expirada o no autorizada.');
    } else {
      print('Error ${response.statusCode} en API: ${response.body}'); 
      throw Exception('Error al conectar con el asistente. Código: ${response.statusCode}');
    }
  }
}