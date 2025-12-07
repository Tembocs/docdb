# Dart Document Database (EntiDB) - Technical Architecture

## 1. Introduction

This document outlines the technical architecture for the next generation of EntiDB. The goal is to build a production-grade, embedded document database from scratch in Dart, without relying on external database engines (like SQLite, Hive, or Isar).

The architecture prioritizes **Data Integrity (ACID)**, **Performance**, **Scalability**, and **Security**, addressing limitations in the initial prototype (such as file-per-document storage and lack of index persistence).

### Design Principles

1. **Layered Architecture**: Clear separation between storage, data, query, and API layers.
2. **Type Safety**: Leverage Dart's strong typing with generic collections for compile-time guarantees.
3. **Entity-First Design**: Store domain objects directly via the `Entity` interface—no schema-less documents or manual wrapping.
4. **Separation of Concerns**: Distinct modules for authentication, data, and system operations.
5. **Extensibility**: Plugin-based design for storage backends, encryption, and custom types.
6. **Testability**: Dependency injection and interface-based design for easy mocking.
7. **No Code Generation**: Core functionality works without build_runner or code generation tools.
8. **No Backward Compatibility**: Clean-slate design without legacy patterns or schema-less fallbacks.

## 2. High-Level Architecture

The system is layered to separate concerns, from the user-facing API down to the raw bytes on the disk.

```mermaid
graph TD
    User[User / Application] --> API[Public API (EntiDB)]
    API --> QM[Query Manager]
    API --> TM[Transaction Manager]
    
    subgraph "Core Engine"
        QM --> Optimizer[Query Optimizer]
        Optimizer --> Executor[Query Executor]
        
        TM --> WAL[Write-Ahead Log]
        TM --> LockMgr[Lock Manager / MVCC]
        
        Executor --> AccessMethods[Access Methods (B+ Tree, Heap)]
        AccessMethods --> BufferMgr[Buffer Manager / Page Cache]
        
        BufferMgr --> Pager[Pager / Disk Manager]
        Pager --> Encryption[Encryption Layer]
    end
    
    subgraph "Storage (Disk)"
        Encryption --> DBFile[Main Database File (.db)]
        Encryption --> WALFile[WAL File (.wal)]
    end
```

## 3. Core Components

### 3.1. Storage Engine (The Foundation)

The most significant shift from the V1 architecture is moving from a "file-per-document" model to a **Page-Based Storage Architecture**. This mimics robust systems like PostgreSQL and SQLite.

#### 3.1.1. The Pager (Disk Manager)
*   **Responsibility**: Abstraction over the file system. It reads and writes fixed-size blocks of data (Pages) to a single database file.
*   **Page Size**: Configurable, typically 4KB or 8KB.
*   **Page ID**: Every page is identified by a unique integer ID (PID).

```dart
// Reading and writing pages
final pager = await Pager.open('database.db');
final page = await pager.readPage(pageId);
page.writeInt32(offset, value);
await pager.writePage(page);
```

*   **File Structure**:
    *   **Header Page (Page 0)**: Contains database metadata (version, page size, encryption salt, pointer to schema root, pointer to free list).
    *   **Data Pages**: Store actual entity data.
    *   **Index Pages**: Store B+ Tree nodes.
    *   **Overflow Pages**: Handle entities larger than a single page.

#### 3.1.2. Buffer Manager (Page Cache)
*   **Responsibility**: Minimizes disk I/O by caching frequently accessed pages in memory.
*   **Replacement Policy**: LRU (Least Recently Used) or Clock algorithm.
*   **Dirty Pages**: Tracks pages modified in memory that need to be flushed to disk.

#### 3.1.3. Data Serialization
*   **Format**: Custom Binary Format (similar to BSON or MessagePack) instead of JSON text.
*   **Benefits**: Smaller size, faster parsing, supports types like `DateTime` and `Binary` natively without base64 encoding overhead.

#### 3.1.4. Entity Interface (Type-Safe Object Storage)

EntiDB uses an **interface-based approach** for storing domain objects directly, without requiring code generation:

```dart
/// Base interface for all storable entities
abstract class Entity {
  String? get id;               // Auto-generated if null
  Map<String, dynamic> toMap(); // Serialization
}
```

Developers implement this interface on their domain classes:

```dart
class Animal implements Entity {
  @override
  final String? id;
  final String name;
  final String species;
  
  Animal({this.id, required this.name, required this.species});
  
  @override
  Map<String, dynamic> toMap() => {
    'name': name, 'species': species,
  };
  
  factory Animal.fromMap(String id, Map<String, dynamic> map) =>
    Animal(id: id, name: map['name'], species: map['species']);
}
```

**Benefits**:
*   **No code generation** required—works with AOT compilation (Flutter).
*   **Familiar pattern**—similar to `toJson()`/`fromJson()` developers already use.
*   **Type-safe collections**—`Collection<Animal>` returns `Animal` objects, not raw maps.
*   **IDE support**—full autocomplete and refactoring support.

