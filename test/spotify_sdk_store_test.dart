import 'package:anno/data/spotify_sdk_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpotifySdkStore.preload();
  });

  test('starts false, and a failure is remembered past a reload', () async {
    expect(SpotifySdkStore.sdkFailed, isFalse);

    await SpotifySdkStore.markFailed();
    expect(SpotifySdkStore.sdkFailed, isTrue);

    // A fresh preload is what the next launch does - the mark has to survive
    // it, or a phone would pay for the same failed attempt every evening.
    await SpotifySdkStore.preload();
    expect(SpotifySdkStore.sdkFailed, isTrue);
  });
}
