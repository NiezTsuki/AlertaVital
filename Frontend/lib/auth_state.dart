import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class AuthState extends ChangeNotifier {
  String? token;
  Map<String, dynamic>? user;
  bool isLoading = false;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    token = sp.getString('token');
    if (token != null) {
      final res = await Api.me(token!);
      if (res['status'] == 200) {
        user = res['body']['user'];
      } else {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<bool> login(String correo, String contrasena) async {
    isLoading = true; notifyListeners();
    final res = await Api.login(correo, contrasena);
    isLoading = false;
    if (res['status'] == 200) {
      token = res['body']['token'];
      final sp = await SharedPreferences.getInstance();
      await sp.setString('token', token!);
      final meRes = await Api.me(token!);
      user = meRes['body']['user'];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<bool> register(String rol, String nombre, String correo, String telefono, String contrasena) async {
    isLoading = true; notifyListeners();
    final res = await Api.register(rol, nombre, correo, telefono, contrasena);
    isLoading = false;
    if (res['status'] == 201) {
      token = res['body']['token'];
      final sp = await SharedPreferences.getInstance();
      await sp.setString('token', token!);
      final meRes = await Api.me(token!);
      user = meRes['body']['user'];
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    token = null; user = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    notifyListeners();
  }
}
