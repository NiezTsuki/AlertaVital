import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart'; // Importa la API para usar la nueva función
import '../auth_state.dart';
import '../widgets/brand_header.dart';
import '../widgets/soft_background.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthState auth) async {
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });

    try {
      final ok = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _loading = false;
          // El error se obtiene desde el authState si se implementa, o se pone uno genérico
          _error = 'Credenciales inválidas o cuenta no verificada.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ocurrió un error inesperado.';
      });
    }
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Restablecer Contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ingresa tu correo electrónico y te enviaremos un enlace para restablecer tu contraseña.'),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo electrónico'),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty || !email.contains('@')) return;

                // Llama a la nueva función de la API
                try {
                  await Api.requestPasswordReset(email);
                } catch (e) {
                  print("Error en requestPasswordReset: $e");
                  // No mostramos el error al usuario por seguridad
                }
                
                if (!mounted) return;
                Navigator.of(context).pop(); // Cierra el diálogo
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Si el correo está registrado, recibirás un enlace en breve.')),
                );
              },
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthState>();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const SoftBackground(),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const BrandHeader(size: 100),
                          const SizedBox(height: 24),
                          Text('Iniciar sesión', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.alternate_email)),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
                            onSubmitted: (_) => _submit(auth),
                          ),
                          const SizedBox(height: 14),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 14), textAlign: TextAlign.center),
                            ),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _loading ? null : () => _submit(auth),
                              child: _loading
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                                  : const Text('Entrar'),
                            ),
                          ),
                          
                          // ✅ BOTÓN DE OLVIDASTE TU CONTRASEÑA AÑADIDO
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _showForgotPasswordDialog(context),
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          ),

                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/register'),
                            child: const Text('¿No tienes cuenta? Regístrate'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}