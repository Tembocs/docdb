/// Querying Example
///
/// Demonstrates how to query documents using QueryBuilder.
///
/// Run with: `dart run example/querying.dart`
import 'package:entidb/entidb.dart';

import 'models/models.dart';

Future<void> main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('                    Querying Documents');
  print('═══════════════════════════════════════════════════════════════\n');

  final db = await EntiDB.open(path: null, config: EntiDBConfig.inMemory());

  try {
    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // Insert sample data
    await _insertSampleData(products);

    // =========================================================================
    // Basic Equality Query
    // =========================================================================
    print('🔍 Query: Products with quantity = 100\n');

    final exactQty = await products.find(
      QueryBuilder().whereEquals('quantity', 100).build(),
    );

    _printResults(exactQty);

    // =========================================================================
    // Comparison Queries
    // =========================================================================
    print('🔍 Query: Products with price > \$500\n');

    final expensive = await products.find(
      QueryBuilder().whereGreaterThan('price', 500.0).build(),
    );

    _printResults(expensive);

    print('🔍 Query: Products with price < \$50\n');

    final cheap = await products.find(
      QueryBuilder().whereLessThan('price', 50.0).build(),
    );

    _printResults(cheap);

    // =========================================================================
    // Contains Query (for strings and lists)
    // =========================================================================
    print('🔍 Query: Products tagged with "electronics"\n');

    final electronics = await products.find(
      QueryBuilder().whereContains('tags', 'electronics').build(),
    );

    _printResults(electronics);

    print('🔍 Query: Products with "Laptop" in name\n');

    final laptops = await products.find(
      QueryBuilder().whereContains('name', 'Laptop').build(),
    );

    _printResults(laptops);

    // =========================================================================
    // Combined Queries
    // =========================================================================
    print('🔍 Query: Electronics over \$200\n');

    final premiumElectronics = await products.find(
      QueryBuilder()
          .whereContains('tags', 'electronics')
          .whereGreaterThan('price', 200.0)
          .build(),
    );

    _printResults(premiumElectronics);

    // =========================================================================
    // FindOne - Get first matching
    // =========================================================================
    print('🔍 Query: First product under \$100\n');

    final firstCheap = await products.findOne(
      QueryBuilder().whereLessThan('price', 100.0).build(),
    );

    if (firstCheap != null) {
      print('   Found: ${firstCheap.name} at \$${firstCheap.price}\n');
    } else {
      print('   No matching product found\n');
    }

    // =========================================================================
    // Summary
    // =========================================================================
    print('═══════════════════════════════════════════════════════════════');
    print('                   Query Methods Summary');
    print('═══════════════════════════════════════════════════════════════');
    print('   QueryBuilder methods:');
    print('     • whereEquals(field, value)');
    print('     • whereNotEquals(field, value)');
    print('     • whereGreaterThan(field, value)');
    print('     • whereLessThan(field, value)');
    print('     • whereGreaterOrEqual(field, value)');
    print('     • whereLessOrEqual(field, value)');
    print('     • whereContains(field, value)');
    print('     • whereIn(field, values)');
    print('   Collection methods:');
    print('     • find(query) → List<T>');
    print('     • findOne(query) → T?');
    print('═══════════════════════════════════════════════════════════════\n');
  } finally {
    await db.close();
  }
}

/// Inserts sample product data.
Future<void> _insertSampleData(Collection<Product> products) async {
  print('📦 Inserting sample data...\n');

  final sampleProducts = [
    Product(
      name: 'Laptop Pro',
      description: 'High-performance laptop',
      price: 1299.99,
      quantity: 50,
      tags: ['electronics', 'computers', 'portable'],
    ),
    Product(
      name: 'Smartphone X',
      description: 'Latest smartphone',
      price: 899.99,
      quantity: 100,
      tags: ['electronics', 'phones', 'mobile'],
    ),
    Product(
      name: 'Wireless Headphones',
      description: 'Noise-cancelling headphones',
      price: 249.99,
      quantity: 75,
      tags: ['electronics', 'audio', 'wireless'],
    ),
    Product(
      name: 'USB-C Cable',
      description: 'Fast charging cable',
      price: 19.99,
      quantity: 500,
      tags: ['accessories', 'cables'],
    ),
    Product(
      name: 'Laptop Stand',
      description: 'Ergonomic aluminum stand',
      price: 79.99,
      quantity: 30,
      tags: ['accessories', 'ergonomic'],
    ),
    Product(
      name: 'Mechanical Keyboard',
      description: 'RGB mechanical keyboard',
      price: 149.99,
      quantity: 100,
      tags: ['electronics', 'peripherals', 'gaming'],
    ),
  ];

  for (final product in sampleProducts) {
    await products.insert(product);
  }

  print('   Inserted ${sampleProducts.length} products\n');
}

/// Prints query results in a formatted way.
void _printResults(List<Product> results) {
  if (results.isEmpty) {
    print('   No results found\n');
    return;
  }

  print('   Found ${results.length} product(s):');
  for (final product in results) {
    print(
      '     • ${product.name.padRight(22)} \$${product.price.toStringAsFixed(2).padLeft(8)}  [${product.tags.join(", ")}]',
    );
  }
  print('');
}
