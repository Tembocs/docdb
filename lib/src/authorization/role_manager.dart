/// DocDB Role Manager Module
///
/// Provides comprehensive role-based access control (RBAC) with role hierarchy,
/// permission inheritance, and integration with the authentication system.
///
/// ## Overview
///
/// The [RoleManager] handles:
///
/// - **Role Management**: CRUD operations for roles
/// - **Permission Resolution**: Resolve effective permissions with inheritance
/// - **Access Control**: Check if users have required permissions
/// - **Role Hierarchy**: Parent-child role relationships
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │                        RoleManager                               │
/// │                                                                  │
/// │  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
/// │  │  Role Registry   │  │ Permission Cache │  │ Inheritance   │  │
/// │  │  (Collection)    │  │    (Memory)      │  │   Resolver    │  │
/// │  └────────┬─────────┘  └────────┬─────────┘  └───────┬───────┘  │
/// │           │                     │                     │          │
/// │           └─────────────────────┴─────────────────────┘          │
/// │                                 │                                │
/// │                                 ▼                                │
/// │  ┌─────────────────────────────────────────────────────────────┐ │
/// │  │                    Storage<Role>                            │ │
/// │  └─────────────────────────────────────────────────────────────┘ │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/authorization/role_manager.dart';
///
/// // Create with storage
/// final roleStorage = MemoryStorage<Role>(name: 'roles');
/// await roleStorage.open();
///
/// final roleManager = RoleManager(storage: roleStorage);
/// await roleManager.initialize();
///
/// // Define a custom role
/// await roleManager.defineRole(Role(
///   name: 'editor',
///   description: 'Content editor',
///   permissions: [
///     Permission.action(Action.write, Resource.document),
///   ],
///   parentRoles: ['user'],
/// ));
///
/// // Check permissions
/// final userRoles = ['editor'];
/// if (roleManager.hasPermission(userRoles, Permissions.documentWrite)) {
///   print('User can write documents');
/// }
/// ```
library;

import 'dart:async';

import 'package:synchronized/synchronized.dart';

import '../collection/collection.dart';
import '../exceptions/exceptions.dart';
import '../index/i_index.dart';
import '../logger/logger.dart';
import '../query/query.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'permissions.dart';
import 'roles.dart';

/// Configuration for the [RoleManager].
class RoleManagerConfig {
  /// Whether to cache resolved permissions.
  final bool enablePermissionCache;

  /// Cache TTL for resolved permissions.
  final Duration cacheTtl;

  /// Whether to create default system roles on initialization.
  final bool createDefaultRoles;

  /// Maximum depth for role inheritance resolution.
  final int maxInheritanceDepth;

  /// Creates a new [RoleManagerConfig].
  const RoleManagerConfig({
    this.enablePermissionCache = true,
    this.cacheTtl = const Duration(minutes: 5),
    this.createDefaultRoles = true,
    this.maxInheritanceDepth = 10,
  });

  /// Development configuration.
  static const RoleManagerConfig development = RoleManagerConfig(
    enablePermissionCache: false,
    createDefaultRoles: true,
    maxInheritanceDepth: 10,
  );

  /// Production configuration.
  static const RoleManagerConfig production = RoleManagerConfig(
    enablePermissionCache: true,
    cacheTtl: Duration(minutes: 10),
    createDefaultRoles: true,
    maxInheritanceDepth: 10,
  );
}

/// Result of a permission check.
class PermissionCheckResult {
  /// Whether permission was granted.
  final bool granted;

  /// The permission that was checked.
  final Permission permission;

  /// The role that granted the permission (if granted).
  final String? grantingRole;

  /// Reason for denial (if denied).
  final String? denialReason;

  /// Creates a new [PermissionCheckResult].
  const PermissionCheckResult({
    required this.granted,
    required this.permission,
    this.grantingRole,
    this.denialReason,
  });

  /// Creates a granted result.
  const PermissionCheckResult.granted({
    required this.permission,
    required this.grantingRole,
  }) : granted = true,
       denialReason = null;

