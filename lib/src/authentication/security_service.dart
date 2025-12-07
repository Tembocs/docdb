/// EntiDB Security Service Module
///
/// Provides cryptographic operations for authentication including password
/// hashing, JWT token generation/verification, and secure credential handling.
///
/// ## Overview
///
/// The [SecurityService] class handles all security-sensitive operations:
///
/// - **Password Hashing**: BCrypt with configurable cost factor
/// - **Token Management**: JWT generation, verification, and refresh
/// - **Credential Validation**: Input sanitization and format checks
///
/// ## Quick Start
///
/// ```dart
/// import 'package:entidb/src/authentication/security_service.dart';
///
/// final config = SecurityConfig(
///   jwtSecret: 'your-256-bit-secret-key-here',
///   tokenExpiry: Duration(hours: 1),
///   refreshTokenExpiry: Duration(days: 7),
/// );
///
/// final security = SecurityService(config: config);
///
/// // Hash a password
/// final hash = security.hashPassword('user-password');
///
/// // Verify a password
/// final valid = security.verifyPassword('user-password', hash);
///
/// // Generate a JWT token
/// final token = security.generateToken(userId: 'user-123', roles: ['user']);
///
/// // Verify a token
/// final claims = security.verifyToken(token);
/// print(claims.userId); // 'user-123'
/// ```
///
/// ## Security Best Practices
///
/// - Store the JWT secret securely (environment variable, secret manager)
/// - Use HTTPS for all authentication traffic
/// - Implement token refresh to limit exposure
/// - Consider adding rate limiting for login attempts
/// - Log authentication events for audit trails
library;

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:meta/meta.dart';

import '../exceptions/exceptions.dart';
import '../logger/logger.dart';
import '../utils/constants.dart';

/// Configuration for security-related operations.
///
/// Defines parameters for password hashing, token generation,
/// and other security settings.
@immutable
class SecurityConfig {
  /// Secret key for signing JWT tokens.
  ///
  /// Must be at least 32 characters (256 bits) for security.
  /// Should be stored securely and never committed to source control.
  final String jwtSecret;

  /// Issuer claim for JWT tokens.
  ///
  /// Identifies your application in the token payload.
  final String jwtIssuer;

  /// Audience claim for JWT tokens.
  ///
  /// Identifies the intended recipients of the token.
  final String? jwtAudience;

  /// Duration until access tokens expire.
  ///
  /// Shorter durations improve security but require more frequent refresh.
  /// Recommended: 15 minutes to 1 hour.
  final Duration tokenExpiry;

  /// Duration until refresh tokens expire.
  ///
  /// Refresh tokens should have longer lifetimes but be revocable.
  /// Recommended: 1 day to 30 days.
  final Duration refreshTokenExpiry;

  /// BCrypt cost factor for password hashing.
  ///
  /// Higher values increase security but also CPU time.
  /// Recommended: 10-12 for most applications.
  final int bcryptCost;

  /// Maximum consecutive failed login attempts before lockout.
  final int maxFailedLoginAttempts;

  /// Duration of account lockout after exceeding failed attempts.
  final Duration lockoutDuration;

  /// Minimum password length requirement.
  final int minPasswordLength;

  /// Whether to require mixed case in passwords.
  final bool requireMixedCase;

  /// Whether to require numbers in passwords.
  final bool requireNumbers;

  /// Whether to require special characters in passwords.
  final bool requireSpecialChars;

