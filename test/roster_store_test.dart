// The roster outlives the saved game: GameStore is cleared when a game ends,
// which is exactly when the names are worth keeping for the next evening.
import 'package:flutter_test/flutter_test.dart';
import 'package:play/data/roster_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing stored means no names', () async {
    expect(await RosterStore.load(), isEmpty);
  });

  test('names survive a round trip in order', () async {
    await RosterStore.save(['Anna', 'Ben', 'Cleo']);
    expect(await RosterStore.load(), ['Anna', 'Ben', 'Cleo']);
  });

  test('the last roster replaces the one before', () async {
    await RosterStore.save(['Anna', 'Ben']);
    await RosterStore.save(['Cleo']);
    expect(await RosterStore.load(), ['Cleo']);
  });

  test('an empty roster leaves the stored one alone', () async {
    await RosterStore.save(['Anna']);
    await RosterStore.save([]);
    expect(await RosterStore.load(), ['Anna']);
  });

  test('blank entries and stray whitespace are dropped', () async {
    await RosterStore.save(['  Anna  ', '', '   ', 'Ben']);
    expect(await RosterStore.load(), ['Anna', 'Ben']);
  });

  test('a broken value does not take the setup screen down', () async {
    SharedPreferences.setMockInitialValues({'roster.names': 'not json'});
    expect(await RosterStore.load(), isEmpty);
  });
}
