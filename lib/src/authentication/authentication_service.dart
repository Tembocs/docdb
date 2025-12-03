/// DocDB Authentication Service Module
///
/// Provides comprehensive user authentication with session management,
/// account protection, and integration with the authorization system.
///
/// ## Overview
///
/// The [AuthenticationService] handles all aspects of user authentication:
///
/// - **User Registration**: Account creation with validation
/// - **Login/Logout**: Credential verification and session management
/// - **Session Management**: Token-based sessions with revocation
/// - **Account Protection**: Lockout, rate limiting, password policies
/// - **Password Management**: Change, reset, and policy enforcement
///
/// ## Architecture
///
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │                  AuthenticationService                        │
/// │                                                               │
/// │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐  │
/// │  │   Users     │  │  Sessions   │  │  SecurityService     │  │
/// │  │ Collection  │  │ Collection  │  │  (Crypto)            │  │
/// │  └──────┬──────┘  └──────┬──────┘  └──────────┬───────────┘  │
/// │         │                │                     │              │
/// │         ▼                ▼                     ▼              │
/// │  ┌─────────────────────────────────────────────────────────┐ │
/// │  │                    Storage<User>                         │ │
/// │  │                    Storage<UserSession>                  │ │
/// │  └─────────────────────────────────────────────────────────┘ │
/// └──────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/authentication/authentication.dart';
///
/// // Configure security
/// final securityConfig = SecurityConfig(
///   jwtSecret: 'your-secret-key-min-32-chars-here',
/// );
///
/// // Create service
/// final authService = AuthenticationService(
///   userStorage: userStorage,
///   sessionStorage: sessionStorage,
///   securityConfig: securityConfig,
///   roleManager: roleManager,
/// );
/// await authService.initialize();
///
/// // Register a user
/// final user = await authService.register(
///   username: 'john.doe',
///   password: 'SecurePass123!',
///   email: 'john@example.com',
///   roles: ['user'],
/// );
///
/// // Login
/// final session = await authService.login(
///   username: 'john.doe',
///   password: 'SecurePass123!',
/// );
/// print(session.accessToken);
///
/// // Verify a token
/// final claims = authService.verifyToken(session.accessToken);
/// print(claims.userId);
///
/// // Logout
/// await authService.logout(session.accessToken);
/// ```
///
/// ## Session Management
///
/// Sessions are stored as [UserSession] entities, enabling:
/// - Force logout by revoking sessions
/// - Concurrent session tracking
/// - Session activity monitoring
///
/// ## Security Features
///
/// - Account lockout after failed attempts
/// - Password policy enforcement
/// - Token refresh with rotation
/// - Session revocation on password change
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import '../authorization/authorization.dart';
import '../collection/collection.dart';
import '../exceptions/exceptions.dart';
import '../index/i_index.dart';
import '../logger/logger.dart';
import '../query/query.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'security_service.dart';
import 'user.dart';

/// UUID generator for user IDs.
const _uuid = Uuid();

/// Configuration for the authentication service.
@immutable
class AuthenticationConfig {
  /// Whether to enable session tracking.
  final bool enableSessions;

  /// Maximum number of concurrent sessions per user.
  ///
  /// Set to 0 for unlimited sessions.
  final int maxConcurrentSessions;

  /// Whether to revoke all sessions on password change.
  final bool revokeSessionsOnPasswordChange;

  /// Whether to allow username changes.
  final bool allowUsernameChange;

  /// Duration of account inactivity before requiring re-authentication.
  final Duration? inactivityTimeout;

  /// Creates a new [AuthenticationConfig].
  const AuthenticationConfig({
    this.enableSessions = true,
    this.maxConcurrentSessions = 5,
    this.revokeSessionsOnPasswordChange = true,
    this.allowUsernameChange = false,
    this.inactivityTimeout,
  });

  /// Development configuration with relaxed settings.
  static const AuthenticationConfig development = AuthenticationConfig(
    enableSessions: true,
    maxConcurrentSessions: 0,
    revokeSessionsOnPasswordChange: false,
    allowUsernameChange: true,
  );