  /// Creates a new [SecurityConfig].
  ///
  /// ## Parameters
  ///
  /// - [jwtSecret]: Secret key for JWT signing (required, min 32 chars).
  /// - [jwtIssuer]: Token issuer claim (default: 'entidb').
  /// - [jwtAudience]: Token audience claim.
  /// - [tokenExpiry]: Access token lifetime (default: 1 hour).
  /// - [refreshTokenExpiry]: Refresh token lifetime (default: 7 days).
  /// - [bcryptCost]: Password hash cost (default: 10).
  /// - [maxFailedLoginAttempts]: Lockout threshold (default: 5).
  /// - [lockoutDuration]: Account lock time (default: 15 minutes).
  /// - [minPasswordLength]: Minimum password length (default: 8).
  const SecurityConfig({
    required this.jwtSecret,
    this.jwtIssuer = 'entidb',
    this.jwtAudience,
    this.tokenExpiry = const Duration(hours: 1),
    this.refreshTokenExpiry = const Duration(days: 7),
    this.bcryptCost = 10,
    this.maxFailedLoginAttempts = 5,
    this.lockoutDuration = const Duration(minutes: 15),
    this.minPasswordLength = 8,
    this.requireMixedCase = true,
    this.requireNumbers = true,
    this.requireSpecialChars = false,
  });

  /// Creates a development configuration with relaxed settings.
  ///
  /// **Warning**: Do not use in production.
  factory SecurityConfig.development({required String jwtSecret}) {
    return SecurityConfig(
      jwtSecret: jwtSecret,
      tokenExpiry: const Duration(hours: 24),
      refreshTokenExpiry: const Duration(days: 30),
      bcryptCost: 4, // Faster for development
      maxFailedLoginAttempts: 100,
      lockoutDuration: const Duration(seconds: 10),
      minPasswordLength: 4,
      requireMixedCase: false,
      requireNumbers: false,
      requireSpecialChars: false,
    );
  }

  /// Creates a production configuration with strict settings.
  factory SecurityConfig.production({
    required String jwtSecret,
    String jwtIssuer = 'entidb',
  }) {
    return SecurityConfig(
      jwtSecret: jwtSecret,
      jwtIssuer: jwtIssuer,
      tokenExpiry: const Duration(minutes: 15),
      refreshTokenExpiry: const Duration(days: 7),
      bcryptCost: 12,
      maxFailedLoginAttempts: 5,
      lockoutDuration: const Duration(minutes: 30),
      minPasswordLength: 12,
      requireMixedCase: true,
      requireNumbers: true,
      requireSpecialChars: true,
    );
  }

  /// Validates that the configuration is secure.
  ///
  /// Throws [ArgumentError] if any settings are insecure.
  void validate() {
    if (jwtSecret.length < 32) {
      throw ArgumentError(
        'JWT secret must be at least 32 characters (256 bits)',
      );
    }
    if (bcryptCost < 4 || bcryptCost > 31) {
      throw ArgumentError('BCrypt cost must be between 4 and 31');
    }
    if (minPasswordLength < 4) {
      throw ArgumentError('Minimum password length must be at least 4');
    }
  }
}

/// Represents the claims extracted from a JWT token.
///
/// Contains the payload data including user identity, roles,
/// and token metadata.
@immutable
class TokenClaims {
  /// The user ID from the token.
  final String userId;

  /// The roles assigned to the user.
  final List<String> roles;

  /// The token issuer.
  final String? issuer;

  /// The token audience.
  final String? audience;

  /// When the token was issued.
  final DateTime issuedAt;

  /// When the token expires.
  final DateTime expiresAt;

  /// The JWT ID (unique token identifier).
  final String? jwtId;

  /// Whether this is a refresh token.
  final bool isRefreshToken;

  /// Creates new [TokenClaims].
  const TokenClaims({
    required this.userId,
    required this.roles,
    this.issuer,
    this.audience,
    required this.issuedAt,
    required this.expiresAt,
    this.jwtId,
    this.isRefreshToken = false,
  });

  /// Creates [TokenClaims] from a JWT payload.
  factory TokenClaims.fromJwtPayload(Map<String, dynamic> payload) {
    return TokenClaims(
      userId: payload['sub'] as String,
      roles: List<String>.from(payload['roles'] as List? ?? []),
      issuer: payload['iss'] as String?,
      audience: payload['aud'] as String?,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(
        ((payload['iat'] as num?) ?? 0) * 1000 as int,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        ((payload['exp'] as num?) ?? 0) * 1000 as int,
      ),
      jwtId: payload['jti'] as String?,
      isRefreshToken: (payload['refresh'] as bool?) ?? false,
    );
  }

