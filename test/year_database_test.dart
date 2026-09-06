import 'package:flutter_test/flutter_test.dart';
import 'package:play/data/year_database.dart';

void main() {
  group('normalizeKey', () {
    test('takes the last path segment of a card link', () {
      expect(
        YearDatabase.normalizeKey(
          'https://play-the-music.com/de/year/182ca01194a98f0b',
        ),
        '182ca01194a98f0b',
      );
    });

    test('ignores case and surrounding whitespace', () {
      expect(
        YearDatabase.normalizeKey('  HTTPS://PLAY-THE-MUSIC.COM/de/year/AB12 '),
        'ab12',
      );
    });

    test('leaves a code without a URL alone', () {
      expect(YearDatabase.normalizeKey('1987'), '1987');
    });
  });

  group('yearFor', () {
    final db = YearDatabase.inMemory(
      defaults: {'182ca01194a98f0b': 2005},
      local: {'86e8ba66ab81706c': 2023},
    );

    test('finds bundled and own entries', () {
      expect(
        db.yearFor('https://play-the-music.com/de/year/182ca01194a98f0b'),
        2005,
      );
      expect(db.yearFor('86e8ba66ab81706c'), 2023);
    });

    test('accepts a bare year as the code', () {
      expect(db.yearFor('1987'), 1987);
    });

    test('reports unknown codes', () {
      expect(db.yearFor('https://play-the-music.com/de/year/deadbeef'), isNull);
      expect(db.yearFor('42'), isNull);
    });
  });

  test('own entries override bundled ones', () async {
    final db = YearDatabase.inMemory(defaults: {'abc': 1999});
    await db.setYear('https://play-the-music.com/de/year/ABC', 2001);

    expect(db.yearFor('abc'), 2001);
    expect(db.isLocal('abc'), isTrue);

    await db.removeLocal('abc');
    expect(db.yearFor('abc'), 1999);
  });

  test('an export can be imported again', () async {
    final source = YearDatabase.inMemory(
      defaults: {'abc': 1999},
      local: {'def': 2010},
    );
    final target = YearDatabase.inMemory();

    final result = await target.importJson(source.exportJson());

    expect(result.added, 2);
    expect(result.updated, 0);
    expect(target.yearFor('abc'), 1999);
    expect(target.yearFor('def'), 2010);
  });

  test('import accepts a flat map and counts the changes', () async {
    final db = YearDatabase.inMemory(local: {'abc': 1999});

    final result = await db.importJson('{"abc": 2000, "xyz": 1975}');

    expect(result.added, 1);
    expect(result.updated, 1);
    expect(db.yearFor('abc'), 2000);
  });

  test('import skips unusable values', () async {
    final db = YearDatabase.inMemory();

    final result = await db.importJson(
      '{"_comment": "hello", "abc": "not a number", "def": 3000, "ghi": 1980}',
    );

    expect(result.added, 1);
    expect(result.skipped, 3);
    expect(db.yearFor('ghi'), 1980);
  });

  test('broken JSON throws a FormatException', () {
    final db = YearDatabase.inMemory();
    expect(() => db.importJson('no json'), throwsFormatException);
    expect(() => db.importJson('[1, 2, 3]'), throwsFormatException);
  });
}
