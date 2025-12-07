/// Operation type definitions for EntiDB transactions.
///
/// Defines the types of operations that can be performed within
/// a transaction.
library;

/// The type of operation to perform on an entity.
///
/// Used by [TransactionOperation] to specify what action should
/// be taken when the transaction is committed.
enum OperationType {
  /// Insert a new entity into storage.
  ///
  /// Requires the entity ID and data to be provided.
  /// Fails if an entity with the same ID already exists.
  insert,

  /// Update an existing entity in storage.
  ///
  /// Requires the entity ID and new data to be provided.
  /// Fails if no entity with the ID exists.
  update,

  /// Insert or update an entity (upsert).
  ///
  /// If an entity with the ID exists, it is updated.
  /// Otherwise, a new entity is inserted.
  upsert,

  /// Delete an entity from storage.
  ///
  /// Requires only the entity ID.
  /// May succeed even if the entity doesn't exist (idempotent).
  delete,
}
