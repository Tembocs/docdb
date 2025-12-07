/// EntiDB Role Module
///
/// Provides the [Role] entity class for role-based access control (RBAC).
/// Roles are collections of permissions that can be assigned to users.
///
/// ## Overview
///
/// Roles provide:
///
/// - **Permission Grouping**: Bundle related permissions together
/// - **Inheritance**: Roles can inherit from parent roles
/// - **Metadata**: Additional role information and constraints
///
/// ## Quick Start
///
/// ```dart
/// import 'package:entidb/src/authorization/roles.dart';
///
/// // Create a basic role
/// final userRole = Role(
///   name: 'user',
///   description: 'Standard user with basic permissions',
///   permissions: [
///     Permission.action(Action.read, Resource.document),
///     Permission.action(Action.create, Resource.document),
///   ],
/// );
///
/// // Create a role with inheritance
/// final moderatorRole = Role(
///   name: 'moderator',
///   description: 'User with moderation capabilities',
///   permissions: [
///     Permission.action(Action.delete, Resource.document),
///   ],
///   parentRoles: ['user'],
/// );
///
/// // Store in collection
/// final roles = Collection<Role>(
///   storage: roleStorage,
///   fromMap: Role.fromMap,
///   name: 'roles',
/// );
/// await roles.insert(userRole);
/// ```
library;

import 'package:meta/meta.dart';

import '../entity/entity.dart';
import 'permissions.dart';

/// Represents a role in the authorization system.
///
/// [Role] implements [Entity] for storage in EntiDB collections.
/// Roles group permissions together and support inheritance.
///
/// ## Inheritance
///
/// Roles can inherit permissions from parent roles:
///
/// ```dart
/// final admin = Role(
///   name: 'admin',
///   permissions: [Permissions.adminAll],
///   parentRoles: ['moderator', 'user'],
/// );
/// ```
///
/// ## System Roles
///
/// Some roles are marked as system roles and cannot be deleted:
///
/// ```dart
/// final superAdmin = Role(
///   name: 'super_admin',
///   isSystem: true,
///   permissions: [Permissions.superAdmin],
/// );
/// ```
@immutable
class Role implements Entity {
  /// Unique identifier for this role.
  @override
  final String? id;

  /// The role name (unique within the system).
  ///
  /// Role names should be lowercase with underscores.
  /// Examples: 'user', 'admin', 'content_moderator'
  final String name;

  /// Human-readable description of the role.
  final String? description;

  /// The permissions directly assigned to this role.
  ///
  /// This does not include inherited permissions from parent roles.
  final List<Permission> permissions;

  /// Names of parent roles to inherit permissions from.
  ///
  /// Inherited permissions are resolved at runtime by the [RoleManager].
  final List<String> parentRoles;

  /// Whether this is a system role.
  ///
  /// System roles cannot be deleted and have limited modification.
  final bool isSystem;

  /// Whether this role is currently active.
  ///
  /// Inactive roles are not considered during permission checks.
  final bool isActive;

  /// Priority for permission resolution.
  ///
  /// Higher priority roles take precedence in conflict resolution.
  final int priority;

  /// Maximum number of users that can have this role.
  ///
  /// Set to 0 for unlimited.
  final int? maxAssignments;

  /// When the role was created.
  final DateTime createdAt;

  /// When the role was last updated.
  final DateTime updatedAt;

  /// Additional metadata for the role.
  final Map<String, dynamic> metadata;

