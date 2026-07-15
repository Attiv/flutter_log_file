final class DemoUser {
  const DemoUser({
    required this.id,
    required this.name,
    required this.roles,
    required this.active,
  });

  final int id;
  final String name;
  final List<String> roles;
  final bool active;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'roles': roles,
        'active': active,
      };
}

enum DemoOrderState { created, paid, shipped }

final class DemoOrder {
  const DemoOrder({
    required this.id,
    required this.amount,
    required this.state,
  });

  final String id;
  final double amount;
  final DemoOrderState state;
}

Map<String, Object?> encodeDemoOrder(DemoOrder order) => {
      'id': order.id,
      'amount': order.amount,
      'state': order.state.name,
    };
