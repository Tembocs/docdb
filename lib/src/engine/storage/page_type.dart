/// Page type enumeration for the storage engine.
///
/// Each page in the database file has a type that determines
/// how its contents are interpreted and managed.
library;

/// Identifies the type and purpose of a database page.
///
/// The page type is stored in the page header and determines:
/// - How the page's data area is structured
/// - What operations are valid on the page
/// - How the page is managed during recovery
///
/// Example:
/// ```dart
/// final page = await pager.readPage(pageId);
/// switch (page.type) {
///   case PageType.data:
///     // Process as slotted data page
///     break;
///   case PageType.index:
///     // Process as B+ tree node
///     break;
///   // ...
/// }
/// ```
enum PageType {
  /// File header page (always Page 0).
  ///
  /// Contains database metadata:
  /// - Magic number and version
  /// - Page size configuration
  /// - Free list pointer
  /// - Schema root pointer
  /// - Encryption settings
  header(0),

  /// Data page storing document records.
  ///
  /// Uses slotted page organization:
  /// - Slot directory at the start of data area
  /// - Record data at the end, growing backward
  /// - Free space in the middle
  data(1),

  /// Index page for B+ tree nodes.
  ///
  /// Structure depends on node type:
  /// - Internal nodes: keys and child page pointers
  /// - Leaf nodes: keys, values, and sibling pointers
  btreeIndex(2),

  /// Overflow page for large records.
  ///
  /// Contains:
  /// - Pointer to next overflow page (or 0 if last)
  /// - Data length in this page
  /// - Continuation of record data
  overflow(3),

  /// Free list page tracking available pages.
  ///
  /// Contains an array of free page IDs that can be
  /// allocated for new data.
  freeList(4),

  /// Schema page storing collection metadata.
  ///
  /// Contains:
  /// - Collection names and IDs
  /// - Index definitions
  /// - Schema validation rules
  schema(5),

  /// Write-ahead log page.
  ///
  /// Contains transaction log records for:
  /// - Crash recovery
  /// - Point-in-time recovery
  /// - Replication
  wal(6),

  /// Uninitialized or corrupted page.
  ///
  /// Pages with this type should not be used and may
  /// indicate file corruption or uninitialized space.
  unknown(255);

  /// The numeric value stored in the page header.
  final int value;

  const PageType(this.value);

  /// Creates a [PageType] from its numeric value.
  ///
  /// Returns [PageType.unknown] for unrecognized values.
  ///
  /// Example:
  /// ```dart
  /// final type = PageType.fromValue(1); // PageType.data
  /// final invalid = PageType.fromValue(99); // PageType.unknown
  /// ```
  static PageType fromValue(int value) {
    return switch (value) {
      0 => PageType.header,
      1 => PageType.data,
      2 => PageType.btreeIndex,
      3 => PageType.overflow,
      4 => PageType.freeList,
      5 => PageType.schema,
      6 => PageType.wal,
      _ => PageType.unknown,
    };
  }

  /// Returns `true` if this page type can contain user data.
  bool get isDataPage => this == PageType.data || this == PageType.overflow;

  /// Returns `true` if this page type is part of the index structure.
  bool get isIndexPage => this == PageType.btreeIndex;

  /// Returns `true` if this page type is a system/metadata page.
  bool get isSystemPage =>
      this == PageType.header ||
      this == PageType.freeList ||
      this == PageType.schema ||
      this == PageType.wal;
}
