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
    if (auth.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return auth.token != null ? const HomePage() : const LoginPage();
  }
}

