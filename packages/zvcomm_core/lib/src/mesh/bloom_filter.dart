import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Compact probabilistic set for mesh dedup of aged message keys.
///
/// False positives possible (treat as already-seen); false negatives never.
final class BloomFilter {
  final int bitCount;
  final int hashCount;
  final Uint8List _bits;

  BloomFilter({
    this.bitCount = 8192 * 8, // 8 KiB
    this.hashCount = 4,
  }) : _bits = Uint8List((bitCount + 7) ~/ 8) {
    if (bitCount < 64 || hashCount < 1) {
      throw ArgumentError('invalid bloom parameters');
    }
  }

  int get byteLength => _bits.length;

  void add(String key) {
    for (final i in _indexes(key)) {
      _bits[i >> 3] |= 1 << (i & 7);
    }
  }

  /// `true` if [key] may have been added (or false-positive).
  bool mightContain(String key) {
    for (final i in _indexes(key)) {
      if ((_bits[i >> 3] & (1 << (i & 7))) == 0) return false;
    }
    return true;
  }

  void clear() => _bits.fillRange(0, _bits.length, 0);

  Iterable<int> _indexes(String key) sync* {
    final digest = sha256.convert(utf8.encode(key)).bytes;
    for (var h = 0; h < hashCount; h++) {
      final o = (h * 4) % (digest.length - 3);
      final v = (digest[o] << 24) |
          (digest[o + 1] << 16) |
          (digest[o + 2] << 8) |
          digest[o + 3];
      yield v.abs() % bitCount;
    }
  }
}

/// Exact LRU window + bloom for keys that age out of the window.
///
/// Policy: exact match on recent keys; bloom only holds **evicted** keys so a
/// bloom hit means "already seen" (rare false positives may drop a new msg).
final class HybridPacketDeduper {
  final int exactCapacity;
  final BloomFilter bloom;
  final _OrderedSet _exact = _OrderedSet();

  HybridPacketDeduper({
    this.exactCapacity = 2048,
    int bloomBits = 8192 * 8,
    int bloomHashes = 4,
  }) : bloom = BloomFilter(bitCount: bloomBits, hashCount: bloomHashes);

  /// Returns `true` if this is the first observation of [key].
  bool observe(String key) {
    if (_exact.contains(key)) return false;
    if (bloom.mightContain(key)) return false;

    _exact.add(key);
    while (_exact.length > exactCapacity) {
      bloom.add(_exact.removeFirst());
    }
    return true;
  }

  void clear() {
    _exact.clear();
    bloom.clear();
  }

  int get exactLength => _exact.length;
}

/// Insertion-ordered unique keys with O(1) contains + remove-first.
final class _OrderedSet {
  final Map<String, _Node> _map = {};
  _Node? _head;
  _Node? _tail;

  int get length => _map.length;

  bool contains(String key) => _map.containsKey(key);

  void add(String key) {
    if (_map.containsKey(key)) return;
    final node = _Node(key);
    _map[key] = node;
    if (_tail == null) {
      _head = _tail = node;
    } else {
      _tail!.next = node;
      node.prev = _tail;
      _tail = node;
    }
  }

  String removeFirst() {
    final h = _head;
    if (h == null) throw StateError('empty');
    _head = h.next;
    if (_head == null) {
      _tail = null;
    } else {
      _head!.prev = null;
    }
    _map.remove(h.key);
    return h.key;
  }

  void clear() {
    _map.clear();
    _head = _tail = null;
  }
}

final class _Node {
  final String key;
  _Node? prev;
  _Node? next;
  _Node(this.key);
}
