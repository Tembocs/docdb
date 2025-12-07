/// Customer Entity
///
/// A simple entity demonstrating minimal Entity implementation.
import 'package:entidb/entidb.dart';

/// A customer entity for user management.
///
/// This is a simpler entity example compared to [Product],
/// showing the minimal implementation required.
class Customer implements Entity {
  @override
  final String? id;

  /// Customer's full name.
  final String name;

  /// Customer's email address.
  final String email;

  /// Whether the customer account is active.
  final bool isActive;

  /// Creates a new customer.
  Customer({
    this.id,
    required this.name,
    required this.email,
    this.isActive = true,
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'isActive': isActive,
  };

  /// Deserializes a customer from storage.
  static Customer fromMap(String id, Map<String, dynamic> map) {
    return Customer(
      id: id,
      name: map['name'] as String,
      email: map['email'] as String,
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  /// Creates a copy with modified fields.
  Customer copyWith({String? id, String? name, String? email, bool? isActive}) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() => 'Customer(id: $id, name: $name, email: $email)';
}
