import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/public_reader_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(AuthService(), prefs),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(ChatService()),
        ),
      ],
      child: MaterialApp(
        title: 'AI Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
            brightness: Brightness.dark,
          ),
          textTheme: GoogleFonts.interTextTheme(
            ThemeData.dark().textTheme,
          ),
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          cardColor: const Color(0xFF1E293B),
        ),
        onGenerateRoute: (settings) {
          // Handle /link/:token for public read-only access
          final uri = Uri.parse(settings.name ?? '');
          if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'link') {
            final token = uri.pathSegments[1];
            return MaterialPageRoute(
              builder: (_) => PublicReaderScreen(token: token),
            );
          }

          // Named routes
          if (settings.name == '/admin') {
            return MaterialPageRoute(builder: (_) => const AdminScreen());
          }

          return MaterialPageRoute(builder: (_) => const AuthGate());
        },
        initialRoute: '/',
      ),
    );
  }
}

/// Routes to LoginScreen or ChatScreen based on auth state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
          );
        }

        if (auth.isAuthenticated) {
          if (auth.isReadOnly) {
            return const ReaderScreen();
          }
          return const ChatScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
