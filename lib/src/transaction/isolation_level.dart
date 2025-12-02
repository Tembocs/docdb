/// Isolation level definitions for DocDB transactions.
///
/// Defines the levels of isolation between concurrent transactions,
/// controlling what data changes are visible to each transaction.
library;

/// The isolation level for a transaction.
///
/// Higher isolation levels provide stronger consistency guarantees
/// but may reduce concurrency and throughput.
///
/// ## Isolation Level Comparison
///
/// | Level | Dirty Read | Non-Repeatable Read | Phantom Read |
/// |-------|------------|---------------------|--------------|
/// | [readUncommitted] | Possible | Possible | Possible |
/// | [readCommitted] | Prevented | Possible | Possible |
/// | [repeatableRead] | Prevented | Prevented | Possible |
/// | [serializable] | Prevented | Prevented | Prevented |
///
/// ## Anomaly Definitions
///
/// - **Dirty Read**: Reading uncommitted changes from another transaction.
/// - **Non-Repeatable Read**: Getting different values when reading the
///   same row twice within a transaction (due to another commit).
/// - **Phantom Read**: Getting different rows when running the same query
///   twice (due to inserts/deletes by other transactions).
///
/// ## Default Behavior
///
/// DocDB defaults to [serializable] isolation for single-writer scenarios.
/// For high-concurrency use cases, consider [readCommitted].
enum IsolationLevel {
  /// Lowest isolation level.
  ///
  /// Transactions can see uncommitted changes from other transactions.
  /// Provides maximum concurrency but minimum consistency.
  ///
  /// **Use case**: Read-only analytics where some inconsistency is acceptable.
  readUncommitted,

  /// Transactions only see committed changes.
  ///
  /// A transaction will never see uncommitted (dirty) data from other
  /// transactions, but may see different committed data between reads.
  ///
  /// **Use case**: Most OLTP applications where some read inconsistency
  /// is acceptable but dirty reads are not.
  readCommitted,

  /// Transactions see a consistent snapshot of committed data.
  ///
  /// All reads within a transaction see the same data, even if other
  /// transactions commit changes. However, phantom reads are possible
  /// if new rows are inserted by other transactions.
  ///
  /// **Use case**: Reports and aggregations that need consistent reads.
  repeatableRead,

  /// Highest isolation level.
  ///
  /// Transactions execute as if they were the only transaction running.
  /// No anomalies are possible, but concurrent transactions may need
  /// to wait or may be aborted to prevent conflicts.
  ///
  /// **Use case**: Critical operations requiring absolute consistency,
  /// such as financial transactions.
  serializable,
}
