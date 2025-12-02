/// Validates an email address format.
///
/// Returns `true` if the email matches the standard email format:
/// `local-part@domain.tld`
///
/// This validation checks for:
/// - Non-empty local part with alphanumeric characters and `._%+-`
/// - An `@` symbol
/// - A domain with alphanumeric characters and `.-`
/// - A top-level domain of at least 2 characters
///
/// Example:
/// ```dart
/// isValidEmail('user@example.com');  // true
/// isValidEmail('invalid');            // false
/// isValidEmail('');                   // false
/// ```
bool isValidEmail(String email) {
  if (email.isEmpty) return false;
  final emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  return emailRegex.hasMatch(email);
}

/// Validates a semantic version string.
///
/// Returns `true` if the version matches the format `MAJOR.MINOR.PATCH`
/// where each component is a non-negative integer.
///
/// Example:
/// ```dart
/// isValidVersion('1.0.0');   // true
/// isValidVersion('2.10.3');  // true
/// isValidVersion('1.0');     // false
/// isValidVersion('v1.0.0');  // false
/// ```
bool isValidVersion(String version) {
  if (version.isEmpty) return false;
  final versionRegex = RegExp(r'^\d+\.\d+\.\d+$');
  return versionRegex.hasMatch(version);
}

/// Validates a username string.
///
/// Returns `true` if the username:
/// - Is between 3 and 32 characters long
/// - Contains only alphanumeric characters, underscores, and hyphens
/// - Starts with an alphanumeric character
///
/// Example:
/// ```dart
/// isValidUsername('john_doe');   // true
/// isValidUsername('user-123');   // true
/// isValidUsername('ab');         // false (too short)
/// isValidUsername('_invalid');   // false (starts with underscore)
/// ```
bool isValidUsername(String username) {
  if (username.isEmpty) return false;
  if (username.length < 3 || username.length > 32) return false;
  final usernameRegex = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$');
  return usernameRegex.hasMatch(username);
}

/// Validates a collection name string.
///
/// Returns `true` if the collection name:
/// - Is between 1 and 64 characters long
/// - Contains only alphanumeric characters and underscores
/// - Starts with a letter
///
/// Example:
/// ```dart
/// isValidCollectionName('users');        // true
/// isValidCollectionName('order_items');  // true
/// isValidCollectionName('123invalid');   // false
/// isValidCollectionName('');             // false
/// ```
bool isValidCollectionName(String name) {
  if (name.isEmpty) return false;
  if (name.length > 64) return false;
  final collectionRegex = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
  return collectionRegex.hasMatch(name);
}

/// Validates a document ID string.
///
/// Returns `true` if the ID:
/// - Is not empty
/// - Is not longer than 128 characters
/// - Contains only URL-safe characters (alphanumeric, `-`, `_`)
///
/// Example:
/// ```dart
/// isValidDocumentId('abc123');                    // true
/// isValidDocumentId('018c5a2e-8f3b-7000-8000');  // true
/// isValidDocumentId('');                          // false
/// isValidDocumentId('id with spaces');            // false
/// ```
bool isValidDocumentId(String id) {
  if (id.isEmpty) return false;
  if (id.length > 128) return false;
  final idRegex = RegExp(r'^[a-zA-Z0-9_-]+$');
  return idRegex.hasMatch(id);
}

/// Validates a field name for use in documents and queries.
///
/// Returns `true` if the field name:
/// - Is not empty
/// - Is not longer than 64 characters
/// - Contains only alphanumeric characters, underscores, and dots (for nesting)
/// - Starts with a letter or underscore
/// - Does not start with a dollar sign (reserved for system fields)
///
/// Example:
/// ```dart
/// isValidFieldName('name');           // true
/// isValidFieldName('user.email');     // true
/// isValidFieldName('_id');            // true
/// isValidFieldName('\$system');        // false (reserved prefix)
/// isValidFieldName('123field');       // false
/// ```
bool isValidFieldName(String fieldName) {
  if (fieldName.isEmpty) return false;
  if (fieldName.length > 64) return false;
  if (fieldName.startsWith(r'$')) return false;
  final fieldRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.]*$');
  return fieldRegex.hasMatch(fieldName);
}

/// Validates a password meets minimum security requirements.
///
/// Returns `true` if the password:
/// - Is at least 8 characters long
/// - Is not longer than 128 characters
///
/// Note: This is a basic length check. For production use, consider
/// additional requirements like character complexity.
///
/// Example:
/// ```dart
/// isValidPassword('securepass123');  // true
/// isValidPassword('short');          // false (too short)
/// ```
bool isValidPassword(String password) {
  if (password.isEmpty) return false;
  if (password.length < 8) return false;
  if (password.length > 128) return false;
  return true;
}

/// Validates that a string is not null, empty, or only whitespace.
///
/// Returns `true` if the string contains at least one non-whitespace
/// character.
///
/// Example:
/// ```dart
/// isNotBlank('hello');   // true
/// isNotBlank('  hi  ');  // true
/// isNotBlank('   ');     // false
/// isNotBlank('');        // false
/// ```
bool isNotBlank(String? value) {
  return value != null && value.trim().isNotEmpty;
}