  /// Creates a denied result.
  const PermissionCheckResult.denied({
    required this.permission,
    required this.denialReason,
  }) : granted = false,
       grantingRole = null;

  @override
  String toString() {
    if (granted) {
      return 'PermissionCheckResult.granted(permission: $permission, grantingRole: $grantingRole)';
    }
    return 'PermissionCheckResult.denied(permission: $permission, reason: $denialReason)';
  }
}

/// Cached permission entry.
class _CacheEntry {
  final PermissionSet permissions;
  final DateTime expiresAt;

  _CacheEntry(this.permissions, Duration ttl)
    : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Manages roles and permissions for the authorization system.
///
/// [RoleManager] provides RBAC with support for role hierarchies,
/// permission inheritance, and caching.
///
/// ## Thread Safety
///
/// All public methods are thread-safe.
///
/// ## Example
///
/// ```dart
/// final roleManager = RoleManager(storage: roleStorage);
/// await roleManager.initialize();
///
/// // Check single permission
/// if (roleManager.hasPermission(['user'], Permissions.documentRead)) {
///   // Allow read
/// }
///
/// // Check multiple permissions
/// final result = roleManager.checkPermissions(
///   ['user', 'editor'],
///   [Permissions.documentWrite, Permissions.documentDelete],
/// );
/// if (result.allGranted) {
///   // Allow action
/// }
/// ```
class RoleManager {
  /// Role collection for persistence.
  final Collection<Role>? _roles;

  /// In-memory role registry (for non-persistent mode).
  final Map<String, Role> _roleRegistry = {};

  /// Permission cache.
  final Map<String, _CacheEntry> _permissionCache = {};

  /// Configuration.
  final RoleManagerConfig _config;

  /// Logger.
  final DocDBLogger _logger;

  /// Lock for role operations.
  final Lock _lock = Lock();

  /// Whether the manager has been initialized.
  bool _initialized = false;

  /// Creates a [RoleManager] with persistent storage.
  ///
  /// ## Parameters
  ///
  /// - [storage]: Storage backend for roles.
  /// - [config]: Role manager configuration.
  RoleManager({
    required Storage<Role> storage,
    RoleManagerConfig config = const RoleManagerConfig(),
  }) : _roles = Collection<Role>(
         storage: storage,
         fromMap: Role.fromMap,
         name: 'roles',
       ),
       _config = config,
       _logger = DocDBLogger(LoggerNameConstants.authorization);

  /// Creates a [RoleManager] that operates in memory only.
  ///
  /// Use this for testing or simple applications that don't need
  /// persistent role storage.
  RoleManager.inMemory({RoleManagerConfig config = const RoleManagerConfig()})
    : _roles = null,
      _config = config,
      _logger = DocDBLogger(LoggerNameConstants.authorization);

  /// Whether the manager has been initialized.
  bool get isInitialized => _initialized;

  /// The configuration.
  RoleManagerConfig get config => _config;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes the role manager.
  ///
  /// Creates indexes and optionally adds default system roles.
  Future<void> initialize() async {
    if (_initialized) {
      _logger.warning('RoleManager already initialized.');
      return;
    }

    await _lock.synchronized(() async {
      // Create indexes if using persistent storage
      if (_roles != null) {
        await _roles.createIndex('name', IndexType.hash);
        await _roles.createIndex('isSystem', IndexType.hash);
        await _roles.createIndex('isActive', IndexType.hash);
        _logger.info('Role indexes created.');
      }

      // Create default roles if configured
      if (_config.createDefaultRoles) {
        await _ensureDefaultRoles();
      }

      _initialized = true;
      _logger.info('RoleManager initialized.');
    });
  }

  /// Ensures default system roles exist.
  Future<void> _ensureDefaultRoles() async {
    for (final systemRole in SystemRoles.all) {
      if (!await _roleExists(systemRole.name)) {
        await _insertRole(systemRole);
        _logger.debug('Created system role: ${systemRole.name}');
      }
    }
  }