### 3.2. Access Methods & Indexing

#### 3.2.1. Heap File (Entity Storage)
*   **Structure**: An unordered collection of pages used to store serialized entities.
*   **Row ID (RID)**: Each entity is identified internally by `(PageID, SlotIndex)`.

#### 3.2.2. B+ Tree Indexes
*   **Persistence**: Unlike V1, indexes are disk-resident structures managed by the Pager.
*   **Clustered Index**: The Primary Key (`_id`) index may store the entity data directly in the leaf nodes (Clustered) or point to the Heap File (Non-Clustered).
*   **Secondary Indexes**: B+ Trees mapping `Field Value -> Primary Key`.

```dart
// Creating and using indexes
await collection.createIndex('email', 'hash');   // Fast equality
await collection.createIndex('age', 'btree');    // Range queries
final results = await collection.findByIndex('email', 'user@example.com');
```

*   **Structure**:
    *   **Internal Nodes**: Contain keys and pointers to child pages.
    *   **Leaf Nodes**: Contain keys and values (or RIDs). Linked to siblings for efficient range scans.

### 3.3. Transaction Management (ACID)

#### 3.3.1. Atomicity & Durability: Write-Ahead Logging (WAL)
*   **Mechanism**: Before any modification is applied to the main database pages, the change is appended to a sequential log file (`.wal`).
*   **Checkpointing**: Periodically, the WAL is "played" into the main database file, and the log is truncated.
*   **Recovery**: On startup, the system checks for a non-empty WAL. If found, it replays the log to restore the database to a consistent state (crash recovery).

```dart
// Transaction usage with typed entities
final txn = await db.beginTransaction();
try {
  txn.insert(Animal(name: 'Buddy', species: 'Dog'));
  txn.insert(Animal(name: 'Whiskers', species: 'Cat'));
  await txn.commit();  // Both inserted atomically
} catch (e) {
  await txn.rollback(); // Neither inserted
}
```

#### 3.3.2. Isolation & Concurrency: MVCC (Multi-Version Concurrency Control)
*   **Concept**: Readers do not block writers, and writers do not block readers.
*   **Implementation**:
    *   Each transaction sees a consistent "snapshot" of the database.
    *   When a record is updated, a new version is created rather than overwriting the old one immediately.
    *   **Visibility Rules**: Determine which version of a record is visible to a transaction based on Transaction IDs.
*   **Alternative (Simpler)**: **Strict Two-Phase Locking (S2PL)** with Read/Write locks. (Easier to implement initially, but lower concurrency).

### 3.4. Query Engine

#### 3.4.1. Parser & Planner
*   **Parser**: Validates the query structure.
*   **Optimizer**: Uses statistics (e.g., entity count, index cardinality) to decide the execution plan.
    *   *Example*: "Should I use the 'Age' index or scan the table?"

#### 3.4.2. Executor (Volcano Model)
*   **Pipeline**: Operators (`Scan`, `Filter`, `Project`, `Sort`, `Join`) are chained together.
*   **Interface**: Each operator implements `open()`, `next()`, `close()`.

```dart
// Query construction with fluent API - returns typed entities
final animals = await db.collection<Animal>('animals', fromMap: Animal.fromMap);
final query = QueryBuilder()
    .whereEquals('species', 'Dog')
    .whereGreaterThan('age', 2)
    .build();
final dogs = await animals.find(query);  // Returns List<Animal>
```

### 3.5. Security & Encryption

*   **Encryption at Rest**:
    *   **Page-Level Encryption**: The Pager encrypts pages before writing to disk and decrypts them upon reading into the Buffer Manager.
    *   **Algorithm**: AES-256-XTS (standard for disk encryption) or AES-GCM (if integrity checks are needed per page).
    *   **Key Management**: Master key wraps the database encryption key.

```dart
// Configuring encryption
final key = Uint8List(32); // 256-bit key
final encryption = EncryptionService(key);
final db = await EntiDB.connect(
  dataPath: 'data/', userPath: 'users/',
  dataEncryption: encryption,
);
```

## 4. Implementation Roadmap

### Phase 1: The Foundation
1.  Implement **Pager** and **Buffer Manager**.
2.  Define **Binary Page Format**.
3.  Implement **Heap File** for storing raw bytes.

### Phase 2: Indexing & Data
1.  Implement **B+ Tree** on top of the Pager.
2.  Implement **Binary Entity Serializer**.
3.  Connect B+ Tree to Entity Storage (Primary Key lookup).

### Phase 3: Transactions
1.  Implement **WAL (Write-Ahead Log)**.
2.  Implement **Recovery** (Replay WAL on startup).
3.  Implement basic **Lock Manager**.

### Phase 4: Query & API
1.  Implement **Query Executor** (Scan, Filter).
2.  Implement **Query Optimizer** (Index selection).
3.  Expose public API (`insert`, `find`, `update`, `delete`).

