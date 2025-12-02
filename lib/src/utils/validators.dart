// lib/src/utils/validators.dart
bool isValidEmail(String email) {
  if (email.isEmpty) return false;
  final emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  return emailRegex.hasMatch(email);
}

bool isValidVersion(String version) {
  if (version.isEmpty) return false;
  final versionRegex = RegExp(r'^\d+\.\d+\.\d+$');
  return versionRegex.hasMatch(version);
}
