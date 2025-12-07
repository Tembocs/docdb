/// Full-Text Search Index implementation for EntiDB.
///
/// This module provides a full-text search index using an inverted index
/// structure with tokenization, normalization, and relevance scoring.
///
/// ## Features
///
/// - Text tokenization with configurable separators
/// - Case-insensitive search by default
/// - Stop word filtering
/// - Prefix matching support
/// - Phrase matching (exact sequence)
/// - TF-IDF based relevance scoring
/// - Proximity search (words near each other)
///
/// ## Performance Characteristics
///
/// | Operation | Time Complexity |
/// |-----------|-----------------|
/// | Insert    | O(t) where t = tokens in document |
/// | Remove    | O(t) where t = tokens in document |
/// | Search    | O(k + r) where k = query tokens, r = results |
/// | Phrase    | O(k * p) where p = positions to check |
///
/// ## Example
///
/// ```dart
/// final index = FullTextIndex('content');
///
/// // Insert documents
/// index.insert('doc-1', {'content': 'The quick brown fox'});
/// index.insert('doc-2', {'content': 'A lazy brown dog'});
///
/// // Search for terms
/// final results = index.search('brown');
/// // results: ['doc-1', 'doc-2']
///
/// // Phrase search
/// final exact = index.searchPhrase('quick brown');
/// // exact: ['doc-1']
/// ```
library;

import 'dart:math' as math;

import 'i_index.dart';

/// Configuration options for full-text indexing.
class FullTextConfig {
  /// Minimum token length to index.
  final int minTokenLength;

  /// Maximum token length to index.
  final int maxTokenLength;

  /// Whether to convert tokens to lowercase.
  final bool caseSensitive;

  /// Custom word separators pattern.
  final Pattern tokenSeparators;

  /// Stop words to exclude from indexing.
  final Set<String> stopWords;

  /// Whether to enable position tracking for phrase queries.
  final bool enablePositions;

  /// Creates a full-text configuration.
  const FullTextConfig({
    this.minTokenLength = 2,
    this.maxTokenLength = 100,
    this.caseSensitive = false,
    this.tokenSeparators = _defaultSeparators,
    this.stopWords = _defaultStopWords,
    this.enablePositions = true,
  });

  /// Default separators: whitespace and common punctuation.
  static const Pattern _defaultSeparators = r'[\s\p{P}]+';

  /// Common English stop words.
  static const Set<String> _defaultStopWords = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'for',
    'from',
    'has',
    'have',
    'he',
    'in',
    'is',
    'it',
    'its',
    'of',
    'on',
    'or',
    'that',
    'the',
    'to',
    'was',
    'were',
    'will',
    'with',
  };

  /// Creates a configuration with no stop words.
  const FullTextConfig.noStopWords({
    this.minTokenLength = 2,
    this.maxTokenLength = 100,
    this.caseSensitive = false,
    this.tokenSeparators = _defaultSeparators,
    this.enablePositions = true,
  }) : stopWords = const {};

  /// Creates a configuration for exact matching (case-sensitive, no stop words).
  const FullTextConfig.exact({
    this.minTokenLength = 1,
    this.maxTokenLength = 100,
    this.tokenSeparators = _defaultSeparators,
    this.enablePositions = true,
  }) : caseSensitive = true,
       stopWords = const {};
}

/// Represents a term posting with position information.
class TermPosting {
  /// The entity ID containing this term.
  final String entityId;

  /// Positions where this term appears in the document.
  final List<int> positions;

  /// Term frequency in this document.
  int get termFrequency => positions.length;

  /// Creates a term posting.
  TermPosting(this.entityId, [List<int>? positions])
    : positions = positions ?? [];

  /// Adds a new position for this term.
  void addPosition(int position) {
    positions.add(position);
  }
}

/// Full-text search index using an inverted index structure.
///
/// This index tokenizes text fields and builds an inverted index mapping
/// terms to documents containing them. Supports various search operations
/// including term search, phrase search, and prefix matching.
class FullTextIndex implements IIndex {
  @override
  final String field;

  /// Configuration options for this index.
  final FullTextConfig config;

  /// Inverted index: term -> (entityId -> posting).
  final Map<String, Map<String, TermPosting>> _invertedIndex = {};

  /// Forward index: entityId -> list of tokens.
  /// Used for document removal and term frequency calculation.
  final Map<String, List<String>> _forwardIndex = {};

  /// Document count for IDF calculation.
  int get documentCount => _forwardIndex.length;

  /// Compiled regex for tokenization.
  late final RegExp _tokenizer;

