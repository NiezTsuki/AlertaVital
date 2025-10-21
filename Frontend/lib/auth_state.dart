import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class AuthState extends ChangeNotifier {
  String? token;
  Map<String, dynamic>? user;
  bool isLoading = true;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    token = sp.getString('token');
    if (token != null) {
      try {
        final res = await Api.me(token!);
        if (res['status'] == 200) {
          user = res['body']['user'];
        } else {
          await logout();
        }
      } catch (e) {
        await logout();
      }
    }
    isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String correo, String contrasena) async {
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
        notifyListeners();
        return true;
      }
    } catch (e) {
      print("💥 [LOGIN_FRONTEND] Falló la petición de login. Error: $e");
    }
    isLoading = false;
    notifyListeners();
    return false;
  }

  // ✅ FUNCIÓN DE REGISTRO CORREGIDA
  Future<bool> register(String rol, String nombre, String correo, String telefono, String contrasena) async {
    print("📲 [REGISTER_FRONTEND] Intentando registrar usuario...");
    isLoading = true;
    notifyListeners();

    try {
      final res = await Api.register(rol, nombre, correo, telefono, contrasena);
      print("📬 [REGISTER_FRONTEND] Respuesta del servidor. Status: ${res['status']}");

      // ✅ CAMBIO: Si el registro es exitoso (201), ya no hacemos login.
      // Simplemente devolvemos 'true' para que la UI sepa que todo salió bien.
      if (res['status'] == 201) {
        print("✅ [REGISTER_FRONTEND] Registro exitoso. El usuario debe verificar su correo.");
        isLoading = false;
        notifyListeners();
        return true; 
      } else {
        final errorBody = res['body']?['error'] ?? 'Error desconocido desde el servidor.';
        print("❌ [REGISTER_FRONTEND] El servidor respondió con un error: $errorBody");
      }
    } catch (e) {
      print("💥 [REGISTER_FRONTEND] Falló la petición de registro. Error: $e");
    }

    isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    token = null; 
    user = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await load(); 
  }
}