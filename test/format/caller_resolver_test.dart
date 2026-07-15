import 'package:flutter_log_file/src/format/caller_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('skips package internal frames and selects the first user frame', () {
    const stack = '''
#0 VLog.i (package:flutter_log_file/src/core/vlog.dart:20:4)
#1 CheckoutPage.submit (package:sample/features/checkout.dart:87:12)
#2 main (file:///C:/sample/test.dart:10:3)
''';

    final caller = const CallerResolver().resolve(StackTrace.fromString(stack));

    expect(caller.fileName, 'checkout.dart');
    expect(caller.line, 87);
    expect(caller.column, 12);
  });

  test('returns unknown rather than throwing for an unparseable stack', () {
    final caller = const CallerResolver().resolve(
      StackTrace.fromString('native stack without source information'),
    );

    expect(caller, CallerLocation.unknown);
  });
}
