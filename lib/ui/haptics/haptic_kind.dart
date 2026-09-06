/// The kinds of feedback the game gives.
enum HapticKind {
  /// One second of the countdown passed.
  tick,

  /// A point was handed out.
  point,

  /// A point was taken back.
  undo,

  /// The year was revealed.
  reveal,
}
