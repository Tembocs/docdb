# EntiDB API Examples

This document provides examples of the new **Entity-based API** for EntiDB. The new approach provides type safety, better IDE support, and cleaner code without requiring code generation.

## Key Differences from Old Approach

| Old (Document-based) | New (Entity-based) |
|---------------------|-------------------|
| `Document(data: {...})` wrapper required | Direct domain objects: `Animal(...)` |
| `doc.data['name']` - untyped access | `animal.name` - fully typed |
| Returns `List<Document>` | Returns `List<Animal>` |
| Manual wrapping/unwrapping | Automatic via `Entity` interface |
| No compile-time safety | Full type checking |

---

## 1. Direct Entity Storage (No Document Wrapper)

```dart
import 'package:entidb/entidb.dart';

// Define your domain class implementing Entity
class Animal implements Entity {
  @override
  final String? id;
  final String name;
  final String species;
  final int age;
  
  Animal({this.id, required this.name, required this.species, required this.age});
  
  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'species': species,
    'age': age,
  };
  
  factory Animal.fromMap(String id, Map<String, dynamic> map) => Animal(
    id: id,
    name: map['name'],
    species: map['species'],
    age: map['age'],
  );
}

void main() async {
  final db = await EntiDB.open(path: './zoo');
  
  // Get typed collection - returns Animal objects, not Documents!
  final animals = await db.collection<Animal>('animals', fromMap: Animal.fromMap);
  
  // Insert domain objects directly
  await animals.insert(Animal(name: 'Buddy', species: 'Dog', age: 3));
  await animals.insert(Animal(name: 'Whiskers', species: 'Cat', age: 5));
  
  // Query returns List<Animal>, fully typed!
  final query = QueryBuilder().whereEquals('species', 'Dog').build();
  final dogs = await animals.find(query);
  print('Found ${dogs.length} dogs: ${dogs.first.name}');
  
  await db.close();
}
```

---

## 2. E-commerce Product Management

```dart
import 'package:entidb/entidb.dart';

// Product entity
class Product implements Entity {
  @override
  final String? id;
  final String name;
  final double price;
  final bool inStock;
  final List<String> tags;
  
  Product({
    this.id,
    required this.name,
    required this.price,
    this.inStock = true,
    this.tags = const [],
  });
  
  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'inStock': inStock,
    'tags': tags,
  };
  
  factory Product.fromMap(String id, Map<String, dynamic> map) => Product(
    id: id,
    name: map['name'],
    price: map['price'],
    inStock: map['inStock'] ?? true,
    tags: List<String>.from(map['tags'] ?? []),
  );
}

void main() async {
  final db = await EntiDB.open(path: './shop');
  final products = await db.collection<Product>('products', fromMap: Product.fromMap);
  
  // Insert with auto-generated ID
  await products.insert(Product(
    name: 'Wireless Mouse',
    price: 29.99,
    tags: ['electronics', 'accessories'],
  ));
  
  // Create index for fast lookups
  await products.createIndex('name', 'hash');
  
  // Find one product by name
  final widget = await products.findOne(
    QueryBuilder().whereEquals('name', 'Wireless Mouse').build()
  );
  print('Price: \$${widget?.price}'); // Fully typed access!
  
  // Range query on price
  final affordableProducts = await products.find(
    QueryBuilder().whereLessThan('price', 50.0).build()
  );
  print('Found ${affordableProducts.length} affordable products');
  
  await db.close();
}
```

---

## 3. Task Management with Transactions

```dart
import 'package:entidb/entidb.dart';

class Task implements Entity {
  @override
  final String? id;
  final String title;
  final bool completed;
  final DateTime? dueDate;
  
  Task({this.id, required this.title, this.completed = false, this.dueDate});
  
  @override
  Map<String, dynamic> toMap() => {
    'title': title,
    'completed': completed,
    'dueDate': dueDate?.toIso8601String(),
  };
  
  factory Task.fromMap(String id, Map<String, dynamic> map) => Task(
    id: id,
    title: map['title'],
    completed: map['completed'] ?? false,
    dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
  );
}

void main() async {
  final db = await EntiDB.open(path: './tasks');
  final tasks = await db.collection<Task>('tasks', fromMap: Task.fromMap);
  
  // Atomic transaction - all or nothing
  final txn = await db.beginTransaction();
  try {
    await txn.insert(Task(title: 'Write docs', completed: false));
    await txn.insert(Task(title: 'Review code', completed: false));
    await txn.insert(Task(title: 'Deploy app', completed: false));
    await txn.commit(); // All 3 tasks inserted atomically
    print('All tasks created successfully!');
  } catch (e) {
    await txn.rollback(); // None inserted if any fails
    print('Transaction failed: $e');
  }
  
  // Query all incomplete tasks
  final incomplete = await tasks.find(
    QueryBuilder().whereEquals('completed', false).build()
  );
  print('${incomplete.length} tasks pending');
  
  await db.close();
}
```

