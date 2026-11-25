import 'package:flutter/services.dart';

const _channel = MethodChannel('deskpilot/feedback');

/// DeskPilot's own click, at media volume, so it plays even when the
/// tablet's touch sounds are off. Elsewhere it falls back to the system click.
Future<void> playClick() async {
  try {
    await _channel.invokeMethod<void>('click');
  } on MissingPluginException {
    await SystemSound.play(SystemSoundType.click);
  }
}

/// A short buzz that doesn't depend on Android's touch vibration setting.
/// Elsewhere it falls back to the system's light haptic.
Future<void> vibrate() async {
  try {
    await _channel.invokeMethod<void>('vibrate');
  } on MissingPluginException {
    await HapticFeedback.lightImpact();
  }
}

/// Whether this phone has a vibration motor; many tablets don't.
Future<bool> canVibrate() async {
  try {
    return await _channel.invokeMethod<bool>('canVibrate') ?? false;
  } on MissingPluginException {
    return true; // only Android answers this so far
  }
}