  /// Creates a new full-text index on the specified [field].
  FullTextIndex(this.field, {FullTextConfig? config})
    : config = config ?? const FullTextConfig() {
    _tokenizer = RegExp(this.config.tokenSeparators.toString());
  }

  @override
  void insert(String entityId, Map<String, dynamic> data) {
    final value = data[field];
    if (value == null) {
      return;
    }

    final text = value.toString();
    final tokens = _tokenize(text);

    if (tokens.isEmpty) {
      return;
    }

    // Store in forward index for removal
    _forwardIndex[entityId] = tokens;

    // Build inverted index with positions
    for (var position = 0; position < tokens.length; position++) {
      final token = tokens[position];
      final postings = _invertedIndex.putIfAbsent(
        token,
        () => <String, TermPosting>{},
      );

      if (postings.containsKey(entityId)) {
        if (config.enablePositions) {
          postings[entityId]!.addPosition(position);
        }
      } else {
        postings[entityId] = TermPosting(
          entityId,
          config.enablePositions ? [position] : null,
        );
      }
    }
  }

  @override
  void remove(String entityId, Map<String, dynamic> data) {
    // Get tokens from forward index
    final tokens = _forwardIndex.remove(entityId);
    if (tokens == null) {
      return;
    }

    // Remove from inverted index
    final uniqueTokens = tokens.toSet();
    for (final token in uniqueTokens) {
      final postings = _invertedIndex[token];
      if (postings != null) {
        postings.remove(entityId);
        if (postings.isEmpty) {
          _invertedIndex.remove(token);
        }
      }
    }
  }

  @override
  List<String> search(dynamic value) {
    if (value == null) {
      return const [];
    }

    final queryText = value.toString();
    final queryTokens = _tokenize(queryText);

    if (queryTokens.isEmpty) {
      return const [];
    }

    // For single-term queries
    if (queryTokens.length == 1) {
      final postings = _invertedIndex[queryTokens.first];
      return postings?.keys.toList() ?? const [];
    }

    // For multi-term queries, return documents containing all terms (AND)
    return searchAll(queryTokens);
  }

  /// Searches for documents containing all specified terms.
  ///
  /// Returns entity IDs where all terms appear (AND semantics).
  List<String> searchAll(List<String> terms) {
    if (terms.isEmpty) {
      return const [];
    }

    // Normalize terms
    final normalizedTerms = terms
        .map((t) => config.caseSensitive ? t : t.toLowerCase())
        .toList();

    // Start with documents containing the first term
    final firstPostings = _invertedIndex[normalizedTerms.first];
    if (firstPostings == null || firstPostings.isEmpty) {
      return const [];
    }

    Set<String> result = firstPostings.keys.toSet();

    // Intersect with documents containing remaining terms
    for (var i = 1; i < normalizedTerms.length; i++) {
      final postings = _invertedIndex[normalizedTerms[i]];
      if (postings == null || postings.isEmpty) {
        return const [];
      }
      result = result.intersection(postings.keys.toSet());
      if (result.isEmpty) {
        return const [];
      }
    }

    return result.toList();
  }

  /// Searches for documents containing any of the specified terms.
  ///
  /// Returns entity IDs where at least one term appears (OR semantics).
  List<String> searchAny(List<String> terms) {
    if (terms.isEmpty) {
      return const [];
    }

    final normalizedTerms = terms
        .map((t) => config.caseSensitive ? t : t.toLowerCase())
        .toList();

    final result = <String>{};
    for (final term in normalizedTerms) {
      final postings = _invertedIndex[term];
      if (postings != null) {
        result.addAll(postings.keys);
      }
    }

    return result.toList();
  }

  /// Searches for an exact phrase (terms appearing consecutively).
  ///
  /// Requires [FullTextConfig.enablePositions] to be true.
  /// Returns entity IDs where the exact phrase appears.
  List<String> searchPhrase(String phrase) {
    if (!config.enablePositions) {
      throw StateError(
        'Phrase search requires enablePositions to be true in FullTextConfig',
      );
    }

    final tokens = _tokenize(phrase);
    if (tokens.isEmpty) {
      return const [];
    }

    if (tokens.length == 1) {
      return search(tokens.first);
    }

    // Get documents containing all terms
    final candidates = searchAll(tokens);
    if (candidates.isEmpty) {
      return const [];
    }

    // Check for consecutive positions
    final results = <String>[];
    for (final entityId in candidates) {
      if (_hasConsecutivePositions(entityId, tokens)) {
        results.add(entityId);
      }
    }

    return results;
  }

