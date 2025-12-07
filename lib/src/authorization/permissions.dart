/// EntiDB Permission Module
///
/// Provides a comprehensive permission system with resource-based access control,
/// scoped permissions, and hierarchical permission inheritance.
///
/// ## Overview
///
/// Permissions in EntiDB are structured as:
///
/// ```
/// resource:action[:scope]
/// ```
///
/// Examples:
/// - `document:read` - Read any document
/// - `document:write:own` - Write only own documents
/// - `admin:*` - All admin actions (wildcard)
///
/// ## Permission Types
///
/// - **Action Permissions**: Basic CRUD operations
/// - **Resource Permissions**: Scoped to specific resources
/// - **Wildcard Permissions**: Match multiple actions/resources
///
/// ## Quick Start
///
/// ```dart
/// import 'package:entidb/src/authorization/permissions.dart';
///
/// // Create permissions
/// final readDocs = Permission.action(Action.read, Resource.document);
/// final adminAll = Permission.wildcard(Resource.admin);
///
/// // Check if one permission implies another
/// if (adminAll.implies(readDocs)) {
///   print('Admin can read documents');
/// }
/// ```
library;

import 'package:meta/meta.dart';

/// Standard actions that can be performed on resources.
///
/// These represent the fundamental operations in a CRUD system
/// plus additional database-specific operations.
enum Action {
  /// Create new resources.
  create,

  /// Read/view resources.
  read,

  /// Update existing resources.
  update,

  /// Delete resources.
  delete,

  /// Full write access (create + update + delete).
  write,

  /// Execute operations (for stored procedures, etc.).
  execute,

  /// Manage resource configuration.
  manage,

  /// Full administrative access.
  admin,

  /// Start a transaction.
  startTransaction,

  /// Commit a transaction.
  commitTransaction,

  /// Rollback a transaction.
  rollbackTransaction,

  /// All actions (wildcard).
  all,
}

/// Extension methods for [Action].
extension ActionExtension on Action {
  /// Returns the string representation for storage.
  String get value {
    switch (this) {
      case Action.create:
        return 'create';
      case Action.read:
        return 'read';
      case Action.update:
        return 'update';
      case Action.delete:
        return 'delete';
      case Action.write:
        return 'write';
      case Action.execute:
        return 'execute';
      case Action.manage:
        return 'manage';
      case Action.admin:
        return 'admin';
      case Action.startTransaction:
        return 'start_transaction';
      case Action.commitTransaction:
        return 'commit_transaction';
      case Action.rollbackTransaction:
        return 'rollback_transaction';
      case Action.all:
        return '*';
    }
  }

  /// Parses an action from its string representation.
  static Action fromString(String value) {
    switch (value.toLowerCase()) {
      case 'create':
        return Action.create;
      case 'read':
        return Action.read;
      case 'update':
        return Action.update;
      case 'delete':
        return Action.delete;
      case 'write':
        return Action.write;
      case 'execute':
        return Action.execute;
      case 'manage':
        return Action.manage;
      case 'admin':
        return Action.admin;
      case 'start_transaction':
        return Action.startTransaction;
      case 'commit_transaction':
        return Action.commitTransaction;
      case 'rollback_transaction':
        return Action.rollbackTransaction;
      case '*':
        return Action.all;
      default:
        throw ArgumentError('Unknown action: $value');
    }
  }

  /// Checks if this action implies another action.
  ///
  /// For example, [Action.write] implies [Action.create], [Action.update],
  /// and [Action.delete].
  bool implies(Action other) {
    if (this == Action.all) return true;
    if (this == other) return true;

    // Write implies create, update, delete
    if (this == Action.write) {
      return other == Action.create ||
          other == Action.update ||
          other == Action.delete;
    }

    // Admin implies all
    if (this == Action.admin) return true;

    return false;
  }
}

/// Standard resources in the system.
///
/// Resources represent the entities or areas that can be accessed.
enum Resource {
  /// Document/entity operations.
  document,

  /// Collection operations.
  collection,

  /// Index operations.
  indexResource,

  /// User management.
  user,

  /// Role management.
  role,

  /// Transaction operations.
  transaction,

  /// Backup operations.
  backup,

  /// System configuration.
  system,

  /// Administrative operations.
  admin,

  /// All resources (wildcard).
  all,
}

