/// Index Persistence Module.
///
/// Provides serialization and deserialization capabilities for indexes,
/// enabling disk-based persistence to avoid rebuilding indexes on startup.
library;

import 'dart:io';

import 'package:cbor/cbor.dart';

import 'btree.dart';
import 'fulltext.dart';
import 'hash.dart';
import 'i_index.dart';

/// Serializable index data structure.
///
/// Contains all information needed to reconstruct an index from disk.
class SerializedIndex {
  /// The field name this index is built on.
  final String field;

  /// The type of index (btree or hash).
  final IndexType type;

  /// The index entries as a map of key -> entity IDs.
  final Map<dynamic, Set<String>> entries;

  /// Version for forward compatibility.
  final int version;

  /// Creates a serialized index.
  const SerializedIndex({
    required this.field,
    required this.type,
    required this.entries,
    this.version = 1,
  });

  /// Converts to CBOR bytes for storage.
  List<int> toBytes() {
    // Convert entries to serializable format
    final entriesMap = <CborValue, CborValue>{};
    for (final entry in entries.entries) {
      final key = _valueToCbor(entry.key);
      final ids = CborList(entry.value.map((id) => CborString(id)).toList());
      entriesMap[key] = ids;
    }

    final cborValue = CborMap({
      CborString('version'): CborSmallInt(version),
      CborString('field'): CborString(field),
      CborString('type'): CborString(type.name),
      CborString('entries'): CborMap(entriesMap),
    });

    return cbor.encode(cborValue);
  }

  /// Creates from CBOR bytes.
  factory SerializedIndex.fromBytes(List<int> bytes) {
    final cborValue = cbor.decode(bytes) as CborMap;

    final version = (cborValue[CborString('version')] as CborSmallInt).value;
    final field = (cborValue[CborString('field')] as CborString).toString();
    final typeStr = (cborValue[CborString('type')] as CborString).toString();
    final type = IndexType.values.firstWhere((t) => t.name == typeStr);

    final entriesMap = cborValue[CborString('entries')] as CborMap;
    final entries = <dynamic, Set<String>>{};

    for (final entry in entriesMap.entries) {
      final key = _cborToValue(entry.key);
      final ids = (entry.value as CborList)
          .map((v) => (v as CborString).toString())
          .toSet();
      entries[key] = ids;
    }

    return SerializedIndex(
      field: field,
      type: type,
      entries: entries,
      version: version,
    );
  }

  /// Converts a Dart value to CBOR.
  static CborValue _valueToCbor(dynamic value) {
    return switch (value) {
      null => const CborNull(),
      int v => CborSmallInt(v),
      double v => CborFloat(v),
      String v => CborString(v),
      bool v => CborBool(v),
      // Store DateTime as a tagged integer (milliseconds since epoch)
      DateTime v => CborMap({
        CborString('__type'): CborString('DateTime'),
        CborString('millis'): CborSmallInt(v.millisecondsSinceEpoch),
      }),
      _ => CborString(value.toString()),
    };
  }

  /// Converts CBOR to a Dart value.
  static dynamic _cborToValue(CborValue value) {
    return switch (value) {
      CborNull() => null,
      CborSmallInt v => v.value,
      CborInt v => v.toInt(),
      CborFloat v => v.value,
      CborString v => v.toString(),
      CborBool v => v.value,
      CborMap m when m[CborString('__type')]?.toString() == 'DateTime' =>
        DateTime.fromMillisecondsSinceEpoch(
          (m[CborString('millis')] as CborSmallInt).value,
        ),
      _ => value.toString(),
    };
  }
}

/// Extension to add serialization to BTreeIndex.
extension BTreeIndexSerialization on BTreeIndex {
  /// Serializes this index to a [SerializedIndex].
  SerializedIndex serialize() {
    return SerializedIndex(
      field: field,
      type: IndexType.btree,
      entries: toMap(),
    );
  }

  /// Restores index state from serialized data.
  void restore(SerializedIndex data) {
    if (data.field != field) {
      throw ArgumentError(
        'Field mismatch: expected "$field", got "${data.field}"',
      );
    }
    if (data.type != IndexType.btree) {
      throw ArgumentError(
        'Type mismatch: expected btree, got ${data.type.name}',
      );
    }

    clear();
    restoreFromMap(data.entries);
  }
}

/// Extension to add serialization to HashIndex.
extension HashIndexSerialization on HashIndex {
  /// Serializes this index to a [SerializedIndex].
  SerializedIndex serialize() {
    return SerializedIndex(
      field: field,
      type: IndexType.hash,
      entries: toMap(),
    );
  }

