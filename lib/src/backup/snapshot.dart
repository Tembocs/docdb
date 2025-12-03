// lib/src/backup/snapshot.dart

/// A class representing a snapshot of the storage engine's state.
class Snapshot {
  /// The timestamp when the snapshot was taken.
  final DateTime timestamp;

  /// The binary data of the snapshot.
  final List<int> data;

  Snapshot({
    required this.timestamp,
    required this.data,
  });
}
