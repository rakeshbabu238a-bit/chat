/// Application-level configuration.
///
/// GROQ_API_KEY is injected at build time via --dart-define:
///   flutter run --dart-define=GROQ_API_KEY=gsk_...
///
/// For production builds:
///   flutter build apk --dart-define=GROQ_API_KEY=gsk_...
///
/// Alternatively, move the Groq call to the Firebase Cloud Function
/// (functions/index.js) and set GROQ_API_KEY there — the Flutter app
/// then writes user messages to Firestore and reads the assistant reply
/// once the function populates it.
class AppConfig {
  AppConfig._();

  static const groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );

  static const groqModel = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: 'llama-3.3-70b-versatile',
  );

  static bool get isGroqConfigured => groqApiKey.isNotEmpty;
}