  /// Restores index state from serialized data.
  void restore(SerializedIndex data) {
    if (data.field != field) {
      throw ArgumentError(
        'Field mismatch: expected "$field", got "${data.field}"',
      );
    }
    if (data.type != IndexType.hash) {
      throw ArgumentError(
        'Type mismatch: expected hash, got ${data.type.name}',
      );
    }

    clear();
    restoreFromMap(data.entries);
  }
}

/// Serializable full-text index data structure.
///
/// Contains all information needed to reconstruct a full-text index from disk.
class SerializedFullTextIndex {
  /// The field name this index is built on.
  final String field;

  /// The index data containing inverted and forward indexes.
  final Map<String, dynamic> data;

  /// Version for forward compatibility.
  final int version;

  /// Creates a serialized full-text index.
  const SerializedFullTextIndex({
    required this.field,
    required this.data,
    this.version = 1,
  });

  /// Converts to CBOR bytes for storage.
  List<int> toBytes() {
    final cborValue = CborMap({
      CborString('version'): CborSmallInt(version),
      CborString('field'): CborString(field),
      CborString('type'): CborString('fulltext'),
      CborString('data'): _mapToCbor(data),
    });

    return cbor.encode(cborValue);
  }

  /// Creates from CBOR bytes.
  factory SerializedFullTextIndex.fromBytes(List<int> bytes) {
    final cborValue = cbor.decode(bytes) as CborMap;

    final version = (cborValue[CborString('version')] as CborSmallInt).value;
    final field = (cborValue[CborString('field')] as CborString).toString();
    final dataCbor = cborValue[CborString('data')];
    final data = _cborToMap(dataCbor);

    return SerializedFullTextIndex(field: field, data: data, version: version);
  }

  /// Recursively converts a Map to CBOR.
  static CborValue _mapToCbor(Map<String, dynamic> map) {
    final entries = <CborValue, CborValue>{};
    for (final entry in map.entries) {
      entries[CborString(entry.key)] = _valueToCbor(entry.value);
    }
    return CborMap(entries);
  }

  /// Converts a Dart value to CBOR.
  static CborValue _valueToCbor(dynamic value) {
    return switch (value) {
      null => const CborNull(),
      int v => CborSmallInt(v),
      double v => CborFloat(v),
      String v => CborString(v),
      bool v => CborBool(v),
      List l => CborList(l.map(_valueToCbor).toList()),
      Map<String, dynamic> m => _mapToCbor(m),
      _ => CborString(value.toString()),
    };
  }

  /// Recursively converts CBOR to a Map.
  static Map<String, dynamic> _cborToMap(CborValue? value) {
    if (value is! CborMap) return {};

    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = (entry.key as CborString).toString();
      result[key] = _cborToValue(entry.value);
    }
    return result;
  }

  /// Converts CBOR to a Dart value.
  static dynamic _cborToValue(CborValue value) {
    return switch (value) {
      CborNull() => null,
      CborSmallInt v => v.value,
      CborInt v => v.toInt(),
      CborFloat v => v.value,
      CborString v => v.toString(),
      CborBool v => v.value,
      CborList l => l.map(_cborToValue).toList(),
      CborMap m => _cborToMap(m),
      _ => value.toString(),
    };
  }
}

/// Extension to add serialization to FullTextIndex.
extension FullTextIndexSerialization on FullTextIndex {
  /// Serializes this index to a [SerializedFullTextIndex].
  SerializedFullTextIndex serialize() {
    return SerializedFullTextIndex(field: field, data: toMap());
  }

  /// Restores index state from serialized data.
  void restore(SerializedFullTextIndex data) {
    if (data.field != field) {
      throw ArgumentError(
        'Field mismatch: expected "$field", got "${data.field}"',
      );
    }

    clear();
    restoreFromMap(data.data);
  }
}

/// Manages persistent storage of indexes to disk.
///
/// ## Usage
///
/// ```dart
/// final persistence = IndexPersistence(directory: './data/indexes');
///
/// // Save an index
/// await persistence.saveIndex('users', 'email', emailIndex);
///
/// // Load an index
/// final data = await persistence.loadIndex('users', 'email');
/// if (data != null) {
///   emailIndex.restore(data);
/// }
/// ```
class IndexPersistence {
  /// The directory where index files are stored.
  final String directory;

