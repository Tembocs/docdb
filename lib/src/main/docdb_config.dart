/// DocDB Configuration
///
/// Provides configuration options for DocDB database instances including
/// storage backend selection, buffer pool settings, encryption, and
/// operational parameters.
library;

import 'package:meta/meta.dart';

import '../encryption/encryption_service.dart';

/// Storage backend types for DocDB.
///
/// Determines how data is persisted:
/// - [paged]: Page-based file storage for production use
/// - [memory]: In-memory storage for testing
enum StorageBackend {
  /// Page-based storage using the engine (production).
  paged,

  /// In-memory storage (testing).
  memory,
}

/// Configuration for DocDB database instance.
///
/// Controls storage behavior, caching, encryption, and other database options.
///
/// ## Usage
///
/// ```dart
/// // Production configuration
/// final config = DocDBConfig.production();
///
/// // Development configuration with encryption
/// final devConfig = DocDBConfig.development(
///   encryptionService: myEncryptionService,
/// );
///
/// // Custom configuration
/// final customConfig = DocDBConfig(
///   bufferPoolSize: 4096,
///   pageSize: 8192,
///   enableDebugLogging: true,
/// );
/// ```
@immutable
class DocDBConfig {
  /// The storage backend to use.
  final StorageBackend storageBackend;

  /// Buffer pool size for paged storage (number of pages).
  final int bufferPoolSize;

  /// Page size in bytes (must be power of 2, >= 4096).
  final int pageSize;

  /// Whether to enable transaction support.
  final bool enableTransactions;

  /// Whether to verify page checksums on read.
  final bool verifyChecksums;

  /// Maximum entity size in bytes.
  final int maxEntitySize;

  /// Encryption service for data-at-rest encryption.
  final EncryptionService? encryptionService;

  /// Whether to enable debug logging.
  final bool enableDebugLogging;

  /// Whether to auto-flush on close.
  final bool autoFlushOnClose;

  /// Whether encryption is enabled.
  bool get encryptionEnabled =>
      encryptionService != null && encryptionService!.isEnabled;

  /// Creates a DocDB configuration.
  const DocDBConfig({
    this.storageBackend = StorageBackend.paged,
    this.bufferPoolSize = 1024,
    this.pageSize = 4096,
    this.enableTransactions = true,
    this.verifyChecksums = true,
    this.maxEntitySize = 1024 * 1024,
    this.encryptionService,
    this.enableDebugLogging = false,
    this.autoFlushOnClose = true,
  });

  /// Production configuration optimized for performance and durability.
  ///
  /// Features:
  /// - Larger buffer pool (2048 pages)
  /// - 4MB max entity size
  /// - Checksum verification enabled
  /// - Debug logging disabled
  factory DocDBConfig.production({EncryptionService? encryptionService}) {
    return DocDBConfig(
      storageBackend: StorageBackend.paged,
      bufferPoolSize: 2048,
      pageSize: 4096,
      enableTransactions: true,
      verifyChecksums: true,
      maxEntitySize: 4 * 1024 * 1024,
      encryptionService: encryptionService,
      enableDebugLogging: false,
      autoFlushOnClose: true,
    );
  }

  /// Development configuration with verbose logging.
  ///
  /// Features:
  /// - Smaller buffer pool (256 pages)
  /// - Debug logging enabled
  /// - Standard entity size limits
  factory DocDBConfig.development({EncryptionService? encryptionService}) {
    return DocDBConfig(
      storageBackend: StorageBackend.paged,
      bufferPoolSize: 256,
      pageSize: 4096,
      enableTransactions: true,
      verifyChecksums: true,
      maxEntitySize: 1024 * 1024,
      encryptionService: encryptionService,
      enableDebugLogging: true,
      autoFlushOnClose: true,
    );
  }

  /// In-memory configuration for testing.
  ///
  /// Features:
  /// - Memory-only storage (no persistence)
  /// - Transactions disabled
  /// - Debug logging enabled
  /// - No auto-flush (not needed for memory)
  factory DocDBConfig.inMemory() {
    return const DocDBConfig(
      storageBackend: StorageBackend.memory,
      enableTransactions: false,
      enableDebugLogging: true,
      autoFlushOnClose: false,
    );
  }

  /// Creates a copy with modified properties.
  DocDBConfig copyWith({
    StorageBackend? storageBackend,
    int? bufferPoolSize,
    int? pageSize,
    bool? enableTransactions,
    bool? verifyChecksums,
    int? maxEntitySize,
    EncryptionService? encryptionService,
    bool? enableDebugLogging,
    bool? autoFlushOnClose,
  }) {
    return DocDBConfig(
      storageBackend: storageBackend ?? this.storageBackend,
      bufferPoolSize: bufferPoolSize ?? this.bufferPoolSize,
      pageSize: pageSize ?? this.pageSize,
      enableTransactions: enableTransactions ?? this.enableTransactions,
      verifyChecksums: verifyChecksums ?? this.verifyChecksums,
      maxEntitySize: maxEntitySize ?? this.maxEntitySize,
      encryptionService: encryptionService ?? this.encryptionService,
      enableDebugLogging: enableDebugLogging ?? this.enableDebugLogging,
      autoFlushOnClose: autoFlushOnClose ?? this.autoFlushOnClose,
    );
  }
}
