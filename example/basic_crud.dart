/// Basic CRUD Operations Example
///
/// Demonstrates Create, Read, Update, Delete operations with EntiDB.
///
/// Run with: `dart run example/basic_crud.dart`
import 'package:entidb/entidb.dart';

import 'models/models.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('                  Basic CRUD Operations');
  print('═══════════════════════════════════════════════════════════════\n');

  // Use in-memory database for this example
  final db = await EntiDB.open(path: null, config: EntiDBConfig.inMemory());

  try {
    // Get a typed collection
    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // =========================================================================
    // CREATE - Insert new documents
    // =========================================================================
    print('📝 CREATE - Inserting products...\n');

    final laptopId = await products.insert(
      Product(
        name: 'Laptop Pro',
        description: 'High-performance laptop',
        price: 1299.99,
        quantity: 50,
        tags: ['electronics', 'computers'],
      ),
    );
    print('   Inserted Laptop Pro with ID: $laptopId');

    final phoneId = await products.insert(
      Product(
        name: 'Smartphone X',
        description: 'Latest smartphone',
        price: 899.99,
        quantity: 100,
        tags: ['electronics', 'phones'],
      ),
    );
    print('   Inserted Smartphone X with ID: $phoneId');

    final headphonesId = await products.insert(
      Product(
        name: 'Wireless Headphones',
        description: 'Noise-cancelling headphones',
        price: 249.99,
        quantity: 75,
        tags: ['electronics', 'audio'],
      ),
    );
    print('   Inserted Wireless Headphones with ID: $headphonesId');

    print('\n   Total products: ${await products.count}\n');

    // =========================================================================
    // READ - Retrieve documents
    // =========================================================================
    print('📖 READ - Retrieving products...\n');

    // Get single document by ID
    final laptop = await products.get(laptopId);
    print('   By ID: $laptop');

    // Get all documents
    final allProducts = await products.getAll();
    print('   All products:');
    for (final product in allProducts) {
      print('     - ${product.name}: \$${product.price}');
    }
    print('');

    // =========================================================================
    // UPDATE - Modify existing documents
    // =========================================================================
    print('✏️ UPDATE - Modifying products...\n');

    if (laptop != null) {
      // Create updated version using copyWith
      final updatedLaptop = laptop.copyWith(
        price: 1199.99, // Sale price!
        quantity: 45,
      );

      await products.update(updatedLaptop);
      print('   Updated laptop price: \$1299.99 → \$1199.99');

      // Verify the update
      final verified = await products.get(laptopId);
      print('   Verified new price: \$${verified?.price}');
    }
    print('');

    // =========================================================================
    // DELETE - Remove documents
    // =========================================================================
    print('🗑️ DELETE - Removing products...\n');

    print('   Before delete: ${await products.count} products');

    await products.delete(headphonesId);
    print('   Deleted: Wireless Headphones');

    print('   After delete: ${await products.count} products');

    // Verify deletion
    final deleted = await products.get(headphonesId);
    print(
      '   Lookup deleted item: ${deleted == null ? "Not found ✓" : "Still exists!"}',
    );
    print('');

    // =========================================================================
    // Summary
    // =========================================================================
    print('═══════════════════════════════════════════════════════════════');
    print('                     CRUD Summary');
    print('═══════════════════════════════════════════════════════════════');
    print('   ✅ CREATE: insert() returns the generated ID');
    print('   ✅ READ:   get(id) or getAll()');
    print('   ✅ UPDATE: update() with modified entity');
    print('   ✅ DELETE: delete(id)');
    print('═══════════════════════════════════════════════════════════════\n');
  } finally {
    await db.close();
  }
}
