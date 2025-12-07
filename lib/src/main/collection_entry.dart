/// Collection Entry - Internal
///
/// Internal helper class for tracking registered collections within EntiDB.
/// This file is not exported as part of the public API.
library;

import '../collection/collection.dart';
import '../storage/storage.dart';

/// Internal entry tracking a registered collection.
///
/// Used by EntiDB to maintain metadata about each collection including
/// its type information, storage backend, and collection instance.
class CollectionEntry {
  /// The collection name.
  final String name;

  /// The entity type for this collection.
  final Type entityType;

  /// The collection instance.
  final Collection<dynamic> collection;

  /// The storage backend for this collection.
  final Storage<dynamic> storage;

  /// Creates a collection entry.
  CollectionEntry({
    required this.name,
    required this.entityType,
    required this.collection,
    required this.storage,
  });
}