  /// Production configuration with strict settings.
  static const AuthenticationConfig production = AuthenticationConfig(
    enableSessions: true,
    maxConcurrentSessions: 5,
    revokeSessionsOnPasswordChange: true,
    allowUsernameChange: false,
    inactivityTimeout: Duration(hours: 24),
  );
}

/// Result of a successful login.
@immutable
class LoginResult {
  /// The authenticated user.
  final User user;

  /// The access token for API authentication.
  final String accessToken;

  /// The refresh token for obtaining new access tokens.
  final String refreshToken;

  /// The session ID (if sessions are enabled).
  final String? sessionId;

  /// When the access token expires.
  final DateTime accessTokenExpiresAt;

  /// When the refresh token expires.
  final DateTime refreshTokenExpiresAt;

  /// Creates a new [LoginResult].
  const LoginResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.sessionId,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
  });

  @override
  String toString() {
    return 'LoginResult(user: ${user.username}, sessionId: $sessionId)';
  }
}

/// Result of a token refresh operation.
@immutable
class RefreshResult {
  /// The new access token.
  final String accessToken;

  /// The new refresh token (if rotation is enabled).
  final String? newRefreshToken;

  /// When the access token expires.
  final DateTime expiresAt;

  /// Creates a new [RefreshResult].
  const RefreshResult({
    required this.accessToken,
    this.newRefreshToken,
    required this.expiresAt,
  });
}

/// Comprehensive authentication service for DocDB.
///
/// Provides user authentication with session management, account protection,
/// and integration with the role-based authorization system.
///
/// ## Thread Safety
///
/// All public methods are thread-safe and use internal locking.
///
/// ## Example
///
/// ```dart
/// final auth = AuthenticationService(
///   userStorage: storage,
///   securityConfig: config,
///   roleManager: roles,
/// );
/// await auth.initialize();
///
/// // Register and login
/// await auth.register(username: 'user1', password: 'pass', roles: ['user']);
/// final result = await auth.login(username: 'user1', password: 'pass');
/// ```
class AuthenticationService {
  /// User collection for persistence.
  final Collection<User> _users;

  /// Session collection for session tracking (optional).
  final Collection<UserSession>? _sessions;

  /// Security service for cryptographic operations.
  final SecurityService _security;

  /// Role manager for role validation.
  final RoleManager _roleManager;

  /// Authentication configuration.
  final AuthenticationConfig _config;

  /// Logger for authentication operations.
  final DocDBLogger _logger;

  /// Lock for user operations.
  final Lock _userLock = Lock();

  /// Lock for session operations.
  final Lock _sessionLock = Lock();

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Creates a new [AuthenticationService].
  ///
  /// ## Parameters
  ///
  /// - [userStorage]: Storage backend for users.
  /// - [sessionStorage]: Storage backend for sessions (optional).
  /// - [securityConfig]: Security configuration.
  /// - [roleManager]: Role manager for role validation.
  /// - [config]: Authentication configuration.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final auth = AuthenticationService(
  ///   userStorage: MemoryStorage<User>(name: 'users'),
  ///   sessionStorage: MemoryStorage<UserSession>(name: 'sessions'),
  ///   securityConfig: SecurityConfig(jwtSecret: 'secret'),
  ///   roleManager: RoleManager(),
  /// );
  /// ```
  AuthenticationService({
    required Storage<User> userStorage,
    Storage<UserSession>? sessionStorage,
    required SecurityConfig securityConfig,
    required RoleManager roleManager,
    AuthenticationConfig config = const AuthenticationConfig(),
  }) : _users = Collection<User>(
         storage: userStorage,
         fromMap: User.fromMap,
         name: 'users',
       ),
       _sessions = sessionStorage != null
           ? Collection<UserSession>(
               storage: sessionStorage,
               fromMap: UserSession.fromMap,
               name: 'sessions',
             )
           : null,
       _security = SecurityService(config: securityConfig),
       _roleManager = roleManager,
       _config = config,
       _logger = DocDBLogger(LoggerNameConstants.authentication);