## 5. Summary of Improvements over V1

| Feature | V1 (Current) | V2 (Proposed Architecture) |
| :--- | :--- | :--- |
| **Storage** | One JSON file per entity | Single binary file (Paged) |
| **Indexing** | In-memory only (rebuilt on boot) | Disk-resident B+ Trees |
| **Transactions** | Full DB Snapshot/Restore | Write-Ahead Log (WAL) |
| **Concurrency** | Global Lock | MVCC or Page-level Locking |
| **Scalability** | Limited by file handles & RAM | Limited by Disk Size |
| **Format** | JSON (Text) | Binary (Compact) |

## 6. Architecture Decisions

### 6.1. Entity Interface for Type-Safe Storage

The architecture adopts an **interface-based approach** for storing domain objects, enabling developers to work with their own classes directly rather than generic documents.

#### The Entity Interface

```dart
/// Base interface for all storable entities (lib/src/entity/entity.dart)
abstract class Entity {
  /// Unique identifier. If null during insert, auto-generated.
  String? get id;
  
  /// Converts the entity to a map for storage.
  Map<String, dynamic> toMap();
}
```

#### Why Interface Over Annotations?

| Approach | Code Gen | Build Step | AOT Compatible | Recommended |
|----------|----------|------------|----------------|-------------|
| **Annotations** (`@Collection`) | Yes | Required | Requires setup | No |
| **Interface** (`Entity`) | No | None | Yes | **Yes** |
| **Manual Registration** | No | None | Yes | Fallback |

The interface approach was chosen because:

1. **No build_runner required**: Works immediately without `dart run build_runner build`.
2. **AOT compilation support**: Essential for Flutter apps compiled ahead-of-time.
3. **Familiar pattern**: Developers already implement `toJson()`/`fromJson()` for JSON serialization.
4. **Full IDE support**: Autocomplete, refactoring, and go-to-definition work seamlessly.

#### Usage Example

```dart
// 1. Define your domain class
class Product implements Entity {
  @override
  final String? id;
  final String name;
  final double price;
  final bool inStock;
  
  Product({this.id, required this.name, required this.price, this.inStock = true});
  
  @override
  Map<String, dynamic> toMap() => {
    'name': name, 'price': price, 'inStock': inStock,
  };
  
  factory Product.fromMap(String id, Map<String, dynamic> map) => Product(
    id: id, name: map['name'], price: map['price'], inStock: map['inStock'] ?? true,
  );
}

// 2. Use typed collections
final db = await EntiDB.open(path: './shop');
final products = await db.collection<Product>('products', fromMap: Product.fromMap);

// 3. Insert, query, update with full type safety
await products.insert(Product(name: 'Widget', price: 29.99));
final widget = await products.findOne(QueryBuilder().whereEquals('name', 'Widget').build());
print(widget?.price);  // 29.99 - fully typed!
```

> **Note**: EntiDB is Entity-only by design. There is no schema-less `Document` class or backward compatibility layer. All stored data must be represented by classes implementing the `Entity` interface. This enforces type safety and better code organization.

### 6.2. Separation of User and Data Storage

The architecture deliberately separates **User** (authentication) data from **Application** (entity) data through parallel hierarchies:

| Layer | User Domain | Data Domain |
|-------|-------------|-------------|
| **Storage** | `UserStorage` | `Storage<T>` |
| **Collection** | `UserCollection` | `Collection<T>` |
| **Entity** | `User` (implements `Entity`) | Any class implementing `Entity` |

#### Rationale

1. **Security Isolation**: Authentication data (password hashes, roles, tokens) requires stricter access control than application data. Separation prevents accidental exposure through generic query APIs.

2. **Type Safety**: `User` is a strongly-typed entity with specific fields (`username`, `passwordHash`, `roles`). Different authentication constraints require specialized handling.

3. **Independent Configuration**: User storage and data storage can have different encryption keys, backup schedules, and storage backends.

```dart
// Current: Separate configurations
final config = StorageConfig(
  dataStorageType: StorageType.fileBased,
  userStorageType: StorageType.fileBased,
  dataStoragePath: 'data/',
  userStoragePath: 'users/',  // Separate path
  dataEncryptionService: dataEncryption,
  userEncryptionService: userEncryption,  // Separate key
);
```

#### Trade-offs

*   **Code Duplication**: `UserCollection` (~436 lines) and `DataCollection` (~383 lines) share similar logic for locking, versioning, indexing, and transactions.
*   **Maintenance Burden**: Bug fixes and feature additions must be applied to both hierarchies.

### 6.3. Generic Collection Architecture

The collection and storage layers use **generics with the Entity interface** to provide type-safe operations:

```dart
/// Generic collection for any Entity type
class Collection<T extends Entity> {
  final Storage<T> _storage;
  final T Function(String id, Map<String, dynamic>) _fromMap;
  final Lock _collectionLock = Lock();
  final IndexManager _indexManager = IndexManager();
  
  Collection(this._storage, {required T Function(String, Map<String, dynamic>) fromMap})
    : _fromMap = fromMap;
  
  Future<void> insert(T entity) async {
    final id = entity.id ?? generateUniqueId();
    await _storage.insert(id, entity.toMap());
    _indexManager.insert(id, entity.toMap());
  }
  
  Future<T?> get(String id) async {
    final data = await _storage.get(id);
    return data != null ? _fromMap(id, data) : null;
  }
  
  Future<List<T>> find(IQuery query) async {
    final results = await _storage.query(query);
    return results.map((r) => _fromMap(r.id, r.data)).toList();
  }
}
```

Similarly for storage:

```dart
/// Generic storage interface
abstract class Storage<T extends Entity> {
  Future<void> init();
  Future<void> insert(String id, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> get(String id);
  Future<void> update(String id, Map<String, dynamic> data);
  Future<void> delete(String id);
  Stream<StorageRecord> streamAll();
  Future<Snapshot> getSnapshot();
}
```

#### User Storage as Specialized Entity

`User` implements `Entity`, making it a specialized case of the generic system:

```dart
class User implements Entity {
  @override
  final String? id;
  final String username;
  final String passwordHash;
  final List<String> roles;
  
  @override
  Map<String, dynamic> toMap() => {
    'username': username, 'passwordHash': passwordHash, 'roles': roles,
  };
  
  factory User.fromMap(String id, Map<String, dynamic> map) => User(
    id: id, username: map['username'], 
    passwordHash: map['passwordHash'], roles: List<String>.from(map['roles']),
  );
}

// UserCollection is just Collection<User> with auth-specific methods
class UserCollection extends Collection<User> {
  Future<User?> findByUsername(String username) => 
    findOne(QueryBuilder().whereEquals('username', username).build());
}
```

#### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **DRY Code** | Single `Collection<T>` implementation for all entity types |
| **Type Safety** | `Collection<Product>` returns `Product`, not `Map` or `Document` |
| **Entity Constraint** | Generic bound `T extends Entity` ensures `toMap()` exists |
| **Extensibility** | New entity types require only implementing `Entity` interface |
| **Security** | `UserCollection` can add auth-specific logic while sharing base implementation |

## 7. Module Layout

The project is organized into the following modules within `lib/src`, arranged from the foundational layers to user-facing components:

---

### 7.1. Foundation Layer

#### **engine**
The low-level storage engine that provides the foundation for all data persistence.

| File | Purpose |
|------|---------|
| `constants.dart` | Defines engine-wide constants such as `kPageSize`. |
| `storage/page.dart` | Represents a fixed-size block **of** data (`Page`) in memory. Provides methods for reading/writing integers, strings, and bytes at specific offsets. Tracks dirty state for write-back optimization. |

```dart
// Page operations
final page = Page(pageId);
page.writeInt32(0, entityCount);
page.writeString(4, 'header', maxLength: 16);
if (page.isDirty) await pager.writePage(page);
```

| `storage/pager.dart` | The Disk Manager that abstracts file system operations. Implements an **append-only** storage strategy where pages are identified by unique IDs. Handles recovery by scanning the file to rebuild the page offset map on startup. |

#### **exceptions**
Centralized location for all custom exceptions, providing clear error handling across the system.

| File | Purpose |
|------|---------|
| `exceptions.dart` | Barrel export for all exception types. |
| `*_exceptions.dart` | Domain-specific exceptions (e.g., `authentication_exceptions.dart`, `transaction_exceptions.dart`, `storage_exceptions.dart`, etc.) providing granular error types for each module. |

#### **utils**
Common utilities shared across all modules.

| File | Purpose |
|------|---------|
| `constants.dart` | Application-wide constants including logger names, file paths, and configuration defaults. |
| `helpers.dart` | Utility functions such as `generateUniqueId()`, `capitalize()`, `formatErrorMessage()`, and `parseTimestamp()`. |
| `validators.dart` | Input validation utilities for data integrity. |

#### **logger**
Provides structured logging capabilities with module-specific contexts.

| File | Purpose |
|------|---------|
| `entidb_logger.dart` | Thread-safe logging utility supporting multiple log levels (INFO, WARNING, ERROR, DEBUG). Uses synchronized file access and maintains log sinks per file path. Supports custom log paths for testing. |

---

### 7.2. Data Layer

#### **entity**
Defines the core interface for storable objects.

| File | Purpose |
|------|---------|
| `entity.dart` | The `Entity` interface that all storable classes must implement. Defines `id` getter and `toMap()` method for serialization. No code generation required. |

```dart
// Any class can be stored by implementing Entity
class Task implements Entity {
  @override
  final String? id;
  final String title;
  final bool completed;
  
  Task({this.id, required this.title, this.completed = false});
  
  @override
  Map<String, dynamic> toMap() => {'title': title, 'completed': completed};
  
  factory Task.fromMap(String id, Map<String, dynamic> m) =>
    Task(id: id, title: m['title'], completed: m['completed'] ?? false);
}
```

