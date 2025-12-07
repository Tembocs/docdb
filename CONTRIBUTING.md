# Contributing to DocDB

Thank you for your interest in contributing to DocDB! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We're all here to build something great together.

## Getting Started

### Prerequisites

- Dart SDK 3.10 or higher
- Git

### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/docdb.git
   cd docdb
   ```
3. Install dependencies:
   ```bash
   dart pub get
   ```
4. Run tests to ensure everything works:
   ```bash
   dart test
   ```

## Development Workflow

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring

### Making Changes

1. Create a new branch from `main`:
   ```bash
   git checkout -b feature/my-feature
   ```

2. Make your changes following our coding standards

3. Run the linter and formatter:
   ```bash
   dart format .
   dart analyze
   ```

4. Run tests:
   ```bash
   dart test
   ```

5. Commit your changes with a descriptive message:
   ```bash
   git commit -m "feat: add new query type for geospatial data"
   ```

### Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `refactor:` - Code refactoring
- `test:` - Test updates
- `perf:` - Performance improvement
- `ci:` - CI/CD changes
- `chore:` - Maintenance

### Submitting a Pull Request

1. Push your branch:
   ```bash
   git push origin feature/my-feature
   ```

2. Open a Pull Request on GitHub

3. Fill out the PR template completely

4. Wait for CI checks to pass

5. Address any review feedback

## Coding Standards

### Code Style

- Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Use `dart format` for consistent formatting
- Keep lines under 80 characters when reasonable

### Documentation

- Add doc comments to all public APIs
- Include examples in doc comments where helpful
- Update README.md for user-facing changes

### Testing

- Write tests for all new functionality
- Maintain or improve code coverage
- Test edge cases and error conditions

### Example Test Structure

```dart
group('MyFeature', () {
  late MyClass instance;
  
  setUp(() {
    instance = MyClass();
  });
  
  tearDown(() {
    instance.dispose();
  });
  
  test('should do something', () {
    expect(instance.doSomething(), equals(expected));
  });
});
```

## Project Structure

```
lib/
├── docdb.dart           # Main library export
└── src/
    ├── collection/      # Collection management
    ├── engine/          # Storage engine (pager, WAL, buffer)
    ├── entity/          # Entity interface
    ├── index/           # Index implementations
    ├── query/           # Query system
    ├── storage/         # Storage backends
    └── ...

test/
├── collection/          # Mirrors lib/src structure
├── engine/
└── ...

example/
├── benchmark.dart       # Performance benchmarks
└── *.dart               # Usage examples
```

## Running Benchmarks

```bash
dart run example/benchmark.dart
```

## Generating Documentation

```bash
dart doc .
# Open doc/api/index.html in a browser
```

## Need Help?

- Open an issue for bugs or feature requests
- Start a discussion for questions
- Check existing issues before creating new ones

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
