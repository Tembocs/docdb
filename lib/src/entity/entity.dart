/// Core entity module for EntiDB.
///
/// This module defines the [Entity] interface that all storable classes
/// must implement. The interface-based approach enables type-safe storage
/// without requiring code generation.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:entidb/src/entity/entity.dart';
///
/// class Product implements Entity {
///   @override
///   final String? id;
///   final String name;
///   final double price;
///
///   Product({this.id, required this.name, required this.price});
///
///   @override
///   Map<String, dynamic> toMap() => {'name': name, 'price': price};
///
///   factory Product.fromMap(String id, Map<String, dynamic> map) =>
///     Product(id: id, name: map['name'], price: map['price']);
/// }
/// ```
///
/// ## Why Interface Over Annotations?
///
/// | Approach | Code Gen | Build Step | AOT Compatible |
/// |----------|----------|------------|----------------|
/// | Annotations | Yes | Required | Requires setup |
/// | **Interface** | No | None | Yes |
///
/// The interface approach was chosen because:
/// - No `build_runner` required
/// - Works with AOT compilation (Flutter)
/// - Familiar pattern (`toJson()`/`fromJson()`)
/// - Full IDE support (autocomplete, refactoring)
///
/// ## Usage with Collections
///
/// ```dart
/// final db = await EntiDB.open(path: './shop');
/// final products = await db.collection<Product>(
///   'products',
///   fromMap: Product.fromMap,
/// );
///
/// await products.insert(Product(name: 'Widget', price: 29.99));
/// final widget = await products.findOne(
///   QueryBuilder().whereEquals('name', 'Widget').build(),
/// );
/// print(widget?.price); // 29.99 - fully typed!
/// ```
library;

/// Base interface for all storable entities in EntiDB.
///
/// Any class that needs to be stored in a EntiDB collection must implement
/// this interface. The interface provides a minimal contract for serialization
/// while allowing full flexibility in class design.
///
/// ## Implementation Requirements
///
/// 1. Provide an [id] getter (can be `null` for new entities)
/// 2. Implement [toMap] to serialize fields (excluding `id`)
/// 3. Create a `fromMap` factory constructor for deserialization
///
/// ## Example Implementation
///
/// ```dart
/// class Task implements Entity {
///   @override
///   final String? id;
///   final String title;
///   final bool completed;
///   final DateTime? dueDate;
///
///   Task({
///     this.id,
///     required this.title,
///     this.completed = false,
///     this.dueDate,
///   });
///
///   @override
///   Map<String, dynamic> toMap() => {
///     'title': title,
///     'completed': completed,
///     if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
///   };
///
///   factory Task.fromMap(String id, Map<String, dynamic> map) => Task(
///     id: id,
///     title: map['title'] as String,
///     completed: map['completed'] as bool? ?? false,
///     dueDate: map['dueDate'] != null
///       ? DateTime.parse(map['dueDate'] as String)
///       : null,
///   );
/// }
/// ```
///
/// ## ID Generation
///
/// When inserting an entity with a `null` id, EntiDB automatically generates
/// a UUID v4 identifier. If an id is provided, it will be used as-is.
///
/// ```dart
/// // Auto-generated ID
/// await collection.insert(Task(title: 'Buy milk'));
///
/// // Custom ID
/// await collection.insert(Task(id: 'task-001', title: 'Buy eggs'));
/// ```
///
/// ## Nested Objects
///
/// For entities containing nested objects, serialize them recursively:
///
/// ```dart
/// class Order implements Entity {
///   @override
///   final String? id;
///   final List<OrderItem> items;
///
///   Order({this.id, required this.items});
///
///   @override
///   Map<String, dynamic> toMap() => {
///     'items': items.map((item) => item.toMap()).toList(),
///   };
///
///   factory Order.fromMap(String id, Map<String, dynamic> map) => Order(
///     id: id,
///     items: (map['items'] as List)
///       .map((item) => OrderItem.fromMap(item))
///       .toList(),
///   );
/// }
/// ```
///
/// ## Type Safety
///
/// The generic collection system ensures type safety at compile time:
///
/// ```dart
/// final tasks = await db.collection<Task>('tasks', fromMap: Task.fromMap);
///
/// // Returns Task, not Map or Document
/// final task = await tasks.get('task-001');
/// print(task?.title); // Full autocomplete support
///
/// // Type-safe queries
/// final completed = await tasks.find(
///   QueryBuilder().whereEquals('completed', true).build(),
/// );
/// // completed is List<Task>
/// ```
abstract interface class Entity {
  /// The unique identifier for this entity.
  ///
  /// Returns `null` for new entities that haven't been persisted yet.
  /// Once inserted into a collection, the id is guaranteed to be non-null.
  ///
  /// EntiDB generates a UUID v4 if this is `null` during insertion.
  /// If a custom id is provided, it must be unique within the collection.
  ///
  /// Example:
  /// ```dart
  /// final task = Task(title: 'New task');
  /// print(task.id); // null
  ///
  /// await collection.insert(task);
  /// final saved = await collection.findOne(...);
  /// print(saved?.id); // 'a1b2c3d4-e5f6-...'
  /// ```
  String? get id;

  /// Converts this entity to a map for storage.
  ///
  /// The returned map should contain all fields that need to be persisted,
  /// **excluding the id** (which is stored separately by EntiDB).
  ///
  /// ## Guidelines
  ///
  /// - Only include serializable values (primitives, lists, maps)
  /// - Convert complex types (DateTime, enums) to serializable formats
  /// - Use consistent key names (consider snake_case for JSON compatibility)
  /// - Omit null values to save storage space (optional)
  ///
  /// ## Supported Types
  ///
  /// EntiDB natively supports:
  /// - `String`, `int`, `double`, `bool`, `null`
  /// - `List<T>` where T is a supported type
  /// - `Map<String, T>` where T is a supported type
  /// - `DateTime` (serialized to ISO 8601 string)
  /// - `Uint8List` (binary data)
  ///
  /// For custom types, use the [TypeRegistry] to register serializers.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Map<String, dynamic> toMap() => {
  ///   'name': name,
  ///   'price': price,
  ///   'tags': tags, // List<String>
  ///   'metadata': metadata, // Map<String, dynamic>
  ///   'createdAt': createdAt.toIso8601String(),
  /// };
  /// ```
  Map<String, dynamic> toMap();
}
