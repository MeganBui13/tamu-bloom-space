import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'routes/app_routes.dart';
import 'services/app_error_mapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;
  final configError = SupabaseConfig.validate();

  if (configError != null) {
    startupError = configError;
  } else {
    final reachabilityError = await SupabaseConfig.verifyReachability();
    if (reachabilityError != null) {
      startupError = reachabilityError;
    } else {
      try {
        await Supabase.initialize(
          url: 'https://lhfxeywsdgwyfsbggirx.supabase.co',
          anonKey: 'sb_publishable_Mi7AByWy0loX_wi6Fx08ow_VE4rE29t',
        );
      } catch (error) {
        startupError = AppErrorMapper.toMessage(
          error,
          fallback: 'Failed to initialize Supabase.',
        );
      }
    }
  }

  runApp(MyApp(startupError: startupError));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return MaterialApp(
        title: 'TAMUBloomSpace',
        debugShowCheckedModeBanner: false,
        home: StartupErrorPage(message: startupError!),
      );
    }

    return MaterialApp(
      title: 'TAMUBloomSpace',
      debugShowCheckedModeBanner: false,
      initialRoute: AppRoutes.login, // Start at login page
      routes: AppRoutes.routes,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Inter', // Optional: Add a nice font
      ),
    );
  }
}

class StartupErrorPage extends StatelessWidget {
  const StartupErrorPage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Startup error',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 20),
                const SelectableText(
                  'Run with valid credentials:\n'
                  'flutter run --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co '
                  '--dart-define=SUPABASE_ANON_KEY=<sb_publishable_or_anon_key>',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