> **Design Decision**: EntiDB does not include a schema-less `Document` class. All data must be represented by typed entities implementing the `Entity` interface. This ensures compile-time type safety and encourages proper domain modeling.

#### **schema**
Defines validation rules and structure for entities.

| File | Purpose |
|------|---------|
| `schema.dart` | The `Schema` class that validates entity data against defined field rules. Supports required fields, type checking, and nested field validation. Provides serialization/deserialization via `toMap()` and `fromMap()`. |

```dart
// Defining and using schemas
final schema = Schema(fields: {
  'email': FieldSchema(expectedType: String, required: true),
  'age': FieldSchema(expectedType: int, required: false),
});
schema.validate(entity.toMap()); // Throws if invalid
```

| `field_schema.dart` | Defines individual field validation rules including expected types, required flags, custom validators, and nested field schemas. |

#### **type_registry**
Enables extensibility through custom type support.

| File | Purpose |
|------|---------|
| `type_registry.dart` | Singleton registry for custom data types. Allows registration of serializers and deserializers for non-primitive types. Provides thread-safe type lookup by both `Type` and string name. |

---

### 7.3. Storage Layer

#### **storage**
High-level storage abstractions supporting multiple backend implementations. Uses generics with the `Entity` interface for type-safe operations (see Section 6.1 and 6.3).

| File/Folder | Purpose |
|-------------|---------|
| `storage.dart` | Generic `Storage<T extends Entity>` interface defining CRUD operations for any entity type. |
| `storage_config.dart` | Configuration class defining storage types, paths, and encryption services. |
| `storage_type.dart` | Enum defining supported storage backends: `inMemory` and `fileBased`. |
| `file_storage.dart` | File-based implementation of `Storage<T>` with encryption support. |
| `memory_storage.dart` | In-memory implementation for testing and temporary storage. |

```dart
// Generic storage interface for any Entity type
abstract class Storage<T extends Entity> {
  Future<void> insert(String id, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> get(String id);
  Future<void> update(String id, Map<String, dynamic> data);
  Future<void> delete(String id);
  Stream<StorageRecord> streamAll();
}

// Usage: storage is type-agnostic, collection adds type safety
final storage = FileStorage(path: 'data/', encryption: encryptionService);
final products = Collection<Product>(storage, fromMap: Product.fromMap);
```

#### **encryption**
Provides data-at-rest encryption services.

| File | Purpose |
|------|---------|
| `encryption_service.dart` | AES-GCM encryption implementation using PointyCastle. Supports 128/192/256-bit keys, generates random IVs per encryption, and provides methods for encrypting/decrypting both strings and binary data with optional AAD (Additional Authenticated Data). |
| `no_encryption_service.dart` | Pass-through implementation for scenarios where encryption is disabled. |

---

### 7.4. Indexing Layer

#### **index**
Implements indexing strategies for efficient entity retrieval.

| File | Purpose |
|------|---------|
| `i_index.dart` | Interface defining the contract for all index implementations (`insert`, `remove`, `search`, `clear`). |
| `btree.dart` | B+ Tree index implementation for range queries and ordered access. |
| `hash.dart` | Hash index implementation for fast equality lookups. |
| `index_manager.dart` | Manages multiple indices per collection. Handles index creation/removal and coordinates entity insertions/removals across all indices. Supports index type selection (`btree`, `hash`). |

---

### 7.5. Transaction Layer

#### **transaction**
Manages ACID transactions ensuring data consistency.

| File | Purpose |
|------|---------|
| `transaction.dart` | Core `Transaction` class that captures initial snapshots of data and user storage, queues operations (insert, update, delete), and provides `commit()` and `rollback()` functionality. |
| `transaction_manager.dart` | Manages transaction lifecycle ensuring only one transaction is active at a time. Provides `beginTransaction()`, `commit()`, and `rollback()` methods. |
| `transaction_status.dart` | Enum defining transaction states: `active`, `committed`, `rolledBack`. |
| `transaction_operation.dart` | Defines the `Operation` class representing a queued operation within a transaction. |
| `operation_types.dart` | Enum for operation types: `create`, `update`, `delete`. |
| `isolation_level.dart` | Defines isolation levels for concurrency control. |

---

### 7.6. Query Layer

#### **query**
Handles query construction, parsing, and execution.

| File | Purpose |
|------|---------|
| `query.dart` | Abstract `IQuery` interface and concrete implementations: `EqualsQuery`, `AndQuery`, `OrQuery`, `NotQuery`, `GreaterThanQuery`, `LessThanQuery`, `InQuery`, `RegexQuery`. Each query type implements `matches(Entity)` for filtering and supports serialization via `toMap()`/`fromMap()`. |
| `query_builder.dart` | Fluent API for constructing queries programmatically (e.g., `QueryBuilder().whereEquals('field', value).build()`). |

