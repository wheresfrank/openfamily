import 'dart:io' show Platform;

/// Real (native) platform checks, backed by dart:io.
bool get isAndroid => Platform.isAndroid;
bool get isIOS => Platform.isIOS;