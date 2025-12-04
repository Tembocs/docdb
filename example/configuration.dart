/// Configuration Example
///
/// Demonstrates various DocDB configuration options.
///
/// Run with: `dart run example/configuration.dart`
import 'dart:io';

import 'package:docdb/docdb.dart';

import 'models/models.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('                Database Configuration');
  print('═══════════════════════════════════════════════════════════════\n');

  // =========================================================================
  // Factory Configurations
  // =========================================================================
  print('🏭 Factory Configuration Presets\n');

  // Development configuration - verbose logging, auto-flush
  final devConfig = DocDBConfig.development();
  print('   DocDBConfig.development():');
  print('     • enableDebugLogging: ${devConfig.enableDebugLogging}');
  print('     • autoFlushOnClose: ${devConfig.autoFlushOnClose}');
  print('     • bufferPoolSize: ${devConfig.bufferPoolSize}');
  print('     • Storage: ${devConfig.storageBackend}');
  print('');

  // Production configuration - optimized for performance
  final prodConfig = DocDBConfig.production();
  print('   DocDBConfig.production():');
  print('     • enableDebugLogging: ${prodConfig.enableDebugLogging}');
  print('     • autoFlushOnClose: ${prodConfig.autoFlushOnClose}');
  print('     • bufferPoolSize: ${prodConfig.bufferPoolSize}');
  print('     • Storage: ${prodConfig.storageBackend}');
  print('');

  // In-memory configuration - for testing
  final memConfig = DocDBConfig.inMemory();
  print('   DocDBConfig.inMemory():');
  print('     • Storage: ${memConfig.storageBackend}');
  print('     • enableTransactions: ${memConfig.enableTransactions}');
  print('     • Note: Data not persisted');
  print('');

  // =========================================================================
  // Custom Configuration with copyWith
  // =========================================================================
  print('🔧 Custom Configuration with copyWith\n');

  final customConfig = DocDBConfig.development().copyWith(
    enableDebugLogging: false,
    bufferPoolSize: 512,
  );

  print('   Custom config (development base):');
  print('     • enableDebugLogging: ${customConfig.enableDebugLogging}');
  print('     • bufferPoolSize: ${customConfig.bufferPoolSize}');
  print('');

  // =========================================================================
  // Using Different Configurations
  // =========================================================================
  print('🚀 Demonstrating Configurations\n');

  // In-memory database
  print('   Opening in-memory database...');
  final memDb = await DocDB.open(path: null, config: DocDBConfig.inMemory());

  final memProducts = await memDb.collection<Product>(
    'products',
    fromMap: Product.fromMap,
  );

  await memProducts.insert(
    Product(
      name: 'Memory Product',
      description: 'Stored in memory only',
      price: 10.00,
    ),
  );

  print('   In-memory products: ${await memProducts.count}');
  await memDb.close();
  print('   Closed (data discarded)\n');

  // File-based database
  final tempDir = await Directory.systemTemp.createTemp('docdb_config_');
  try {
    print('   Opening file-based database...');
    final fileDb = await DocDB.open(
      path: tempDir.path,
      config: DocDBConfig.development(),
    );

    final fileProducts = await fileDb.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    await fileProducts.insert(
      Product(
        name: 'Persistent Product',
        description: 'Stored on disk',
        price: 20.00,
      ),
    );

    print('   File-based products: ${await fileProducts.count}');
    await fileDb.close();
    print('   Closed (data persisted)\n');
  } finally {
    await tempDir.delete(recursive: true);
  }

  // =========================================================================
  // Configuration Options Reference
  // =========================================================================
  print('═══════════════════════════════════════════════════════════════');
  print('             Configuration Options Reference');
  print('═══════════════════════════════════════════════════════════════');
  print('');
  print('   StorageBackend:');
  print('     • paged  - File-based storage with paging');
  print('     • memory - In-memory storage (no persistence)');
  print('');
  print('   Key Settings:');
  print('     • bufferPoolSize     - Buffer pool size (pages)');
  print('     • pageSize           - Page size in bytes (≥4096)');
  print('     • enableTransactions - Enable transaction support');
  print('     • verifyChecksums    - Verify page checksums');
  print('     • maxEntitySize      - Maximum entity size');
  print('     • enableDebugLogging - Enable debug output');
  print('     • autoFlushOnClose   - Flush on database close');
  print('');
  print('   Encryption:');
  print('     • encryptionService  - Optional encryption service');
  print('═══════════════════════════════════════════════════════════════\n');
}
