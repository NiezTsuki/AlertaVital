import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:provider/provider.dart';
import '../auth_state.dart';
import '../widgets/brand_header.dart';
import '../widgets/soft_background.dart';
import 'login_page.dart'; 

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  final _roles = const ['ADULTO_MAYOR', 'CUIDADOR'];
  String _rol = 'ADULTO_MAYOR';

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Correo requerido';
    final emailReg = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$', caseSensitive: false);
    if (!emailReg.hasMatch(v.trim())) return 'Correo no válido';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Contraseña requerida';
    if (v.length < 6) return 'Mínimo 6 caracteres'; // Ajustado a 6 como en el backend
    // Puedes volver a añadir las otras validaciones si las implementas en el backend
    // if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Incluye 1 mayúscula';
    // if (!RegExp(r'[0-9]').hasMatch(v)) return 'Incluye 1 número';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Confirma la contraseña';
    if (v != _passCtrl.text) return 'Las contraseñas no coinciden';
    return null;
  }

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Teléfono requerido';
    final clean = toNumericString(v);
    if (!(clean.startsWith('569') && clean.length == 11)) {
      return 'Formato válido: +56 9 #### ####';
    }
    return null;
  }

  String _normalizePhone(String v) {
    final d = toNumericString(v);
    if (d.startsWith('569') && d.length == 11) return '+$d';
    if (d.length == 9 && d.startsWith('9')) return '+569$d';
    return '+$d';
  }

  // ✅ FUNCIÓN _submit COMPLETAMENTE ACTUALIZADA
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthState>();
    setState(() => _isSubmitting = true);

    final ok = await auth.register(
      _rol,
      _nameCtrl.text.trim(),
      _emailCtrl.text.trim(),
      _normalizePhone(_phoneCtrl.text.trim()),
      _passCtrl.text,
    );
    
    // El 'isSubmitting' se desactiva dentro de los if/else para un mejor control.

    if (ok && mounted) {
      // Si el registro es exitoso, muestra el diálogo de "Revisa tu correo".
      setState(() => _isSubmitting = false);
      showDialog(
        context: context,
        barrierDismissible: false, // El usuario debe presionar el botón
        builder: (context) => AlertDialog(
          title: const Text('¡Registro Exitoso!'),
          content: const Text('Hemos enviado un enlace de verificación a tu correo electrónico. Por favor, revísalo para activar tu cuenta antes de iniciar sesión.'),
          actions: [
            TextButton(
              onPressed: () {
                // Navega a la página de login y limpia el historial de navegación.
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()), 
                  (route) => false
                );
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } else {
      // Si el registro falla, muestra el SnackBar de error.
      setState(() => _isSubmitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El registro falló. El correo puede que ya esté en uso.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const SoftBackground(),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Volver',
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                const SizedBox(width: 8),
                                const BrandHeader(size: 70, centered: false),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Crear cuenta',
                                style: theme.textTheme.headlineSmall,
                              ),
                            ),
                            const SizedBox(height: 18),

                            DropdownButtonFormField<String>(
                              value: _rol,
                              decoration: _inputDeco('Tipo de usuario', icon: Icons.groups_2_outlined),
                              items: _roles
                                  .map((r) => DropdownMenuItem(
                                        value: r,
                                        child: Text(r.replaceAll('_', ' ')),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => _rol = v ?? _rol),
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDeco('Nombre completo', icon: Icons.person_outline),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nombre requerido' : null,
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _emailCtrl,
                              textInputAction: TextInputAction.next,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDeco('Correo electrónico', icon: Icons.alternate_email),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _phoneCtrl,
                              textInputAction: TextInputAction.next,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                MaskedInputFormatter('+56 9 #### ####'),
                                FilteringTextInputFormatter.allow(RegExp(r'[\d+\s]')),
                              ],
                              decoration: _inputDeco('Teléfono (Chile)', icon: Icons.phone_outlined, hint: '+56 9 1234 5678'),
                              validator: _validatePhone,
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscure1,
                              decoration: _inputDeco(
                                'Contraseña',
                                icon: Icons.lock_outline,
                                // helper: 'Mín. 8, 1 mayúscula y 1 número', // Desactivado temporalmente
                                suffix: IconButton(
                                  tooltip: _obscure1 ? 'Mostrar' : 'Ocultar',
                                  icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscure1 = !_obscure1),
                                ),
                              ),
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _pass2Ctrl,
                              obscureText: _obscure2,
                              decoration: _inputDeco(
                                'Confirmar contraseña',
                                icon: Icons.lock_reset,
                                suffix: IconButton(
                                  tooltip: _obscure2 ? 'Mostrar' : 'Ocultar',
                                  icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                                ),
                              ),
                              validator: _validateConfirm,
                            ),
                            const SizedBox(height: 22),

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _isSubmitting ? null : _submit,
                                child: _isSubmitting
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                                    : const Text('Registrar'),
                              ),
                            ),

                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('¿Ya tienes cuenta? Inicia sesión'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Al registrarte aceptas los Términos y la Política de Privacidad.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.3),
                            ),
                          ],
                        ),
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

  InputDecoration _inputDeco(
    String label, { IconData? icon, String? hint, String? helper, Widget? suffix }
  ) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffix,
    );
  }
}