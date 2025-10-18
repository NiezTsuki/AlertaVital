import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/home_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthState()..load(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Alerta Vital',
        theme: buildAppTheme(),
        home: const RootPage(),
        routes: {
          '/login': (_) => const LoginPage(),
          '/register': (_) => const RegisterPage(),
          '/home': (_) => const HomePage(),
        },
      ),
    );
  }
}

class RootPage extends StatelessWidget {
  const RootPage({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    print("--- [RootPage] build() llamado. Estado: isLoading=${auth.isLoading}, token=${auth.token != null}, user=${auth.user != null}");

    if (auth.isLoading) {
      print("--- [RootPage] Decisión: Mostrar pantalla de carga principal.");
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth.token != null && auth.user != null) {
      print("--- [RootPage] Decisión: NAVEGAR A HOMEPAGE.");
      return const HomePage();
    } else {
      print("--- [RootPage] Decisión: NAVEGAR A LOGINPAGE.");
      return const LoginPage();
    }
  }
}