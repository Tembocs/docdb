/// DocDB Backup - Storage Statistics
///
/// Provides comprehensive statistics about storage state including
/// entity counts, memory usage, and performance metrics.
library;

import '../entity/entity.dart';

/// Represents comprehensive storage statistics.
///
/// Provides detailed information about a storage instance including:
/// - Entity counts and size metrics
/// - Memory and disk usage
/// - Performance statistics
/// - Index information
///
/// ## Usage
///
/// ```dart
/// final stats = await storage.getStatistics();
///
/// print('Entities: ${stats.entityCount}');
/// print('Memory: ${stats.humanReadableMemoryUsage}');
/// print('Disk: ${stats.humanReadableDiskUsage}');
///
/// if (stats.fragmentationRatio > 0.3) {
///   await storage.compact();
/// }
/// ```
///
/// ## Monitoring
///
/// ```dart
/// // Collect statistics periodically
/// Timer.periodic(Duration(minutes: 5), (_) async {
///   final stats = await storage.getStatistics();
///   logger.info('Storage stats: ${stats.toMap()}');
///
///   if (stats.memoryUsageBytes > maxMemory) {
///     await storage.evictCache();
///   }
/// });
/// ```
final class StorageStatistics implements Entity {
  /// Unique identifier for this statistics snapshot.
  @override
  final String? id;

  /// Name of the storage instance.
  final String storageName;

  /// Timestamp when statistics were collected.
  final DateTime collectedAt;

  /// Number of entities currently stored.
  final int entityCount;

  /// Current memory usage in bytes.
  final int memoryUsageBytes;

  /// Current disk usage in bytes (if applicable).
  final int diskUsageBytes;

  /// Number of indexes on this storage.
  final int indexCount;

  /// Total number of read operations since startup.
  final int readOperations;

  /// Total number of write operations since startup.
  final int writeOperations;

  /// Average read latency in microseconds.
  final int avgReadLatencyMicros;

  /// Average write latency in microseconds.
  final int avgWriteLatencyMicros;

  /// Cache hit ratio (0.0 to 1.0).
  final double cacheHitRatio;

  /// Fragmentation ratio (0.0 to 1.0).
  ///
  /// Higher values indicate more wasted space that could be
  /// reclaimed through compaction.
  final double fragmentationRatio;

  /// Whether the storage is currently open.
  final bool isOpen;

  /// Whether the storage supports transactions.
  final bool supportsTransactions;

  /// Additional storage-specific metrics.
  final Map<String, dynamic> customMetrics;

  /// Creates a new storage statistics instance.
  const StorageStatistics({
    this.id,
    required this.storageName,
    required this.collectedAt,
    required this.entityCount,
    this.memoryUsageBytes = 0,
    this.diskUsageBytes = 0,
    this.indexCount = 0,
    this.readOperations = 0,
    this.writeOperations = 0,
    this.avgReadLatencyMicros = 0,
    this.avgWriteLatencyMicros = 0,
    this.cacheHitRatio = 0.0,
    this.fragmentationRatio = 0.0,
    this.isOpen = true,
    this.supportsTransactions = false,
    this.customMetrics = const {},
  });

  /// Creates statistics for an empty or newly initialized storage.
  factory StorageStatistics.empty({
    String? id,
    required String storageName,
    bool isOpen = true,
    bool supportsTransactions = false,
  }) {
    return StorageStatistics(
      id: id,
      storageName: storageName,
      collectedAt: DateTime.now(),
      entityCount: 0,
      isOpen: isOpen,
      supportsTransactions: supportsTransactions,
    );
  }

  /// Creates statistics with basic counts only.
  factory StorageStatistics.basic({
    String? id,
    required String storageName,
    required int entityCount,
    int memoryUsageBytes = 0,
    bool isOpen = true,
  }) {
    return StorageStatistics(
      id: id,
      storageName: storageName,
      collectedAt: DateTime.now(),
      entityCount: entityCount,
      memoryUsageBytes: memoryUsageBytes,
      isOpen: isOpen,
    );
  }

  /// Returns human-readable memory usage.
  String get humanReadableMemoryUsage => _formatBytes(memoryUsageBytes);

  /// Returns human-readable disk usage.
  String get humanReadableDiskUsage => _formatBytes(diskUsageBytes);

  /// Total operations (read + write).
  int get totalOperations => readOperations + writeOperations;