---

### 7.7. Collection Layer

#### **collection**
Provides high-level, type-safe entity management with concurrency control. Uses generics with the `Entity` interface (see Section 6.1 and 6.3).

| File | Purpose |
|------|---------|
| `collection.dart` | Generic `Collection<T extends Entity>` class providing type-safe CRUD operations, transaction support, index management, and concurrency control. Requires a `fromMap` factory for deserialization. |
| `user_collection.dart` | Specialized `Collection<User>` with authentication-specific methods like `findByUsername()`. |

```dart
// Type-safe collection operations
final products = await db.collection<Product>('products', fromMap: Product.fromMap);

// Insert returns void, but entity gets ID assigned
final widget = Product(name: 'Widget', price: 29.99);
await products.insert(widget);

// Create index for fast lookups
await products.createIndex('name', 'hash');

// Query returns List<Product>, not List<Entity> or Map
final query = QueryBuilder().whereEquals('name', 'Widget').build();
final results = await products.find(query);  // List<Product>
print(results.first.price);  // 29.99 - fully typed!
```

> **Key Benefit**: The generic `Collection<T>` class eliminates code duplication. `UserCollection` simply extends `Collection<User>` and adds authentication-specific methods.

---

### 7.8. Security Layer

#### **authentication**
Handles user authentication and session management.

| File | Purpose |
|------|---------|
| `user.dart` | The `User` class implementing `Entity`, representing a database user with ID, username, password hash, and roles. Provides `toMap()` and `fromMap()` for storage serialization. |
| `authentication_service.dart` | Provides `register()`, `login()`, and `logout()` methods. Validates roles during registration, generates JWT tokens on successful login, and maintains a set of invalidated tokens. |
| `security_service.dart` | Handles password hashing and verification, JWT token generation and validation. |

```dart
// Authentication flow
await authService.register('alice', 'password123', ['user']);
final token = await authService.login('alice', 'password123');
await authService.logout(token);
```

#### **authorization**
Manages role-based access control (RBAC).

| File | Purpose |
|------|---------|
| `permissions.dart` | Enum defining available permissions: `create`, `read`, `update`, `delete`, `startTransaction`, `commitTransaction`, `rollbackTransaction`, etc. |
| `roles.dart` | The `Role` class associating a role name with a list of permissions. |
| `role_manager.dart` | Manages role definitions and permission checks. Initializes default roles (`admin`, `user`, `transaction_manager`) and provides methods for defining custom roles and checking permissions. |

```dart
// Role-based access control
roleManager.defineRole('editor', [Permission.read, Permission.update]);
if (roleManager.hasPermission(user.roles, Permission.delete)) {
  await collection.delete(docId);
}
```

---

### 7.9. Operations Layer

#### **backup**
Handles database backup and restoration.

| File | Purpose |
|------|---------|
| `backup_manager.dart` | Manages backup/restore operations for both data and user storage. Creates timestamped backup files, lists available backups, and restores from snapshots. |
| `snapshot.dart` | Represents a point-in-time snapshot of storage state for backup/restore operations. |
| `storage_statistics.dart` | Provides storage metrics and statistics. |

#### **migration**
Manages database schema and data migrations.

| File | Purpose |
|------|---------|
| `migration_manager.dart` | Coordinates data and user migrations, provides combined migration histories, and handles version data import/export. |
| `migration_config.dart` | Configuration for migration behavior. |
| `data_migration.dart` | Handles data storage migrations. |
| `user_migration.dart` | Handles user storage migrations. |
| `migration_step.dart` | Defines individual migration steps. |
| `migration_strategy.dart` | Defines migration strategies. |
| `migration_log.dart` | Records migration history. |
| `versioned_data.dart` | Tracks version information for migrations. |

---

### 7.10. User-Facing Layer

#### **main**
The primary entry point and public API for EntiDB.

| File | Purpose |
|------|---------|
| `entidb.dart` | The `EntiDB` class providing the main public API. Offers factory methods for initialization: `inMemory()` for testing, `connect()` for production with encryption, and `open()` for rapid setup with secure defaults. Provides generic `collection<T>()` method for type-safe entity storage. |

```dart
// Quick start with secure defaults
final db = await EntiDB.open(path: './mydb');

// Get a typed collection - all data requires Entity implementation
final animals = await db.collection<Animal>('animals', fromMap: Animal.fromMap);

// Insert domain objects directly
await animals.insert(Animal(name: 'Buddy', species: 'Dog', age: 3));
await animals.insert(Animal(name: 'Whiskers', species: 'Cat', age: 5));

// Query returns typed results
final dogs = await animals.find(
  QueryBuilder().whereEquals('species', 'Dog').build()
);
print('Found ${dogs.length} dogs');  // dogs is List<Animal>

await db.close();
```

---