/// Extension methods for [Resource].
extension ResourceExtension on Resource {
  /// Returns the string representation for storage.
  String get value {
    switch (this) {
      case Resource.document:
        return 'document';
      case Resource.collection:
        return 'collection';
      case Resource.indexResource:
        return 'index';
      case Resource.user:
        return 'user';
      case Resource.role:
        return 'role';
      case Resource.transaction:
        return 'transaction';
      case Resource.backup:
        return 'backup';
      case Resource.system:
        return 'system';
      case Resource.admin:
        return 'admin';
      case Resource.all:
        return '*';
    }
  }

  /// Parses a resource from its string representation.
  static Resource fromString(String value) {
    switch (value.toLowerCase()) {
      case 'document':
        return Resource.document;
      case 'collection':
        return Resource.collection;
      case 'index':
        return Resource.indexResource;
      case 'user':
        return Resource.user;
      case 'role':
        return Resource.role;
      case 'transaction':
        return Resource.transaction;
      case 'backup':
        return Resource.backup;
      case 'system':
        return Resource.system;
      case 'admin':
        return Resource.admin;
      case '*':
        return Resource.all;
      default:
        throw ArgumentError('Unknown resource: $value');
    }
  }
}

/// Scope modifiers for permissions.
///
/// Scopes restrict permissions to specific contexts.
enum PermissionScope {
  /// No scope restriction (full access).
  none,

  /// Only own resources.
  own,

  /// Only resources in same group/team.
  group,

  /// Only resources in same organization.
  organization,

  /// Inherited from parent.
  inherited,
}

/// Extension methods for [PermissionScope].
extension PermissionScopeExtension on PermissionScope {
  /// Returns the string representation for storage.
  String get value {
    switch (this) {
      case PermissionScope.none:
        return '';
      case PermissionScope.own:
        return 'own';
      case PermissionScope.group:
        return 'group';
      case PermissionScope.organization:
        return 'organization';
      case PermissionScope.inherited:
        return 'inherited';
    }
  }

  /// Parses a scope from its string representation.
  static PermissionScope fromString(String value) {
    switch (value.toLowerCase()) {
      case '':
      case 'none':
        return PermissionScope.none;
      case 'own':
        return PermissionScope.own;
      case 'group':
        return PermissionScope.group;
      case 'organization':
        return PermissionScope.organization;
      case 'inherited':
        return PermissionScope.inherited;
      default:
        return PermissionScope.none;
    }
  }
}

/// Represents a permission in the system.
///
/// Permissions are structured as `resource:action[:scope]` and support:
/// - Wildcards for actions or resources
/// - Scoped permissions for fine-grained access
/// - Permission implication checking
///
/// ## Examples
///
/// ```dart
/// // Basic permission
/// final readDocs = Permission.action(Action.read, Resource.document);
///
/// // Scoped permission
/// final writeOwn = Permission.scoped(
///   Action.write,
///   Resource.document,
///   PermissionScope.own,
/// );
///
/// // Wildcard permission
/// final adminAll = Permission.wildcard(Resource.admin);
///
/// // From string
/// final perm = Permission.parse('document:read:own');
/// ```
@immutable
class Permission {
  /// The action this permission grants.
  final Action action;

  /// The resource this permission applies to.
  final Resource resource;

  /// Optional scope restriction.
  final PermissionScope scope;

  /// Optional custom resource name for non-standard resources.
  final String? customResource;

  /// Creates a new [Permission].
  const Permission({
    required this.action,
    required this.resource,
    this.scope = PermissionScope.none,
    this.customResource,
  });

  /// Creates a permission for a specific action on a resource.
  const Permission.action(this.action, this.resource)
    : scope = PermissionScope.none,
      customResource = null;

  /// Creates a scoped permission.
  const Permission.scoped(this.action, this.resource, this.scope)
    : customResource = null;

  /// Creates a wildcard permission for all actions on a resource.
  const Permission.wildcard(this.resource)
    : action = Action.all,
      scope = PermissionScope.none,
      customResource = null;

  /// Creates a permission for a custom resource name.
  Permission.custom({
    required this.action,
    required String resource,
    this.scope = PermissionScope.none,
  }) : resource = Resource.all,
       customResource = resource;

  /// Parses a permission from its string representation.
  ///
  /// Format: `resource:action[:scope]`
  ///
  /// ## Examples
  ///
  /// - `document:read` → Read documents
  /// - `document:write:own` → Write own documents
  /// - `admin:*` → All admin actions
  /// - `*:*` → All permissions
  factory Permission.parse(String value) {
    final parts = value.split(':');
    if (parts.length < 2) {
      throw ArgumentError('Invalid permission format: $value');
    }

    final resourceStr = parts[0];
    final actionStr = parts[1];
    final scopeStr = parts.length > 2 ? parts[2] : '';

    Resource resource;
    String? customResource;
    try {
      resource = ResourceExtension.fromString(resourceStr);
    } catch (e) {
      // Custom resource
      resource = Resource.all;
      customResource = resourceStr;
    }

    return Permission(
      action: ActionExtension.fromString(actionStr),
      resource: resource,
      scope: PermissionScopeExtension.fromString(scopeStr),
      customResource: customResource,
    );
  }

