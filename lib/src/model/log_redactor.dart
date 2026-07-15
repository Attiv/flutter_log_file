/// An opt-in regular-expression replacement applied to formatted messages.
final class LogRedactor {
  LogRedactor({required this.pattern, this.replacement = '***'});

  final RegExp pattern;
  final String replacement;

  String apply(String value) => value.replaceAll(pattern, replacement);
}
