import 'package:flutter_test/flutter_test.dart';
import 'package:vlog_demo/demo_models.dart';

void main() {
  test('DemoUser exposes stable structured JSON fields', () {
    const user = DemoUser(
      id: 7,
      name: 'Ada',
      roles: ['admin', 'tester'],
      active: true,
    );

    expect(user.toJson(), {
      'id': 7,
      'name': 'Ada',
      'roles': ['admin', 'tester'],
      'active': true,
    });
  });

  test('DemoOrder can be encoded through a registered encoder', () {
    const order = DemoOrder(
      id: 'ORDER-2026-001',
      amount: 128.50,
      state: DemoOrderState.paid,
    );

    expect(encodeDemoOrder(order), {
      'id': 'ORDER-2026-001',
      'amount': 128.5,
      'state': 'paid',
    });
  });
}