  /// Gets the effective resource name.
  String get resourceName => customResource ?? resource.value;

  /// Checks if this permission implies (grants) another permission.
  ///
  /// A permission A implies permission B if having A means you also have B.
  ///
  /// ## Rules
  ///
  /// 1. Wildcard action (`*`) implies all actions
  /// 2. Wildcard resource (`*`) implies all resources
  /// 3. Broader scope implies narrower scope
  /// 4. [Action.write] implies create/update/delete
  bool implies(Permission other) {
    // Check resource match
    if (resource != Resource.all && resource != other.resource) {
      if (customResource != null && customResource != other.customResource) {
        return false;
      }
      if (customResource == null) {
        return false;
      }
    }

    // Check action match
    if (!action.implies(other.action)) {
      return false;
    }

    // Check scope - broader scopes imply narrower ones
    if (scope != PermissionScope.none) {
      // If this permission has a scope, it only implies same or narrower scopes
      if (other.scope == PermissionScope.none) {
        return false; // Cannot grant unscoped with scoped
      }
      // Own < Group < Organization
      final scopeOrder = {
        PermissionScope.own: 1,
        PermissionScope.group: 2,
        PermissionScope.organization: 3,
        PermissionScope.none: 4,
      };
      if ((scopeOrder[scope] ?? 0) < (scopeOrder[other.scope] ?? 0)) {
        return false;
      }
    }

    return true;
  }

  /// Converts to string representation.
  ///
  /// Format: `resource:action[:scope]`
  @override
  String toString() {
    final parts = [resourceName, action.value];
    if (scope != PermissionScope.none) {
      parts.add(scope.value);
    }
    return parts.join(':');
  }

  /// Converts to a map for storage.
  Map<String, dynamic> toMap() {
    return {
      'action': action.value,
      'resource': resource.value,
      if (customResource != null) 'customResource': customResource,
      if (scope != PermissionScope.none) 'scope': scope.value,
    };
  }

  /// Creates a permission from a stored map.
  factory Permission.fromMap(Map<String, dynamic> map) {
    return Permission(
      action: ActionExtension.fromString(map['action'] as String),
      resource: ResourceExtension.fromString(map['resource'] as String),
      scope: PermissionScopeExtension.fromString(
        (map['scope'] as String?) ?? '',
      ),
      customResource: map['customResource'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Permission) return false;
    return action == other.action &&
        resource == other.resource &&
        scope == other.scope &&
        customResource == other.customResource;
  }

  @override
  int get hashCode => Object.hash(action, resource, scope, customResource);
}

/// A set of common/built-in permissions.
///
/// Provides quick access to frequently used permissions.
abstract final class Permissions {
  // Document permissions
  static const Permission documentCreate = Permission.action(
    Action.create,
    Resource.document,
  );
  static const Permission documentRead = Permission.action(
    Action.read,
    Resource.document,
  );
  static const Permission documentUpdate = Permission.action(
    Action.update,
    Resource.document,
  );
  static const Permission documentDelete = Permission.action(
    Action.delete,
    Resource.document,
  );
  static const Permission documentWrite = Permission.action(
    Action.write,
    Resource.document,
  );
  static const Permission documentAll = Permission.wildcard(Resource.document);

  // Collection permissions
  static const Permission collectionCreate = Permission.action(
    Action.create,
    Resource.collection,
  );
  static const Permission collectionRead = Permission.action(
    Action.read,
    Resource.collection,
  );
  static const Permission collectionManage = Permission.action(
    Action.manage,
    Resource.collection,
  );
  static const Permission collectionAll = Permission.wildcard(
    Resource.collection,
  );

  // User permissions
  static const Permission userCreate = Permission.action(
    Action.create,
    Resource.user,
  );
  static const Permission userRead = Permission.action(
    Action.read,
    Resource.user,
  );
  static const Permission userUpdate = Permission.action(
    Action.update,
    Resource.user,
  );
  static const Permission userDelete = Permission.action(
    Action.delete,
    Resource.user,
  );
  static const Permission userManage = Permission.action(
    Action.manage,
    Resource.user,
  );

