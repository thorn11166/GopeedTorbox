import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../../database/database.dart';
import '../torbox_service.dart';

// ─────────────────────────────────────────
// Task state
// ─────────────────────────────────────────

enum TorBoxTaskState {
  queued,
  caching, // uploading to TorBox / waiting for cache
  downloading, // pulling bytes to local disk
  done,
  error,
}

class TorBoxTask {
  final String id; // local uuid
  int? torrentId; // id from TorBox API
  final String input; // original magnet / filename
  String name;
  TorBoxTaskState state;
  String message;
  double cacheProgress; // 0–1
  double downloadProgress; // 0–1
  int downloadedBytes;
  int totalBytes;
  String? savePath;
  CancelToken? cancelToken;

  TorBoxTask({
    required this.id,
    required this.input,
    this.torrentId,
    this.name = '',
    this.state = TorBoxTaskState.queued,
    this.message = '',
    this.cacheProgress = 0.0,
    this.downloadProgress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.savePath,
    this.cancelToken,
  });
}

// ─────────────────────────────────────────
// Controller
// ─────────────────────────────────────────

class TorBoxController extends GetxController {
  // ── API key / auth ─────────────────────────────────────────

  final apiKey = ''.obs;
  final isAuthenticated = false.obs;
  final authStatus = ''.obs; // '' | 'checking' | 'ok' | error message
  TorBoxService? _service;

  // ── Settings ───────────────────────────────────────────────

  final downloadDir = ''.obs;

  // ── Tasks ──────────────────────────────────────────────────

