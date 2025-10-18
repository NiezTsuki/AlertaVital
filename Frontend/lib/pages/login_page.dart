import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  Future<void> _submit(AuthState auth) async {
    // Esconde el teclado para que el usuario vea los mensajes de estado.
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);

    // ✅ CORRECCIÓN CLAVE:
    // Después de la operación asíncrona (login), verificamos si el widget
    // todavía existe en el árbol de widgets antes de continuar. Si el login
    // fue exitoso, es probable que la app ya haya navegado a HomePage,
    // por lo que detenemos la ejecución aquí para evitar el error.
    if (!mounted) return;

    // Si el login fue exitoso, la navegación es manejada por RootPage.
    // Si no fue exitoso, actualizamos el estado para mostrar un error.
    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'Credenciales inválidas. Inténtalo de nuevo.';
      });
    }
    // No necesitamos hacer nada si 'ok' es true, porque RootPage se encargará
    // de la navegación automáticamente.
  }

  @override
  Widget build(BuildContext context) {
    // Usamos context.read aquí para pasar el AuthState a la función _submit
    // sin causar reconstrucciones innecesarias del widget.
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
                        children: [
                          const BrandHeader(size: 100),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Iniciar sesión',
                                style: Theme.of(context).textTheme.headlineSmall),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            onSubmitted: (_) => _submit(auth),
                          ),
                          const SizedBox(height: 14),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 14),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: _loading ? null : () => _submit(auth),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 3))
                                  : const Text('Entrar'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () =>
                                Navigator.pushNamed(context, '/register'),
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