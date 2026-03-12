import 'package:get/get.dart';

enum TorBoxLogLevel { info, warning, error }

class TorBoxLogEntry {
  final DateTime time;
  final TorBoxLogLevel level;
  final String message;

  TorBoxLogEntry(this.level, this.message) : time = DateTime.now();

  String get levelTag {
    switch (level) {
      case TorBoxLogLevel.info:
        return 'INFO';
      case TorBoxLogLevel.warning:
        return 'WARN';
      case TorBoxLogLevel.error:
        return 'ERR ';
    }
  }

  String get timeStr {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// In-memory circular log buffer, max 300 entries.
class TorBoxLog {
  static const _max = 300;

  TorBoxLog._();
  static final instance = TorBoxLog._();

  final entries = <TorBoxLogEntry>[].obs;

  void info(String msg) => _add(TorBoxLogLevel.info, msg);
  void warn(String msg) => _add(TorBoxLogLevel.warning, msg);
  void error(String msg) => _add(TorBoxLogLevel.error, msg);

  void clear() => entries.clear();

  void _add(TorBoxLogLevel level, String msg) {
    if (entries.length >= _max) entries.removeAt(0);
    entries.add(TorBoxLogEntry(level, msg));
  }
}