  /// Creates a new [Role].
  ///
  /// ## Parameters
  ///
  /// - [id]: Unique identifier (auto-generated if null).
  /// - [name]: Role name (required, should be unique).
  /// - [description]: Human-readable description.
  /// - [permissions]: List of permissions for this role.
  /// - [parentRoles]: Names of roles to inherit from.
  /// - [isSystem]: Whether this is a system role.
  /// - [isActive]: Whether the role is active.
  /// - [priority]: Permission resolution priority.
  /// - [maxAssignments]: Maximum number of assignments.
  /// - [createdAt]: Creation timestamp.
  /// - [updatedAt]: Last update timestamp.
  /// - [metadata]: Additional data.
  Role({
    this.id,
    required this.name,
    this.description,
    List<Permission>? permissions,
    List<String>? parentRoles,
    this.isSystem = false,
    this.isActive = true,
    this.priority = 0,
    this.maxAssignments,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) : permissions = permissions ?? const [],
       parentRoles = parentRoles ?? const [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       metadata = metadata ?? const {};

  /// Creates a system role.
  ///
  /// System roles are protected from deletion.
  factory Role.system({
    String? id,
    required String name,
    String? description,
    required List<Permission> permissions,
    List<String>? parentRoles,
    int priority = 100,
  }) {
    return Role(
      id: id,
      name: name,
      description: description,
      permissions: permissions,
      parentRoles: parentRoles,
      isSystem: true,
      priority: priority,
    );
  }

  /// Converts this role to a map for storage.
  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'permissions': permissions.map((p) => p.toMap()).toList(),
      if (parentRoles.isNotEmpty) 'parentRoles': parentRoles,
      'isSystem': isSystem,
      'isActive': isActive,
      'priority': priority,
      if (maxAssignments != null) 'maxAssignments': maxAssignments,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  /// Creates a [Role] from a stored map.
  factory Role.fromMap(String id, Map<String, dynamic> map) {
    return Role(
      id: id,
      name: map['name'] as String,
      description: map['description'] as String?,
      permissions: _parsePermissions(map['permissions']),
      parentRoles: _parseStringList(map['parentRoles']),
      isSystem: (map['isSystem'] as bool?) ?? false,
      isActive: (map['isActive'] as bool?) ?? true,
      priority: (map['priority'] as int?) ?? 0,
      maxAssignments: map['maxAssignments'] as int?,
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
      metadata: _parseMetadata(map['metadata']),
    );
  }

  /// Parses permissions from storage.
  static List<Permission> _parsePermissions(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];

    return value
        .whereType<Map<String, dynamic>>()
        .map(Permission.fromMap)
        .toList();
  }

  /// Parses a string list from storage.
  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Parses a DateTime from storage.
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  /// Parses metadata from storage.
  static Map<String, dynamic> _parseMetadata(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  /// Checks if this role has a specific permission directly.
  ///
  /// This does not check inherited permissions.
  bool hasPermission(Permission permission) {
    return permissions.any((p) => p.implies(permission));
  }

  /// Gets the permission set for this role.
  PermissionSet get permissionSet => PermissionSet(permissions);

  /// Creates a copy with modified fields.
  Role copyWith({
    String? id,
    String? name,
    String? description,
    List<Permission>? permissions,
    List<String>? parentRoles,
    bool? isSystem,
    bool? isActive,
    int? priority,
    int? maxAssignments,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return Role(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      permissions: permissions ?? List.from(this.permissions),
      parentRoles: parentRoles ?? List.from(this.parentRoles),
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      maxAssignments: maxAssignments ?? this.maxAssignments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? Map.from(this.metadata),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Role) return false;
    return id == other.id && name == other.name;
  }

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() {
    return 'Role(name: $name, permissions: ${permissions.length}, '
        'isSystem: $isSystem, isActive: $isActive)';
  }
}

/// Predefined system roles.
///
/// These roles are automatically created during [RoleManager] initialization.
abstract final class SystemRoles {
  /// Super administrator with full access.
  static final Role superAdmin = Role.system(
    name: 'super_admin',
    description: 'Full system access with all permissions',
    permissions: [Permissions.superAdmin],
    priority: 1000,
  );

  /// Administrator with management access.
  static final Role admin = Role.system(
    name: 'admin',
    description: 'Administrative access for system management',
    permissions: [
      Permissions.adminAll,
      Permissions.userManage,
      Permissions.backupManage,
    ],
    parentRoles: ['user'],
    priority: 500,
  );

  /// Standard user with basic access.
  static final Role user = Role.system(
    name: 'user',
    description: 'Standard user with basic document access',
    permissions: [
      Permissions.documentRead,
      Permissions.documentCreate,
      Permissions.documentUpdate,
      Permissions.documentDelete,
      Permissions.collectionRead,
    ],
    priority: 100,
  );

  /// Read-only guest access.
  static final Role guest = Role.system(
    name: 'guest',
    description: 'Read-only access to public resources',
    permissions: [Permissions.documentRead, Permissions.collectionRead],
    priority: 10,
  );

  /// Transaction manager with transaction permissions.
  static final Role transactionManager = Role.system(
    name: 'transaction_manager',
    description: 'Permissions for transaction operations',
    permissions: [
      Permissions.transactionStart,
      Permissions.transactionCommit,
      Permissions.transactionRollback,
    ],
    priority: 200,
  );

  /// All system roles.
  static List<Role> get all => [
    superAdmin,
    admin,
    user,
    guest,
    transactionManager,
  ];

  /// Gets a system role by name.
  static Role? byName(String name) {
    try {
      return all.firstWhere((r) => r.name == name);
    } catch (e) {
      return null;
    }
  }
}
