import 'dart:convert';

import '../model/log_redactor.dart';

typedef _UntypedObjectEncoder = Object? Function(Object value);

/// Registry used to serialize business objects without runtime reflection.
final class ObjectEncoderRegistry {
  final Map<Type, _UntypedObjectEncoder> _encoders = {};

  void register<T>(Object? Function(T value) encoder) {
    _encoders[T] = (value) => encoder(value as T);
  }

  void unregister<T>() => _encoders.remove(T);

  Object? Function(Object value)? encoderFor(Object value) =>
      _encoders[value.runtimeType];
}

/// A normalized message that can be rendered as compact or pretty JSON.
final class SerializedMessage {
  const SerializedMessage._(
    this.value, {
    required this.isJson,
    required this.redactors,
  });

  final Object? value;
  final bool isJson;
  final List<LogRedactor> redactors;

  String render({bool pretty = false}) {
    var result = isJson
        ? (pretty
            ? const JsonEncoder.withIndent('  ').convert(value)
            : jsonEncode(value))
        : value?.toString() ?? 'null';
    for (final redactor in redactors) {
      result = redactor.apply(result);
    }
    return result;
  }
}

/// Converts common values, `toJson` objects and registered application types
/// into a safe representation for log formatting.
final class MessageSerializer {
  MessageSerializer({
    ObjectEncoderRegistry? registry,
    Set<String> redactedKeys = const {},
    List<LogRedactor> redactors = const [],
  })  : registry = registry ?? ObjectEncoderRegistry(),
        redactedKeys = redactedKeys.map((key) => key.toLowerCase()).toSet(),
        redactors = List.unmodifiable(redactors);

  final ObjectEncoderRegistry registry;
  final Set<String> redactedKeys;
  final List<LogRedactor> redactors;

  SerializedMessage serialize(Object? message) {
    final normalized = _normalize(message, <Object>{});
    return SerializedMessage._(
      normalized.value,
      isJson: normalized.isJson,
      redactors: redactors,
    );
  }

  _NormalizedValue _normalize(Object? value, Set<Object> visiting) {
    if (value == null || value is num || value is bool || value is String) {
      return _NormalizedValue(value, isJson: false);
    }

    if (!visiting.add(value)) {
      return const _NormalizedValue('<circular-reference>', isJson: false);
    }

    try {
      if (value is Map) {
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          final key = entry.key.toString();
          if (redactedKeys.contains(key.toLowerCase())) {
            result[key] = '***';
          } else {
            result[key] = _normalize(entry.value, visiting).value;
          }
        }
        return _NormalizedValue(result, isJson: true);
      }

      if (value is Iterable) {
        return _NormalizedValue(
          value.map((item) => _normalize(item, visiting).value).toList(),
          isJson: true,
        );
      }

      final registered = registry.encoderFor(value);
      if (registered != null) {
        try {
          final encoded = _normalize(registered(value), visiting);
          return _NormalizedValue(encoded.value, isJson: encoded.isJson);
        } catch (_) {
          // Continue with toJson/toString when an application encoder fails.
        }
      }

      try {
        final dynamic dynamicValue = value;
        final encoded = _normalize(dynamicValue.toJson(), visiting);
        return _NormalizedValue(encoded.value, isJson: encoded.isJson);
      } catch (_) {
        return _NormalizedValue(value.toString(), isJson: false);
      }
    } finally {
      visiting.remove(value);
    }
  }
}

final class _NormalizedValue {
  const _NormalizedValue(this.value, {required this.isJson});

  final Object? value;
  final bool isJson;
}