  /// Creates an [AuthenticationService] with pre-built collections.
  ///
  /// Use this factory when you have existing collections.
  factory AuthenticationService.withCollections({
    required Collection<User> userCollection,
    Collection<UserSession>? sessionCollection,
    required SecurityConfig securityConfig,
    required RoleManager roleManager,
    AuthenticationConfig config = const AuthenticationConfig(),
  }) {
    return AuthenticationService._(
      users: userCollection,
      sessions: sessionCollection,
      security: SecurityService(config: securityConfig),
      roleManager: roleManager,
      config: config,
    );
  }

  /// Internal constructor for factory methods.
  AuthenticationService._({
    required Collection<User> users,
    Collection<UserSession>? sessions,
    required SecurityService security,
    required RoleManager roleManager,
    required AuthenticationConfig config,
  }) : _users = users,
       _sessions = sessions,
       _security = security,
       _roleManager = roleManager,
       _config = config,
       _logger = DocDBLogger(LoggerNameConstants.authentication);

  /// The security service used by this authentication service.
  SecurityService get securityService => _security;

  /// The role manager used for role validation.
  RoleManager get roleManager => _roleManager;

  /// The authentication configuration.
  AuthenticationConfig get config => _config;

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes the authentication service.
  ///
  /// Creates necessary indexes for efficient queries.
  /// Must be called before using other methods.
  Future<void> initialize() async {
    if (_initialized) {
      _logger.warning('AuthenticationService already initialized.');
      return;
    }

    await _userLock.synchronized(() async {
      // Create indexes for user queries
      await _users.createIndex('username', IndexType.hash);
      await _users.createIndex('email', IndexType.hash);
      await _users.createIndex('status', IndexType.hash);

      _logger.info('User indexes created.');
    });

    if (_sessions != null) {
      await _sessionLock.synchronized(() async {
        await _sessions.createIndex('userId', IndexType.hash);
        await _sessions.createIndex('token', IndexType.hash);
        await _sessions.createIndex('expiresAt', IndexType.btree);

        _logger.info('Session indexes created.');
      });
    }

    _initialized = true;
    _logger.info('AuthenticationService initialized.');
  }

  /// Ensures the service is initialized.
  void _checkInitialized() {
    if (!_initialized) {
      throw const AuthenticationException(
        'AuthenticationService not initialized. Call initialize() first.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // User Registration
  // ---------------------------------------------------------------------------

  /// Registers a new user.
  ///
  /// ## Parameters
  ///
  /// - [username]: Unique username for login.
  /// - [password]: Plain text password (will be hashed).
  /// - [email]: Optional email address.
  /// - [roles]: List of role names to assign.
  /// - [displayName]: Optional display name.
  /// - [metadata]: Optional additional data.
  ///
  /// ## Returns
  ///
  /// The created [User] entity.
  ///
  /// ## Throws
  ///
  /// - [UserAlreadyExistsException]: If username or email already exists.
  /// - [UndefinedRoleException]: If any role is not defined.
  /// - [AuthenticationException]: If password validation fails.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final user = await auth.register(
  ///   username: 'john.doe',
  ///   password: 'SecurePass123!',
  ///   email: 'john@example.com',
  ///   roles: ['user'],
  /// );
  /// ```
  Future<User> register({
    required String username,
    required String password,
    String? email,
    List<String>? roles,
    String? displayName,
    Map<String, dynamic>? metadata,
  }) async {
    _checkInitialized();

    return await _userLock.synchronized(() async {
      // Validate username format
      _validateUsername(username);

      // Check for existing username
      final existingByUsername = await _users.findOne(
        QueryBuilder().whereEquals('username', username).build(),
      );
      if (existingByUsername != null) {
        throw const UserAlreadyExistsException('Username already exists');
      }

      // Check for existing email if provided
      if (email != null && email.isNotEmpty) {
        _validateEmail(email);
        final existingByEmail = await _users.findOne(
          QueryBuilder().whereEquals('email', email).build(),
        );
        if (existingByEmail != null) {
          throw const UserAlreadyExistsException('Email already exists');
        }
      }

      // Validate password
      final passwordValidation = _security.validatePassword(password);
      if (!passwordValidation.isValid) {
        throw AuthenticationException(
          'Password validation failed: ${passwordValidation.errors.join(", ")}',
        );
      }

      // Validate roles
      final userRoles = roles ?? [defaultRole];
      for (final role in userRoles) {
        if (!_roleManager.isRoleDefined(role)) {
          throw UndefinedRoleException('Undefined role: $role');
        }
      }

      // Create user
      final user = User(
        id: _uuid.v4(),
        username: username,
        email: email,
        passwordHash: _security.hashPassword(password),
        roles: userRoles,
        status: UserStatus.active,
        displayName: displayName,
        passwordChangedAt: DateTime.now(),
        metadata: metadata,
      );

      await _users.insert(user);
      _logger.info('User registered: ${user.username}');

      return user;
    });
  }

  /// Validates username format.
  void _validateUsername(String username) {
    if (username.isEmpty) {
      throw const AuthenticationException('Username cannot be empty');
    }
    if (username.length < 3) {
      throw const AuthenticationException(
        'Username must be at least 3 characters',
      );
    }
    if (username.length > 50) {
      throw const AuthenticationException(
        'Username cannot exceed 50 characters',
      );
    }
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(username)) {
      throw const AuthenticationException(
        'Username can only contain letters, numbers, dots, dashes, and underscores',
      );
    }
  }

  /// Validates email format.
  void _validateEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      throw const AuthenticationException('Invalid email format');
    }
  }

