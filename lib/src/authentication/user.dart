/// EntiDB User Entity Module
///
/// Provides the [User] entity class that implements [Entity] for storage
/// in EntiDB collections. Users are the primary subjects for authentication
/// and authorization operations.
///
/// ## Overview
///
/// The [User] class represents an authenticated user in the system with:
///
/// - **Identity**: Unique ID and username
/// - **Credentials**: Securely hashed password
/// - **Authorization**: Role-based access control
/// - **Metadata**: Timestamps and profile information
/// - **Status**: Account state tracking (active, locked, etc.)
///
/// ## Quick Start
///
/// ```dart
/// import 'package:entidb/src/authentication/user.dart';
///
/// // Create a new user
/// final user = User(
///   username: 'john.doe',
///   email: 'john@example.com',
///   passwordHash: securityService.hashPassword('secret123'),
///   roles: ['user'],
/// );
///
/// // Store in collection
/// final users = Collection<User>(
///   storage: userStorage,
///   fromMap: User.fromMap,
///   name: 'users',
/// );
/// await users.insert(user);
///
/// // Query users
/// final found = await users.findOne(
///   QueryBuilder().whereEquals('username', 'john.doe').build(),
/// );
/// ```
///
/// ## Security Considerations
///
/// - Password hashes are stored, never plain text passwords
/// - Use [SecurityService] for password hashing and verification
/// - Account lockout prevents brute force attacks
/// - Session tracking enables forced logout
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../entity/entity.dart';

/// Represents the status of a user account.
///
/// Account status controls authentication and authorization behavior.
enum UserStatus {
  /// Account is active and can authenticate.
  active,

  /// Account is temporarily locked (e.g., failed login attempts).
  locked,

  /// Account is suspended by an administrator.
  suspended,

  /// Account is pending email/phone verification.
  pendingVerification,

  /// Account has been deactivated by the user.
  deactivated,
}

/// Extension methods for [UserStatus] serialization.
extension UserStatusExtension on UserStatus {
  /// Converts the status to a string for storage.
  String toStorageString() => name;

  /// Parses a status from a stored string.
  static UserStatus fromString(String value) {
    return UserStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => UserStatus.active,
    );
  }
}

/// Represents a user in the EntiDB authentication system.
///
/// [User] implements [Entity] for seamless integration with EntiDB
/// collections. It stores all user-related data including credentials,
/// roles, and account metadata.
///
/// ## Example
///
/// ```dart
/// final user = User(
///   username: 'alice',
///   email: 'alice@example.com',
///   passwordHash: hashedPassword,
///   roles: ['user', 'moderator'],
/// );
///
/// // Serialize for storage
/// final data = user.toMap();
///
/// // Deserialize from storage
/// final restored = User.fromMap('user-123', data);
/// ```
///
/// ## Immutability
///
/// [User] is immutable. Use [copyWith] to create modified copies:
///
/// ```dart
/// final updated = user.copyWith(
///   roles: [...user.roles, 'admin'],
///   updatedAt: DateTime.now(),
/// );
/// ```
@immutable
class User implements Entity {
  /// Unique identifier for this user.
  ///
  /// Generated automatically when inserted into a collection if not provided.
  @override
  final String? id;

  /// Unique username for authentication.
  ///
  /// Must be unique within the user collection. Used as the primary
  /// login credential along with password.
  final String username;

  /// Email address for the user.
  ///
  /// Used for account recovery, notifications, and verification.
  /// Should be validated before storage.
  final String? email;

  /// BCrypt hash of the user's password.
  ///
  /// Never store plain text passwords. Use [SecurityService.hashPassword]
  /// to generate this value.
  final String passwordHash;

  /// List of role names assigned to this user.
  ///
  /// Roles determine the user's permissions through the authorization
  /// system. Common roles include 'user', 'admin', 'moderator'.
  final List<String> roles;

  /// Current account status.
  ///
  /// Controls whether the user can authenticate and what actions
  /// are available.
  final UserStatus status;

  /// Display name for the user.
  ///
  /// Optional friendly name for UI display purposes.
  final String? displayName;

  /// URL to the user's profile image.
  final String? profileImageUrl;

  /// Number of consecutive failed login attempts.
  ///
  /// Used for account lockout protection. Reset on successful login.
  final int failedLoginAttempts;

  /// Timestamp when the account was locked.
  ///
  /// Used to implement time-based automatic unlock.
  final DateTime? lockedUntil;

  /// Timestamp when the user last logged in.
  final DateTime? lastLoginAt;

  /// Timestamp when the password was last changed.
  ///
  /// Used to enforce password rotation policies.
  final DateTime? passwordChangedAt;

  /// Timestamp when the user was created.
  final DateTime createdAt;