  /// Whether to use compression (future feature).
  final bool compress;

  /// Creates an index persistence manager.
  const IndexPersistence({required this.directory, this.compress = false});

  /// Generates the file path for an index.
  String _indexPath(String collectionName, String fieldName) {
    return '$directory/${collectionName}_$fieldName.idx';
  }

  /// Saves an index to disk.
  ///
  /// - [collectionName]: The collection this index belongs to.
  /// - [fieldName]: The field name the index is on.
  /// - [index]: The index to save.
  Future<void> saveIndex(
    String collectionName,
    String fieldName,
    IIndex index,
  ) async {
    final List<int> bytes;

    switch (index) {
      case BTreeIndex btree:
        bytes = btree.serialize().toBytes();
      case HashIndex hash:
        bytes = hash.serialize().toBytes();
      case FullTextIndex fulltext:
        bytes = fulltext.serialize().toBytes();
      default:
        throw UnsupportedError('Unknown index type: ${index.runtimeType}');
    }

    final file = File(_indexPath(collectionName, fieldName));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  /// Loads an index from disk.
  ///
  /// Returns null if the index file doesn't exist.
  /// Returns a [SerializedIndex] for btree/hash indexes,
  /// or a [SerializedFullTextIndex] for fulltext indexes.
  Future<dynamic> loadIndex(String collectionName, String fieldName) async {
    final file = File(_indexPath(collectionName, fieldName));
    if (!await file.exists()) {
      return null;
    }

    final bytes = await file.readAsBytes();

    // Peek at the type to determine which deserializer to use
    final cborValue = cbor.decode(bytes) as CborMap;
    final typeStr = (cborValue[CborString('type')] as CborString).toString();

    if (typeStr == 'fulltext') {
      return SerializedFullTextIndex.fromBytes(bytes);
    }
    return SerializedIndex.fromBytes(bytes);
  }

  /// Loads a btree or hash index from disk.
  ///
  /// Returns null if the index file doesn't exist or is a fulltext index.
  Future<SerializedIndex?> loadStandardIndex(
    String collectionName,
    String fieldName,
  ) async {
    final data = await loadIndex(collectionName, fieldName);
    if (data is SerializedIndex) {
      return data;
    }
    return null;
  }

  /// Loads a full-text index from disk.
  ///
  /// Returns null if the index file doesn't exist or is not a fulltext index.
  Future<SerializedFullTextIndex?> loadFullTextIndex(
    String collectionName,
    String fieldName,
  ) async {
    final data = await loadIndex(collectionName, fieldName);
    if (data is SerializedFullTextIndex) {
      return data;
    }
    return null;
  }

  /// Deletes an index file from disk.
  Future<void> deleteIndex(String collectionName, String fieldName) async {
    final file = File(_indexPath(collectionName, fieldName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Lists all persisted indexes for a collection.
  Future<List<String>> listIndexes(String collectionName) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      return [];
    }

    final prefix = '${collectionName}_';
    final suffix = '.idx';

    return await dir
        .list()
        .where(
          (entity) =>
              entity is File &&
              entity.path.contains(prefix) &&
              entity.path.endsWith(suffix),
        )
        .map((entity) {
          final name = entity.path.split('/').last;
          return name.substring(prefix.length, name.length - suffix.length);
        })
        .toList();
  }

  /// Clears all persisted indexes for a collection.
  Future<void> clearCollection(String collectionName) async {
    final fields = await listIndexes(collectionName);
    for (final field in fields) {
      await deleteIndex(collectionName, field);
    }
  }

  /// Checks if an index exists on disk.
  Future<bool> indexExists(String collectionName, String fieldName) async {
    final file = File(_indexPath(collectionName, fieldName));
    return await file.exists();
  }
}

/// Metadata about a persisted index.
class IndexMetadata {
  /// The collection name.
  final String collectionName;

  /// The field name.
  final String fieldName;

  /// The index type.
  final IndexType type;

  /// Number of entries in the index.
  final int entryCount;

  /// Size of the index file in bytes.
  final int fileSize;

  /// Last modification time.
  final DateTime lastModified;

  /// Creates index metadata.
  const IndexMetadata({
    required this.collectionName,
    required this.fieldName,
    required this.type,
    required this.entryCount,
    required this.fileSize,
    required this.lastModified,
  });

  @override
  String toString() {
    return 'IndexMetadata($collectionName.$fieldName: '
        '${type.name}, $entryCount entries, $fileSize bytes)';
  }
}
