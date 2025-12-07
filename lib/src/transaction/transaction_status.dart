/// Transaction status definitions for EntiDB.
///
/// Defines the lifecycle states of a transaction.
library;

/// The current status of a transaction.
///
/// Transactions follow a state machine:
///
/// ```
/// [pending] ──begin──► [active] ──commit──► [committed]
///                         │
///                         └──rollback──► [rolledBack]
///                         │
///                         └──error──► [failed]
/// ```
enum TransactionStatus {
  /// Transaction has been created but not yet started.
  ///
  /// This is the initial state before any operations are queued.
  pending,

  /// Transaction is active and accepting operations.
  ///
  /// In this state, operations can be queued via insert, update,
  /// delete methods. The transaction remains active until commit
  /// or rollback is called.
  active,

  /// Transaction has been successfully committed.
  ///
  /// All queued operations have been applied to storage.
  /// The transaction cannot be modified after this point.
  committed,

  /// Transaction has been rolled back.
  ///
  /// All queued operations have been discarded. Storage
  /// has been restored to its state before the transaction began.
  /// The transaction cannot be modified after this point.
  rolledBack,

  /// Transaction has failed due to an error.
  ///
  /// An error occurred during commit or operation execution.
  /// The transaction may have been partially applied depending
  /// on when the error occurred.
  failed,
}