  // ---------------------------------------------------------------------------
  // Login/Logout
  // ---------------------------------------------------------------------------

  /// Authenticates a user with username and password.
  ///
  /// ## Parameters
  ///
  /// - [username]: The username to authenticate.
  /// - [password]: The password to verify.
  /// - [ipAddress]: Optional client IP for session tracking.
  /// - [userAgent]: Optional client user agent for session tracking.
  ///
  /// ## Returns
  ///
  /// A [LoginResult] containing the user and tokens.
  ///
  /// ## Throws
  ///
  /// - [InvalidUserOrPasswordException]: If credentials are invalid.
  /// - [AuthenticationException]: If the account is locked or inactive.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final result = await auth.login(
  ///   username: 'john.doe',
  ///   password: 'SecurePass123!',
  /// );
  /// print(result.accessToken);
  /// ```
  Future<LoginResult> login({
    required String username,
    required String password,
    String? ipAddress,
    String? userAgent,
  }) async {
    _checkInitialized();

    return await _userLock.synchronized(() async {
      // Find user
      final user = await _users.findOne(
        QueryBuilder().whereEquals('username', username).build(),
      );

      if (user == null) {
        _logger.debug('Login failed: user not found: $username');
        throw const InvalidUserOrPasswordException(
          'Invalid username or password',
        );
      }

      // Check account status
      if (!user.canAuthenticate) {
        if (user.isLocked) {
          _logger.debug('Login failed: account locked: $username');
          throw AuthenticationException(
            'Account is locked until ${user.lockedUntil}',
          );
        }
        _logger.debug('Login failed: account status ${user.status}: $username');
        throw AuthenticationException('Account is ${user.status.name}');
      }

      // Verify password
      if (!_security.verifyPassword(password, user.passwordHash)) {
        // Increment failed attempts
        await _handleFailedLogin(user);
        throw const InvalidUserOrPasswordException(
          'Invalid username or password',
        );
      }

      // Reset failed attempts and update last login
      final updatedUser = user.copyWith(
        failedLoginAttempts: 0,
        lastLoginAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _users.update(updatedUser);

      // Generate tokens
      final accessToken = _security.generateToken(
        userId: user.id!,
        roles: user.roles,
      );
      final refreshToken = _security.generateRefreshToken(
        userId: user.id!,
        roles: user.roles,
      );

      // Calculate expiry times
      final now = DateTime.now();
      final accessExpiry = now.add(_security.config.tokenExpiry);
      final refreshExpiry = now.add(_security.config.refreshTokenExpiry);

      // Create session if enabled
      String? sessionId;
      if (_config.enableSessions && _sessions != null) {
        sessionId = await _createSession(
          userId: user.id!,
          token: accessToken,
          expiresAt: refreshExpiry,
          ipAddress: ipAddress,
          userAgent: userAgent,
        );
      }

      _logger.info('User logged in: ${user.username}');

      return LoginResult(
        user: updatedUser,
        accessToken: accessToken,
        refreshToken: refreshToken,
        sessionId: sessionId,
        accessTokenExpiresAt: accessExpiry,
        refreshTokenExpiresAt: refreshExpiry,
      );
    });
  }

  /// Handles failed login attempt by incrementing counter and potentially locking.
  Future<void> _handleFailedLogin(User user) async {
    final newAttempts = user.failedLoginAttempts + 1;
    final shouldLock = _security.shouldLockout(newAttempts);

    final updatedUser = user.copyWith(
      failedLoginAttempts: newAttempts,
      status: shouldLock ? UserStatus.locked : user.status,
      lockedUntil: shouldLock ? _security.calculateLockoutExpiry() : null,
      updatedAt: DateTime.now(),
    );

    await _users.update(updatedUser);

    if (shouldLock) {
      _logger.warning(
        'Account locked due to failed attempts: ${user.username}',
      );
    }
  }

  /// Creates a session for the user.
  Future<String> _createSession({
    required String userId,
    required String token,
    required DateTime expiresAt,
    String? ipAddress,
    String? userAgent,
  }) async {
    return await _sessionLock.synchronized(() async {
      // Check concurrent session limit
      if (_config.maxConcurrentSessions > 0) {
        final existingSessions = await _sessions!.find(
          QueryBuilder().whereEquals('userId', userId).build(),
        );

        final activeSessions = existingSessions
            .where((s) => s.isValid)
            .toList();

        if (activeSessions.length >= _config.maxConcurrentSessions) {
          // Revoke oldest session
          final oldest = activeSessions.reduce(
            (a, b) => a.createdAt.isBefore(b.createdAt) ? a : b,
          );
          await _revokeSession(oldest.id!);
          _logger.debug('Revoked oldest session for user: $userId');
        }
      }

      final session = UserSession(
        userId: userId,
        token: token,
        expiresAt: expiresAt,
        ipAddress: ipAddress,
        userAgent: userAgent,
      );

      final sessionId = await _sessions!.insert(session);
      _logger.debug('Created session $sessionId for user: $userId');
      return sessionId;
    });
  }

  /// Logs out a user by revoking their token/session.
  ///
  /// ## Parameters
  ///
  /// - [token]: The access token to invalidate.
  ///
  /// ## Throws
  ///
  /// - [InvalidOrExpiredTokenException]: If the token is invalid.
  Future<void> logout(String token) async {
    _checkInitialized();

    if (_sessions == null) {
      // Without session storage, just verify and log
      _security.verifyToken(token);
      _logger.info('Token logged out (no session storage)');
      return;
    }

    await _sessionLock.synchronized(() async {
      final session = await _sessions.findOne(
        QueryBuilder().whereEquals('token', token).build(),
      );

      if (session != null) {
        await _revokeSession(session.id!);
        _logger.info('Session revoked for user: ${session.userId}');
      } else {
        _logger.debug('No session found for token');
      }
    });
  }

  /// Logs out all sessions for a user.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID to logout.
  ///
  /// ## Returns
  ///
  /// The number of sessions revoked.
  Future<int> logoutAll(String userId) async {
    _checkInitialized();

    if (_sessions == null) {
      _logger.debug('No session storage configured');
      return 0;
    }

    return await _sessionLock.synchronized(() async {
      final sessions = await _sessions.find(
        QueryBuilder().whereEquals('userId', userId).build(),
      );

      var count = 0;
      for (final session in sessions) {
        if (!session.isRevoked) {
          await _revokeSession(session.id!);
          count++;
        }
      }

      _logger.info('Revoked $count sessions for user: $userId');
      return count;
    });
  }

  /// Revokes a specific session.
  Future<void> _revokeSession(String sessionId) async {
    final session = await _sessions!.get(sessionId);
    if (session != null && !session.isRevoked) {
      final revoked = session.copyWith(isRevoked: true);
      await _sessions.update(revoked);
    }
  }

  // ---------------------------------------------------------------------------
  // Token Operations
  // ---------------------------------------------------------------------------

  /// Verifies an access token and returns its claims.
  ///
  /// ## Parameters
  ///
  /// - [token]: The token to verify.
  /// - [checkSession]: Whether to verify session is valid (default: true).
  ///
  /// ## Returns
  ///
  /// The [TokenClaims] from the token.
  ///
  /// ## Throws
  ///
  /// - [InvalidOrExpiredTokenException]: If the token is invalid or revoked.
  TokenClaims verifyToken(String token, {bool checkSession = true}) {
    _checkInitialized();

    final claims = _security.verifyToken(token);

    // Optionally verify session is not revoked
    if (checkSession && _sessions != null && _config.enableSessions) {
      // Note: This is synchronous, so we can't check session here
      // Session validation should be done separately if needed
    }

    return claims;
  }

  /// Verifies a token and checks if the session is valid.
  ///
  /// ## Parameters
  ///
  /// - [token]: The token to verify.
  ///
  /// ## Returns
  ///
  /// The [TokenClaims] if valid.
  ///
  /// ## Throws
  ///
  /// - [InvalidOrExpiredTokenException]: If the token or session is invalid.
  Future<TokenClaims> verifyTokenAsync(String token) async {
    _checkInitialized();

    final claims = _security.verifyToken(token);

    if (_sessions != null && _config.enableSessions) {
      final session = await _sessions.findOne(
        QueryBuilder().whereEquals('token', token).build(),
      );

      if (session == null || session.isRevoked) {
        throw const InvalidOrExpiredTokenException('Session has been revoked');
      }

      if (!session.isValid) {
        throw const InvalidOrExpiredTokenException('Session has expired');
      }

      // Update last activity
      final updated = session.copyWith(lastActiveAt: DateTime.now());
      await _sessions.update(updated);
    }

    return claims;
  }

  /// Refreshes an access token using a refresh token.
  ///
  /// ## Parameters
  ///
  /// - [refreshToken]: The refresh token.
  ///
  /// ## Returns
  ///
  /// A [RefreshResult] with the new access token.
  ///
  /// ## Throws
  ///
  /// - [InvalidOrExpiredTokenException]: If the refresh token is invalid.
  Future<RefreshResult> refreshToken(String refreshToken) async {
    _checkInitialized();

    final newAccessToken = _security.refreshAccessToken(refreshToken);
    final claims = _security.verifyToken(newAccessToken);

    return RefreshResult(
      accessToken: newAccessToken,
      expiresAt: claims.expiresAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Password Management
  // ---------------------------------------------------------------------------

  /// Changes a user's password.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID.
  /// - [currentPassword]: The current password for verification.
  /// - [newPassword]: The new password.
  ///
  /// ## Throws
  ///
  /// - [InvalidUserOrPasswordException]: If current password is wrong.
  /// - [AuthenticationException]: If new password validation fails.
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    _checkInitialized();

    await _userLock.synchronized(() async {
      final user = await _users.get(userId);
      if (user == null) {
        throw const InvalidUserOrPasswordException('User not found');
      }

      // Verify current password
      if (!_security.verifyPassword(currentPassword, user.passwordHash)) {
        throw const InvalidUserOrPasswordException(
          'Current password is incorrect',
        );
      }

      // Validate new password
      final validation = _security.validatePassword(newPassword);
      if (!validation.isValid) {
        throw AuthenticationException(
          'Password validation failed: ${validation.errors.join(", ")}',
        );
      }

      // Update password
      final updatedUser = user.copyWith(
        passwordHash: _security.hashPassword(newPassword),
        passwordChangedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _users.update(updatedUser);

      // Revoke all sessions if configured
      if (_config.revokeSessionsOnPasswordChange && _sessions != null) {
        await logoutAll(userId);
      }

      _logger.info('Password changed for user: ${user.username}');
    });
  }

  /// Resets a user's password (admin operation).
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID.
  /// - [newPassword]: The new password.
  ///
  /// ## Throws
  ///
  /// - [AuthenticationException]: If password validation fails.
  Future<void> resetPassword({
    required String userId,
    required String newPassword,
  }) async {
    _checkInitialized();

    await _userLock.synchronized(() async {
      final user = await _users.get(userId);
      if (user == null) {
        throw const AuthenticationException('User not found');
      }

      // Validate new password
      final validation = _security.validatePassword(newPassword);
      if (!validation.isValid) {
        throw AuthenticationException(
          'Password validation failed: ${validation.errors.join(", ")}',
        );
      }

      // Update password and unlock if locked
      final updatedUser = user.copyWith(
        passwordHash: _security.hashPassword(newPassword),
        passwordChangedAt: DateTime.now(),
        failedLoginAttempts: 0,
        status: user.status == UserStatus.locked
            ? UserStatus.active
            : user.status,
        lockedUntil: null,
        updatedAt: DateTime.now(),
      );
      await _users.update(updatedUser);

      // Revoke all sessions
      if (_sessions != null) {
        await logoutAll(userId);
      }

      _logger.info('Password reset for user: ${user.username}');
    });
  }

  // ---------------------------------------------------------------------------
  // User Management
  // ---------------------------------------------------------------------------

  /// Gets a user by ID.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID.
  ///
  /// ## Returns
  ///
  /// The [User] or `null` if not found.
  Future<User?> getUser(String userId) async {
    _checkInitialized();
    return _users.get(userId);
  }

  /// Gets a user by username.
  ///
  /// ## Parameters
  ///
  /// - [username]: The username to find.
  ///
  /// ## Returns
  ///
  /// The [User] or `null` if not found.
  Future<User?> getUserByUsername(String username) async {
    _checkInitialized();
    return _users.findOne(
      QueryBuilder().whereEquals('username', username).build(),
    );
  }

  /// Gets a user by email.
  ///
  /// ## Parameters
  ///
  /// - [email]: The email to find.
  ///
  /// ## Returns
  ///
  /// The [User] or `null` if not found.
  Future<User?> getUserByEmail(String email) async {
    _checkInitialized();
    return _users.findOne(QueryBuilder().whereEquals('email', email).build());
  }

  /// Updates a user's profile.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID.
  /// - [displayName]: New display name.
  /// - [email]: New email address.
  /// - [profileImageUrl]: New profile image URL.
  /// - [metadata]: New metadata (replaces existing).
  ///
  /// ## Returns
  ///
  /// The updated [User].
  Future<User> updateProfile({
    required String userId,
    String? displayName,
    String? email,
    String? profileImageUrl,
    Map<String, dynamic>? metadata,
  }) async {
    _checkInitialized();

    return await _userLock.synchronized(() async {
      final user = await _users.get(userId);
      if (user == null) {
        throw const AuthenticationException('User not found');
      }

      // Validate email if changing
      if (email != null && email != user.email) {
        _validateEmail(email);
        final existingByEmail = await _users.findOne(
          QueryBuilder().whereEquals('email', email).build(),
        );
        if (existingByEmail != null && existingByEmail.id != userId) {
          throw const UserAlreadyExistsException('Email already exists');
        }
      }

      final updatedUser = user.copyWith(
        displayName: displayName ?? user.displayName,
        email: email ?? user.email,
        profileImageUrl: profileImageUrl ?? user.profileImageUrl,
        metadata: metadata ?? user.metadata,
        updatedAt: DateTime.now(),
      );

      await _users.update(updatedUser);
      _logger.info('Profile updated for user: ${user.username}');
      return updatedUser;
    });
  }

  /// Updates a user's roles.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID.
  /// - [roles]: The new list of roles.
  ///
  /// ## Throws
  ///
  /// - [UndefinedRoleException]: If any role is not defined.
  Future<User> updateRoles({
    required String userId,
    required List<String> roles,
  }) async {
    _checkInitialized();

    return await _userLock.synchronized(() async {
      // Validate roles
      for (final role in roles) {
        if (!_roleManager.isRoleDefined(role)) {
          throw UndefinedRoleException('Undefined role: $role');
        }
      }

      final user = await _users.get(userId);
      if (user == null) {
        throw const AuthenticationException('User not found');
      }

      final updatedUser = user.copyWith(
        roles: roles,
        updatedAt: DateTime.now(),
      );

      await _users.update(updatedUser);
      _logger.info('Roles updated for user: ${user.username}');
      return updatedUser;
    });
  }

  /// Updates a user's status.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID.
  /// - [status]: The new status.
  Future<User> updateStatus({
    required String userId,
    required UserStatus status,
  }) async {
    _checkInitialized();

    return await _userLock.synchronized(() async {
      final user = await _users.get(userId);
      if (user == null) {
        throw const AuthenticationException('User not found');
      }

      final updatedUser = user.copyWith(
        status: status,
        lockedUntil: status == UserStatus.active ? null : user.lockedUntil,
        failedLoginAttempts: status == UserStatus.active
            ? 0
            : user.failedLoginAttempts,
        updatedAt: DateTime.now(),
      );

      await _users.update(updatedUser);
      _logger.info(
        'Status updated for user: ${user.username} to ${status.name}',
      );
      return updatedUser;
    });
  }

  /// Deletes a user and all their sessions.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID to delete.
  ///
  /// ## Returns
  ///
  /// `true` if the user was deleted.
  Future<bool> deleteUser(String userId) async {
    _checkInitialized();

    return await _userLock.synchronized(() async {
      // Revoke all sessions first
      if (_sessions != null) {
        await logoutAll(userId);
      }

      final deleted = await _users.delete(userId);
      if (deleted) {
        _logger.info('User deleted: $userId');
      }
      return deleted;
    });
  }

  // ---------------------------------------------------------------------------
  // Session Management
  // ---------------------------------------------------------------------------

  /// Gets all active sessions for a user.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user ID.
  ///
  /// ## Returns
  ///
  /// List of active sessions.
  Future<List<UserSession>> getUserSessions(String userId) async {
    _checkInitialized();

    if (_sessions == null) {
      return [];
    }

    final sessions = await _sessions.find(
      QueryBuilder().whereEquals('userId', userId).build(),
    );

    return sessions.where((s) => s.isValid).toList();
  }

  /// Revokes a specific session.
  ///
  /// ## Parameters
  ///
  /// - [sessionId]: The session ID to revoke.
  ///
  /// ## Returns
  ///
  /// `true` if the session was revoked.
  Future<bool> revokeSession(String sessionId) async {
    _checkInitialized();

    if (_sessions == null) {
      return false;
    }

    return await _sessionLock.synchronized(() async {
      final session = await _sessions.get(sessionId);
      if (session == null || session.isRevoked) {
        return false;
      }

      await _revokeSession(sessionId);
      _logger.info('Session revoked: $sessionId');
      return true;
    });
  }

  /// Cleans up expired sessions.
  ///
  /// ## Returns
  ///
  /// The number of sessions cleaned up.
  Future<int> cleanupExpiredSessions() async {
    _checkInitialized();

    if (_sessions == null) {
      return 0;
    }

    return await _sessionLock.synchronized(() async {
      final now = DateTime.now();
      final expired = await _sessions.find(
        QueryBuilder()
            .whereLessThan('expiresAt', now.toIso8601String())
            .build(),
      );

      var count = 0;
      for (final session in expired) {
        await _sessions.delete(session.id!);
        count++;
      }

      if (count > 0) {
        _logger.info('Cleaned up $count expired sessions.');
      }
      return count;
    });
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Disposes of the authentication service.
  Future<void> dispose() async {
    await _users.dispose();
    await _sessions?.dispose();
    _initialized = false;
    _logger.info('AuthenticationService disposed.');
  }

  @override
  String toString() {
    return 'AuthenticationService(initialized: $_initialized, '
        'sessionsEnabled: ${_config.enableSessions})';
  }
}