  final tasks = <TorBoxTask>[].obs;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _loadSaved();
  }

  void _loadSaved() {
    final key = Database.instance.getTorBoxApiKey() ?? '';
    final dir = Database.instance.getTorBoxDownloadDir() ?? '';
    apiKey.value = key;
    downloadDir.value = dir;
    if (key.isNotEmpty) {
      _service = TorBoxService(key);
      checkAuth(silent: true);
    }
  }

  // ── Auth ──────────────────────────────────────────────────

  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      apiKey.value = '';
      isAuthenticated.value = false;
      authStatus.value = '';
      _service = null;
      Database.instance.saveTorBoxApiKey('');
      return;
    }

    authStatus.value = 'checking';
    _service = TorBoxService(trimmed);
    try {
      final user = await _service!.getUser();
      apiKey.value = trimmed;
      isAuthenticated.value = true;
      authStatus.value = '${user.email} · ${user.plan}';
      Database.instance.saveTorBoxApiKey(trimmed);
    } catch (e) {
      _service = null;
      isAuthenticated.value = false;
      authStatus.value = _friendlyError(e);
    }
  }

  Future<void> checkAuth({bool silent = false}) async {
    if (_service == null) return;
    if (!silent) authStatus.value = 'checking';
    try {
      final user = await _service!.getUser();
      isAuthenticated.value = true;
      authStatus.value = '${user.email} · ${user.plan}';
    } catch (e) {
      isAuthenticated.value = false;
      authStatus.value = _friendlyError(e);
    }
  }

  void signOut() {
    apiKey.value = '';
    isAuthenticated.value = false;
    authStatus.value = '';
    _service = null;
    Database.instance.saveTorBoxApiKey('');
  }

  // ── Download dir ──────────────────────────────────────────

  void setDownloadDir(String dir) {
    downloadDir.value = dir;
    Database.instance.saveTorBoxDownloadDir(dir);
  }

  // ── Add torrent ───────────────────────────────────────────

  Future<TorBoxTask?> addMagnet(String magnet) async {
    if (_service == null) return null;
    final task = TorBoxTask(
      id: _uid(),
      input: magnet,
      name: _nameFromMagnet(magnet),
      state: TorBoxTaskState.queued,
    );
    tasks.add(task);
    _startCaching(task);
    return task;
  }

  Future<TorBoxTask?> addTorrentFile(String filename, Uint8List bytes) async {
    if (_service == null) return null;
    final task = TorBoxTask(
      id: _uid(),
      input: filename,
      name: filename,
      state: TorBoxTaskState.queued,
    );
    tasks.add(task);
    _startCachingFile(task, filename, bytes);
    return task;
  }

  // ── Cancel / remove ───────────────────────────────────────

  void cancelTask(TorBoxTask task) {
    task.cancelToken?.cancel('Cancelled by user');
    _mutateTask(task, (t) {
      t.state = TorBoxTaskState.error;
      t.message = 'Cancelled';
    });
  }

  void removeTask(TorBoxTask task) {
    task.cancelToken?.cancel();
    tasks.remove(task);
  }

  // ── Internal helpers ──────────────────────────────────────

  Future<void> _startCaching(TorBoxTask task) async {
    _mutateTask(task, (t) => t.state = TorBoxTaskState.caching);
    try {
      final torrentId = await _service!.addMagnet(task.input);
      _mutateTask(task, (t) => t.torrentId = torrentId);
      await _pollUntilCached(task);
    } catch (e) {
      _mutateTask(task, (t) {
        t.state = TorBoxTaskState.error;
        t.message = _friendlyError(e);
      });
    }
  }

  Future<void> _startCachingFile(TorBoxTask task, String filename, Uint8List bytes) async {
    _mutateTask(task, (t) => t.state = TorBoxTaskState.caching);
    try {
      final torrentId = await _service!.addTorrentFile(filename, bytes);
      _mutateTask(task, (t) => t.torrentId = torrentId);
      await _pollUntilCached(task);
    } catch (e) {
      _mutateTask(task, (t) {
        t.state = TorBoxTaskState.error;
        t.message = _friendlyError(e);
      });
    }
  }

  Future<void> _pollUntilCached(TorBoxTask task) async {
    const pollInterval = Duration(seconds: 5);
    const maxWait = Duration(hours: 6);
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      if (task.state == TorBoxTaskState.error) return; // cancelled externally

      try {
        final torrent = await _service!.getTorrent(task.torrentId!);

        // Update name if available
        if (torrent.name.isNotEmpty && task.name != torrent.name) {
          _mutateTask(task, (t) => t.name = torrent.name);
        }

        _mutateTask(task, (t) => t.cacheProgress = torrent.progress);

        if (torrent.isDownloadReady) {
          await _startDownloading(task, torrent);
          return;
        }
      } catch (_) {
        // network hiccup – just retry
      }

      await Future.delayed(pollInterval);
    }

    _mutateTask(task, (t) {
      t.state = TorBoxTaskState.error;
      t.message = 'Timed out waiting for TorBox to cache';
    });
  }

  Future<void> _startDownloading(TorBoxTask task, TorBoxTorrent torrent) async {
    _mutateTask(task, (t) {
      t.state = TorBoxTaskState.downloading;
      t.totalBytes = torrent.size;
    });

    try {
      // If there are multiple files, download each; otherwise download the whole torrent
      if (torrent.files.length > 1) {
        await _downloadMultiFile(task, torrent);
      } else {
        await _downloadSingleFile(task, torrent);
      }
      _mutateTask(task, (t) {
        t.state = TorBoxTaskState.done;
        t.downloadProgress = 1.0;
        t.message = 'Saved to ${t.savePath ?? downloadDir.value}';
      });
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) return;
      _mutateTask(task, (t) {
        t.state = TorBoxTaskState.error;
        t.message = _friendlyError(e);
      });
    }
  }

  Future<void> _downloadSingleFile(TorBoxTask task, TorBoxTorrent torrent) async {
    final fileId = torrent.files.isNotEmpty ? torrent.files.first.id : null;
    final url = await _service!.requestDownloadLink(torrent.id, fileId: fileId);
    if (url.isEmpty) throw Exception('No download URL returned');

    final ext = _guessExt(torrent.name);
    final filename = '${_sanitize(torrent.name)}$ext';
    final savePath = p.join(downloadDir.value, filename);

    task.cancelToken = CancelToken();
    _mutateTask(task, (t) => t.savePath = savePath);

    await downloadFileWithProgress(
      url,
      savePath,
      cancelToken: task.cancelToken,
      onProgress: (received, total) {
        if (total <= 0) return;
        _mutateTask(task, (t) {
          t.downloadedBytes = received;
          t.totalBytes = total;
          t.downloadProgress = received / total;
        });
      },
    );
  }

  Future<void> _downloadMultiFile(TorBoxTask task, TorBoxTorrent torrent) async {
    int totalDownloaded = 0;
    final totalSize = torrent.files.fold<int>(0, (sum, f) => sum + f.size);

    for (final file in torrent.files) {
      if (task.state == TorBoxTaskState.error) return;

      final url = await _service!.requestDownloadLink(torrent.id, fileId: file.id);
      if (url.isEmpty) continue;

      final savePath = p.join(downloadDir.value, _sanitize(torrent.name), _sanitize(file.name));
      if (task.savePath == null) {
        _mutateTask(task, (t) => t.savePath = p.join(downloadDir.value, _sanitize(torrent.name)));
      }

      task.cancelToken = CancelToken();
      await downloadFileWithProgress(
        url,
        savePath,
        cancelToken: task.cancelToken,
        onProgress: (received, total) {
          if (totalSize <= 0) return;
          _mutateTask(task, (t) {
            t.downloadedBytes = totalDownloaded + received;
            t.downloadProgress = t.downloadedBytes / totalSize;
          });
        },
      );
      totalDownloaded += file.size;
    }
    _mutateTask(task, (t) => t.totalBytes = totalSize);
  }

  void _mutateTask(TorBoxTask task, void Function(TorBoxTask) fn) {
    fn(task);
    tasks.refresh();
  }

  // ── Misc ──────────────────────────────────────────────────

  String _uid() => DateTime.now().millisecondsSinceEpoch.toString() +
      (tasks.length).toString();

  String _nameFromMagnet(String magnet) {
    final dn = RegExp(r'[?&]dn=([^&]+)').firstMatch(magnet)?.group(1) ?? '';
    if (dn.isNotEmpty) return Uri.decodeComponent(dn.replaceAll('+', ' '));
    final hash = RegExp(r'btih:([a-fA-F0-9]{40}|[A-Z2-7]{32})', caseSensitive: false)
        .firstMatch(magnet)
        ?.group(1) ?? '';
    return hash.isNotEmpty ? hash : 'Unknown';
  }

  String _guessExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && name.length - dot <= 5) return '';
    return '';
  }

  String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();

  String _friendlyError(dynamic e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return 'Invalid API key';
      final msg = e.response?.data?['detail'] ??
          e.response?.data?['error'] ??
          e.message ?? 'Network error';
      return msg.toString();
    }
    return e.toString();
  }
}
