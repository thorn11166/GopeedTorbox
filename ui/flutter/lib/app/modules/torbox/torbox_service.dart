import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────
// Models
// ─────────────────────────────────────────

class TorBoxUser {
  final String email;
  final String plan;
  final bool isPremium;

  TorBoxUser({required this.email, required this.plan, required this.isPremium});

  factory TorBoxUser.fromJson(Map<String, dynamic> j) {
    final data = j['data'] ?? j;
    return TorBoxUser(
      email: data['email']?.toString() ?? '',
      plan: _planName(data['plan'] ?? 0),
      isPremium: (data['plan'] ?? 0) > 0,
    );
  }

  static String _planName(dynamic plan) {
    switch (plan) {
      case 1:
        return 'Essential';
      case 2:
        return 'Pro';
      case 3:
        return 'Standard';
      default:
        return 'Free';
    }
  }
}

class TorBoxTorrent {
  final int id;
  final String name;
  final int size; // bytes
  final double progress; // 0.0 – 1.0
  final String status;
  final bool cached;
  final DateTime? createdAt;
  final List<TorBoxFile> files;

  TorBoxTorrent({
    required this.id,
    required this.name,
    required this.size,
    required this.progress,
    required this.status,
    required this.cached,
    this.createdAt,
    this.files = const [],
  });

  bool get isDownloadReady => cached || status == 'cached' || progress >= 1.0;

  factory TorBoxTorrent.fromJson(Map<String, dynamic> j) {
    final rawFiles = j['files'] as List<dynamic>? ?? [];
    return TorBoxTorrent(
      id: _int(j['id']),
      name: j['name']?.toString() ?? 'Unknown',
      size: _int(j['size']),
      progress: _double(j['progress']),
      status: j['download_state']?.toString() ?? j['status']?.toString() ?? '',
      cached: j['cached'] == true,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString())
          : null,
      files: rawFiles.map((f) => TorBoxFile.fromJson(f as Map<String, dynamic>)).toList(),
    );
  }
}

class TorBoxFile {
  final int id;
  final String name;
  final int size;

  TorBoxFile({required this.id, required this.name, required this.size});

  factory TorBoxFile.fromJson(Map<String, dynamic> j) => TorBoxFile(
        id: _int(j['id']),
        name: j['name']?.toString() ?? '',
        size: _int(j['size']),
      );
}

class TorBoxDownloadLink {
  final String url;

  TorBoxDownloadLink({required this.url});

  factory TorBoxDownloadLink.fromJson(Map<String, dynamic> j) {
    final data = j['data'];
    return TorBoxDownloadLink(url: data?.toString() ?? '');
  }
}

// ─────────────────────────────────────────
// Service
// ─────────────────────────────────────────

class TorBoxService {
  static const _base = 'https://api.torbox.app/v1/api';

  final Dio _dio;
  String _apiKey;

  TorBoxService(String apiKey)
      : _apiKey = apiKey,
        _dio = Dio(BaseOptions(
          baseUrl: _base,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ));

  void updateApiKey(String key) => _apiKey = key;

  Map<String, dynamic> get _authHeader => {'Authorization': 'Bearer $_apiKey'};

  // ── Auth ──────────────────────────────────────────────────

  Future<TorBoxUser> getUser() async {
    final res = await _dio.get('/user/me', queryParameters: {'settings': 'false'},
        options: Options(headers: _authHeader));
    _check(res);
    return TorBoxUser.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Create torrent ─────────────────────────────────────────

  Future<int> addMagnet(String magnet) async {
    final fd = FormData.fromMap({'magnet': magnet, 'seed': '1'});
    final res = await _dio.post('/torrents/createtorrent',
        data: fd, options: Options(headers: _authHeader));
    _check(res);
    final data = res.data?['data'];
    return _int(data?['torrent_id'] ?? data?['id'] ?? 0);
  }

  Future<int> addTorrentFile(String filename, Uint8List bytes) async {
    final fd = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: filename, contentType: DioMediaType('application', 'x-bittorrent')),
      'seed': '1',
    });
    final res = await _dio.post('/torrents/createtorrent',
        data: fd, options: Options(headers: _authHeader));
    _check(res);
    final data = res.data?['data'];
    return _int(data?['torrent_id'] ?? data?['id'] ?? 0);
  }

  // ── Poll status ────────────────────────────────────────────

  Future<TorBoxTorrent> getTorrent(int id) async {
    final res = await _dio.get('/torrents/mylist',
        queryParameters: {'id': id, 'bypass_cache': true},
        options: Options(headers: _authHeader));
    _check(res);
    final data = res.data?['data'];
    if (data is List && data.isNotEmpty) {
      return TorBoxTorrent.fromJson(data.first as Map<String, dynamic>);
    }
    if (data is Map<String, dynamic>) {
      return TorBoxTorrent.fromJson(data);
    }
    throw Exception('Torrent not found');
  }

  Future<List<TorBoxTorrent>> listTorrents() async {
    final res = await _dio.get('/torrents/mylist',
        queryParameters: {'bypass_cache': true},
        options: Options(headers: _authHeader));
    _check(res);
    final data = res.data?['data'];
    if (data == null) return [];
    final list = data is List ? data : [data];
    return list.map((e) => TorBoxTorrent.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── Download links ─────────────────────────────────────────

  /// Returns a time-limited download URL for a specific file within a torrent.
  Future<String> requestDownloadLink(int torrentId, {int? fileId}) async {
    final params = <String, dynamic>{'torrent_id': torrentId, 'zip_link': 'false'};
    if (fileId != null) params['file_id'] = fileId;
    final res = await _dio.get('/torrents/requestdl',
        queryParameters: params, options: Options(headers: _authHeader));
    _check(res);
    return res.data?['data']?.toString() ?? '';
  }

  // ── Delete ─────────────────────────────────────────────────

  Future<void> deleteTorrent(int id) async {
    await _dio.post('/torrents/controltorrent',
        data: {'torrent_id': id, 'operation': 'delete'},
        options: Options(headers: _authHeader));
  }

  // ── Helpers ────────────────────────────────────────────────

  void _check(Response res) {
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw Exception('TorBox API error ${res.statusCode}: ${res.data}');
    }
    final ok = res.data?['success'];
    if (ok == false) {
      throw Exception('TorBox error: ${res.data?['error'] ?? res.data?['detail'] ?? 'Unknown'}');
    }
  }
}

// ─────────────────────────────────────────
// Download helper
// ─────────────────────────────────────────

/// Downloads a file from [url] to [savePath] with progress callbacks.
Future<void> downloadFileWithProgress(
  String url,
  String savePath, {
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  final dio = Dio();
  final dir = Directory(p.dirname(savePath));
  if (!dir.existsSync()) dir.createSync(recursive: true);

  await dio.download(
    url,
    savePath,
    cancelToken: cancelToken,
    onReceiveProgress: onProgress,
    options: Options(
      receiveTimeout: null, // no timeout for large files
    ),
  );
}

// ── Tiny helpers ─────────────────────────
int _int(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? 0;
}

double _double(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}
