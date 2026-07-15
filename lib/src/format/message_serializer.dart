import 'dart:collection';
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
    this.maximumNodes = 4096,
    this.maximumCharacters = 256 * 1024,
    this.maximumDepth = 64,
  })  : registry = registry ?? ObjectEncoderRegistry(),
        assert(maximumNodes > 0),
        assert(maximumCharacters > 0),
        assert(maximumDepth > 0),
        redactedKeys = redactedKeys.map((key) => key.toLowerCase()).toSet(),
        redactors = List.unmodifiable(redactors);

  final ObjectEncoderRegistry registry;
  final Set<String> redactedKeys;
  final List<LogRedactor> redactors;
  final int maximumNodes;
  final int maximumCharacters;
  final int maximumDepth;

  SerializedMessage serialize(Object? message) {
    final normalized = _normalize(
      message,
      HashSet<Object>.identity(),
      _NormalizationBudget(
        remainingNodes: maximumNodes,
        remainingCharacters: maximumCharacters,
      ),
      0,
    );
    return SerializedMessage._(
      normalized.value,
      isJson: normalized.isJson,
      redactors: redactors,
    );
  }

  _NormalizedValue _normalize(
    Object? value,
    Set<Object> visiting,
    _NormalizationBudget budget,
    int depth,
  ) {
    if (depth > maximumDepth) {
      return const _NormalizedValue('<depth-limit>', isJson: false);
    }
    if (!budget.takeNode()) {
      return const _NormalizedValue('<node-limit>', isJson: false);
    }
    if (value == null || value is num || value is bool) {
      return _NormalizedValue(value, isJson: false);
    }
    if (value is String) {
      return _NormalizedValue(budget.takeString(value), isJson: false);
    }

    if (!visiting.add(value)) {
      return const _NormalizedValue('<circular-reference>', isJson: false);
    }

    try {
      if (value is Map) {
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          if (!budget.hasNodes) {
            result['__truncated__'] = '<collection-truncated>';
            break;
          }
          final rawKey = entry.key.toString();
          final key = budget.takeString(rawKey);
          if (redactedKeys.contains(rawKey.toLowerCase())) {
            result[key] = '***';
          } else {
            result[key] =
                _normalize(entry.value, visiting, budget, depth + 1).value;
          }
        }
        return _NormalizedValue(result, isJson: true);
      }

      if (value is Iterable) {
        final result = <Object?>[];
        for (final item in value) {
          if (!budget.hasNodes) {
            result.add('<collection-truncated>');
            break;
          }
          result.add(_normalize(item, visiting, budget, depth + 1).value);
        }
        return _NormalizedValue(result, isJson: true);
      }

      final registered = registry.encoderFor(value);
      if (registered != null) {
        try {
          final encoded =
              _normalize(registered(value), visiting, budget, depth + 1);
          return _NormalizedValue(encoded.value, isJson: encoded.isJson);
        } catch (_) {
          // Continue with toJson/toString when an application encoder fails.
        }
      }

      try {
        final dynamic dynamicValue = value;
        final encoded =
            _normalize(dynamicValue.toJson(), visiting, budget, depth + 1);
        return _NormalizedValue(encoded.value, isJson: encoded.isJson);
      } catch (_) {
        return _NormalizedValue(
          budget.takeString(value.toString()),
          isJson: false,
        );
      }
    } finally {
      visiting.remove(value);
    }
  }
}

final class _NormalizationBudget {
  _NormalizationBudget({
    required this.remainingNodes,
    required this.remainingCharacters,
  });

  int remainingNodes;
  int remainingCharacters;

  bool get hasNodes => remainingNodes > 0;

  bool takeNode() {
    if (remainingNodes <= 0) return false;
    remainingNodes -= 1;
    return true;
  }

  String takeString(String value) {
    if (remainingCharacters <= 0) return '…[truncated]';
    if (value.length <= remainingCharacters) {
      remainingCharacters -= value.length;
      return value;
    }
    final buffer = StringBuffer();
    var usedCharacters = 0;
    for (final rune in value.runes) {
      final width = rune > 0xFFFF ? 2 : 1;
      if (usedCharacters + width > remainingCharacters) break;
      buffer.writeCharCode(rune);
      usedCharacters += width;
    }
    remainingCharacters = 0;
    return '$buffer…[truncated]';
  }
}

final class _NormalizedValue {
  const _NormalizedValue(this.value, {required this.isJson});

  final Object? value;
  final bool isJson;
}
