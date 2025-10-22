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
          await _clearSession();
        }
      } catch (e) {
        print("--- 5. [AuthState] ERROR llamando a Api.me(): $e. Haciendo logout.");
        await _clearSession();
      }
    }

    isLoading = false;
    print("--- 6. [AuthState] load() FINALIZADO. isLoading: $isLoading, token: ${token != null}, user: ${user != null}");
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

  Future<bool> register(String rol, String nombre, String correo, String telefono, String contrasena) async {
    isLoading = true;
    notifyListeners();
    try {
      final res = await Api.register(rol, nombre, correo, telefono, contrasena);
      if (res['status'] == 201) {
        isLoading = false;
        notifyListeners();
        return true; 
      }
    } catch (e) {
      print("💥 [REGISTER_FRONTEND] Falló la petición de registro. Error: $e");
    }
    isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    print("--- [AuthState] logout() INICIADO ---");
    await _clearSession();
    await load(); 
  }

  // Función auxiliar para evitar duplicar código.
  Future<void> _clearSession() async {
    token = null; 
    user = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
  }
}