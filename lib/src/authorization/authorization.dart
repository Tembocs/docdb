/// DocDB Authorization Module
///
/// Provides role-based access control (RBAC) with permission inheritance,
/// hierarchical roles, and fine-grained access control.
///
/// ## Overview
///
/// This module exports all authorization-related classes:
///
/// - **[Permission]**: Resource-action based permissions
/// - **[Role]**: Entity for grouping permissions with inheritance
/// - **[RoleManager]**: Service for role management and permission checking
///
/// ## Architecture
///
/// ```
/// ┌────────────────────────────────────────────────────────────────┐
/// │                    Authorization Module                         │
/// │                                                                 │
/// │  ┌───────────────────────────────────────────────────────────┐ │
/// │  │                     RoleManager                            │ │
/// │  │   - Role CRUD operations                                   │ │
/// │  │   - Permission resolution with inheritance                 │ │
/// │  │   - Access control checks                                  │ │
/// │  └────────────────────────┬──────────────────────────────────┘ │
/// │                           │                                    │
/// │            ┌──────────────┼──────────────┐                     │
/// │            │              │              │                     │
/// │            ▼              ▼              ▼                     │
/// │  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐           │
/// │  │    Role     │  │ Permission  │  │ PermissionSet│           │
/// │  │   Entity    │  │   Class     │  │    Class     │           │
/// │  └─────────────┘  └─────────────┘  └──────────────┘           │
/// └────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/docdb.dart';
///
/// // Create role storage
/// final roleStorage = MemoryStorage<Role>(name: 'roles');
/// await roleStorage.open();
///
/// // Create role manager
/// final roleManager = RoleManager(storage: roleStorage);
/// await roleManager.initialize();
///
/// // Define a custom role
/// await roleManager.defineRole(Role(
///   name: 'editor',
///   description: 'Content editor with write access',
///   permissions: [
///     Permission.action(Action.write, Resource.document),
///   ],
///   parentRoles: ['user'], // Inherits from user role
/// ));
///
/// // Check permissions
/// final userRoles = ['editor'];
/// if (roleManager.hasPermission(userRoles, Permissions.documentWrite)) {
///   print('User can write documents');
/// }
///
/// // Detailed permission check
/// final result = await roleManager.checkPermission(
///   userRoles,
///   Permission.action(Action.delete, Resource.document),
/// );
/// if (result.granted) {
///   print('Granted by role: ${result.grantingRole}');
/// } else {
///   print('Denied: ${result.denialReason}');
/// }
/// ```
///
/// ## Permission System
///
/// Permissions follow the format: `resource:action[:scope]`
///
/// ### Actions
///
/// - `create`, `read`, `update`, `delete` - CRUD operations
/// - `write` - Implies create, update, delete
/// - `manage` - Administrative operations on a resource
/// - `*` - Wildcard for all actions
///
/// ### Resources
///
/// - `document` - Document/entity operations
/// - `collection` - Collection management
/// - `user` - User management
/// - `role` - Role management
/// - `admin` - Administrative operations
/// - `*` - Wildcard for all resources
///
/// ### Scopes
///
/// - (none) - Full access
/// - `own` - Only own resources
/// - `group` - Resources in same group
/// - `organization` - Resources in same organization
///
/// ### Examples
///
/// ```dart
/// // Read any document
/// Permission.parse('document:read')
///
/// // Write own documents only
/// Permission.parse('document:write:own')
///
/// // All admin operations
/// Permission.parse('admin:*')
///
/// // Full system access
/// Permission.parse('*:*')
/// ```
///
/// ## Role Inheritance
///
/// Roles can inherit permissions from parent roles:
///
/// ```dart
/// // Base user role
/// final userRole = Role(
///   name: 'user',
///   permissions: [
///     Permissions.documentRead,
///     Permissions.documentCreate,
///   ],
/// );
///
/// // Editor extends user
/// final editorRole = Role(
///   name: 'editor',
///   permissions: [
///     Permissions.documentWrite, // Additional permission
///   ],
///   parentRoles: ['user'], // Inherits user permissions
/// );
///
/// // Admin extends editor
/// final adminRole = Role(
///   name: 'admin',
///   permissions: [
///     Permissions.userManage,
///     Permissions.backupManage,
///   ],
///   parentRoles: ['editor'], // Inherits editor (and thus user) permissions
/// );
/// ```
///
/// ## System Roles
///
/// Built-in system roles are created automatically:
///
/// - `super_admin` - Full system access
/// - `admin` - Administrative access
/// - `user` - Standard user permissions
/// - `guest` - Read-only access
/// - `transaction_manager` - Transaction operations
///
/// ## Integration with Authentication
///
/// ```dart
/// // After login, verify permissions
/// final loginResult = await auth.login(...);
/// final claims = auth.verifyToken(loginResult.accessToken);
///
/// // Check user's permissions
/// if (await roleManager.hasPermissionAsync(
///   claims.roles,
///   Permission.action(Action.delete, Resource.user),
/// )) {
///   // Allow user deletion
/// } else {
///   throw PermissionDeniedException('Cannot delete users');
/// }
/// ```
library;

export 'permissions.dart'
    show
        Action,
        ActionExtension,
        Resource,
        ResourceExtension,
        PermissionScope,
        PermissionScopeExtension,
        Permission,
        Permissions,
        PermissionSet;
export 'role_manager.dart'
    show
        RoleManager,
        RoleManagerConfig,
        PermissionCheckResult,
        MultiPermissionCheckResult;
export 'roles.dart' show Role, SystemRoles;
