import 'package:web/web.dart' as web;

web.AudioContext? _context;

bool beepSupported() => true;

/// A 40ms blip at 1kHz, loud enough to hear across a room and short enough to
/// be a point in time rather than a note.
///
/// The envelope is there so it starts and stops without the crack a square
/// switch-off makes - a crack is itself a transient and would blur the very
/// edge this is meant to be.
void playBeep() {
  try {
    final context = _context ??= web.AudioContext();
    if (context.state == 'suspended') context.resume();

    final oscillator = context.createOscillator();
    final gain = context.createGain();
    oscillator.frequency.value = 1000;
    oscillator.connect(gain);
    gain.connect(context.destination);

    final now = context.currentTime;
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(0.3, now + 0.004);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.04);
    oscillator.start(now);
    oscillator.stop(now + 0.05);
  } on Object {
    // No Web Audio, or a browser that refuses it. The flash still flashes and
    // the numbers can still be set by hand.
  }
}