### 7.11. Module Dependency Graph

The following diagram illustrates the dependency relationships between modules, from the foundation layer at the bottom to the user-facing API at the top:

```
┌─────────────────────────────────────────────────────────────┐
│                     main (EntiDB)                            │
├─────────────────────────────────────────────────────────────┤
│  collection<T>   authentication   authorization    backup   │
├─────────────────────────────────────────────────────────────┤
│      query          transaction          migration          │
├─────────────────────────────────────────────────────────────┤
│            index              schema           encryption   │
├─────────────────────────────────────────────────────────────┤
│       entity              storage<T>           type_reg     │
├─────────────────────────────────────────────────────────────┤
│                  engine (Pager, Page)                       │
├─────────────────────────────────────────────────────────────┤
│           logger           utils           exceptions       │
└─────────────────────────────────────────────────────────────┘
```

> **Note**: `entity` is the core interface. All collections and storage are generic over `T extends Entity`. There is no schema-less `Document` class.

## 8. Developer Workflow & Call Stack

This section illustrates the complete workflow from a developer's perspective, showing the call stack from database initialization to inserting a sample object.

### 8.1. Complete Code Example

```dart
import 'package:entidb/entidb.dart';

// Step 1: Define your domain entity
class Task implements Entity {
  @override
  final String? id;
  final String title;
  final bool completed;
  
  Task({this.id, required this.title, this.completed = false});
  
  @override
  Map<String, dynamic> toMap() => {
    'title': title,
    'completed': completed,
  };
  
  factory Task.fromMap(String id, Map<String, dynamic> map) => Task(
    id: id,
    title: map['title'],
    completed: map['completed'] ?? false,
  );
}

void main() async {
  // Step 2: Initialize the database
  final db = await EntiDB.open(path: './myapp');
  
  // Step 3: Get a typed collection
  final tasks = await db.collection<Task>('tasks', fromMap: Task.fromMap);
  
  // Step 4: Insert an entity
  await tasks.insert(Task(title: 'Learn EntiDB', completed: false));
  
  // Step 5: Close the database
  await db.close();
}
```

### 8.2. Initialization Call Stack

```
Developer Code                    EntiDB Internals
─────────────────────────────────────────────────────────────────────────────

EntiDB.open(path: './myapp')
    │
    ├──► StorageConfig.create()
    │        └── Sets up paths for data/ and users/ subdirectories
    │        └── Configures file-based storage type
    │
    ├──► EncryptionService (optional)
    │        └── Generates or loads encryption key
    │        └── Initializes AES-GCM cipher
    │
    ├──► Storage.init()
    │        │
    │        ├──► FileStorage.init()
    │        │        └── Creates data directory if not exists
    │        │        └── Loads existing entities into memory index
    │        │
    │        └──► Pager.open() (future: page-based storage)
    │                 └── Opens/creates database file
    │                 └── Reads header page (page 0)
    │                 └── Initializes page offset map
    │
    ├──► UserStorage.init()
    │        └── Same as above for user authentication data
    │
    ├──► AuthenticationService.init()
    │        └── Loads SecurityService (JWT, password hashing)
    │        └── Connects to UserCollection
    │
    ├──► RoleManager.init()
    │        └── Defines default roles (admin, user, transaction_manager)
    │
    └──► Returns EntiDB instance (ready to use)
```

### 8.3. Collection Access Call Stack

```
Developer Code                    EntiDB Internals
─────────────────────────────────────────────────────────────────────────────

db.collection<Task>('tasks', fromMap: Task.fromMap)
    │
    ├──► Check if collection 'tasks' already exists in cache
    │        └── If yes: return cached Collection<Task>
    │
    ├──► Create new Collection<Task>
    │        │
    │        ├──► Storage<Task>.forCollection('tasks')
    │        │        └── Creates/opens storage for this collection
    │        │        └── Sets up collection-specific file/directory
    │        │
    │        ├──► IndexManager.init()
    │        │        └── Loads existing indexes from disk (B+ Tree, Hash)
    │        │        └── Rebuilds in-memory index structures
    │        │
    │        ├──► Store fromMap factory function
    │        │        └── Used for deserializing Task objects
    │        │
    │        └──► Initialize Lock for concurrency control
    │
    ├──► Cache the collection for future access
    │
    └──► Returns Collection<Task> (typed, ready to use)
```

### 8.4. Insert Operation Call Stack

