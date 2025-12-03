/// DocDB Authentication Module
///
/// Provides comprehensive user authentication with secure credential handling,
/// session management, and account protection.
///
/// ## Overview
///
/// This module exports all authentication-related classes:
///
/// - **[User]**: User entity with profile and status information
/// - **[UserSession]**: Session entity for tracking active sessions
/// - **[SecurityService]**: Cryptographic operations (hashing, JWT)
/// - **[AuthenticationService]**: Main authentication service
///
/// ## Architecture
///
/// ```
/// ┌───────────────────────────────────────────────────────────────────┐
/// │                     Authentication Module                          │
/// │                                                                    │
/// │  ┌──────────────────────────────────────────────────────────────┐ │
/// │  │                  AuthenticationService                        │ │
/// │  │   - User registration and management                         │ │
/// │  │   - Login/logout with session tracking                       │ │
/// │  │   - Password management and policies                         │ │
/// │  └─────────────────────────┬────────────────────────────────────┘ │
/// │                            │                                       │
/// │            ┌───────────────┼───────────────┐                      │
/// │            │               │               │                      │
/// │            ▼               ▼               ▼                      │
/// │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐          │
/// │  │    User     │  │ UserSession │  │ SecurityService  │          │
/// │  │   Entity    │  │   Entity    │  │    (Crypto)      │          │
/// │  └─────────────┘  └─────────────┘  └──────────────────┘          │
/// └───────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/docdb.dart';
///
/// // Configure security
/// final securityConfig = SecurityConfig(
///   jwtSecret: 'your-256-bit-secret-key-here',
///   tokenExpiry: Duration(hours: 1),
/// );
///
/// // Create storage
/// final userStorage = MemoryStorage<User>(name: 'users');
/// final sessionStorage = MemoryStorage<UserSession>(name: 'sessions');
/// await userStorage.open();
/// await sessionStorage.open();
///
/// // Create role manager
/// final roleManager = RoleManager();
///
/// // Create authentication service
/// final auth = AuthenticationService(
///   userStorage: userStorage,
///   sessionStorage: sessionStorage,
///   securityConfig: securityConfig,
///   roleManager: roleManager,
/// );
/// await auth.initialize();
///
/// // Register a user
/// final user = await auth.register(
///   username: 'john.doe',
///   password: 'SecurePass123!',
///   email: 'john@example.com',
///   roles: ['user'],
/// );
///
/// // Login
/// final result = await auth.login(
///   username: 'john.doe',
///   password: 'SecurePass123!',
/// );
/// print('Access token: ${result.accessToken}');
///
/// // Verify token
/// final claims = auth.verifyToken(result.accessToken);
/// print('User ID: ${claims.userId}');
/// print('Roles: ${claims.roles}');
///
/// // Logout
/// await auth.logout(result.accessToken);
/// ```
///
/// ## Security Features
///
/// ### Password Security
///
/// - BCrypt hashing with configurable cost factor
/// - Password policy enforcement (length, complexity)
/// - Secure password change with session revocation
///
/// ### Token Security
///
/// - JWT tokens with configurable expiration
/// - Refresh tokens for token rotation
/// - Token verification with signature validation
///
/// ### Account Protection
///
/// - Account lockout after failed attempts
/// - Session management with revocation
/// - Activity tracking and auditing
///
/// ## Configuration
///
/// ### Security Configuration
///
/// ```dart
/// // Development (relaxed)
/// final devConfig = SecurityConfig.development(
///   jwtSecret: 'dev-secret-key-32-chars-minimum',
/// );
///
/// // Production (strict)
/// final prodConfig = SecurityConfig.production(
///   jwtSecret: 'production-secret-from-env-var!',
///   jwtIssuer: 'my-app',
/// );
/// ```
///
/// ### Authentication Configuration
///
/// ```dart
/// final authConfig = AuthenticationConfig(
///   enableSessions: true,
///   maxConcurrentSessions: 5,
///   revokeSessionsOnPasswordChange: true,
/// );
/// ```
///
/// ## Integration with Authorization
///
/// The authentication module works with the authorization module:
///
/// ```dart
/// // Get user's roles from token
/// final claims = auth.verifyToken(token);
///
/// // Check permissions
/// final hasAccess = roleManager.hasPermission(
///   claims.roles,
///   Permission.write,
/// );
/// ```
library;

export 'authentication_service.dart'
    show
        AuthenticationService,
        AuthenticationConfig,
        LoginResult,
        RefreshResult;
export 'security_service.dart'
    show SecurityService, SecurityConfig, TokenClaims, PasswordValidationResult;
export 'user.dart' show User, UserSession, UserStatus, UserStatusExtension;
