/// DocDB Examples Overview
///
/// This directory contains comprehensive examples demonstrating DocDB features.
///
/// ## Available Examples
///
/// Run each example with: `dart run example/<filename>.dart`
///
/// - **docdb_example.dart** - This file: Complete overview of all features
/// - **basic_crud.dart** - Create, Read, Update, Delete operations
/// - **querying.dart** - Query documents using QueryBuilder
/// - **persistence.dart** - Data persistence across sessions
/// - **collections.dart** - Working with multiple typed collections
/// - **configuration.dart** - Database configuration options
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/docdb.dart';
///
/// // Open a database
/// final db = await DocDB.open(
///   path: './myapp_data',
///   config: DocDBConfig.production(),
/// );
///
/// // Get a typed collection
/// final products = await db.collection<Product>(
///   'products',
///   fromMap: Product.fromMap,
/// );
///
/// // CRUD operations
/// final id = await products.insert(myProduct);
/// final product = await products.get(id);
/// await products.update(updatedProduct);
/// await products.delete(id);
///
/// // Query
/// final results = await products.find(
///   QueryBuilder().whereGreaterThan('price', 100.0).build(),
/// );
///
/// await db.close();
/// ```
import 'dart:io';

import 'package:docdb/docdb.dart';

import 'models/models.dart';

// =============================================================================
// Main Example
// =============================================================================

