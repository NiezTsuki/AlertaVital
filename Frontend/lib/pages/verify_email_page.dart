import 'package:flutter/material.dart';
import '../api.dart';
import 'login_page.dart';

class VerifyEmailPage extends StatefulWidget {
  final String? token;
  const VerifyEmailPage({super.key, this.token});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  String _message = 'Verificando tu correo, por favor espera...';
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _verifyToken();
  }

  Future<void> _verifyToken() async {
    if (widget.token == null) {
      setState(() {
        _message = 'No se proporcionó un token de verificación.';
        _isError = true;
      });
      return;
    }
    try {
      final response = await Api.verifyEmail(widget.token!);
      setState(() {
        _message = response['message'] ?? '¡Correo verificado! Ya puedes iniciar sesión.';
        _isError = false;
      });
    } catch (e) {
      setState(() {
        _message = e.toString();
        _isError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isError ? Icons.error_outline : Icons.check_circle_outline,
                color: _isError ? Colors.red : Colors.green,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                ),
                child: const Text('Ir a Iniciar Sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}