  /// Checks if the token has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Checks if the token is valid (not expired).
  bool get isValid => !isExpired;

  /// Gets the remaining time until expiration.
  Duration get remainingTime {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  String toString() {
    return 'TokenClaims(userId: $userId, roles: $roles, '
        'expiresAt: $expiresAt, isRefreshToken: $isRefreshToken)';
  }
}

/// Result of a password validation check.
@immutable
class PasswordValidationResult {
  /// Whether the password is valid.
  final bool isValid;

  /// List of validation error messages.
  final List<String> errors;

  /// Creates a new [PasswordValidationResult].
  const PasswordValidationResult({
    required this.isValid,
    this.errors = const [],
  });

  /// Creates a valid result.
  const PasswordValidationResult.valid() : isValid = true, errors = const [];

  /// Creates an invalid result with errors.
  const PasswordValidationResult.invalid(this.errors) : isValid = false;
}

/// Service for security operations including password hashing and JWT management.
///
/// [SecurityService] provides a centralized, configurable interface for
/// all authentication-related cryptographic operations.
///
/// ## Thread Safety
///
/// All methods are thread-safe and can be called concurrently.
///
/// ## Example
///
/// ```dart
/// final security = SecurityService(
///   config: SecurityConfig(jwtSecret: 'your-secret-key'),
/// );
///
/// // Password operations
/// final hash = security.hashPassword('myPassword123');
/// final isValid = security.verifyPassword('myPassword123', hash);
///
/// // Token operations
/// final accessToken = security.generateToken(
///   userId: 'user-123',
///   roles: ['user', 'admin'],
/// );
/// final claims = security.verifyToken(accessToken);
/// ```
class SecurityService {
  /// Configuration for security operations.
  final SecurityConfig _config;

  /// Logger for security operations.
  final EntiDBLogger _logger;

  /// Creates a new [SecurityService] with the given configuration.
  ///
  /// The configuration is validated on creation.
  ///
  /// ## Parameters
  ///
  /// - [config]: Security configuration settings.
  ///
  /// ## Throws
  ///
  /// - [ArgumentError]: If the configuration is invalid.
  SecurityService({required SecurityConfig config})
    : _config = config,
      _logger = EntiDBLogger(LoggerNameConstants.authentication) {
    _config.validate();
    _logger.debug('SecurityService initialized.');
  }

  /// The security configuration.
  SecurityConfig get config => _config;

  // ---------------------------------------------------------------------------
  // Password Operations
  // ---------------------------------------------------------------------------

  /// Validates a password against the configured policy.
  ///
  /// ## Parameters
  ///
  /// - [password]: The password to validate.
  ///
  /// ## Returns
  ///
  /// A [PasswordValidationResult] indicating validity and any errors.
  PasswordValidationResult validatePassword(String password) {
    final errors = <String>[];

    if (password.length < _config.minPasswordLength) {
      errors.add(
        'Password must be at least ${_config.minPasswordLength} characters',
      );
    }

    if (_config.requireMixedCase) {
      if (!password.contains(RegExp(r'[a-z]'))) {
        errors.add('Password must contain at least one lowercase letter');
      }
      if (!password.contains(RegExp(r'[A-Z]'))) {
        errors.add('Password must contain at least one uppercase letter');
      }
    }

    if (_config.requireNumbers) {
      if (!password.contains(RegExp(r'[0-9]'))) {
        errors.add('Password must contain at least one number');
      }
    }

    if (_config.requireSpecialChars) {
      if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
        errors.add('Password must contain at least one special character');
      }
    }

    if (errors.isEmpty) {
      return const PasswordValidationResult.valid();
    }
    return PasswordValidationResult.invalid(errors);
  }

  /// Hashes a password using BCrypt.
  ///
  /// ## Parameters
  ///
  /// - [password]: The plain text password to hash.
  ///
  /// ## Returns
  ///
  /// A BCrypt hash string.
  ///
  /// ## Throws
  ///
  /// - [ArgumentError]: If the password is empty.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final hash = security.hashPassword('mySecurePassword123');
  /// // Store `hash` in the database
  /// ```
  String hashPassword(String password) {
    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty');
    }