Future<void> main() async {
  print('╔════════════════════════════════════════════════════════════════╗');
  print('║                    DocDB Example                               ║');
  print('╚════════════════════════════════════════════════════════════════╝');
  print('');

  // Create a temporary directory for the example database
  final tempDir = await Directory.systemTemp.createTemp('docdb_example_');
  final dbPath = tempDir.path;

  try {
    // =========================================================================
    // 1. Open the Database
    // =========================================================================
    print('📂 Opening database at: $dbPath');
    print('');

    final db = await DocDB.open(
      path: dbPath,
      config: DocDBConfig.development(),
    );

    print('✅ Database opened successfully');
    print('   - Storage backend: ${db.config.storageBackend}');
    print('   - Page size: ${db.config.pageSize} bytes');
    print('   - Buffer pool: ${db.config.bufferPoolSize} pages');
    print('');

    // =========================================================================
    // 2. Create Collections
    // =========================================================================
    print('📁 Creating collections...');

    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    final customers = await db.collection<Customer>(
      'customers',
      fromMap: Customer.fromMap,
    );

    print('   - Created "products" collection');
    print('   - Created "customers" collection');
    print('');

    // =========================================================================
    // 3. Insert Documents
    // =========================================================================
    print('📝 Inserting documents...');

    // Insert products
    final laptopId = await products.insert(
      Product(
        name: 'Laptop Pro',
        description: 'High-performance laptop for professionals',
        price: 1299.99,
        quantity: 50,
        tags: ['electronics', 'computers', 'portable'],
      ),
    );

    final phoneId = await products.insert(
      Product(
        name: 'Smartphone X',
        description: 'Latest smartphone with advanced features',
        price: 899.99,
        quantity: 100,
        tags: ['electronics', 'phones', 'mobile'],
      ),
    );

    await products.insert(
      Product(
        name: 'Wireless Headphones',
        description: 'Premium noise-cancelling headphones',
        price: 249.99,
        quantity: 75,
        tags: ['electronics', 'audio', 'wireless'],
      ),
    );

    await products.insert(
      Product(
        name: 'USB-C Cable',
        description: 'Fast charging cable, 2 meters',
        price: 19.99,
        quantity: 500,
        tags: ['accessories', 'cables'],
      ),
    );

    await products.insert(
      Product(
        name: 'Laptop Stand',
        description: 'Ergonomic aluminum laptop stand',
        price: 79.99,
        quantity: 30,
        tags: ['accessories', 'ergonomic'],
      ),
    );

    // Insert customers
    await customers.insert(
      Customer(name: 'Alice Johnson', email: 'alice@example.com'),
    );

    await customers.insert(
      Customer(name: 'Bob Smith', email: 'bob@example.com'),
    );

    print('   - Inserted ${await products.count} products');
    print('   - Inserted ${await customers.count} customers');
    print('');

    // =========================================================================
    // 4. Read Documents
    // =========================================================================
    print('📖 Reading documents...');

    final laptop = await products.get(laptopId);
    print('   - Retrieved: $laptop');

    final phone = await products.get(phoneId);
    print('   - Retrieved: $phone');
    print('');

    // =========================================================================
    // 5. Query Documents
    // =========================================================================
    print('🔍 Querying documents...');

    // Find expensive products (price > 500)
    final expensiveProducts = await products.find(
      QueryBuilder().whereGreaterThan('price', 500.0).build(),
    );
    print('   - Products over \$500: ${expensiveProducts.length}');
    for (final product in expensiveProducts) {
      print('     • ${product.name}: \$${product.price}');
    }

    // Find products with specific tag
    final electronicsProducts = await products.find(
      QueryBuilder().whereContains('tags', 'electronics').build(),
    );
    print('   - Electronics products: ${electronicsProducts.length}');

    // Find products by name pattern
    final laptopProducts = await products.find(
      QueryBuilder().whereContains('name', 'Laptop').build(),
    );
    print('   - Products containing "Laptop": ${laptopProducts.length}');
    print('');

    // =========================================================================
    // 6. Update Documents
    // =========================================================================
    print('✏️ Updating documents...');

    // Update laptop price
    if (laptop != null) {
      final updatedLaptop = Product(
        id: laptop.id,
        name: laptop.name,
        description: laptop.description,
        price: 1199.99, // Reduced price
        quantity: laptop.quantity,
        tags: laptop.tags,
        createdAt: laptop.createdAt,
      );
      await products.update(updatedLaptop);
      print('   - Updated Laptop Pro price to \$1199.99');
    }

    // Verify update
    final updatedProduct = await products.get(laptopId);
    print(
      '   - Verified: ${updatedProduct?.name} now costs \$${updatedProduct?.price}',
    );
    print('');

    // =========================================================================
    // 7. Delete Documents
    // =========================================================================
    print('🗑️ Deleting documents...');

    // Delete the USB cable
    final cables = await products.find(
      QueryBuilder().whereContains('name', 'Cable').build(),
    );
    if (cables.isNotEmpty) {
      await products.delete(cables.first.id!);
      print('   - Deleted: ${cables.first.name}');
    }

    print('   - Remaining products: ${await products.count}');
    print('');

    // =========================================================================
    // 8. Get All Documents
    // =========================================================================
    print('📋 All products in database:');

    final allProducts = await products.getAll();
    for (final product in allProducts) {
      print(
        '   • ${product.name.padRight(25)} \$${product.price.toStringAsFixed(2).padLeft(8)} (qty: ${product.quantity})',
      );
    }
    print('');

    // =========================================================================
    // 9. Database Statistics
    // =========================================================================
    print('📊 Database statistics:');

    final stats = await db.getStats();
    print('   - Collections: ${stats.collectionCount}');
    print('   - Total entities: ${stats.totalEntityCount}');
    print('   - Storage backend: ${stats.storageBackend}');
    print(
      '   - Encryption: ${stats.encryptionEnabled ? "enabled" : "disabled"}',
    );

    for (final entry in stats.collections.entries) {
      print(
        '   - ${entry.key}: ${entry.value.entityCount} entities, ${entry.value.indexCount} indexes',
      );
    }
    print('');

    // =========================================================================
    // 10. Flush and Close
    // =========================================================================
    print('💾 Flushing and closing database...');

    await db.flush();
    await db.close();

    print('✅ Database closed successfully');
    print('');

    // =========================================================================
    // 11. Reopen and Verify Persistence
    // =========================================================================
    print('🔄 Reopening database to verify persistence...');

    final db2 = await DocDB.open(
      path: dbPath,
      config: DocDBConfig.development(),
    );

    final products2 = await db2.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    final persistedCount = await products2.count;
    print('   - Found $persistedCount persisted products');

    final persistedLaptop = await products2.get(laptopId);
    print(
      '   - Verified: ${persistedLaptop?.name} at \$${persistedLaptop?.price}',
    );

    await db2.close();
    print('✅ Persistence verified!');
    print('');

    // =========================================================================
    // 12. In-Memory Database Example
    // =========================================================================
    print('🧠 Creating in-memory database...');

    final memDb = await DocDB.open(path: null, config: DocDBConfig.inMemory());

    final memProducts = await memDb.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    await memProducts.insert(
      Product(
        name: 'Temporary Item',
        description: 'This will not persist',
        price: 9.99,
      ),
    );

    print('   - In-memory product count: ${await memProducts.count}');
    print('   - Storage backend: ${memDb.config.storageBackend}');

    await memDb.close();
    print('✅ In-memory database closed (data discarded)');
    print('');
  } finally {
    // Cleanup
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  print('╔════════════════════════════════════════════════════════════════╗');
  print('║                    Example Complete!                           ║');
  print('╚════════════════════════════════════════════════════════════════╝');
}