  /// Checks if a role exists.
  Future<bool> _roleExists(String name) async {
    if (_roles != null) {
      final existing = await _roles.findOne(
        QueryBuilder().whereEquals('name', name).build(),
      );
      return existing != null;
    }
    return _roleRegistry.containsKey(name);
  }

  /// Inserts a role.
  Future<void> _insertRole(Role role) async {
    if (_roles != null) {
      await _roles.insert(role);
    } else {
      _roleRegistry[role.name] = role;
    }
    _invalidateCache();
  }

  /// Ensures the manager is initialized.
  void _checkInitialized() {
    if (!_initialized) {
      throw const AuthorizationException(
        'RoleManager not initialized. Call initialize() first.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Role Management
  // ---------------------------------------------------------------------------

  /// Defines a new role.
  ///
  /// ## Parameters
  ///
  /// - [role]: The role to define.
  ///
  /// ## Throws
  ///
  /// - [RoleAlreadyDefinedException]: If a role with the same name exists.
  /// - [AuthorizationException]: If parent roles don't exist.
  Future<Role> defineRole(Role role) async {
    _checkInitialized();

    return await _lock.synchronized(() async {
      // Validate role name
      _validateRoleName(role.name);

      // Check for existing role
      if (await _roleExists(role.name)) {
        throw RoleAlreadyDefinedException('Role "${role.name}" already exists');
      }

      // Validate parent roles exist
      for (final parent in role.parentRoles) {
        if (!await _roleExists(parent)) {
          throw UndefinedRoleException('Parent role "$parent" does not exist');
        }
      }

      // Check for circular inheritance
      await _checkCircularInheritance(role.name, role.parentRoles);

      await _insertRole(role);
      _logger.info('Defined role: ${role.name}');

      return role;
    });
  }

  /// Validates role name format.
  void _validateRoleName(String name) {
    if (name.isEmpty) {
      throw const AuthorizationException('Role name cannot be empty');
    }
    if (name.length > 50) {
      throw const AuthorizationException(
        'Role name cannot exceed 50 characters',
      );
    }
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw const AuthorizationException(
        'Role name must start with a lowercase letter and contain only '
        'lowercase letters, numbers, and underscores',
      );
    }
  }

  /// Checks for circular inheritance.
  Future<void> _checkCircularInheritance(
    String roleName,
    List<String> parentRoles,
  ) async {
    final visited = <String>{roleName};

    Future<void> check(List<String> parents, int depth) async {
      if (depth > _config.maxInheritanceDepth) {
        throw AuthorizationException(
          'Maximum inheritance depth (${_config.maxInheritanceDepth}) exceeded',
        );
      }

      for (final parent in parents) {
        if (visited.contains(parent)) {
          throw AuthorizationException(
            'Circular inheritance detected: $parent',
          );
        }

        visited.add(parent);
        final parentRole = await _getRole(parent);
        if (parentRole != null && parentRole.parentRoles.isNotEmpty) {
          await check(parentRole.parentRoles, depth + 1);
        }
      }
    }

    await check(parentRoles, 1);
  }

  /// Gets a role by name.
  Future<Role?> _getRole(String name) async {
    if (_roles != null) {
      return await _roles.findOne(
        QueryBuilder().whereEquals('name', name).build(),
      );
    }
    return _roleRegistry[name];
  }

  /// Gets a role by name.
  ///
  /// ## Parameters
  ///
  /// - [name]: The role name.
  ///
  /// ## Returns
  ///
  /// The [Role] or `null` if not found.
  Future<Role?> getRole(String name) async {
    _checkInitialized();
    return _getRole(name);
  }

  /// Gets all defined roles.
  ///
  /// ## Parameters
  ///
  /// - [includeInactive]: Whether to include inactive roles.
  ///
  /// ## Returns
  ///
  /// List of all roles.
  Future<List<Role>> getAllRoles({bool includeInactive = false}) async {
    _checkInitialized();

    if (_roles != null) {
      if (includeInactive) {
        return _roles.getAll();
      }
      return _roles.find(QueryBuilder().whereEquals('isActive', true).build());
    }

    if (includeInactive) {
      return _roleRegistry.values.toList();
    }
    return _roleRegistry.values.where((r) => r.isActive).toList();
  }

  /// Updates an existing role.
  ///
  /// ## Parameters
  ///
  /// - [role]: The updated role.
  ///
  /// ## Throws
  ///
  /// - [UndefinedRoleException]: If the role doesn't exist.
  /// - [AuthorizationException]: If trying to modify a system role improperly.
  Future<Role> updateRole(Role role) async {
    _checkInitialized();

    return await _lock.synchronized(() async {
      final existing = await _getRole(role.name);
      if (existing == null) {
        throw UndefinedRoleException('Role "${role.name}" does not exist');
      }

      // Protect system role properties
      if (existing.isSystem) {
        if (role.isActive != existing.isActive) {
          throw const AuthorizationException('Cannot deactivate a system role');
        }
      }

      // Validate parent roles
      for (final parent in role.parentRoles) {
        if (!await _roleExists(parent)) {
          throw UndefinedRoleException('Parent role "$parent" does not exist');
        }
      }

      // Check for circular inheritance
      await _checkCircularInheritance(role.name, role.parentRoles);

      final updated = role.copyWith(updatedAt: DateTime.now());

      if (_roles != null) {
        await _roles.update(updated);
      } else {
        _roleRegistry[role.name] = updated;
      }

      _invalidateCache();
      _logger.info('Updated role: ${role.name}');

      return updated;
    });
  }

  /// Deletes a role.
  ///
  /// ## Parameters
  ///
  /// - [name]: The role name to delete.
  ///
  /// ## Returns
  ///
  /// `true` if the role was deleted.
  ///
  /// ## Throws
  ///
  /// - [AuthorizationException]: If trying to delete a system role.
  Future<bool> deleteRole(String name) async {
    _checkInitialized();

    return await _lock.synchronized(() async {
      final role = await _getRole(name);
      if (role == null) {
        return false;
      }

      if (role.isSystem) {
        throw const AuthorizationException('Cannot delete a system role');
      }

      if (_roles != null) {
        await _roles.delete(role.id!);
      } else {
        _roleRegistry.remove(name);
      }

      _invalidateCache();
      _logger.info('Deleted role: $name');

      return true;
    });
  }

  /// Checks if a role is defined.
  ///
  /// ## Parameters
  ///
  /// - [name]: The role name to check.
  ///
  /// ## Returns
  ///
  /// `true` if the role exists.
  bool isRoleDefined(String name) {
    if (!_initialized) return false;

    if (_roles != null) {
      // For persistent storage, check synchronously from cache if possible
      // This is a limitation - consider making this async
      return _roleRegistry.containsKey(name) ||
          SystemRoles.byName(name) != null;
    }
    return _roleRegistry.containsKey(name);
  }

  /// Async version of role existence check.
  Future<bool> isRoleDefinedAsync(String name) async {
    _checkInitialized();
    return _roleExists(name);
  }

  // ---------------------------------------------------------------------------
  // Permission Resolution
  // ---------------------------------------------------------------------------

  /// Gets all permissions for the given roles.
  ///
  /// Resolves inheritance and combines all permissions.
  ///
  /// ## Parameters
  ///
  /// - [roleNames]: List of role names.
  ///
  /// ## Returns
  ///
  /// Combined [PermissionSet] from all roles.
  Future<PermissionSet> getPermissions(List<String> roleNames) async {
    _checkInitialized();

    // Check cache
    final cacheKey = roleNames.toSet().join(',');
    if (_config.enablePermissionCache) {
      final cached = _permissionCache[cacheKey];
      if (cached != null && !cached.isExpired) {
        return cached.permissions;
      }
    }

    // Resolve permissions
    final allPermissions = <Permission>{};
    final visited = <String>{};

    Future<void> resolveRole(String roleName) async {
      if (visited.contains(roleName)) return;
      visited.add(roleName);

      final role = await _getRole(roleName);
      if (role == null || !role.isActive) return;

      allPermissions.addAll(role.permissions);

      // Resolve parent roles
      for (final parent in role.parentRoles) {
        await resolveRole(parent);
      }
    }

    for (final roleName in roleNames) {
      await resolveRole(roleName);
    }

    final permissionSet = PermissionSet(allPermissions);

    // Cache result
    if (_config.enablePermissionCache) {
      _permissionCache[cacheKey] = _CacheEntry(permissionSet, _config.cacheTtl);
    }

    return permissionSet;
  }

  /// Synchronous permission retrieval for simple cases.
  ///
  /// Note: This only works with in-memory mode or after roles are cached.
  List<Permission> getPermissionsSync(List<String> roleNames) {
    final allPermissions = <Permission>{};
    final visited = <String>{};

    void resolveRole(String roleName) {
      if (visited.contains(roleName)) return;
      visited.add(roleName);

      final role = _roleRegistry[roleName];
      if (role == null || !role.isActive) return;

      allPermissions.addAll(role.permissions);

      for (final parent in role.parentRoles) {
        resolveRole(parent);
      }
    }

    for (final roleName in roleNames) {
      resolveRole(roleName);
    }

    return allPermissions.toList();
  }

  // ---------------------------------------------------------------------------
  // Permission Checking
  // ---------------------------------------------------------------------------

  /// Checks if the user with the given roles has a specific permission.
  ///
  /// ## Parameters
  ///
  /// - [userRoles]: List of role names assigned to the user.
  /// - [permission]: The permission to check.
  ///
  /// ## Returns
  ///
  /// `true` if the permission is granted.
  bool hasPermission(List<String> userRoles, Permission permission) {
    if (!_initialized) return false;

    // Use sync method for in-memory mode
    final permissions = getPermissionsSync(userRoles);
    return PermissionSet(permissions).grants(permission);
  }

  /// Async version of permission check.
  Future<bool> hasPermissionAsync(
    List<String> userRoles,
    Permission permission,
  ) async {
    _checkInitialized();

    final permissions = await getPermissions(userRoles);
    return permissions.grants(permission);
  }

  /// Checks a permission and returns detailed result.
  ///
  /// ## Parameters
  ///
  /// - [userRoles]: List of role names.
  /// - [permission]: The permission to check.
  ///
  /// ## Returns
  ///
  /// A [PermissionCheckResult] with details.
  Future<PermissionCheckResult> checkPermission(
    List<String> userRoles,
    Permission permission,
  ) async {
    _checkInitialized();

    if (userRoles.isEmpty) {
      return PermissionCheckResult.denied(
        permission: permission,
        denialReason: 'No roles assigned',
      );
    }

    final visited = <String>{};

    Future<String?> findGrantingRole(String roleName) async {
      if (visited.contains(roleName)) return null;
      visited.add(roleName);

      final role = await _getRole(roleName);
      if (role == null || !role.isActive) return null;

      if (role.hasPermission(permission)) {
        return roleName;
      }

      for (final parent in role.parentRoles) {
        final grantingParent = await findGrantingRole(parent);
        if (grantingParent != null) return grantingParent;
      }

      return null;
    }

    for (final roleName in userRoles) {
      final grantingRole = await findGrantingRole(roleName);
      if (grantingRole != null) {
        return PermissionCheckResult.granted(
          permission: permission,
          grantingRole: grantingRole,
        );
      }
    }

    return PermissionCheckResult.denied(
      permission: permission,
      denialReason: 'No role grants this permission',
    );
  }

  /// Checks multiple permissions at once.
  ///
  /// ## Parameters
  ///
  /// - [userRoles]: List of role names.
  /// - [permissions]: The permissions to check.
  ///
  /// ## Returns
  ///
  /// A [MultiPermissionCheckResult] with all results.
  Future<MultiPermissionCheckResult> checkPermissions(
    List<String> userRoles,
    List<Permission> permissions,
  ) async {
    _checkInitialized();

    final results = <PermissionCheckResult>[];

    for (final permission in permissions) {
      results.add(await checkPermission(userRoles, permission));
    }

    return MultiPermissionCheckResult(results);
  }

  /// Checks if the user has all required permissions.
  Future<bool> hasAllPermissions(
    List<String> userRoles,
    List<Permission> permissions,
  ) async {
    _checkInitialized();

    final permSet = await getPermissions(userRoles);
    return permSet.grantsAll(permissions);
  }

  /// Checks if the user has any of the required permissions.
  Future<bool> hasAnyPermission(
    List<String> userRoles,
    List<Permission> permissions,
  ) async {
    _checkInitialized();

    final permSet = await getPermissions(userRoles);
    return permSet.grantsAny(permissions);
  }

  // ---------------------------------------------------------------------------
  // Role Assignment Helpers
  // ---------------------------------------------------------------------------

  /// Gets all roles that would grant a specific permission.
  ///
  /// ## Parameters
  ///
  /// - [permission]: The permission to find roles for.
  ///
  /// ## Returns
  ///
  /// List of role names that grant this permission.
  Future<List<String>> getRolesWithPermission(Permission permission) async {
    _checkInitialized();

    final allRoles = await getAllRoles();
    final matchingRoles = <String>[];

    for (final role in allRoles) {
      if (role.hasPermission(permission)) {
        matchingRoles.add(role.name);
      }
    }

    return matchingRoles;
  }

  /// Gets the inheritance chain for a role.
  ///
  /// ## Parameters
  ///
  /// - [roleName]: The role to trace.
  ///
  /// ## Returns
  ///
  /// List of role names in the inheritance chain.
  Future<List<String>> getInheritanceChain(String roleName) async {
    _checkInitialized();

    final chain = <String>[];
    final visited = <String>{};

    Future<void> trace(String name) async {
      if (visited.contains(name)) return;
      visited.add(name);
      chain.add(name);

      final role = await _getRole(name);
      if (role != null) {
        for (final parent in role.parentRoles) {
          await trace(parent);
        }
      }
    }

    await trace(roleName);
    return chain;
  }

  // ---------------------------------------------------------------------------
  // Cache Management
  // ---------------------------------------------------------------------------

  /// Invalidates the permission cache.
  void _invalidateCache() {
    _permissionCache.clear();
    _logger.debug('Permission cache invalidated.');
  }

  /// Clears the permission cache.
  void clearCache() {
    _permissionCache.clear();
    _logger.info('Permission cache cleared.');
  }

  /// Cleans up expired cache entries.
  void cleanupExpiredCache() {
    _permissionCache.removeWhere((_, entry) => entry.isExpired);
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Disposes of the role manager.
  Future<void> dispose() async {
    await _roles?.dispose();
    _roleRegistry.clear();
    _permissionCache.clear();
    _initialized = false;
    _logger.info('RoleManager disposed.');
  }

  @override
  String toString() {
    return 'RoleManager(initialized: $_initialized, '
        'cached: ${_permissionCache.length})';
  }
}

/// Result of checking multiple permissions.
class MultiPermissionCheckResult {
  /// Individual check results.
  final List<PermissionCheckResult> results;

  /// Creates a new [MultiPermissionCheckResult].
  const MultiPermissionCheckResult(this.results);

  /// Whether all permissions were granted.
  bool get allGranted => results.every((r) => r.granted);

  /// Whether any permission was granted.
  bool get anyGranted => results.any((r) => r.granted);

  /// Whether all permissions were denied.
  bool get allDenied => results.every((r) => !r.granted);

  /// Gets only the granted permissions.
  List<PermissionCheckResult> get granted =>
      results.where((r) => r.granted).toList();

  /// Gets only the denied permissions.
  List<PermissionCheckResult> get denied =>
      results.where((r) => !r.granted).toList();

  /// The number of granted permissions.
  int get grantedCount => granted.length;

  /// The number of denied permissions.
  int get deniedCount => denied.length;

  @override
  String toString() {
    return 'MultiPermissionCheckResult(granted: $grantedCount, '
        'denied: $deniedCount)';
  }
}
