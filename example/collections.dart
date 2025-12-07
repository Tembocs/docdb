/// Multiple Collections Example
///
/// Demonstrates working with multiple typed collections.
///
/// Run with: `dart run example/collections.dart`
import 'package:entidb/entidb.dart';

import 'models/models.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('                 Multiple Collections');
  print('═══════════════════════════════════════════════════════════════\n');

  final db = await EntiDB.open(path: null, config: EntiDBConfig.inMemory());

  try {
    // =========================================================================
    // Creating Multiple Collections
    // =========================================================================
    print('📁 Creating collections...\n');

    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    final customers = await db.collection<Customer>(
      'customers',
      fromMap: Customer.fromMap,
    );

    print('   Created collections: ${db.collectionNames.join(", ")}');
    print('   Collection count: ${db.collectionCount}\n');

    // =========================================================================
    // Populating Collections
    // =========================================================================
    print('📝 Populating collections...\n');

    // Products
    await products.insert(
      Product(
        name: 'Widget A',
        description: 'First widget',
        price: 29.99,
        quantity: 100,
      ),
    );

    await products.insert(
      Product(
        name: 'Widget B',
        description: 'Second widget',
        price: 49.99,
        quantity: 50,
      ),
    );

    // Customers
    await customers.insert(
      Customer(name: 'Alice Johnson', email: 'alice@example.com'),
    );

    await customers.insert(
      Customer(name: 'Bob Smith', email: 'bob@example.com'),
    );

    await customers.insert(
      Customer(
        name: 'Carol White',
        email: 'carol@example.com',
        isActive: false,
      ),
    );

    print('   Products: ${await products.count}');
    print('   Customers: ${await customers.count}\n');

    // =========================================================================
    // Type Safety
    // =========================================================================
    print('🔒 Type Safety Demonstration\n');

    // Collections return the correct type
    final allProducts = await products.getAll();
    final allCustomers = await customers.getAll();

    print('   Products (List<Product>):');
    for (final p in allProducts) {
      // Full access to Product properties
      print('     • ${p.name}: \$${p.price}, qty: ${p.quantity}');
    }

    print('\n   Customers (List<Customer>):');
    for (final c in allCustomers) {
      // Full access to Customer properties
      print(
        '     • ${c.name} <${c.email}> - ${c.isActive ? "Active" : "Inactive"}',
      );
    }
    print('');

    // =========================================================================
    // Collection Lookup
    // =========================================================================
    print('🔍 Collection Lookup\n');

    print('   Has "products" collection: ${db.hasCollection("products")}');
    print('   Has "orders" collection: ${db.hasCollection("orders")}');
    print('');

    // =========================================================================
    // Re-accessing Collections
    // =========================================================================
    print('♻️ Re-accessing Collections\n');

    // Getting the same collection returns the same instance
    final products2 = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    print('   Same instance: ${identical(products, products2)}');
    print('');

    // =========================================================================
    // Type Mismatch Protection
    // =========================================================================
    print('🛡️ Type Mismatch Protection\n');

    try {
      // This will throw! Products collection was created with Product type
      await db.collection<Customer>(
        'products', // Trying to access products as customers
        fromMap: Customer.fromMap,
      );
    } on CollectionTypeMismatchException catch (e) {
      print('   ✅ Caught type mismatch: ${e.message}');
    }
    print('');

    // =========================================================================
    // Dropping Collections
    // =========================================================================
    print('🗑️ Dropping Collections\n');

    print('   Before drop: ${db.collectionNames.join(", ")}');

    final dropped = await db.dropCollection('customers');
    print('   Dropped "customers": $dropped');

    print('   After drop: ${db.collectionNames.join(", ")}');
    print('   Has "customers": ${db.hasCollection("customers")}');
    print('');

    // =========================================================================
    // Database Statistics
    // =========================================================================
    print('📊 Database Statistics\n');

    final stats = await db.getStats();
    print('   Collections: ${stats.collectionCount}');
    print('   Total entities: ${stats.totalEntityCount}');
    print('   Storage backend: ${stats.storageBackend}');

    for (final entry in stats.collections.entries) {
      print('   • ${entry.key}: ${entry.value.entityCount} entities');
    }
    print('');

    // =========================================================================
    // Summary
    // =========================================================================
    print('═══════════════════════════════════════════════════════════════');
    print('                   Collections Summary');
    print('═══════════════════════════════════════════════════════════════');
    print('   Creating:   db.collection<T>(name, fromMap: T.fromMap)');
    print('   Checking:   db.hasCollection(name)');
    print('   Listing:    db.collectionNames');
    print('   Counting:   db.collectionCount');
    print('   Dropping:   db.dropCollection(name)');
    print('   Stats:      db.getStats()');
    print('═══════════════════════════════════════════════════════════════\n');
  } finally {
    await db.close();
  }
}