---

## 4. Blog with Complex Queries

```dart
import 'package:entidb/entidb.dart';

class BlogPost implements Entity {
  @override
  final String? id;
  final String title;
  final String content;
  final String author;
  final List<String> tags;
  final DateTime publishedAt;
  final int views;
  
  BlogPost({
    this.id,
    required this.title,
    required this.content,
    required this.author,
    this.tags = const [],
    DateTime? publishedAt,
    this.views = 0,
  }) : publishedAt = publishedAt ?? DateTime.now();
  
  @override
  Map<String, dynamic> toMap() => {
    'title': title,
    'content': content,
    'author': author,
    'tags': tags,
    'publishedAt': publishedAt.toIso8601String(),
    'views': views,
  };
  
  factory BlogPost.fromMap(String id, Map<String, dynamic> map) => BlogPost(
    id: id,
    title: map['title'],
    content: map['content'],
    author: map['author'],
    tags: List<String>.from(map['tags'] ?? []),
    publishedAt: DateTime.parse(map['publishedAt']),
    views: map['views'] ?? 0,
  );
}

void main() async {
  final db = await EntiDB.open(path: './blog');
  final posts = await db.collection<BlogPost>('posts', fromMap: BlogPost.fromMap);
  
  // Insert posts
  await posts.insert(BlogPost(
    title: 'Getting Started with EntiDB',
    content: 'EntiDB is a powerful embedded database...',
    author: 'Alice',
    tags: ['tutorial', 'database'],
    views: 150,
  ));
  
  // Create indices for common queries
  await posts.createIndex('author', 'hash');
  await posts.createIndex('views', 'btree');
  
  // Complex query: popular posts by Alice
  final alicePopular = await posts.find(
    QueryBuilder()
      .whereEquals('author', 'Alice')
      .whereGreaterThan('views', 100)
      .build()
  );
  print('Alice has ${alicePopular.length} popular posts');
  
  // Find posts with specific tags
  final tutorials = await posts.find(
    QueryBuilder().whereIn('tags', ['tutorial']).build()
  );
  print('Tutorial posts: ${tutorials.map((p) => p.title).join(", ")}');
  
  await db.close();
}
```

---

## 5. Encrypted Customer Data

```dart
import 'dart:typed_data';
import 'package:entidb/entidb.dart';

class Customer implements Entity {
  @override
  final String? id;
  final String email;
  final String fullName;
  final String phoneNumber;
  
  Customer({
    this.id,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
  });
  
  @override
  Map<String, dynamic> toMap() => {
    'email': email,
    'fullName': fullName,
    'phoneNumber': phoneNumber,
  };
  
  factory Customer.fromMap(String id, Map<String, dynamic> map) => Customer(
    id: id,
    email: map['email'],
    fullName: map['fullName'],
    phoneNumber: map['phoneNumber'],
  );
}

void main() async {
  // Setup encryption for sensitive customer data
  final encryptionKey = Uint8List(32); // 256-bit key (use secure key in production!)
  final encryption = EncryptionService(encryptionKey);
  
  final db = await EntiDB.connect(
    dataPath: 'customers/',
    userPath: 'users/',
    dataEncryption: encryption, // Data encrypted at rest
  );
  
  final customers = await db.collection<Customer>('customers', fromMap: Customer.fromMap);
  
  // Insert encrypted customer data
  await customers.insert(Customer(
    email: 'john@example.com',
    fullName: 'John Doe',
    phoneNumber: '+1-555-0123',
  ));
  
  // Query encrypted data (transparent decryption)
  final customer = await customers.findOne(
    QueryBuilder().whereEquals('email', 'john@example.com').build()
  );
  print('Customer: ${customer?.fullName}');
  
  await db.close();
}
```

---

## Summary

The new Entity-based API provides:

- **Type Safety**: Collections return your domain objects, not generic Documents
- **No Code Generation**: Works with AOT compilation (Flutter) without build_runner
- **Familiar Pattern**: Similar to `toJson()`/`fromJson()` developers already use
- **Full IDE Support**: Autocomplete, refactoring, and go-to-definition work seamlessly
- **Backward Compatibility**: Legacy `Document` class still works for untyped data