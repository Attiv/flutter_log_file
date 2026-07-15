/// Prepares raw or payload-only text for clipboard/export actions.
final class LogCopyFormatter {
  const LogCopyFormatter();

  String payloadOnly(Iterable<String> lines) => lines.map((line) {
        final separator = line.indexOf(' | ');
        return separator < 0 ? line : line.substring(separator + 3);
      }).join('\n');
}
