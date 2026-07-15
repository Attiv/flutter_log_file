import 'package:flutter_log_file/src/format/message_serializer.dart';
import 'package:flutter_log_file/src/model/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

final class EncodableUser {
  EncodableUser(this.name);

  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'name': name};

  @override
  String toString() => 'fallback:$name';
}

final class PlainObject {
  @override
  String toString() => 'plain-object';
}

void main() {
  group('MessageSerializer', () {
    test('serializes Map and List as compact JSON by default', () {
      final serializer = MessageSerializer();

      expect(serializer.serialize({'a': 1}).render(), '{"a":1}');
      expect(serializer.serialize([1, 2]).render(), '[1,2]');
    });

    test('pretty prints JSON only when requested', () {
      final value = MessageSerializer().serialize({
        'items': [1, 2],
      });

      expect(value.render(), isNot(contains('\n')));
      expect(value.render(pretty: true), contains('\n  "items"'));
    });

    test('uses a registered encoder before toJson', () {
      final registry = ObjectEncoderRegistry()
        ..register<EncodableUser>((user) => {'alias': user.name});
      final serializer = MessageSerializer(registry: registry);

      expect(
        serializer.serialize(EncodableUser('Ada')).render(),
        '{"alias":"Ada"}',
      );
    });

    test('uses toJson when no registered encoder matches', () {
      final serializer = MessageSerializer();

      expect(
        serializer.serialize(EncodableUser('Ada')).render(),
        '{"name":"Ada"}',
      );
    });

    test('falls back to toString when object cannot be encoded', () {
      final serializer = MessageSerializer();

      expect(serializer.serialize(PlainObject()).render(), 'plain-object');
    });

    test('does not redact anything with empty default configuration', () {
      final serializer = MessageSerializer();

      expect(
        serializer.serialize({'token': 'secret'}).render(),
        '{"token":"secret"}',
      );
    });

    test('redacts configured keys case-insensitively and recursively', () {
      final serializer = MessageSerializer(redactedKeys: {'token'});

      expect(
        serializer.serialize({
          'TOKEN': 'secret',
          'nested': {'Token': 'another'},
        }).render(),
        '{"TOKEN":"***","nested":{"Token":"***"}}',
      );
    });

    test('applies only explicitly configured regex redactors', () {
      final plain = MessageSerializer().serialize('phone=13800138000').render();
      final redacted = MessageSerializer(
        redactors: [
          LogRedactor(pattern: RegExp(r'1\d{10}')),
        ],
      ).serialize('phone=13800138000').render();

      expect(plain, 'phone=13800138000');
      expect(redacted, 'phone=***');
    });

    test('faulty custom encoder falls back without throwing', () {
      final registry = ObjectEncoderRegistry()
        ..register<EncodableUser>((_) => throw StateError('broken'));

      expect(
        MessageSerializer(registry: registry)
            .serialize(EncodableUser('Ada'))
            .render(),
        '{"name":"Ada"}',
      );
    });
  });
}