  // Transaction permissions
  static const Permission transactionStart = Permission.action(
    Action.startTransaction,
    Resource.transaction,
  );
  static const Permission transactionCommit = Permission.action(
    Action.commitTransaction,
    Resource.transaction,
  );
  static const Permission transactionRollback = Permission.action(
    Action.rollbackTransaction,
    Resource.transaction,
  );
  static const Permission transactionAll = Permission.wildcard(
    Resource.transaction,
  );

  // Backup permissions
  static const Permission backupCreate = Permission.action(
    Action.create,
    Resource.backup,
  );
  static const Permission backupRead = Permission.action(
    Action.read,
    Resource.backup,
  );
  static const Permission backupManage = Permission.action(
    Action.manage,
    Resource.backup,
  );

  // Admin permissions
  static const Permission adminAll = Permission.wildcard(Resource.admin);
  static const Permission systemAll = Permission.wildcard(Resource.system);
  static const Permission superAdmin = Permission.action(
    Action.all,
    Resource.all,
  );

  /// Gets all standard permissions as a list.
  static List<Permission> get all => [
    documentCreate,
    documentRead,
    documentUpdate,
    documentDelete,
    documentWrite,
    documentAll,
    collectionCreate,
    collectionRead,
    collectionManage,
    collectionAll,
    userCreate,
    userRead,
    userUpdate,
    userDelete,
    userManage,
    transactionStart,
    transactionCommit,
    transactionRollback,
    transactionAll,
    backupCreate,
    backupRead,
    backupManage,
    adminAll,
    systemAll,
    superAdmin,
  ];
}

/// A collection of permissions that can be checked together.
@immutable
class PermissionSet {
  /// The permissions in this set.
  final Set<Permission> _permissions;

  /// Creates a new [PermissionSet] from a list of permissions.
  PermissionSet(Iterable<Permission> permissions)
    : _permissions = Set.unmodifiable(permissions.toSet());

  /// Creates an empty permission set.
  const PermissionSet.empty() : _permissions = const {};

  /// Creates a permission set from string representations.
  factory PermissionSet.parse(Iterable<String> permissions) {
    return PermissionSet(permissions.map(Permission.parse));
  }

  /// The number of permissions in this set.
  int get length => _permissions.length;

  /// Whether this set is empty.
  bool get isEmpty => _permissions.isEmpty;

  /// Whether this set is not empty.
  bool get isNotEmpty => _permissions.isNotEmpty;

  /// All permissions in this set.
  Iterable<Permission> get permissions => _permissions;

  /// Checks if this set contains a specific permission.
  bool contains(Permission permission) => _permissions.contains(permission);

  /// Checks if this set grants a specific permission.
  ///
  /// This checks both exact matches and implications.
  bool grants(Permission required) {
    for (final permission in _permissions) {
      if (permission.implies(required)) {
        return true;
      }
    }
    return false;
  }

  /// Checks if this set grants all of the required permissions.
  bool grantsAll(Iterable<Permission> required) {
    return required.every(grants);
  }

  /// Checks if this set grants any of the required permissions.
  bool grantsAny(Iterable<Permission> required) {
    return required.any(grants);
  }

  /// Returns a new set with the given permissions added.
  PermissionSet add(Permission permission) {
    return PermissionSet({..._permissions, permission});
  }

  /// Returns a new set with the given permissions added.
  PermissionSet addAll(Iterable<Permission> permissions) {
    return PermissionSet({..._permissions, ...permissions});
  }

  /// Returns a new set with the given permission removed.
  PermissionSet remove(Permission permission) {
    return PermissionSet(_permissions.where((p) => p != permission));
  }

  /// Returns the union of this set with another.
  PermissionSet union(PermissionSet other) {
    return PermissionSet({..._permissions, ...other._permissions});
  }

  /// Returns the intersection of this set with another.
  PermissionSet intersection(PermissionSet other) {
    return PermissionSet(
      _permissions.where((p) => other._permissions.contains(p)),
    );
  }

  /// Converts to a list of string representations.
  List<String> toStringList() {
    return _permissions.map((p) => p.toString()).toList();
  }

  /// Converts to a list of maps for storage.
  List<Map<String, dynamic>> toMapList() {
    return _permissions.map((p) => p.toMap()).toList();
  }

  @override
  String toString() => 'PermissionSet(${_permissions.join(", ")})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PermissionSet) return false;
    if (_permissions.length != other._permissions.length) return false;
    return _permissions.containsAll(other._permissions);
  }

  @override
  int get hashCode => Object.hashAll(_permissions);
}
