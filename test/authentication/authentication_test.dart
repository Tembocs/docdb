/// EntiDB Authentication Module Tests
///
/// Comprehensive tests for the authentication module including:
/// - AuthenticationService: User registration, login, logout, password management
/// - SecurityService: Password hashing, JWT token operations
/// - User entity: Serialization, status management
/// - UserSession entity: Session tracking and validation
library;

import 'package:test/test.dart';

import 'package:entidb/src/authentication/authentication.dart';
import 'package:entidb/src/authorization/authorization.dart';
import 'package:entidb/src/exceptions/exceptions.dart';
import 'package:entidb/src/storage/memory_storage.dart';

void main() {
  group('SecurityConfig', () {
    test('should create with required parameters', () {
      const config = SecurityConfig(
        jwtSecret: 'test-secret-key-32-chars-long!!',
      );

      expect(config.jwtSecret, equals('test-secret-key-32-chars-long!!'));
      expect(config.jwtIssuer, equals('entidb'));
      expect(config.tokenExpiry, equals(const Duration(hours: 1)));
      expect(config.refreshTokenExpiry, equals(const Duration(days: 7)));
    });

    test('should create development config', () {
      final config = SecurityConfig.development(
        jwtSecret: 'dev-secret-key-32-characters-!!',
      );

      expect(config.minPasswordLength, equals(4));
      expect(config.requireMixedCase, isFalse);
      expect(config.bcryptCost, equals(4));
    });

    test('should create production config', () {
      final config = SecurityConfig.production(
        jwtSecret: 'prod-secret-key-32-characters-!',
      );

      expect(config.minPasswordLength, equals(12));
      expect(config.requireMixedCase, isTrue);
      expect(config.requireNumbers, isTrue);
      expect(config.requireSpecialChars, isTrue);
      expect(config.bcryptCost, equals(12));
    });

    test('should validate config with short secret', () {
      const config = SecurityConfig(jwtSecret: 'short');

      expect(() => config.validate(), throwsArgumentError);
    });

    test('should validate config with invalid bcrypt cost', () {
      const config = SecurityConfig(
        jwtSecret: 'valid-secret-key-32-characters-!',
        bcryptCost: 2,
      );

      expect(() => config.validate(), throwsArgumentError);
    });
  });

  group('SecurityService', () {
    late SecurityService security;

    setUp(() {
      security = SecurityService(
        config: SecurityConfig.development(
          jwtSecret: 'test-secret-key-32-characters-min',
        ),
      );
    });

    group('Password Validation', () {
      test('should validate password meeting requirements', () {
        final result = security.validatePassword('TestPass123');
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });

      test('should reject password too short', () {
        final devSecurity = SecurityService(
          config: SecurityConfig.development(
            jwtSecret: 'test-secret-key-32-characters-min',
          ),
        );

        final result = devSecurity.validatePassword('ab');
        expect(result.isValid, isFalse);
        expect(result.errors, contains(contains('at least')));
      });

      test('should reject password without lowercase (in production)', () {
        final prodSecurity = SecurityService(
          config: SecurityConfig.production(
            jwtSecret: 'test-secret-key-32-characters-min',
          ),
        );

        final result = prodSecurity.validatePassword('UPPERCASEONLY123!');
        expect(result.isValid, isFalse);
        expect(result.errors, anyElement(contains('lowercase')));
      });

      test('should reject password without uppercase (in production)', () {
        final prodSecurity = SecurityService(
          config: SecurityConfig.production(
            jwtSecret: 'test-secret-key-32-characters-min',
          ),
        );

        final result = prodSecurity.validatePassword('lowercaseonly123!');
        expect(result.isValid, isFalse);
        expect(result.errors, anyElement(contains('uppercase')));
      });

      test('should reject password without numbers (in production)', () {
        final prodSecurity = SecurityService(
          config: SecurityConfig.production(
            jwtSecret: 'test-secret-key-32-characters-min',
          ),
        );

        final result = prodSecurity.validatePassword('NoNumbersHere!');
        expect(result.isValid, isFalse);
        expect(result.errors, anyElement(contains('number')));
      });
    });

    group('Password Hashing', () {
      test('should hash password', () {
        final hash = security.hashPassword('myPassword123');

        expect(hash, isNotEmpty);
        expect(hash, isNot(equals('myPassword123')));
        expect(hash, startsWith(r'$2'));
      });

      test('should verify correct password', () {
        final hash = security.hashPassword('myPassword123');
        final isValid = security.verifyPassword('myPassword123', hash);

        expect(isValid, isTrue);
      });

      test('should reject incorrect password', () {
        final hash = security.hashPassword('myPassword123');
        final isValid = security.verifyPassword('wrongPassword', hash);

        expect(isValid, isFalse);
      });

      test('should throw on empty password', () {
        expect(() => security.hashPassword(''), throwsArgumentError);
      });

      test('should return false for empty inputs', () {
        expect(security.verifyPassword('', 'hash'), isFalse);
        expect(security.verifyPassword('password', ''), isFalse);
      });
    });

    group('Token Generation', () {
      test('should generate access token', () {
        final token = security.generateToken(
          userId: 'user-123',
          roles: ['user', 'admin'],
        );

        expect(token, isNotEmpty);
        expect(token.split('.'), hasLength(3)); // JWT format
      });

      test('should generate refresh token', () {
        final token = security.generateRefreshToken(
          userId: 'user-123',
          roles: ['user'],
        );

        expect(token, isNotEmpty);
      });

      test('should throw on empty user ID', () {
        expect(
          () => security.generateToken(userId: '', roles: ['user']),
          throwsA(isA<JWTTokenException>()),
        );
      });
    });

    group('Token Verification', () {
      test('should verify valid token', () {
        final token = security.generateToken(
          userId: 'user-123',
          roles: ['user', 'admin'],
        );

        final claims = security.verifyToken(token);

        expect(claims.userId, equals('user-123'));
        expect(claims.roles, containsAll(['user', 'admin']));
        expect(claims.isExpired, isFalse);
      });

      test('should detect refresh token', () {
        final refreshToken = security.generateRefreshToken(
          userId: 'user-123',
          roles: ['user'],
        );

        final claims = security.verifyToken(refreshToken);

        expect(claims.isRefreshToken, isTrue);
      });

      test('should throw on invalid token', () {
        expect(
          () => security.verifyToken('invalid.token.here'),
          throwsA(isA<InvalidOrExpiredTokenException>()),
        );
      });

      test('should throw on empty token', () {
        expect(
          () => security.verifyToken(''),
          throwsA(isA<InvalidOrExpiredTokenException>()),
        );
      });

      test('should check token validity without throwing', () {
        final validToken = security.generateToken(
          userId: 'user-123',
          roles: ['user'],
        );

        expect(security.isTokenValid(validToken), isTrue);
        expect(security.isTokenValid('invalid'), isFalse);
      });
    });

    group('Token Refresh', () {
      test('should refresh access token from refresh token', () {
        final refreshToken = security.generateRefreshToken(
          userId: 'user-123',
          roles: ['user'],
        );

        final newAccessToken = security.refreshAccessToken(refreshToken);

        expect(newAccessToken, isNotEmpty);

        final claims = security.verifyToken(newAccessToken);
        expect(claims.userId, equals('user-123'));
        expect(claims.isRefreshToken, isFalse);
      });

      test('should throw when using access token for refresh', () {
        final accessToken = security.generateToken(
          userId: 'user-123',
          roles: ['user'],
        );

        expect(
          () => security.refreshAccessToken(accessToken),
          throwsA(isA<JWTTokenException>()),
        );
      });
    });

    group('Lockout', () {
      test('should calculate lockout expiry', () {
        final expiry = security.calculateLockoutExpiry();

        expect(expiry.isAfter(DateTime.now()), isTrue);
      });

      test('should determine when to lockout', () {
        expect(security.shouldLockout(0), isFalse);
        expect(security.shouldLockout(99), isFalse);
        expect(security.shouldLockout(100), isTrue);
        expect(security.shouldLockout(101), isTrue);
      });
    });

    group('Decode Token Unsafe', () {
      test('should decode token without verification', () {
        final token = security.generateToken(
          userId: 'user-123',
          roles: ['user'],
        );

        final claims = security.decodeTokenUnsafe(token);

        expect(claims, isNotNull);
        expect(claims!.userId, equals('user-123'));
      });

      test('should return null for invalid token', () {
        final claims = security.decodeTokenUnsafe('invalid');
        expect(claims, isNull);
      });
    });
  });

  group('TokenClaims', () {
    test('should check if expired', () {
      final expiredClaims = TokenClaims(
        userId: 'user-123',
        roles: ['user'],
        issuedAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(expiredClaims.isExpired, isTrue);
      expect(expiredClaims.isValid, isFalse);
    });

    test('should calculate remaining time', () {
      final claims = TokenClaims(
        userId: 'user-123',
        roles: ['user'],
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(claims.remainingTime.inMinutes, greaterThan(50));
    });

    test('should return zero for expired token remaining time', () {
      final claims = TokenClaims(
        userId: 'user-123',
        roles: ['user'],
        issuedAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(claims.remainingTime, equals(Duration.zero));
    });
  });

  group('PasswordValidationResult', () {
    test('should create valid result', () {
      const result = PasswordValidationResult.valid();

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('should create invalid result', () {
      const result = PasswordValidationResult.invalid(['Error 1', 'Error 2']);

      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(2));
    });
  });

  group('User Entity', () {
    test('should create user with required fields', () {
      final user = User(username: 'john.doe', passwordHash: 'hashed-password');

      expect(user.username, equals('john.doe'));
      expect(user.passwordHash, equals('hashed-password'));
      expect(user.roles, isEmpty);
      expect(user.status, equals(UserStatus.active));
      expect(user.failedLoginAttempts, equals(0));
    });

    test('should create user with all fields', () {
      final user = User(
        id: 'user-123',
        username: 'john.doe',
        email: 'john@example.com',
        passwordHash: 'hashed-password',
        roles: ['user', 'admin'],
        status: UserStatus.active,
        displayName: 'John Doe',
        failedLoginAttempts: 0,
      );

      expect(user.id, equals('user-123'));
      expect(user.email, equals('john@example.com'));
      expect(user.roles, containsAll(['user', 'admin']));
      expect(user.displayName, equals('John Doe'));
    });

    test('should serialize to map', () {
      final user = User(
        username: 'john.doe',
        email: 'john@example.com',
        passwordHash: 'hashed-password',
        roles: ['user'],
      );

      final map = user.toMap();

      expect(map['username'], equals('john.doe'));
      expect(map['email'], equals('john@example.com'));
      expect(map['passwordHash'], equals('hashed-password'));
      expect(map['roles'], equals(['user']));
    });

    test('should deserialize from map', () {
      final map = {
        'username': 'jane.doe',
        'email': 'jane@example.com',
        'passwordHash': 'hashed',
        'roles': ['admin'],
        'status': 'active',
        'failedLoginAttempts': 0,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      final user = User.fromMap('user-456', map);

      expect(user.id, equals('user-456'));
      expect(user.username, equals('jane.doe'));
      expect(user.email, equals('jane@example.com'));
      expect(user.roles, contains('admin'));
    });

    test('should throw on missing required field', () {
      final map = {'passwordHash': 'hash'};

      expect(() => User.fromMap('id', map), throwsA(isA<FormatException>()));
    });

    test('should check if locked', () {
      final lockedUser = User(
        username: 'locked',
        passwordHash: 'hash',
        status: UserStatus.locked,
        lockedUntil: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(lockedUser.isLocked, isTrue);
      expect(lockedUser.canAuthenticate, isFalse);
    });

    test('should check if can authenticate', () {
      final activeUser = User(
        username: 'active',
        passwordHash: 'hash',
        status: UserStatus.active,
      );

      expect(activeUser.canAuthenticate, isTrue);
    });

    test('should check role membership', () {
      final user = User(
        username: 'user',
        passwordHash: 'hash',
        roles: ['user', 'editor'],
      );

      expect(user.hasRole('user'), isTrue);
      expect(user.hasRole('admin'), isFalse);
      expect(user.hasAnyRole(['admin', 'editor']), isTrue);
      expect(user.hasAllRoles(['user', 'editor']), isTrue);
      expect(user.hasAllRoles(['user', 'admin']), isFalse);
    });

    test('should create copy with modifications', () {
      final user = User(
        id: 'user-123',
        username: 'john',
        passwordHash: 'hash',
        failedLoginAttempts: 0,
      );

      final updated = user.copyWith(failedLoginAttempts: 3);

      expect(updated.id, equals('user-123'));
      expect(updated.username, equals('john'));
      expect(updated.failedLoginAttempts, equals(3));
    });

    test('should serialize to JSON', () {
      final user = User(username: 'test', passwordHash: 'hash');

      final json = user.toJson();

      expect(json, contains('test'));
      expect(json, contains('hash'));
    });

    test('should compare users by id and username', () {
      final user1 = User(id: 'id-1', username: 'user', passwordHash: 'hash');
      final user2 = User(id: 'id-1', username: 'user', passwordHash: 'hash');
      final user3 = User(id: 'id-2', username: 'user', passwordHash: 'hash');

      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
    });
  });

  group('UserStatus', () {
    test('should convert to storage string', () {
      expect(UserStatus.active.toStorageString(), equals('active'));
      expect(UserStatus.locked.toStorageString(), equals('locked'));
      expect(UserStatus.suspended.toStorageString(), equals('suspended'));
    });

    test('should parse from string', () {
      expect(
        UserStatusExtension.fromString('active'),
        equals(UserStatus.active),
      );
      expect(
        UserStatusExtension.fromString('locked'),
        equals(UserStatus.locked),
      );
      expect(
        UserStatusExtension.fromString('unknown'),
        equals(UserStatus.active),
      );
    });
  });

  group('UserSession Entity', () {
    test('should create session with required fields', () {
      final session = UserSession(
        userId: 'user-123',
        token: 'jwt-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(session.userId, equals('user-123'));
      expect(session.token, equals('jwt-token'));
      expect(session.isRevoked, isFalse);
    });

    test('should check if valid', () {
      final validSession = UserSession(
        userId: 'user-123',
        token: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(validSession.isValid, isTrue);
    });

    test('should check if expired', () {
      final expiredSession = UserSession(
        userId: 'user-123',
        token: 'token',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(expiredSession.isValid, isFalse);
    });

    test('should check if revoked', () {
      final revokedSession = UserSession(
        userId: 'user-123',
        token: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        isRevoked: true,
      );

      expect(revokedSession.isValid, isFalse);
    });

    test('should serialize to map', () {
      final session = UserSession(
        userId: 'user-123',
        token: 'token',
        expiresAt: DateTime(2024, 12, 31),
        ipAddress: '127.0.0.1',
        userAgent: 'TestAgent/1.0',
      );

      final map = session.toMap();

      expect(map['userId'], equals('user-123'));
      expect(map['token'], equals('token'));
      expect(map['ipAddress'], equals('127.0.0.1'));
      expect(map['userAgent'], equals('TestAgent/1.0'));
    });

    test('should deserialize from map', () {
      final map = {
        'userId': 'user-456',
        'token': 'session-token',
        'createdAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'lastActiveAt': DateTime.now().toIso8601String(),
        'isRevoked': false,
      };

      final session = UserSession.fromMap('session-id', map);

      expect(session.id, equals('session-id'));
      expect(session.userId, equals('user-456'));
      expect(session.token, equals('session-token'));
    });

    test('should create copy with modifications', () {
      final session = UserSession(
        userId: 'user-123',
        token: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final revoked = session.copyWith(isRevoked: true);

      expect(revoked.userId, equals('user-123'));
      expect(revoked.isRevoked, isTrue);
    });
  });

  group('AuthenticationConfig', () {
    test('should have default values', () {
      const config = AuthenticationConfig();

      expect(config.enableSessions, isTrue);
      expect(config.maxConcurrentSessions, equals(5));
      expect(config.revokeSessionsOnPasswordChange, isTrue);
      expect(config.allowUsernameChange, isFalse);
    });

    test('should have development preset', () {
      expect(AuthenticationConfig.development.maxConcurrentSessions, equals(0));
      expect(
        AuthenticationConfig.development.revokeSessionsOnPasswordChange,
        isFalse,
      );
      expect(AuthenticationConfig.development.allowUsernameChange, isTrue);
    });

    test('should have production preset', () {
      expect(AuthenticationConfig.production.maxConcurrentSessions, equals(5));
      expect(
        AuthenticationConfig.production.revokeSessionsOnPasswordChange,
        isTrue,
      );
      expect(AuthenticationConfig.production.inactivityTimeout, isNotNull);
    });
  });

  group('AuthenticationService', () {
    late AuthenticationService authService;
    late MemoryStorage<User> userStorage;
    late MemoryStorage<UserSession> sessionStorage;
    late RoleManager roleManager;

    setUp(() async {
      userStorage = MemoryStorage<User>(name: 'users');
      sessionStorage = MemoryStorage<UserSession>(name: 'sessions');
      await userStorage.open();
      await sessionStorage.open();

      roleManager = RoleManager.inMemory();
      await roleManager.initialize();

      authService = AuthenticationService(
        userStorage: userStorage,
        sessionStorage: sessionStorage,
        securityConfig: SecurityConfig.development(
          jwtSecret: 'test-secret-key-32-characters-min',
        ),
        roleManager: roleManager,
      );
      await authService.initialize();
    });

    tearDown(() async {
      await authService.dispose();
      await userStorage.close();
      await sessionStorage.close();
    });

    group('Initialization', () {
      test('should initialize successfully', () {
        expect(authService.isInitialized, isTrue);
      });

      test('should not throw on double initialization', () async {
        await authService.initialize(); // Should not throw
      });

      test('should throw when not initialized', () async {
        final newAuth = AuthenticationService(
          userStorage: userStorage,
          securityConfig: SecurityConfig.development(
            jwtSecret: 'test-secret-key-32-characters-min',
          ),
          roleManager: roleManager,
        );

        expect(
          () => newAuth.verifyToken('token'),
          throwsA(isA<AuthenticationException>()),
        );
      });
    });

    group('Registration', () {
      test('should register new user', () async {
        final user = await authService.register(
          username: 'newuser',
          password: 'TestPassword123',
          email: 'new@example.com',
          roles: ['user'],
        );

        expect(user.username, equals('newuser'));
        expect(user.email, equals('new@example.com'));
        expect(user.roles, contains('user'));
        expect(user.status, equals(UserStatus.active));
      });

      test('should throw on duplicate username', () async {
        await authService.register(
          username: 'existinguser',
          password: 'TestPassword123',
          roles: ['user'],
        );

        expect(
          () => authService.register(
            username: 'existinguser',
            password: 'AnotherPass123',
            roles: ['user'],
          ),
          throwsA(isA<UserAlreadyExistsException>()),
        );
      });

      test('should throw on duplicate email', () async {
        await authService.register(
          username: 'user1',
          password: 'TestPassword123',
          email: 'same@example.com',
          roles: ['user'],
        );

        expect(
          () => authService.register(
            username: 'user2',
            password: 'TestPassword123',
            email: 'same@example.com',
            roles: ['user'],
          ),
          throwsA(isA<UserAlreadyExistsException>()),
        );
      });

      test('should reject invalid username format', () async {
        expect(
          () => authService.register(
            username: 'ab',
            password: 'TestPassword123',
            roles: ['user'],
          ),
          throwsA(isA<AuthenticationException>()),
        );

        expect(
          () => authService.register(
            username: 'invalid username!',
            password: 'TestPassword123',
            roles: ['user'],
          ),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('should reject invalid email format', () async {
        expect(
          () => authService.register(
            username: 'validuser',
            password: 'TestPassword123',
            email: 'invalid-email',
            roles: ['user'],
          ),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('should reject undefined role', () async {
        expect(
          () => authService.register(
            username: 'validuser',
            password: 'TestPassword123',
            roles: ['undefined_role'],
          ),
          throwsA(isA<UndefinedRoleException>()),
        );
      });
    });

    group('Login', () {
      setUp(() async {
        await authService.register(
          username: 'testuser',
          password: 'TestPassword123',
          roles: ['user'],
        );
      });

      test('should login with correct credentials', () async {
        final result = await authService.login(
          username: 'testuser',
          password: 'TestPassword123',
        );

        expect(result.user.username, equals('testuser'));
        expect(result.accessToken, isNotEmpty);
        expect(result.refreshToken, isNotEmpty);
        expect(result.sessionId, isNotNull);
      });

      test('should throw on invalid username', () async {
        expect(
          () => authService.login(
            username: 'wronguser',
            password: 'TestPassword123',
          ),
          throwsA(isA<InvalidUserOrPasswordException>()),
        );
      });

      test('should throw on invalid password', () async {
        expect(
          () => authService.login(
            username: 'testuser',
            password: 'WrongPassword',
          ),
          throwsA(isA<InvalidUserOrPasswordException>()),
        );
      });
    });

    group('Logout', () {
      test('should logout successfully', () async {
        // Create isolated user for this test
        await authService.register(
          username: 'logoutuser1',
          password: 'TestPassword123',
          roles: ['user'],
        );

        final loginResult = await authService.login(
          username: 'logoutuser1',
          password: 'TestPassword123',
        );

        await authService.logout(loginResult.accessToken);

        // Session should be revoked
        expect(
          () => authService.verifyTokenAsync(loginResult.accessToken),
          throwsA(isA<InvalidOrExpiredTokenException>()),
        );
      });

      test('should logout all sessions', () async {
        // Create isolated user for this test
        await authService.register(
          username: 'logoutuser2',
          password: 'TestPassword123',
          roles: ['user'],
        );

        final loginResult1 = await authService.login(
          username: 'logoutuser2',
          password: 'TestPassword123',
        );

        // Create second session
        await authService.login(
          username: 'logoutuser2',
          password: 'TestPassword123',
        );

        final revokedCount = await authService.logoutAll(loginResult1.user.id!);

        expect(revokedCount, greaterThanOrEqualTo(1));
      });
    });

    group('Token Verification', () {
      late LoginResult loginResult;

      setUp(() async {
        await authService.register(
          username: 'tokenuser',
          password: 'TestPassword123',
          roles: ['user', 'admin'],
        );

        loginResult = await authService.login(
          username: 'tokenuser',
          password: 'TestPassword123',
        );
      });

      test('should verify valid token', () {
        final claims = authService.verifyToken(loginResult.accessToken);

        expect(claims.userId, equals(loginResult.user.id));
        expect(claims.roles, containsAll(['user', 'admin']));
      });

      test('should verify token async with session check', () async {
        final claims = await authService.verifyTokenAsync(
          loginResult.accessToken,
        );

        expect(claims.userId, equals(loginResult.user.id));
      });

      test('should refresh token', () async {
        final refreshResult = await authService.refreshToken(
          loginResult.refreshToken,
        );

        expect(refreshResult.accessToken, isNotEmpty);
      });
    });

    group('Password Management', () {
      test('should change password', () async {
        // Create isolated user for this test
        final user = await authService.register(
          username: 'pwduser1',
          password: 'OldPassword123',
          roles: ['user'],
        );

        await authService.changePassword(
          userId: user.id!,
          currentPassword: 'OldPassword123',
          newPassword: 'NewPassword456',
        );

        // Old password should not work
        expect(
          () => authService.login(
            username: 'pwduser1',
            password: 'OldPassword123',
          ),
          throwsA(isA<InvalidUserOrPasswordException>()),
        );

        // New password should work
        final result = await authService.login(
          username: 'pwduser1',
          password: 'NewPassword456',
        );
        expect(result.user.username, equals('pwduser1'));
      });

      test('should throw on wrong current password', () async {
        // Create isolated user for this test
        final user = await authService.register(
          username: 'pwduser2',
          password: 'OldPassword123',
          roles: ['user'],
        );

        expect(
          () => authService.changePassword(
            userId: user.id!,
            currentPassword: 'WrongPassword',
            newPassword: 'NewPassword456',
          ),
          throwsA(isA<InvalidUserOrPasswordException>()),
        );
      });

      test('should reset password', () async {
        // Create isolated user for this test
        final user = await authService.register(
          username: 'pwduser3',
          password: 'OldPassword123',
          roles: ['user'],
        );

        await authService.resetPassword(
          userId: user.id!,
          newPassword: 'ResetPassword789',
        );

        final result = await authService.login(
          username: 'pwduser3',
          password: 'ResetPassword789',
        );
        expect(result.user.username, equals('pwduser3'));
      });
    });

    group('User Management', () {
      late User user;

      setUp(() async {
        user = await authService.register(
          username: 'manageuser',
          password: 'TestPassword123',
          email: 'manage@example.com',
          roles: ['user'],
        );
      });

      test('should get user by ID', () async {
        final retrieved = await authService.getUser(user.id!);

        expect(retrieved, isNotNull);
        expect(retrieved!.username, equals('manageuser'));
      });

      test('should get user by username', () async {
        final retrieved = await authService.getUserByUsername('manageuser');

        expect(retrieved, isNotNull);
        expect(retrieved!.email, equals('manage@example.com'));
      });

      test('should get user by email', () async {
        final retrieved = await authService.getUserByEmail(
          'manage@example.com',
        );

        expect(retrieved, isNotNull);
        expect(retrieved!.username, equals('manageuser'));
      });

      test('should update profile', () async {
        final updated = await authService.updateProfile(
          userId: user.id!,
          displayName: 'Managed User',
          email: 'newemail@example.com',
        );

        expect(updated.displayName, equals('Managed User'));
        expect(updated.email, equals('newemail@example.com'));
      });

      test('should update roles', () async {
        final updated = await authService.updateRoles(
          userId: user.id!,
          roles: ['user', 'admin'],
        );

        expect(updated.roles, containsAll(['user', 'admin']));
      });

      test('should update status', () async {
        final updated = await authService.updateStatus(
          userId: user.id!,
          status: UserStatus.suspended,
        );

        expect(updated.status, equals(UserStatus.suspended));
      });

      test('should delete user', () async {
        final deleted = await authService.deleteUser(user.id!);

        expect(deleted, isTrue);
        expect(await authService.getUser(user.id!), isNull);
      });
    });

    group('Session Management', () {
      late User user;
      late LoginResult loginResult;

      setUp(() async {
        user = await authService.register(
          username: 'sessionuser',
          password: 'TestPassword123',
          roles: ['user'],
        );

        loginResult = await authService.login(
          username: 'sessionuser',
          password: 'TestPassword123',
        );
      });

      test('should get user sessions', () async {
        final sessions = await authService.getUserSessions(user.id!);

        expect(sessions, isNotEmpty);
      });

      test('should revoke session', () async {
        final revoked = await authService.revokeSession(loginResult.sessionId!);

        expect(revoked, isTrue);
      });

      test('should cleanup expired sessions', () async {
        final cleanedUp = await authService.cleanupExpiredSessions();

        expect(cleanedUp, greaterThanOrEqualTo(0));
      });
    });
  });

  group('LoginResult', () {
    test('should have meaningful string representation', () {
      final user = User(
        id: 'user-123',
        username: 'testuser',
        passwordHash: 'hash',
      );

      final result = LoginResult(
        user: user,
        accessToken: 'access',
        refreshToken: 'refresh',
        sessionId: 'session-1',
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        refreshTokenExpiresAt: DateTime.now().add(const Duration(days: 7)),
      );

      expect(result.toString(), contains('testuser'));
    });
  });
}