  /// Searches for terms within a specified distance of each other.
  ///
  /// [maxDistance] is the maximum number of words between terms.
  /// Requires [FullTextConfig.enablePositions] to be true.
  List<String> searchProximity(List<String> terms, int maxDistance) {
    if (!config.enablePositions) {
      throw StateError(
        'Proximity search requires enablePositions to be true in FullTextConfig',
      );
    }

    if (terms.isEmpty) {
      return const [];
    }

    final normalizedTerms = terms
        .map((t) => config.caseSensitive ? t : t.toLowerCase())
        .toList();

    if (normalizedTerms.length == 1) {
      return search(normalizedTerms.first);
    }

    // Get documents containing all terms
    final candidates = searchAll(normalizedTerms);
    if (candidates.isEmpty) {
      return const [];
    }

    // Check proximity for each candidate
    final results = <String>[];
    for (final entityId in candidates) {
      if (_isWithinProximity(entityId, normalizedTerms, maxDistance)) {
        results.add(entityId);
      }
    }

    return results;
  }

  /// Searches for terms starting with the given prefix.
  ///
  /// Returns entity IDs containing any term starting with [prefix].
  List<String> searchPrefix(String prefix) {
    if (prefix.isEmpty) {
      return const [];
    }

    final normalizedPrefix = config.caseSensitive
        ? prefix
        : prefix.toLowerCase();

    final result = <String>{};
    for (final entry in _invertedIndex.entries) {
      if (entry.key.startsWith(normalizedPrefix)) {
        result.addAll(entry.value.keys);
      }
    }

    return result.toList();
  }

  /// Performs a ranked search using TF-IDF scoring.
  ///
  /// Returns a list of [ScoredResult] sorted by relevance score (descending).
  List<ScoredResult> searchRanked(String query) {
    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty) {
      return const [];
    }

    final scores = <String, double>{};

    for (final token in queryTokens) {
      final postings = _invertedIndex[token];
      if (postings == null) {
        continue;
      }

      // Calculate IDF: log(N / df)
      final idf = _log2(
        documentCount / postings.length.toDouble(),
      ).clamp(0.0, 100.0);

      for (final entry in postings.entries) {
        final entityId = entry.key;
        final tf = entry.value.termFrequency;

        // TF-IDF score
        final score = (1 + _log2(tf.toDouble())) * idf;
        scores.update(entityId, (v) => v + score, ifAbsent: () => score);
      }
    }

