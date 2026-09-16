import 'package:flutter/widgets.dart';

/// Tells a screen that the route above it is gone again.
///
/// The setup screen reads the saved game once at startup - and a game left by
/// the back button is still saved, so without this its resume card would only
/// come back after a reload.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