```
Developer Code                    EntiDB Internals
─────────────────────────────────────────────────────────────────────────────

tasks.insert(Task(title: 'Learn EntiDB', completed: false))
    │
    ├──► Acquire collection lock (concurrency control)
    │
    ├──► Generate ID (if entity.id is null)
    │        └── UUID v4 generation: "a1b2c3d4-e5f6-..."
    │
    ├──► Entity.toMap()
    │        └── Task.toMap() → {'title': 'Learn EntiDB', 'completed': false}
    │
    ├──► Schema validation (if schema defined)
    │        └── Validate required fields
    │        └── Validate field types
    │
    ├──► Storage.insert(id, data)
    │        │
    │        ├──► EncryptionService.encrypt(data) (if enabled)
    │        │        └── Serialize to JSON/binary
    │        │        └── Generate random IV
    │        │        └── AES-GCM encrypt
    │        │
    │        ├──► FileStorage.write()
    │        │        │
    │        │        └──► (Current) Write to individual file
    │        │                  └── File: data/tasks/a1b2c3d4-e5f6-...json
    │        │
    │        │        └──► (Future: Page-based)
    │        │                  ├── Pager.allocatePage()
    │        │                  ├── Page.writeBytes(serializedData)
    │        │                  ├── BufferManager.markDirty(page)
    │        │                  └── WAL.appendInsert(id, data)
    │        │
    │        └──► Update storage metadata
    │
    ├──► IndexManager.insert(id, data)
    │        │
    │        ├──► For each index on collection:
    │        │        ├── Extract indexed field value
    │        │        ├── BTreeIndex.insert(value, id)
    │        │        │       └── Navigate to leaf node
    │        │        │       └── Insert key-value pair
    │        │        │       └── Split node if overflow
    │        │        └── HashIndex.insert(value, id)
    │        │                └── Compute hash bucket
    │        │                └── Add to bucket chain
    │        │
    │        └──► Primary key index updated automatically
    │
    ├──► Release collection lock
    │
    └──► Return (void) - insert complete
```

### 8.5. Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DEVELOPER CODE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  final db = await EntiDB.open(path: './myapp');                          │
│  final tasks = await db.collection<Task>('tasks', fromMap: ...);        │
│  await tasks.insert(Task(title: 'Learn EntiDB'));                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         PUBLIC API (EntiDB)                              │
├─────────────────────────────────────────────────────────────────────────┤
│  • open() / connect() / inMemory()                                      │
│  • collection<T>() - returns typed Collection<T>                        │
│  • beginTransaction() / close()                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      COLLECTION<T> LAYER                                │
├─────────────────────────────────────────────────────────────────────────┤
│  • insert(T entity) → void                                              │
│  • get(String id) → T?                                                  │
│  • find(IQuery) → List<T>                                               │
│  • update(String id, T entity) → void                                   │
│  • delete(String id) → void                                             │
│  • Manages: Lock, IndexManager, Schema validation                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
┌───────────────────────┐ ┌─────────────────┐ ┌─────────────────────────┐
│    INDEX MANAGER      │ │  QUERY ENGINE   │ │  TRANSACTION MANAGER    │
├───────────────────────┤ ├─────────────────┤ ├─────────────────────────┤
│ • B+ Tree indexes     │ │ • QueryBuilder  │ │ • begin/commit/rollback │
│ • Hash indexes        │ │ • Query parsing │ │ • WAL logging           │
│ • insert/remove/search│ │ • Optimization  │ │ • Snapshot isolation    │
└───────────────────────┘ └─────────────────┘ └─────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         STORAGE<T> LAYER                                │
├─────────────────────────────────────────────────────────────────────────┤
│  • FileStorage<T> - file-based persistence                              │
│  • MemoryStorage<T> - in-memory (testing)                               │
│  • insert/get/update/delete/streamAll                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       ENCRYPTION LAYER                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  • EncryptionService - AES-256-GCM                                      │
│  • NoEncryptionService - passthrough                                    │
│  • Transparent encrypt/decrypt                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     ENGINE (Pager / Page)                               │
├─────────────────────────────────────────────────────────────────────────┤
│  • Page - fixed-size data blocks                                        │
│  • Pager - disk I/O abstraction                                         │
│  • BufferManager - page caching (LRU)                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          FILE SYSTEM                                    │
├─────────────────────────────────────────────────────────────────────────┤
│  ./myapp/                                                               │
│  ├── data/                                                              │
│  │   └── tasks/                                                         │
│  │       └── a1b2c3d4-e5f6-....json  ← encrypted task data              │
│  └── users/                                                             │
│      └── (authentication data)                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 8.6. Summary: Developer Touchpoints

| Step | Developer Action | EntiDB Response |
|------|------------------|----------------|
| **1** | Implement `Entity` interface on domain class | Enables type-safe storage |
| **2** | Call `EntiDB.open()` or `connect()` | Initializes storage, encryption, auth |
| **3** | Call `db.collection<T>('name', fromMap: ...)` | Returns typed `Collection<T>` |
| **4** | Call `collection.insert(entity)` | Serializes, encrypts, indexes, persists |
| **5** | Call `collection.find(query)` | Deserializes, returns `List<T>` |
| **6** | Call `db.close()` | Flushes buffers, closes files |

> **Key Insight**: The developer only interacts with the top two layers (Public API and Collection). All complexity—encryption, indexing, storage, concurrency—is handled transparently by EntiDB.