    // Sort by score descending
    final sortedEntries = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries.map((e) => ScoredResult(e.key, e.value)).toList();
  }

  @override
  void clear() {
    _invertedIndex.clear();
    _forwardIndex.clear();
  }

  /// Returns the number of unique terms in the index.
  int get termCount => _invertedIndex.length;

  /// Returns the total number of indexed documents.
  int get entryCount => _forwardIndex.length;

  /// Returns the document frequency for a term.
  int getDocumentFrequency(String term) {
    final normalized = config.caseSensitive ? term : term.toLowerCase();
    return _invertedIndex[normalized]?.length ?? 0;
  }

  /// Returns all indexed terms (vocabulary).
  Iterable<String> get terms => _invertedIndex.keys;

  /// Tokenizes text into a list of normalized tokens.
  List<String> _tokenize(String text) {
    final tokens = <String>[];

    // Split by configured separators
    final parts = text.split(_tokenizer);

    for (final part in parts) {
      final token = config.caseSensitive ? part : part.toLowerCase();

      // Apply length constraints
      if (token.length < config.minTokenLength ||
          token.length > config.maxTokenLength) {
        continue;
      }

      // Filter stop words
      if (config.stopWords.contains(token)) {
        continue;
      }

      tokens.add(token);
    }

    return tokens;
  }

  /// Checks if tokens appear consecutively in the document.
  bool _hasConsecutivePositions(String entityId, List<String> tokens) {
    // Get positions for the first token
    final firstPostings = _invertedIndex[tokens.first]?[entityId];
    if (firstPostings == null) {
      return false;
    }

    // For each starting position of the first token
    for (final startPos in firstPostings.positions) {
      bool match = true;

      // Check if remaining tokens follow consecutively
      for (var i = 1; i < tokens.length; i++) {
        final expectedPos = startPos + i;
        final posting = _invertedIndex[tokens[i]]?[entityId];

        if (posting == null || !posting.positions.contains(expectedPos)) {
          match = false;
          break;
        }
      }

      if (match) {
        return true;
      }
    }

    return false;
  }

  /// Checks if terms appear within the specified proximity.
  bool _isWithinProximity(
    String entityId,
    List<String> terms,
    int maxDistance,
  ) {
    // Get all positions for each term
    final termPositions = <List<int>>[];
    for (final term in terms) {
      final posting = _invertedIndex[term]?[entityId];
      if (posting == null || posting.positions.isEmpty) {
        return false;
      }
      termPositions.add(List.from(posting.positions)..sort());
    }

    // Check if there's a window where all terms appear within maxDistance
    return _checkProximityWindow(termPositions, maxDistance);
  }

  /// Checks if all term positions can fit within a proximity window.
  bool _checkProximityWindow(List<List<int>> termPositions, int maxDistance) {
    // Use a sliding window approach
    // Find the minimum span containing at least one position from each term
    final pointers = List<int>.filled(termPositions.length, 0);

    while (true) {
      // Find current min and max positions
      int minPos = termPositions[0][pointers[0]];
      int maxPos = minPos;
      int minIdx = 0;

      for (var i = 1; i < termPositions.length; i++) {
        final pos = termPositions[i][pointers[i]];
        if (pos < minPos) {
          minPos = pos;
          minIdx = i;
        }
        if (pos > maxPos) {
          maxPos = pos;
        }
      }

      // Check if current window satisfies proximity
      if (maxPos - minPos <= maxDistance) {
        return true;
      }

      // Advance the pointer at the minimum position
      pointers[minIdx]++;
      if (pointers[minIdx] >= termPositions[minIdx].length) {
        break;
      }
    }

    return false;
  }

  /// Log base 2 calculation for TF-IDF.
  double _log2(double x) {
    if (x <= 0) return 0;
    if (x == 1) return 0;
    return math.log(x) / math.ln2;
  }

  // ===========================================================================
  // Serialization Support
  // ===========================================================================

  /// Exports the index state as a map for persistence.
  ///
  /// Returns a map containing:
  /// - 'inverted': The inverted index structure
  /// - 'forward': The forward index structure
  /// - 'config': Configuration settings
  Map<String, dynamic> toMap() {
    final invertedMap = <String, Map<String, dynamic>>{};
    for (final entry in _invertedIndex.entries) {
      final postingsMap = <String, dynamic>{};
      for (final posting in entry.value.entries) {
        postingsMap[posting.key] = {'positions': posting.value.positions};
      }
      invertedMap[entry.key] = postingsMap;
    }

    final forwardMap = <String, List<String>>{};
    for (final entry in _forwardIndex.entries) {
      forwardMap[entry.key] = entry.value;
    }

    return {
      'inverted': invertedMap,
      'forward': forwardMap,
      'config': {
        'minTokenLength': config.minTokenLength,
        'maxTokenLength': config.maxTokenLength,
        'caseSensitive': config.caseSensitive,
        'enablePositions': config.enablePositions,
      },
    };
  }

  /// Restores the index state from a serialized map.
  ///
  /// Clears existing entries and populates from the provided [data].
  void restoreFromMap(Map<String, dynamic> data) {
    clear();

    // Restore inverted index
    final invertedMap = data['inverted'] as Map<String, dynamic>?;
    if (invertedMap != null) {
      for (final entry in invertedMap.entries) {
        final term = entry.key;
        final postingsMap = entry.value as Map<String, dynamic>;
        final postings = <String, TermPosting>{};

        for (final postingEntry in postingsMap.entries) {
          final entityId = postingEntry.key;
          final postingData = postingEntry.value as Map<String, dynamic>;
          final positions =
              (postingData['positions'] as List?)?.cast<int>().toList() ??
              <int>[];
          postings[entityId] = TermPosting(entityId, positions);
        }

        _invertedIndex[term] = postings;
      }
    }

    // Restore forward index
    final forwardMap = data['forward'] as Map<String, dynamic>?;
    if (forwardMap != null) {
      for (final entry in forwardMap.entries) {
        _forwardIndex[entry.key] = (entry.value as List)
            .cast<String>()
            .toList();
      }
    }
  }
}

/// A search result with relevance score.
class ScoredResult {
  /// The entity ID.
  final String entityId;

  /// The relevance score (higher is more relevant).
  final double score;

  /// Creates a scored result.
  const ScoredResult(this.entityId, this.score);

  @override
  String toString() => 'ScoredResult($entityId, score: $score)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoredResult &&
          entityId == other.entityId &&
          score == other.score;

  @override
  int get hashCode => Object.hash(entityId, score);
}
