import 'package:fl_lib/fl_lib.dart';

/// SSH operation logger with multiple levels
class SSHLogger {
  final bool enableDebug;
  final String prefix;
  
  SSHLogger({
    this.enableDebug = true,
    this.prefix = 'SSH',
  });

  void debug(String message) {
    if (enableDebug) {
      Loggers.app.fine('[$prefix] $message');
    }
  }

  void info(String message) {
    Loggers.app.info('[$prefix] $message');
  }

  void warning(String message, [Object? error]) {
    if (error != null) {
      Loggers.app.warning('[$prefix] $message: $error');
    } else {
      Loggers.app.warning('[$prefix] $message');
    }
  }

  void error(String message, [Object? error, StackTrace? stack]) {
    if (error != null) {
      Loggers.app.severe('[$prefix] $message', error, stack);
    } else {
      Loggers.app.severe('[$prefix] $message');
    }
  }

  void log(String level, String message) {
    switch (level.toLowerCase()) {
      case 'debug':
        debug(message);
        break;
      case 'info':
        info(message);
        break;
      case 'warning':
      case 'warn':
        warning(message);
        break;
      case 'error':
      case 'severe':
        error(message);
        break;
      default:
        info(message);
    }
  }
}