  /// Read/write ratio.
  double get readWriteRatio {
    if (writeOperations == 0) return readOperations > 0 ? double.infinity : 0;
    return readOperations / writeOperations;
  }

  /// Formats bytes to human-readable string.
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Creates a copy with updated fields.
  StorageStatistics copyWith({
    String? id,
    String? storageName,
    DateTime? collectedAt,
    int? entityCount,
    int? memoryUsageBytes,
    int? diskUsageBytes,
    int? indexCount,
    int? readOperations,
    int? writeOperations,
    int? avgReadLatencyMicros,
    int? avgWriteLatencyMicros,
    double? cacheHitRatio,
    double? fragmentationRatio,
    bool? isOpen,
    bool? supportsTransactions,
    Map<String, dynamic>? customMetrics,
  }) {
    return StorageStatistics(
      id: id ?? this.id,
      storageName: storageName ?? this.storageName,
      collectedAt: collectedAt ?? this.collectedAt,
      entityCount: entityCount ?? this.entityCount,
      memoryUsageBytes: memoryUsageBytes ?? this.memoryUsageBytes,
      diskUsageBytes: diskUsageBytes ?? this.diskUsageBytes,
      indexCount: indexCount ?? this.indexCount,
      readOperations: readOperations ?? this.readOperations,
      writeOperations: writeOperations ?? this.writeOperations,
      avgReadLatencyMicros: avgReadLatencyMicros ?? this.avgReadLatencyMicros,
      avgWriteLatencyMicros:
          avgWriteLatencyMicros ?? this.avgWriteLatencyMicros,
      cacheHitRatio: cacheHitRatio ?? this.cacheHitRatio,
      fragmentationRatio: fragmentationRatio ?? this.fragmentationRatio,
      isOpen: isOpen ?? this.isOpen,
      supportsTransactions: supportsTransactions ?? this.supportsTransactions,
      customMetrics: customMetrics ?? this.customMetrics,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'storageName': storageName,
    'collectedAt': collectedAt.toIso8601String(),
    'entityCount': entityCount,
    'memoryUsageBytes': memoryUsageBytes,
    'diskUsageBytes': diskUsageBytes,
    'indexCount': indexCount,
    'readOperations': readOperations,
    'writeOperations': writeOperations,
    'avgReadLatencyMicros': avgReadLatencyMicros,
    'avgWriteLatencyMicros': avgWriteLatencyMicros,
    'cacheHitRatio': cacheHitRatio,
    'fragmentationRatio': fragmentationRatio,
    'isOpen': isOpen,
    'supportsTransactions': supportsTransactions,
    if (customMetrics.isNotEmpty) 'customMetrics': customMetrics,
  };

  /// Creates statistics from a stored map.
  factory StorageStatistics.fromMap(String id, Map<String, dynamic> map) {
    return StorageStatistics(
      id: id,
      storageName: map['storageName'] as String,
      collectedAt: DateTime.parse(map['collectedAt'] as String),
      entityCount: map['entityCount'] as int,
      memoryUsageBytes: map['memoryUsageBytes'] as int? ?? 0,
      diskUsageBytes: map['diskUsageBytes'] as int? ?? 0,
      indexCount: map['indexCount'] as int? ?? 0,
      readOperations: map['readOperations'] as int? ?? 0,
      writeOperations: map['writeOperations'] as int? ?? 0,
      avgReadLatencyMicros: map['avgReadLatencyMicros'] as int? ?? 0,
      avgWriteLatencyMicros: map['avgWriteLatencyMicros'] as int? ?? 0,
      cacheHitRatio: (map['cacheHitRatio'] as num?)?.toDouble() ?? 0.0,
      fragmentationRatio:
          (map['fragmentationRatio'] as num?)?.toDouble() ?? 0.0,
      isOpen: map['isOpen'] as bool? ?? true,
      supportsTransactions: map['supportsTransactions'] as bool? ?? false,
      customMetrics:
          (map['customMetrics'] as Map<String, dynamic>?) ?? const {},
    );
  }

  @override
  String toString() =>
      'StorageStatistics(storage: $storageName, entities: $entityCount, '
      'memory: $humanReadableMemoryUsage, disk: $humanReadableDiskUsage)';
}

/// Legacy alias for backward compatibility.
///
/// @deprecated Use [StorageStatistics] instead.
@Deprecated('Use StorageStatistics instead')
typedef StorageStats = StorageStatistics;
