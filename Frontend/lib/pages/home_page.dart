import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_state.dart';
import '../widgets/soft_background.dart';
import 'mis_vinculos_page.dart';
import 'vincular_page.dart';


class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final nombre = auth.user?['nombre_completo'] ?? 'Usuario';

    return Scaffold(
      body: Stack(
        children: [
          const SoftBackground(),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Hola, $nombre 👋',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🚨 SOS enviado (mock)')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.emergency, size: 28),
                    label: const Text('SOS'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'En caso de emergencia presiona el botón SOS',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: () async {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                  ),
                  Card(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  elevation: 1.5,
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.diversity_3, size: 22),
            SizedBox(width: 8),
            Text('Vínculos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Gestiona cuidadores y adultos mayores.'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.groups_2),
                label: const Text('Mis vínculos'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MisVinculosPage()),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.alternate_email),
                label: const Text('Vincular por correo'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const VincularPage()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
                 ),
                  ),
                )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
