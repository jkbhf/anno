import 'dart:async';

import 'package:flutter/material.dart';

import 'haptics/haptics.dart';

/// Fullscreen countdown between the scan and Spotify.
///
/// Returns `true` when it ran through and `false` when the round was cancelled.
class CountdownScreen extends StatefulWidget {
  const CountdownScreen({this.from = 3, super.key});

  final int from;

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  late int _remaining = widget.from;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Haptics.tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      Haptics.tick();
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                color: theme.colorScheme.onPrimary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Text(
                      '$_remaining',
                      key: ValueKey(_remaining),
                      style: TextStyle(
                        fontSize: 160,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Here we go',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
