import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  test('search finds smileys by keyword', () {
    final hits = EmojiSearch.search('laugh');
    expect(hits, isNotEmpty);
    expect(hits, contains('😂'));
  });

  test('search finds thumbs up', () {
    final hits = EmojiSearch.search('thumbs');
    expect(hits, contains('👍'));
  });

  test('search finds heart', () {
    final hits = EmojiSearch.search('heart');
    expect(hits, contains('❤️'));
    expect(hits.length, greaterThan(3));
  });

  test('search finds fire', () {
    expect(EmojiSearch.search('fire'), contains('🔥'));
  });

  test('multi-term AND search', () {
    final hits = EmojiSearch.search('red heart');
    expect(hits, contains('❤️'));
  });

  test('empty query returns empty', () {
    expect(EmojiSearch.search(''), isEmpty);
    expect(EmojiSearch.search('   '), isEmpty);
  });

  test('unknown word returns empty', () {
    expect(EmojiSearch.search('xyzzynotanemoji'), isEmpty);
  });

  test('category word returns members', () {
    final food = EmojiSearch.search('food');
    expect(food, isNotEmpty);
    expect(food, contains('🍕'));
  });

  test('fuzzy prefix ranks best first', () {
    final hits = EmojiSearch.search('hea');
    expect(hits, isNotEmpty);
    // Heart-related should appear before unrelated category noise.
    expect(hits.take(8), contains('❤️'));
  });

  test('subsequence fuzzy match', () {
    // h-e-a-r-t letters in order
    final hits = EmojiSearch.search('hrt');
    expect(hits, contains('❤️'));
  });

  test('typo tolerance', () {
    final hits = EmojiSearch.search('hearr'); // heart + typo
    expect(hits, contains('❤️'));
  });

  test('thumb prefix finds thumbs up early', () {
    final hits = EmojiSearch.search('thumb');
    expect(hits.first, '👍');
  });
}
