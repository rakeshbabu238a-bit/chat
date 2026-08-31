/// Application-level configuration.
///
/// The app talks to any OpenAI-compatible chat completions endpoint.
/// Defaults target Google Gemini (gemini-2.5-flash), which has a generous
/// free tier. Values are injected at build time via --dart-define:
///
///   flutter run --dart-define=LLM_API_KEY=your_gemini_key
///
/// Override the model or endpoint to switch providers, e.g. to use Groq:
///   --dart-define=LLM_API_KEY=gsk_... \
///   --dart-define=LLM_MODEL=openai/gpt-oss-120b \
///   --dart-define=LLM_API_URL=https://api.groq.com/openai/v1/chat/completions
class AppConfig {
  AppConfig._();

  /// LLM provider API key. Injected at build time via --dart-define.
  /// Works for any OpenAI-compatible provider (Gemini, Groq, OpenAI, ...).
  static const llmApiKey = String.fromEnvironment(
    'LLM_API_KEY',
    defaultValue: '',
  );

  /// Model name. Defaults to Google Gemini 3.6 Flash.
  /// (gemini-2.5-flash is closed to new users; Google directs new keys to 3.6.)
  /// The Gemini OpenAI-compatibility endpoint expects the `models/` prefix.
  static const llmModel = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'models/gemini-3.6-flash',
  );

  /// OpenAI-compatible chat completions endpoint.
  /// Defaults to the Gemini OpenAI-compatibility endpoint.
  static const llmApiUrl = String.fromEnvironment(
    'LLM_API_URL',
    defaultValue:
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
  );

  static bool get isLlmConfigured => llmApiKey.isNotEmpty;
}
