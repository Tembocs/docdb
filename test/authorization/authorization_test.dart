/// DocDB Authorization Module Tests
///
/// Comprehensive tests for the authorization module including:
/// - Permission: Permission parsing, matching, and implication logic
/// - Action, Resource, PermissionScope: Enum behavior and parsing
/// - Role: Role entity serialization and permission management
/// - RoleManager: RBAC operations, inheritance, and permission resolution
/// - PermissionSet: Set operations for permissions
library;

import 'package:test/test.dart';

import 'package:docdb/src/authorization/authorization.dart';
import 'package:docdb/src/exceptions/exceptions.dart';
import 'package:docdb/src/storage/memory_storage.dart';

void main() {
  group('Action Enum', () {
    test('should have expected actions', () {
      expect(
        Action.values,
        containsAll([
          Action.create,
          Action.read,
          Action.update,
          Action.delete,
          Action.write,
          Action.execute,
          Action.manage,
          Action.admin,
          Action.all,
        ]),
      );
    });

    test('should check if action implies another', () {
      expect(Action.write.implies(Action.create), isTrue);
      expect(Action.write.implies(Action.update), isTrue);
      expect(Action.write.implies(Action.delete), isTrue);

      expect(Action.admin.implies(Action.create), isTrue);
      expect(Action.admin.implies(Action.manage), isTrue);

      expect(Action.all.implies(Action.create), isTrue);
      expect(Action.all.implies(Action.manage), isTrue);

      expect(Action.read.implies(Action.create), isFalse);
      expect(Action.create.implies(Action.read), isFalse);
    });

    test('should get value string', () {
      expect(Action.create.value, equals('create'));
      expect(Action.manage.value, equals('manage'));
      expect(Action.all.value, equals('*'));
    });

    test('should parse from string', () {
      expect(ActionExtension.fromString('create'), equals(Action.create));
      expect(ActionExtension.fromString('*'), equals(Action.all));
    });
  });

  group('Resource Enum', () {
    test('should have expected resources', () {
      expect(
        Resource.values,
        containsAll([
          Resource.document,
          Resource.collection,
          Resource.indexResource,
          Resource.user,
          Resource.role,
          Resource.backup,
          Resource.system,
          Resource.all,
        ]),
      );
    });

    test('should get value string', () {
      expect(Resource.document.value, equals('document'));
      expect(Resource.collection.value, equals('collection'));
      expect(Resource.all.value, equals('*'));
    });

    test('should parse from string', () {
      expect(
        ResourceExtension.fromString('document'),
        equals(Resource.document),
      );
      expect(ResourceExtension.fromString('*'), equals(Resource.all));
    });
  });

  group('PermissionScope Enum', () {
    test('should have expected scopes', () {
      expect(
        PermissionScope.values,
        containsAll([
          PermissionScope.none,
          PermissionScope.own,
          PermissionScope.group,
          PermissionScope.organization,
          PermissionScope.inherited,
        ]),
      );
    });

    test('should get value string', () {
      expect(PermissionScope.own.value, equals('own'));
      expect(PermissionScope.none.value, equals(''));
    });

    test('should parse from string', () {
      expect(
        PermissionScopeExtension.fromString('own'),
        equals(PermissionScope.own),
      );
      expect(
        PermissionScopeExtension.fromString('group'),
        equals(PermissionScope.group),
      );
      expect(
        PermissionScopeExtension.fromString(''),
        equals(PermissionScope.none),
      );
    });
  });

  group('Permission', () {
    test('should create with required fields', () {
      final permission = Permission(
        action: Action.read,
        resource: Resource.document,
      );

      expect(permission.resource, equals(Resource.document));
      expect(permission.action, equals(Action.read));
      expect(permission.scope, equals(PermissionScope.none));
    });

    test('should create with all fields', () {
      final permission = Permission(
        action: Action.manage,
        resource: Resource.collection,
        scope: PermissionScope.organization,
      );

      expect(permission.resource, equals(Resource.collection));
      expect(permission.action, equals(Action.manage));
      expect(permission.scope, equals(PermissionScope.organization));
    });

    test('should create with action factory', () {
      final permission = Permission.action(Action.read, Resource.document);

      expect(permission.resource, equals(Resource.document));
      expect(permission.action, equals(Action.read));
      expect(permission.scope, equals(PermissionScope.none));
    });

    test('should create scoped permission', () {
      final permission = Permission.scoped(
        Action.write,
        Resource.document,
        PermissionScope.own,
      );

      expect(permission.action, equals(Action.write));
      expect(permission.resource, equals(Resource.document));
      expect(permission.scope, equals(PermissionScope.own));
    });

    test('should create wildcard permission', () {
      final permission = Permission.wildcard(Resource.document);

      expect(permission.action, equals(Action.all));
      expect(permission.resource, equals(Resource.document));
    });

    test('should parse from string', () {
      final permission = Permission.parse('document:read');

      expect(permission.resource, equals(Resource.document));
      expect(permission.action, equals(Action.read));
    });

    test('should parse with scope', () {
      final permission = Permission.parse('document:read:own');

      expect(permission.resource, equals(Resource.document));
      expect(permission.action, equals(Action.read));
      expect(permission.scope, equals(PermissionScope.own));
    });

    test('should parse wildcard permission', () {
      final permission = Permission.parse('*:*');

      expect(permission.resource, equals(Resource.all));
      expect(permission.action, equals(Action.all));
    });

    test('should throw on invalid permission string', () {
      expect(() => Permission.parse('invalid'), throwsArgumentError);
    });

    test('should convert to string', () {
      final permission = Permission(
        action: Action.read,
        resource: Resource.document,
      );

      expect(permission.toString(), equals('document:read'));
    });

    test('should convert scoped to string', () {
      final permission = Permission(
        action: Action.read,
        resource: Resource.document,
        scope: PermissionScope.own,
      );

      expect(permission.toString(), equals('document:read:own'));
    });

    group('Permission Implication', () {
      test('should imply same permission', () {
        final permission = Permission(
          action: Action.read,
          resource: Resource.document,
        );

        expect(permission.implies(permission), isTrue);
      });

      test('should imply less specific action', () {
        final write = Permission(
          action: Action.write,
          resource: Resource.document,
        );

        final create = Permission(
          action: Action.create,
          resource: Resource.document,
        );

        final update = Permission(
          action: Action.update,
          resource: Resource.document,
        );

        expect(write.implies(create), isTrue);
        expect(write.implies(update), isTrue);
        expect(create.implies(write), isFalse);
      });

      test('should imply with all action', () {
        final allAction = Permission(
          action: Action.all,
          resource: Resource.document,
        );

        final read = Permission(
          action: Action.read,
          resource: Resource.document,
        );

        expect(allAction.implies(read), isTrue);
        expect(read.implies(allAction), isFalse);
      });

      test('should imply with all resource', () {
        final allResource = Permission(
          action: Action.read,
          resource: Resource.all,
        );

        final document = Permission(
          action: Action.read,
          resource: Resource.document,
        );

        expect(allResource.implies(document), isTrue);
        expect(document.implies(allResource), isFalse);
      });

      test('superuser permission implies all', () {
        final superuser = Permission(
          action: Action.all,
          resource: Resource.all,
        );

        final specific = Permission(
          action: Action.read,
          resource: Resource.document,
        );

        expect(superuser.implies(specific), isTrue);
        expect(specific.implies(superuser), isFalse);
      });
    });

    test('should convert to map', () {
      final permission = Permission(
        action: Action.read,
        resource: Resource.document,
        scope: PermissionScope.own,
      );

      final map = permission.toMap();

      expect(map['action'], equals('read'));
      expect(map['resource'], equals('document'));
      expect(map['scope'], equals('own'));
    });

    test('should create from map', () {
      final map = {'action': 'read', 'resource': 'document', 'scope': 'own'};

      final permission = Permission.fromMap(map);

      expect(permission.action, equals(Action.read));
      expect(permission.resource, equals(Resource.document));
      expect(permission.scope, equals(PermissionScope.own));
    });

    test('should compare permissions', () {
      final p1 = Permission(action: Action.read, resource: Resource.document);

      final p2 = Permission(action: Action.read, resource: Resource.document);

      final p3 = Permission(action: Action.create, resource: Resource.document);

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
    });
  });

  group('Permissions Constants', () {
    test('should have document permissions', () {
      expect(Permissions.documentRead.action, equals(Action.read));
      expect(Permissions.documentRead.resource, equals(Resource.document));

      expect(Permissions.documentWrite.action, equals(Action.write));
      expect(Permissions.documentCreate.action, equals(Action.create));
      expect(Permissions.documentUpdate.action, equals(Action.update));
      expect(Permissions.documentDelete.action, equals(Action.delete));
    });

    test('should have collection permissions', () {
      expect(Permissions.collectionRead.resource, equals(Resource.collection));
      expect(
        Permissions.collectionCreate.resource,
        equals(Resource.collection),
      );
    });

    test('should have user permissions', () {
      expect(Permissions.userRead.resource, equals(Resource.user));
      expect(Permissions.userManage.action, equals(Action.manage));
    });

    test('should have admin permissions', () {
      expect(Permissions.adminAll.action, equals(Action.all));
      expect(Permissions.adminAll.resource, equals(Resource.admin));
    });

    test('should have superAdmin permission', () {
      expect(Permissions.superAdmin.action, equals(Action.all));
      expect(Permissions.superAdmin.resource, equals(Resource.all));
    });
  });

  group('PermissionSet', () {
    test('should create empty set', () {
      const set = PermissionSet.empty();

      expect(set.isEmpty, isTrue);
      expect(set.length, equals(0));
    });

    test('should create from permissions', () {
      final set = PermissionSet([
        Permission.action(Action.read, Resource.document),
        Permission.action(Action.write, Resource.document),
      ]);

      expect(set.length, equals(2));
    });

    test('should create from string representations', () {
      final set = PermissionSet.parse(['document:read', 'user:update']);

      expect(set.length, equals(2));
    });

    test('should check if contains permission', () {
      final set = PermissionSet([
        Permission.action(Action.read, Resource.document),
      ]);

      expect(
        set.contains(Permission.action(Action.read, Resource.document)),
        isTrue,
      );
      expect(
        set.contains(Permission.action(Action.write, Resource.document)),
        isFalse,
      );
    });

    test('should check if grants permission', () {
      final set = PermissionSet([
        Permission.action(Action.write, Resource.document),
      ]);

      expect(
        set.grants(Permission.action(Action.create, Resource.document)),
        isTrue,
      );
      expect(
        set.grants(Permission.action(Action.update, Resource.document)),
        isTrue,
      );
      expect(
        set.grants(Permission.action(Action.read, Resource.user)),
        isFalse,
      );
    });

    test('should check if grants all permissions', () {
      final set = PermissionSet([
        Permission.action(Action.write, Resource.document),
        Permission.action(Action.read, Resource.user),
      ]);

      expect(
        set.grantsAll([
          Permission.action(Action.create, Resource.document),
          Permission.action(Action.update, Resource.document),
        ]),
        isTrue,
      );

      expect(
        set.grantsAll([
          Permission.action(Action.read, Resource.document),
          Permission.action(Action.create, Resource.user),
        ]),
        isFalse,
      );
    });

    test('should check if grants any permission', () {
      final set = PermissionSet([
        Permission.action(Action.read, Resource.document),
      ]);

      expect(
        set.grantsAny([
          Permission.action(Action.read, Resource.document),
          Permission.action(Action.read, Resource.user),
        ]),
        isTrue,
      );

      expect(
        set.grantsAny([
          Permission.action(Action.create, Resource.document),
          Permission.action(Action.read, Resource.user),
        ]),
        isFalse,
      );
    });

    test('should add permissions', () {
      final original = PermissionSet([
        Permission.action(Action.read, Resource.document),
      ]);
      final updated = original.add(
        Permission.action(Action.write, Resource.document),
      );

      expect(updated.length, equals(2));
      expect(original.length, equals(1)); // Original is immutable
    });

    test('should add all permissions', () {
      final set1 = PermissionSet([
        Permission.action(Action.read, Resource.document),
      ]);
      final set2 = set1.addAll([
        Permission.action(Action.write, Resource.document),
        Permission.action(Action.read, Resource.user),
      ]);

      expect(set2.length, equals(3));
    });

    test('should remove permissions', () {
      final set = PermissionSet([
        Permission.action(Action.read, Resource.document),
        Permission.action(Action.write, Resource.document),
      ]);

      final updated = set.remove(
        Permission.action(Action.read, Resource.document),
      );

      expect(updated.length, equals(1));
      expect(
        updated.contains(Permission.action(Action.read, Resource.document)),
        isFalse,
      );
    });

    test('should union sets', () {
      final set1 = PermissionSet([
        Permission.action(Action.read, Resource.document),
      ]);
      final set2 = PermissionSet([
        Permission.action(Action.read, Resource.user),
      ]);

      final union = set1.union(set2);

      expect(union.length, equals(2));
      expect(
        union.grants(Permission.action(Action.read, Resource.document)),
        isTrue,
      );
      expect(
        union.grants(Permission.action(Action.read, Resource.user)),
        isTrue,
      );
    });

    test('should intersect sets', () {
      final set1 = PermissionSet([
        Permission.action(Action.read, Resource.document),
        Permission.action(Action.read, Resource.user),
      ]);
      final set2 = PermissionSet([
        Permission.action(Action.read, Resource.document),
        Permission.action(Action.read, Resource.collection),
      ]);

      final intersection = set1.intersection(set2);

      expect(intersection.length, equals(1));
      expect(
        intersection.grants(Permission.action(Action.read, Resource.document)),
        isTrue,
      );
    });

    test('should convert to list of strings', () {
      final set = PermissionSet([
        Permission.action(Action.read, Resource.document),
        Permission.action(Action.update, Resource.user),
      ]);

      final strings = set.toStringList();

      expect(strings, hasLength(2));
      expect(strings, contains('document:read'));
    });

    test('should convert to list of maps', () {
      final set = PermissionSet([
        Permission.action(Action.read, Resource.document),
      ]);

      final maps = set.toMapList();

      expect(maps, hasLength(1));
      expect(maps.first['action'], equals('read'));
    });
  });

  group('Role Entity', () {
    test('should create with required fields', () {
      final role = Role(
        name: 'editor',
        permissions: [
          Permission.action(Action.read, Resource.document),
          Permission.action(Action.update, Resource.document),
        ],
      );

      expect(role.name, equals('editor'));
      expect(role.permissions, hasLength(2));
    });

    test('should create with description', () {
      final role = Role(
        name: 'viewer',
        description: 'Read-only access',
        permissions: [Permission.action(Action.read, Resource.document)],
      );

      expect(role.description, equals('Read-only access'));
    });

    test('should create with parent roles', () {
      final role = Role(
        name: 'admin',
        permissions: [Permission.action(Action.manage, Resource.user)],
        parentRoles: ['editor'],
      );

      expect(role.parentRoles, contains('editor'));
    });

    test('should check if system role', () {
      final systemRole = Role.system(
        name: 'admin',
        description: 'Admin role',
        permissions: [],
      );

      final customRole = Role(name: 'custom', permissions: []);

      expect(systemRole.isSystem, isTrue);
      expect(customRole.isSystem, isFalse);
    });

    test('should serialize to map', () {
      final role = Role(
        name: 'viewer',
        description: 'Read-only access',
        permissions: [Permission.action(Action.read, Resource.document)],
      );

      final map = role.toMap();

      expect(map['name'], equals('viewer'));
      expect(map['description'], equals('Read-only access'));
      expect(map['permissions'], isList);
    });

    test('should deserialize from map', () {
      final map = {
        'name': 'moderator',
        'description': 'Content moderation',
        'permissions': [
          {'action': 'update', 'resource': 'document'},
          {'action': 'delete', 'resource': 'document'},
        ],
        'parentRoles': ['viewer'],
        'isSystem': false,
        'isActive': true,
        'priority': 50,
      };

      final role = Role.fromMap('role-123', map);

      expect(role.id, equals('role-123'));
      expect(role.name, equals('moderator'));
      expect(role.permissions, hasLength(2));
      expect(role.parentRoles, contains('viewer'));
    });

    test('should check if has permission directly', () {
      final role = Role(
        name: 'user',
        permissions: [
          Permission.action(Action.read, Resource.document),
          Permission.action(Action.write, Resource.document),
        ],
      );

      expect(
        role.hasPermission(Permission.action(Action.read, Resource.document)),
        isTrue,
      );
      expect(
        role.hasPermission(Permission.action(Action.create, Resource.document)),
        isTrue,
      );
      expect(
        role.hasPermission(Permission.action(Action.read, Resource.user)),
        isFalse,
      );
    });

    test('should get permission set', () {
      final role = Role(
        name: 'user',
        permissions: [
          Permission.action(Action.read, Resource.document),
          Permission.action(Action.create, Resource.document),
        ],
      );

      final permissionSet = role.permissionSet;

      expect(permissionSet.length, equals(2));
      expect(
        permissionSet.grants(Permission.action(Action.read, Resource.document)),
        isTrue,
      );
    });

    test('should create copy with modifications', () {
      final role = Role(
        id: 'role-1',
        name: 'original',
        description: 'Original',
        permissions: [Permission.action(Action.read, Resource.document)],
      );

      final updated = role.copyWith(
        description: 'Updated',
        permissions: [
          Permission.action(Action.read, Resource.document),
          Permission.action(Action.create, Resource.document),
        ],
      );

      expect(updated.id, equals('role-1'));
      expect(updated.name, equals('original'));
      expect(updated.description, equals('Updated'));
      expect(updated.permissions, hasLength(2));
    });

    test('should compare roles', () {
      final role1 = Role(id: 'role-1', name: 'test', permissions: []);

      final role2 = Role(id: 'role-1', name: 'test', permissions: []);

      final role3 = Role(id: 'role-2', name: 'other', permissions: []);

      expect(role1, equals(role2));
      expect(role1, isNot(equals(role3)));
    });
  });

  group('SystemRoles', () {
    test('should have expected system roles', () {
      expect(SystemRoles.superAdmin.name, equals('super_admin'));
      expect(SystemRoles.admin.name, equals('admin'));
      expect(SystemRoles.user.name, equals('user'));
      expect(SystemRoles.guest.name, equals('guest'));
      expect(
        SystemRoles.transactionManager.name,
        equals('transaction_manager'),
      );
    });

    test('should have all roles list', () {
      expect(
        SystemRoles.all.map((r) => r.name),
        containsAll([
          'super_admin',
          'admin',
          'user',
          'guest',
          'transaction_manager',
        ]),
      );
    });

    test('should get role by name', () {
      expect(SystemRoles.byName('admin')?.name, equals('admin'));
      expect(SystemRoles.byName('nonexistent'), isNull);
    });

    test('should have correct permissions for superAdmin', () {
      expect(
        SystemRoles.superAdmin.hasPermission(Permissions.superAdmin),
        isTrue,
      );
    });
  });

  group('RoleManager', () {
    late RoleManager roleManager;
    late MemoryStorage<Role> roleStorage;

    setUp(() async {
      roleStorage = MemoryStorage<Role>(name: 'roles');
      await roleStorage.open();

      roleManager = RoleManager(
        storage: roleStorage,
        config: RoleManagerConfig.development,
      );
      await roleManager.initialize();
    });

    tearDown(() async {
      await roleManager.dispose();
      await roleStorage.close();
    });

    group('Initialization', () {
      test('should initialize with system roles', () async {
        expect(roleManager.isInitialized, isTrue);

        final superAdmin = await roleManager.getRole('super_admin');
        expect(superAdmin, isNotNull);

        final admin = await roleManager.getRole('admin');
        expect(admin, isNotNull);

        final user = await roleManager.getRole('user');
        expect(user, isNotNull);
      });

      test('should not re-initialize', () async {
        await roleManager.initialize();
        expect(roleManager.isInitialized, isTrue);
      });

      test('should create in-memory manager', () async {
        final inMemory = RoleManager.inMemory();
        await inMemory.initialize();

        expect(inMemory.isInitialized, isTrue);

        await inMemory.dispose();
      });
    });

    group('Role Operations', () {
      test('should define custom role', () async {
        final role = await roleManager.defineRole(
          Role(
            name: 'editor',
            description: 'Content editor role',
            permissions: [
              Permission.action(Action.read, Resource.document),
              Permission.action(Action.update, Resource.document),
            ],
          ),
        );

        expect(role.name, equals('editor'));
        expect(role.permissions, hasLength(2));
        expect(role.isSystem, isFalse);
      });

      test('should throw on duplicate role name', () async {
        await roleManager.defineRole(
          Role(name: 'unique_role', permissions: []),
        );

        expect(
          () => roleManager.defineRole(
            Role(name: 'unique_role', permissions: []),
          ),
          throwsA(isA<RoleAlreadyDefinedException>()),
        );
      });

      test('should get role by name', () async {
        await roleManager.defineRole(Role(name: 'findme', permissions: []));

        final found = await roleManager.getRole('findme');

        expect(found, isNotNull);
        expect(found!.name, equals('findme'));
      });

      test('should return null for non-existent role', () async {
        final found = await roleManager.getRole('non_existent');
        expect(found, isNull);
      });

      test('should update role', () async {
        await roleManager.defineRole(
          Role(
            name: 'updateme',
            description: 'Original',
            permissions: [Permission.action(Action.read, Resource.document)],
          ),
        );

        // Retrieve the role to get it with its assigned ID
        final created = await roleManager.getRole('updateme');
        expect(created, isNotNull);

        final updated = await roleManager.updateRole(
          created!.copyWith(
            description: 'Updated',
            permissions: [
              Permission.action(Action.read, Resource.document),
              Permission.action(Action.create, Resource.document),
            ],
          ),
        );

        expect(updated.description, equals('Updated'));
        expect(updated.permissions, hasLength(2));
      });

      test('should throw on updating non-existent role', () async {
        expect(
          () => roleManager.updateRole(
            Role(name: 'non_existent', permissions: []),
          ),
          throwsA(isA<UndefinedRoleException>()),
        );
      });

      test('should delete custom role', () async {
        await roleManager.defineRole(Role(name: 'deleteme', permissions: []));

        final deleted = await roleManager.deleteRole('deleteme');

        expect(deleted, isTrue);
        expect(await roleManager.getRole('deleteme'), isNull);
      });

      test('should throw on deleting system role', () async {
        expect(
          () => roleManager.deleteRole('admin'),
          throwsA(isA<AuthorizationException>()),
        );
      });
    });

    group('Permission Resolution', () {
      test('should get permissions for single role', () async {
        final permissions = await roleManager.getPermissions(['user']);

        expect(permissions.length, greaterThan(0));
      });

      test('should combine permissions from multiple roles', () async {
        await roleManager.defineRole(
          Role(
            name: 'role_a',
            permissions: [Permission.action(Action.read, Resource.document)],
          ),
        );

        await roleManager.defineRole(
          Role(
            name: 'role_b',
            permissions: [Permission.action(Action.read, Resource.user)],
          ),
        );

        final permissions = await roleManager.getPermissions([
          'role_a',
          'role_b',
        ]);

        expect(
          permissions.grants(Permission.action(Action.read, Resource.document)),
          isTrue,
        );
        expect(
          permissions.grants(Permission.action(Action.read, Resource.user)),
          isTrue,
        );
      });

      test('should resolve inherited permissions', () async {
        await roleManager.defineRole(
          Role(
            name: 'parent_role',
            permissions: [Permission.action(Action.read, Resource.document)],
          ),
        );

        await roleManager.defineRole(
          Role(
            name: 'child_role',
            permissions: [Permission.action(Action.create, Resource.document)],
            parentRoles: ['parent_role'],
          ),
        );

        final permissions = await roleManager.getPermissions(['child_role']);

        expect(
          permissions.grants(Permission.action(Action.read, Resource.document)),
          isTrue,
        );
        expect(
          permissions.grants(
            Permission.action(Action.create, Resource.document),
          ),
          isTrue,
        );
      });

      test('should handle multi-level inheritance', () async {
        await roleManager.defineRole(
          Role(
            name: 'level_1',
            permissions: [Permission.action(Action.read, Resource.document)],
          ),
        );

        await roleManager.defineRole(
          Role(
            name: 'level_2',
            permissions: [Permission.action(Action.update, Resource.document)],
            parentRoles: ['level_1'],
          ),
        );

        await roleManager.defineRole(
          Role(
            name: 'level_3',
            permissions: [Permission.action(Action.delete, Resource.document)],
            parentRoles: ['level_2'],
          ),
        );

        final permissions = await roleManager.getPermissions(['level_3']);

        expect(
          permissions.grants(Permission.action(Action.read, Resource.document)),
          isTrue,
        );
        expect(
          permissions.grants(
            Permission.action(Action.update, Resource.document),
          ),
          isTrue,
        );
        expect(
          permissions.grants(
            Permission.action(Action.delete, Resource.document),
          ),
          isTrue,
        );
      });
    });

    group('Permission Checking', () {
      test('should check single permission', () async {
        // Use async version for storage-backed mode
        final hasPermission = await roleManager.hasPermissionAsync([
          'user',
        ], Permission.action(Action.read, Resource.document));

        expect(hasPermission, isTrue);
      });

      test('should check async permission', () async {
        final hasPermission = await roleManager.hasPermissionAsync([
          'user',
        ], Permission.action(Action.read, Resource.document));

        expect(hasPermission, isTrue);
      });

      test('should check all permissions', () async {
        await roleManager.defineRole(
          Role(
            name: 'multi_perm',
            permissions: [
              Permission.action(Action.read, Resource.document),
              Permission.action(Action.create, Resource.document),
            ],
          ),
        );

        final hasAll = await roleManager.hasAllPermissions(
          ['multi_perm'],
          [
            Permission.action(Action.read, Resource.document),
            Permission.action(Action.create, Resource.document),
          ],
        );

        expect(hasAll, isTrue);

        final hasAllWithExtra = await roleManager.hasAllPermissions(
          ['multi_perm'],
          [
            Permission.action(Action.read, Resource.document),
            Permission.action(Action.delete, Resource.document),
          ],
        );

        expect(hasAllWithExtra, isFalse);
      });

      test('should check any permission', () async {
        await roleManager.defineRole(
          Role(
            name: 'single_perm',
            permissions: [Permission.action(Action.read, Resource.document)],
          ),
        );

        final hasAny = await roleManager.hasAnyPermission(
          ['single_perm'],
          [
            Permission.action(Action.read, Resource.document),
            Permission.action(Action.delete, Resource.document),
          ],
        );

        expect(hasAny, isTrue);

        final hasNone = await roleManager.hasAnyPermission(
          ['single_perm'],
          [
            Permission.action(Action.create, Resource.document),
            Permission.action(Action.delete, Resource.document),
          ],
        );

        expect(hasNone, isFalse);
      });

      test('should check permission with result', () async {
        await roleManager.defineRole(
          Role(
            name: 'check_role',
            permissions: [Permission.action(Action.read, Resource.document)],
          ),
        );

        final result = await roleManager.checkPermission([
          'check_role',
        ], Permission.action(Action.read, Resource.document));

        expect(result.granted, isTrue);
        expect(result.grantingRole, equals('check_role'));
      });

      test('should return denied result for missing permission', () async {
        await roleManager.defineRole(
          Role(
            name: 'limited_role',
            permissions: [Permission.action(Action.read, Resource.document)],
          ),
        );

        final result = await roleManager.checkPermission([
          'limited_role',
        ], Permission.action(Action.delete, Resource.document));

        expect(result.granted, isFalse);
        expect(result.denialReason, isNotNull);
      });
    });

    group('Role Listing', () {
      test('should list all roles', () async {
        final roles = await roleManager.getAllRoles();

        expect(roles.length, greaterThanOrEqualTo(SystemRoles.all.length));
      });

      test('should list roles including inactive', () async {
        final allRoles = await roleManager.getAllRoles(includeInactive: true);
        final activeRoles = await roleManager.getAllRoles(
          includeInactive: false,
        );

        expect(allRoles.length, greaterThanOrEqualTo(activeRoles.length));
      });
    });

    group('Role Hierarchy', () {
      test('should get inheritance chain', () async {
        await roleManager.defineRole(Role(name: 'base', permissions: []));

        await roleManager.defineRole(
          Role(name: 'child', permissions: [], parentRoles: ['base']),
        );

        final chain = await roleManager.getInheritanceChain('child');

        expect(chain, contains('child'));
        expect(chain, contains('base'));
      });

      test('should detect circular inheritance', () async {
        await roleManager.defineRole(Role(name: 'role_x', permissions: []));

        expect(
          () => roleManager.defineRole(
            Role(name: 'role_y', permissions: [], parentRoles: ['role_y']),
          ),
          throwsA(isA<AuthorizationException>()),
        );
      });
    });

    group('Roles with Permission', () {
      test('should get roles that grant permission', () async {
        await roleManager.defineRole(
          Role(
            name: 'role_with_read',
            permissions: [Permission.action(Action.read, Resource.backup)],
          ),
        );

        final roles = await roleManager.getRolesWithPermission(
          Permission.action(Action.read, Resource.backup),
        );

        expect(roles, contains('role_with_read'));
      });
    });
  });

  group('RoleManagerConfig', () {
    test('should have default values', () {
      const config = RoleManagerConfig();

      expect(config.enablePermissionCache, isTrue);
      expect(config.createDefaultRoles, isTrue);
      expect(config.maxInheritanceDepth, equals(10));
    });

    test('should have development preset', () {
      expect(RoleManagerConfig.development.enablePermissionCache, isFalse);
      expect(RoleManagerConfig.development.createDefaultRoles, isTrue);
    });

    test('should have production preset', () {
      expect(RoleManagerConfig.production.enablePermissionCache, isTrue);
      expect(RoleManagerConfig.production.createDefaultRoles, isTrue);
    });
  });

  group('PermissionCheckResult', () {
    test('should create granted result', () {
      final result = PermissionCheckResult.granted(
        permission: Permission.action(Action.read, Resource.document),
        grantingRole: 'user',
      );

      expect(result.granted, isTrue);
      expect(result.grantingRole, equals('user'));
    });

    test('should create denied result', () {
      final result = PermissionCheckResult.denied(
        permission: Permission.action(Action.delete, Resource.document),
        denialReason: 'No role grants this permission',
      );

      expect(result.granted, isFalse);
      expect(result.denialReason, contains('No role'));
    });
  });

  group('MultiPermissionCheckResult', () {
    test('should check all granted', () {
      final results = MultiPermissionCheckResult([
        PermissionCheckResult.granted(
          permission: Permission.action(Action.read, Resource.document),
          grantingRole: 'user',
        ),
        PermissionCheckResult.granted(
          permission: Permission.action(Action.create, Resource.document),
          grantingRole: 'user',
        ),
      ]);

      expect(results.allGranted, isTrue);
      expect(results.anyGranted, isTrue);
      expect(results.allDenied, isFalse);
      expect(results.grantedCount, equals(2));
    });

    test('should check partial grant', () {
      final results = MultiPermissionCheckResult([
        PermissionCheckResult.granted(
          permission: Permission.action(Action.read, Resource.document),
          grantingRole: 'user',
        ),
        PermissionCheckResult.denied(
          permission: Permission.action(Action.delete, Resource.document),
          denialReason: 'No permission',
        ),
      ]);

      expect(results.allGranted, isFalse);
      expect(results.anyGranted, isTrue);
      expect(results.allDenied, isFalse);
      expect(results.grantedCount, equals(1));
      expect(results.deniedCount, equals(1));
    });

    test('should check all denied', () {
      final results = MultiPermissionCheckResult([
        PermissionCheckResult.denied(
          permission: Permission.action(Action.delete, Resource.document),
          denialReason: 'No permission',
        ),
      ]);

      expect(results.allGranted, isFalse);
      expect(results.anyGranted, isFalse);
      expect(results.allDenied, isTrue);
    });
  });
}