  /// Timestamp when the user was last updated.
  final DateTime updatedAt;

  /// Additional metadata for the user.
  ///
  /// Flexible key-value storage for application-specific data.
  final Map<String, dynamic> metadata;

  /// Creates a new [User] instance.
  ///
  /// ## Parameters
  ///
  /// - [id]: Unique identifier (auto-generated if null).
  /// - [username]: Login username (required).
  /// - [email]: Email address for notifications and recovery.
  /// - [passwordHash]: BCrypt-hashed password (required).
  /// - [roles]: List of assigned role names.
  /// - [status]: Account status (defaults to active).
  /// - [displayName]: Friendly display name.
  /// - [profileImageUrl]: Profile image URL.
  /// - [failedLoginAttempts]: Failed login counter.
  /// - [lockedUntil]: Lock expiration timestamp.
  /// - [lastLoginAt]: Last successful login.
  /// - [passwordChangedAt]: Last password change.
  /// - [createdAt]: Creation timestamp.
  /// - [updatedAt]: Last update timestamp.
  /// - [metadata]: Additional custom data.
  User({
    this.id,
    required this.username,
    this.email,
    required this.passwordHash,
    List<String>? roles,
    this.status = UserStatus.active,
    this.displayName,
    this.profileImageUrl,
    this.failedLoginAttempts = 0,
    this.lockedUntil,
    this.lastLoginAt,
    this.passwordChangedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) : roles = roles ?? const [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       metadata = metadata ?? const {};

  /// Converts this user to a map for storage.
  ///
  /// The [id] is excluded as it's stored separately by EntiDB.
  /// All nested objects are serialized to JSON-compatible formats.
  @override
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      if (email != null) 'email': email,
      'passwordHash': passwordHash,
      'roles': roles,
      'status': status.toStorageString(),
      if (displayName != null) 'displayName': displayName,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      'failedLoginAttempts': failedLoginAttempts,
      if (lockedUntil != null) 'lockedUntil': lockedUntil!.toIso8601String(),
      if (lastLoginAt != null) 'lastLoginAt': lastLoginAt!.toIso8601String(),
      if (passwordChangedAt != null)
        'passwordChangedAt': passwordChangedAt!.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  /// Creates a [User] from a stored map.
  ///
  /// This factory is used by [Collection] to deserialize users.
  ///
  /// ## Parameters
  ///
  /// - [id]: The entity ID from storage.
  /// - [map]: The stored data map.
  ///
  /// ## Throws
  ///
  /// - [FormatException]: If required fields are missing or malformed.
  factory User.fromMap(String id, Map<String, dynamic> map) {
    _validateRequiredField(map, 'username');
    _validateRequiredField(map, 'passwordHash');

    return User(
      id: id,
      username: map['username'] as String,
      email: map['email'] as String?,
      passwordHash: map['passwordHash'] as String,
      roles: _parseRoles(map['roles']),
      status: _parseStatus(map['status']),
      displayName: map['displayName'] as String?,
      profileImageUrl: map['profileImageUrl'] as String?,
      failedLoginAttempts: (map['failedLoginAttempts'] as int?) ?? 0,
      lockedUntil: _parseDateTime(map['lockedUntil']),
      lastLoginAt: _parseDateTime(map['lastLoginAt']),
      passwordChangedAt: _parseDateTime(map['passwordChangedAt']),
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']) ?? DateTime.now(),
      metadata: _parseMetadata(map['metadata']),
    );
  }

  /// Validates that a required field exists in the map.
  static void _validateRequiredField(Map<String, dynamic> map, String field) {
    if (map[field] == null) {
      throw FormatException('User.fromMap: Missing required field "$field".');
    }
  }

  /// Parses the roles list from storage.
  static List<String> _parseRoles(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Parses the user status from storage.
  static UserStatus _parseStatus(dynamic value) {
    if (value == null) return UserStatus.active;
    if (value is String) {
      return UserStatusExtension.fromString(value);
    }
    return UserStatus.active;
  }

  /// Parses a DateTime from storage.
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Parses metadata from storage.
  static Map<String, dynamic> _parseMetadata(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  /// Serializes this user to a JSON string.
  String toJson() => json.encode(toMap());

  /// Creates a [User] from a JSON string.
  ///
  /// The [id] must be provided separately as it's not in the JSON.
  factory User.fromJson(String id, String source) {
    return User.fromMap(id, json.decode(source) as Map<String, dynamic>);
  }

  /// Creates a copy of this user with modified fields.
  ///
  /// Use this method to create updated versions of users while
  /// maintaining immutability.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final updated = user.copyWith(
  ///   lastLoginAt: DateTime.now(),
  ///   failedLoginAttempts: 0,
  /// );
  /// ```
  User copyWith({
    String? id,
    String? username,
    String? email,
    String? passwordHash,
    List<String>? roles,
    UserStatus? status,
    String? displayName,
    String? profileImageUrl,
    int? failedLoginAttempts,
    DateTime? lockedUntil,
    DateTime? lastLoginAt,
    DateTime? passwordChangedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      roles: roles ?? List<String>.from(this.roles),
      status: status ?? this.status,
      displayName: displayName ?? this.displayName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      failedLoginAttempts: failedLoginAttempts ?? this.failedLoginAttempts,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      passwordChangedAt: passwordChangedAt ?? this.passwordChangedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? Map<String, dynamic>.from(this.metadata),
    );
  }

  /// Checks if the account is currently locked.
  ///
  /// Returns `true` if the status is [UserStatus.locked] and the
  /// lock has not expired.
  bool get isLocked {
    if (status != UserStatus.locked) return false;
    if (lockedUntil == null) return true;
    return DateTime.now().isBefore(lockedUntil!);
  }

  /// Checks if the account can authenticate.
  ///
  /// Returns `true` if the account is active and not locked.
  bool get canAuthenticate {
    return status == UserStatus.active && !isLocked;
  }

  /// Checks if the user has a specific role.
  bool hasRole(String role) => roles.contains(role);

  /// Checks if the user has any of the specified roles.
  bool hasAnyRole(List<String> checkRoles) {
    return checkRoles.any((role) => roles.contains(role));
  }

  /// Checks if the user has all of the specified roles.
  bool hasAllRoles(List<String> checkRoles) {
    return checkRoles.every((role) => roles.contains(role));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! User) return false;

    return id == other.id &&
        username == other.username &&
        email == other.email &&
        passwordHash == other.passwordHash &&
        _listEquals(roles, other.roles) &&
        status == other.status &&
        displayName == other.displayName &&
        failedLoginAttempts == other.failedLoginAttempts;
  }

  /// Compares two lists for equality.
  static bool _listEquals<E>(List<E> a, List<E> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      username,
      email,
      passwordHash,
      Object.hashAll(roles),
      status,
      displayName,
      failedLoginAttempts,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, username: $username, status: ${status.name}, '
        'roles: [${roles.join(", ")}])';
  }
}

/// Represents an active user session.
///
/// Sessions track authenticated user activity and enable features
/// like forced logout and concurrent session limits.
@immutable
class UserSession implements Entity {
  /// Unique session identifier.
  @override
  final String? id;

  /// The ID of the user this session belongs to.
  final String userId;

  /// The JWT token for this session.
  final String token;

  /// When the session was created.
  final DateTime createdAt;

  /// When the session expires.
  final DateTime expiresAt;

  /// When the session was last active.
  final DateTime lastActiveAt;

  /// IP address of the client.
  final String? ipAddress;

  /// User agent string of the client.
  final String? userAgent;

  /// Whether the session has been explicitly revoked.
  final bool isRevoked;

  /// Creates a new [UserSession].
  UserSession({
    this.id,
    required this.userId,
    required this.token,
    required this.expiresAt,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    this.ipAddress,
    this.userAgent,
    this.isRevoked = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       lastActiveAt = lastActiveAt ?? DateTime.now();

  /// Checks if the session is currently valid.
  bool get isValid {
    if (isRevoked) return false;
    return DateTime.now().isBefore(expiresAt);
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'token': token,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'lastActiveAt': lastActiveAt.toIso8601String(),
      if (ipAddress != null) 'ipAddress': ipAddress,
      if (userAgent != null) 'userAgent': userAgent,
      'isRevoked': isRevoked,
    };
  }

  /// Creates a [UserSession] from a stored map.
  factory UserSession.fromMap(String id, Map<String, dynamic> map) {
    return UserSession(
      id: id,
      userId: map['userId'] as String,
      token: map['token'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      expiresAt: DateTime.parse(map['expiresAt'] as String),
      lastActiveAt: DateTime.parse(map['lastActiveAt'] as String),
      ipAddress: map['ipAddress'] as String?,
      userAgent: map['userAgent'] as String?,
      isRevoked: (map['isRevoked'] as bool?) ?? false,
    );
  }

  /// Creates a copy with modified fields.
  UserSession copyWith({
    String? id,
    String? userId,
    String? token,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? lastActiveAt,
    String? ipAddress,
    String? userAgent,
    bool? isRevoked,
  }) {
    return UserSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      ipAddress: ipAddress ?? this.ipAddress,
      userAgent: userAgent ?? this.userAgent,
      isRevoked: isRevoked ?? this.isRevoked,
    );
  }

  @override
  String toString() {
    return 'UserSession(id: $id, userId: $userId, valid: $isValid)';
  }
}