    final salt = BCrypt.gensalt(logRounds: _config.bcryptCost);
    final hash = BCrypt.hashpw(password, salt);

    _logger.debug('Password hashed successfully.');
    return hash;
  }

  /// Verifies a password against a stored hash.
  ///
  /// ## Parameters
  ///
  /// - [password]: The plain text password to verify.
  /// - [hash]: The stored BCrypt hash to compare against.
  ///
  /// ## Returns
  ///
  /// `true` if the password matches, `false` otherwise.
  ///
  /// ## Example
  ///
  /// ```dart
  /// if (security.verifyPassword(inputPassword, storedHash)) {
  ///   print('Login successful');
  /// }
  /// ```
  bool verifyPassword(String password, String hash) {
    if (password.isEmpty || hash.isEmpty) {
      _logger.warning('Empty password or hash in verification attempt.');
      return false;
    }

    try {
      final matches = BCrypt.checkpw(password, hash);
      if (matches) {
        _logger.debug('Password verification successful.');
      } else {
        _logger.debug('Password verification failed.');
      }
      return matches;
    } catch (e, stackTrace) {
      _logger.error('Password verification error', e, stackTrace);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Token Operations
  // ---------------------------------------------------------------------------

  /// Generates a JWT access token.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user's unique identifier (becomes 'sub' claim).
  /// - [roles]: List of role names for the user.
  /// - [additionalClaims]: Optional additional JWT claims.
  ///
  /// ## Returns
  ///
  /// A signed JWT token string.
  ///
  /// ## Throws
  ///
  /// - [JWTTokenException]: If token generation fails.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final token = security.generateToken(
  ///   userId: 'user-123',
  ///   roles: ['user', 'admin'],
  /// );
  /// ```
  String generateToken({
    required String userId,
    required List<String> roles,
    Map<String, dynamic>? additionalClaims,
  }) {
    if (userId.isEmpty) {
      throw const JWTTokenException('User ID cannot be empty');
    }

    try {
      final payload = <String, dynamic>{
        'sub': userId,
        'roles': roles,
        if (additionalClaims != null) ...additionalClaims,
      };

      final jwt = JWT(
        payload,
        issuer: _config.jwtIssuer,
        jwtId: _generateJwtId(),
      );

      final token = jwt.sign(
        SecretKey(_config.jwtSecret),
        expiresIn: _config.tokenExpiry,
      );

      _logger.debug('Generated access token for user: $userId');
      return token;
    } catch (e, stackTrace) {
      _logger.error('Failed to generate token', e, stackTrace);
      throw JWTTokenException('Failed to generate token: $e', cause: e);
    }
  }

  /// Generates a JWT refresh token.
  ///
  /// Refresh tokens have longer expiration and include a 'refresh' claim.
  ///
  /// ## Parameters
  ///
  /// - [userId]: The user's unique identifier.
  /// - [roles]: List of role names for the user.
  ///
  /// ## Returns
  ///
  /// A signed JWT refresh token string.
  String generateRefreshToken({
    required String userId,
    required List<String> roles,
  }) {
    try {
      final payload = <String, dynamic>{
        'sub': userId,
        'roles': roles,
        'refresh': true,
      };

      final jwt = JWT(
        payload,
        issuer: _config.jwtIssuer,
        jwtId: _generateJwtId(),
      );

      final token = jwt.sign(
        SecretKey(_config.jwtSecret),
        expiresIn: _config.refreshTokenExpiry,
      );

      _logger.debug('Generated refresh token for user: $userId');
      return token;
    } catch (e, stackTrace) {
      _logger.error('Failed to generate refresh token', e, stackTrace);
      throw JWTTokenException('Failed to generate refresh token: $e', cause: e);
    }
  }

  /// Verifies a JWT token and extracts its claims.
  ///
  /// ## Parameters
  ///
  /// - [token]: The JWT token string to verify.
  ///
  /// ## Returns
  ///
  /// [TokenClaims] containing the token payload.
  ///
  /// ## Throws
  ///
  /// - [InvalidOrExpiredTokenException]: If the token is invalid or expired.
  ///
  /// ## Example
  ///
  /// ```dart
  /// try {
  ///   final claims = security.verifyToken(token);
  ///   print('User ID: ${claims.userId}');
  ///   print('Roles: ${claims.roles}');
  /// } on InvalidOrExpiredTokenException {
  ///   print('Token is invalid or expired');
  /// }
  /// ```
  TokenClaims verifyToken(String token) {
    if (token.isEmpty) {
      throw const InvalidOrExpiredTokenException('Token cannot be empty');
    }

    try {
      final jwt = JWT.verify(
        token,
        SecretKey(_config.jwtSecret),
        issuer: _config.jwtIssuer,
      );

      final claims = TokenClaims.fromJwtPayload(
        jwt.payload as Map<String, dynamic>,
      );

      _logger.debug('Token verified for user: ${claims.userId}');
      return claims;
    } on JWTExpiredException {
      _logger.debug('Token expired');
      throw const InvalidOrExpiredTokenException('Token has expired');
    } on JWTException catch (e) {
      _logger.debug('Token verification failed: $e');
      throw InvalidOrExpiredTokenException('Invalid token: $e');
    } catch (e, stackTrace) {
      _logger.error('Token verification error', e, stackTrace);
      throw InvalidOrExpiredTokenException('Token verification failed: $e');
    }
  }

  /// Checks if a token is valid without throwing.
  ///
  /// ## Parameters
  ///
  /// - [token]: The JWT token to check.
  ///
  /// ## Returns
  ///
  /// `true` if the token is valid, `false` otherwise.
  bool isTokenValid(String token) {
    try {
      verifyToken(token);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Refreshes an access token using a refresh token.
  ///
  /// Verifies the refresh token and generates a new access token.
  ///
  /// ## Parameters
  ///
  /// - [refreshToken]: A valid refresh token.
  ///
  /// ## Returns
  ///
  /// A new access token.
  ///
  /// ## Throws
  ///
  /// - [InvalidOrExpiredTokenException]: If the refresh token is invalid.
  /// - [JWTTokenException]: If the token is not a refresh token.
  String refreshAccessToken(String refreshToken) {
    final claims = verifyToken(refreshToken);

    if (!claims.isRefreshToken) {
      throw const JWTTokenException('Token is not a refresh token');
    }

    return generateToken(userId: claims.userId, roles: claims.roles);
  }

  /// Extracts claims from a token without verification.
  ///
  /// **Warning**: This does not verify the token signature.
  /// Use only for debugging or when verification is done elsewhere.
  ///
  /// ## Parameters
  ///
  /// - [token]: The JWT token to decode.
  ///
  /// ## Returns
  ///
  /// [TokenClaims] from the token payload, or `null` if decoding fails.
  TokenClaims? decodeTokenUnsafe(String token) {
    try {
      final jwt = JWT.decode(token);
      return TokenClaims.fromJwtPayload(jwt.payload as Map<String, dynamic>);
    } catch (e) {
      _logger.debug('Failed to decode token: $e');
      return null;
    }
  }

  /// Generates a unique JWT ID.
  String _generateJwtId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  // ---------------------------------------------------------------------------
  // Utility Methods
  // ---------------------------------------------------------------------------

  /// Calculates the lockout expiration time.
  ///
  /// ## Returns
  ///
  /// A [DateTime] when the lockout should expire.
  DateTime calculateLockoutExpiry() {
    return DateTime.now().add(_config.lockoutDuration);
  }

  /// Checks if a user should be locked out based on failed attempts.
  ///
  /// ## Parameters
  ///
  /// - [failedAttempts]: The current number of failed login attempts.
  ///
  /// ## Returns
  ///
  /// `true` if the account should be locked.
  bool shouldLockout(int failedAttempts) {
    return failedAttempts >= _config.maxFailedLoginAttempts;
  }

  @override
  String toString() {
    return 'SecurityService(issuer: ${_config.jwtIssuer}, '
        'tokenExpiry: ${_config.tokenExpiry})';
  }
}
