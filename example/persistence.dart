/// Persistence Example
///
/// Demonstrates data persistence across database sessions.
///
/// Run with: `dart run example/persistence.dart`
import 'dart:io';

import 'package:docdb/docdb.dart';

import 'models/models.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('                   Data Persistence');
  print('═══════════════════════════════════════════════════════════════\n');

  // Create a temporary directory for the database
  final tempDir = await Directory.systemTemp.createTemp('docdb_persist_');
  final dbPath = tempDir.path;

  try {
    String savedProductId;

    // =========================================================================
    // Session 1: Create and populate database
    // =========================================================================
    print('📝 SESSION 1: Creating database and inserting data\n');
    print('   Database path: $dbPath\n');

    {
      final db = await DocDB.open(
        path: dbPath,
        config: DocDBConfig.development(),
      );

      final products = await db.collection<Product>(
        'products',
        fromMap: Product.fromMap,
      );

      // Insert a product
      savedProductId = await products.insert(
        Product(
          name: 'Persisted Widget',
          description: 'This product will survive database restarts',
          price: 42.00,
          quantity: 100,
          tags: ['test', 'persistence'],
        ),
      );

      print('   Inserted product with ID: $savedProductId');
      print('   Product count: ${await products.count}');

      // Flush to ensure data is written
      await db.flush();
      print('   Flushed data to disk');

      // Close the database
      await db.close();
      print('   Database closed\n');
    }

    // =========================================================================
    // Session 2: Reopen and verify data
    // =========================================================================
    print('🔄 SESSION 2: Reopening database and verifying data\n');

    {
      final db = await DocDB.open(
        path: dbPath,
        config: DocDBConfig.development(),
      );

      final products = await db.collection<Product>(
        'products',
        fromMap: Product.fromMap,
      );

      print('   Product count after reopen: ${await products.count}');

      // Retrieve the saved product
      final product = await products.get(savedProductId);

      if (product != null) {
        print('   ✅ Product successfully retrieved!');
        print('      Name: ${product.name}');
        print('      Price: \$${product.price}');
        print('      Quantity: ${product.quantity}');
        print('      Tags: ${product.tags.join(", ")}');
      } else {
        print('   ❌ Product not found!');
      }

      await db.close();
      print('\n   Database closed\n');
    }

    // =========================================================================
    // Session 3: Modify and persist changes
    // =========================================================================
    print('✏️ SESSION 3: Modifying persisted data\n');

    {
      final db = await DocDB.open(
        path: dbPath,
        config: DocDBConfig.development(),
      );

      final products = await db.collection<Product>(
        'products',
        fromMap: Product.fromMap,
      );

      // Retrieve and modify
      final product = await products.get(savedProductId);
      if (product != null) {
        final updated = product.copyWith(
          price: 35.00, // Discounted!
          quantity: 150,
        );
        await products.update(updated);
        print('   Updated product price and quantity');
      }

      // Add another product
      await products.insert(
        Product(
          name: 'Another Widget',
          description: 'Added in session 3',
          price: 15.00,
        ),
      );
      print('   Added another product');
      print('   Total products: ${await products.count}');

      await db.close();
      print('   Database closed\n');
    }

    // =========================================================================
    // Session 4: Final verification
    // =========================================================================
    print('✅ SESSION 4: Final verification\n');

    {
      final db = await DocDB.open(
        path: dbPath,
        config: DocDBConfig.development(),
      );

      final products = await db.collection<Product>(
        'products',
        fromMap: Product.fromMap,
      );

      final allProducts = await products.getAll();
      print('   All persisted products:');
      for (final product in allProducts) {
        print(
          '     • ${product.name}: \$${product.price} (qty: ${product.quantity})',
        );
      }

      await db.close();
    }

    // =========================================================================
    // Comparison: In-Memory (No Persistence)
    // =========================================================================
    print('\n💭 COMPARISON: In-Memory Database (no persistence)\n');

    {
      final memDb = await DocDB.open(
        path: null, // null path = in-memory
        config: DocDBConfig.inMemory(),
      );

      final memProducts = await memDb.collection<Product>(
        'products',
        fromMap: Product.fromMap,
      );

      await memProducts.insert(
        Product(
          name: 'Temporary Item',
          description: 'This will be lost when database closes',
          price: 9.99,
        ),
      );

      print('   In-memory product count: ${await memProducts.count}');

      await memDb.close();
      print('   In-memory database closed (data discarded)');
    }

    // =========================================================================
    // Summary
    // =========================================================================
    print('\n═══════════════════════════════════════════════════════════════');
    print('                   Persistence Summary');
    print('═══════════════════════════════════════════════════════════════');
    print('   File-based (StorageBackend.paged):');
    print('     • Data persists across sessions');
    print('     • Use db.flush() to ensure writes');
    print('     • Automatic flush on close (configurable)');
    print('');
    print('   In-memory (StorageBackend.memory):');
    print('     • Data lost when database closes');
    print('     • Faster, no disk I/O');
    print('     • Great for testing');
    print('═══════════════════════════════════════════════════════════════\n');
  } finally {
    // Cleanup temp directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
