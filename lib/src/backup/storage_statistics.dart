// PATH: lib/src/backup/storage_statistics.dart

/// A class representing storage statistics.
class StorageStats {
  /// The number of documents currently stored.
  final int documentCount;

  /// The current memory usage in bytes.
  final int memoryUsage;

  /// Additional metrics can be added here.

  StorageStats({
    required this.documentCount,
    required this.memoryUsage,
  });
}
