import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class AuthState extends ChangeNotifier {
  String? token;
  Map<String, dynamic>? user;
  bool isLoading = true;

  Future<void> load() async {
    print("--- 1. [AuthState] load() INICIADO ---");
    isLoading = true;
    notifyListeners();

    final sp = await SharedPreferences.getInstance();
    token = sp.getString('token');
    print("--- 2. [AuthState] Token desde almacenamiento: ${token != null ? 'ENCONTRADO' : 'NO ENCONTRADO'}");

    if (token != null) {
      try {
        print("--- 3. [AuthState] Token encontrado. Llamando a Api.me()...");
        final res = await Api.me(token!);
        print("--- 4. [AuthState] Respuesta de Api.me(): status ${res['status']}");
        if (res['status'] == 200) {
          user = res['body']['user'];
          print("--- 5. [AuthState] Datos del usuario cargados: ${user?['id']}");
        } else {
          print("--- 5. [AuthState] Api.me() falló. Token inválido. Haciendo logout.");
          await logout();
        }
      } catch (e) {
        print("--- 5. [AuthState] ERROR llamando a Api.me(): $e. Haciendo logout.");
        await logout();
      }
    }

    isLoading = false;
    print("--- 6. [AuthState] load() FINALIZADO. isLoading: $isLoading, token: ${token != null}, user: ${user != null}");
    notifyListeners();
  }

  Future<bool> login(String correo, String contrasena) async {
    print("--- [AuthState] login() INICIADO ---");
    isLoading = true; 
    notifyListeners();
    
    try {
      final res = await Api.login(correo, contrasena);
      if (res['status'] == 200) {
        token = res['body']['token'];
        final sp = await SharedPreferences.getInstance();
        await sp.setString('token', token!);
        final meRes = await Api.me(token!);
        user = meRes['body']['user'];
        isLoading = false;
        print("--- [AuthState] login() EXITOSO. user: ${user != null}");
        notifyListeners();
        return true;
      }
    } catch (e) {
      print("💥 [LOGIN_FRONTEND] Falló la petición de login. Error: $e");
    }
    
    isLoading = false;
    print("--- [AuthState] login() FALLIDO.");
    notifyListeners();
    return false;
  }

  // ✅ FUNCIÓN DE REGISTRO COMPLETA Y CON DEPURACIÓN
  Future<bool> register(String rol, String nombre, String correo, String telefono, String contrasena) async {
    print("📲 [REGISTER_FRONTEND] Intentando registrar usuario...");
    isLoading = true;
    notifyListeners();

    try {
      // Llama a la función de registro de la API que ya tienes en api.dart
      final res = await Api.register(rol, nombre, correo, telefono, contrasena);
      print("📬 [REGISTER_FRONTEND] Respuesta recibida del servidor. Status: ${res['status']}");

      if (res['status'] == 201) { // 201 Created = Éxito
        print("✅ [REGISTER_FRONTEND] Registro exitoso. Procediendo a login automático...");
        // Si el registro es exitoso, hacemos login automáticamente para obtener el token y los datos del usuario.
        return await login(correo, contrasena);
      } else {
        // Si el servidor devuelve un código de error (400, 409, 500)
        final errorBody = res['body']?['error'] ?? 'Error desconocido desde el servidor.';
        print("❌ [REGISTER_FRONTEND] El servidor respondió con un error: $errorBody");
      }
    } catch (e) {
      // Si la petición falla antes de recibir respuesta (ej. sin internet o error de red)
      print("💥 [REGISTER_FRONTEND] Falló la petición de registro. Error: $e");
    }

    isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    print("--- [AuthState] logout() INICIADO ---");
    token = null; 
    user = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    
    // Llama a load() para reiniciar el estado de la app de forma segura.
    await load(); 
  }
}