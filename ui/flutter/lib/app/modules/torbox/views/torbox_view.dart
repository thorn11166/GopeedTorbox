import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../views/directory_selector.dart';
import '../controllers/torbox_controller.dart';
import '../torbox_log.dart';
import '../torbox_service.dart';

// ─────────────────────────────────────────
// Colours (mirrors TorDeck's dark palette)
// ─────────────────────────────────────────
const _kAccent = Color(0xFF22D3A7);
const _kAccent2 = Color(0xFF60A5FA);
const _kSurface = Color(0xFF0F1320);
const _kSuccess = Color(0xFF26D16F);
const _kDanger = Color(0xFFEF4444);
const _kMuted = Color(0xFF94A3B8);

class TorBoxView extends GetView<TorBoxController> {
  const TorBoxView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.cloud_download, color: _kAccent, size: 22),
            const SizedBox(width: 8),
            const Text('TorBox'),
            const SizedBox(width: 8),
            Obx(() => controller.isAuthenticated.value
                ? const _StatusDot(color: _kSuccess)
                : const _StatusDot(color: _kMuted)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal_outlined),
            tooltip: 'View logs',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _LogViewerScreen()),
            ),
          ),
          Obx(() => controller.isAuthenticated.value
              ? IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sign out',
                  onPressed: () => _confirmSignOut(context),
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: Obx(() {
        if (!controller.isAuthenticated.value) {
          return _AuthPanel(controller: controller);
        }
        return _MainPanel(controller: controller);
      }),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Remove your TorBox API key from this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.signOut();
            },
            child: const Text('Sign out', style: TextStyle(color: _kDanger)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Auth panel
// ─────────────────────────────────────────

class _AuthPanel extends StatefulWidget {
  final TorBoxController controller;
  const _AuthPanel({required this.controller});

  @override
  State<_AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<_AuthPanel> {
  final _keyController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Logo / headline ────────────────────────────
              const Icon(Icons.cloud_download_outlined, size: 56, color: _kAccent),
              const SizedBox(height: 16),
              Text(
                'Connect to TorBox',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Paste your TorBox API key to start sending magnets and torrents to the cloud.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _kMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── API key input ──────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _keyController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'TorBox API Key',
                          hintText: 'Paste your API key…',
                          prefixIcon: const Icon(Icons.vpn_key_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 8),
                      Obx(() {
                        final status = widget.controller.authStatus.value;
                        if (status.isEmpty) return const SizedBox.shrink();
                        final isError = status != 'checking' &&
                            !widget.controller.isAuthenticated.value;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            status == 'checking' ? 'Verifying…' : status,
                            style: TextStyle(
                              fontSize: 12,
                              color: status == 'checking'
                                  ? _kMuted
                                  : isError
                                      ? _kDanger
                                      : _kSuccess,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      Obx(() {
                        final checking = widget.controller.authStatus.value == 'checking';
                        return FilledButton.icon(
                          onPressed: checking ? null : _save,
                          icon: checking
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check),
                          label: Text(checking ? 'Connecting…' : 'Connect'),
                          style: FilledButton.styleFrom(backgroundColor: _kAccent),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  // Open TorBox dashboard to get API key
                  // ignore: deprecated_member_use
                },
                child: const Text(
                  'Get your API key at torbox.app',
                  style: TextStyle(color: _kAccent2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    widget.controller.saveApiKey(key);
  }
}

// ─────────────────────────────────────────
// Main panel (authenticated)
// ─────────────────────────────────────────

class _MainPanel extends StatefulWidget {
  final TorBoxController controller;
  const _MainPanel({required this.controller});

  @override
  State<_MainPanel> createState() => _MainPanelState();
}

class _MainPanelState extends State<_MainPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _magnetController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _magnetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Add section ────────────────────────────────────
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add to TorBox',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: _kAccent)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _magnetController,
                      decoration: const InputDecoration(
                        hintText: 'magnet:?xt=urn:btih:…',
                        labelText: 'Magnet link or infohash',
                        prefixIcon: Icon(Icons.link),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendMagnet(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Upload .torrent file button
                  IconButton.outlined(
                    icon: const Icon(Icons.file_upload_outlined),
                    tooltip: 'Upload .torrent file',
                    onPressed: _pickTorrentFile,
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _sendMagnet,
                      icon: _sending
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 16),
                      label: const Text('Send'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _magnetController.clear(),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                  ),
                ]),
              ],
            ),
          ),
        ),

        // ── Download dir setting ───────────────────────────
        Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const Icon(Icons.folder_outlined, size: 18, color: _kMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Obx(() => Text(
                      widget.controller.downloadDir.value.isEmpty
                          ? 'No download directory set'
                          : widget.controller.downloadDir.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.controller.downloadDir.value.isEmpty
                            ? _kDanger
                            : _kMuted,
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    )),
              ),
              TextButton(
                onPressed: _pickDownloadDir,
                child: const Text('Change', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ),

        // ── Tabs ──────────────────────────────────────────
        const SizedBox(height: 8),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Done'),
          ],
        ),

        // ── Task lists ─────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _TaskList(
                controller: widget.controller,
                filter: (t) => t.state != TorBoxTaskState.done,
              ),
              _TaskList(
                controller: widget.controller,
                filter: (t) => t.state == TorBoxTaskState.done,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendMagnet() async {
    final text = _magnetController.text.trim();
    if (text.isEmpty) return;

    if (widget.controller.downloadDir.value.isEmpty) {
      _showNoDirSnack();
      return;
    }

    // Accept magnet links or bare infohashes
    String magnet = text;
    if (!magnet.toLowerCase().startsWith('magnet:')) {
      final hex40 = RegExp(r'^[a-fA-F0-9]{40}$');
      if (hex40.hasMatch(text)) {
        magnet = 'magnet:?xt=urn:btih:$text';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a magnet link or 40-char infohash')),
        );
        return;
      }
    }

    setState(() => _sending = true);
    _magnetController.clear();
    await widget.controller.addMagnet(magnet);
    setState(() => _sending = false);
  }

  Future<void> _pickTorrentFile() async {
    if (widget.controller.downloadDir.value.isEmpty) {
      _showNoDirSnack();
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['torrent'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    await widget.controller.addTorrentFile(file.name, Uint8List.fromList(bytes));
  }

  void _pickDownloadDir() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      widget.controller.setDownloadDir(result);
    }
  }

  void _showNoDirSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please set a download directory first'),
        backgroundColor: _kDanger,
      ),
    );
  }
}

// ─────────────────────────────────────────
// Task list widget
// ─────────────────────────────────────────

class _TaskList extends StatelessWidget {
  final TorBoxController controller;
  final bool Function(TorBoxTask) filter;

  const _TaskList({required this.controller, required this.filter});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tasks = controller.tasks.where(filter).toList();
      if (tasks.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: _kMuted.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text('No tasks', style: TextStyle(color: _kMuted.withOpacity(0.6))),
            ],
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: tasks.length,
        itemBuilder: (_, i) => _TaskCard(task: tasks[i], controller: controller),
      );
    });
  }
}

// ─────────────────────────────────────────
// Task card
// ─────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final TorBoxTask task;
  final TorBoxController controller;

  const _TaskCard({required this.task, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Name + state chip + remove ─────────────────
            Row(children: [
              _StateIcon(task.state),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.name.isEmpty ? task.input : task.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              _StateChip(task.state),
              IconButton(
                icon: Icon(
                  task.state == TorBoxTaskState.done ||
                          task.state == TorBoxTaskState.error
                      ? Icons.close
                      : Icons.cancel_outlined,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => task.state == TorBoxTaskState.done ||
                        task.state == TorBoxTaskState.error
                    ? controller.removeTask(task)
                    : controller.cancelTask(task),
              ),
            ]),

            // ── Progress bars ──────────────────────────────
            if (task.state == TorBoxTaskState.caching) ...[
              const SizedBox(height: 8),
              _ProgressRow(
                label: 'Caching on TorBox',
                value: task.cacheProgress,
                color: _kAccent2,
              ),
            ],
            if (task.state == TorBoxTaskState.downloading) ...[
              const SizedBox(height: 8),
              _ProgressRow(
                label: 'Downloading',
                value: task.downloadProgress,
                color: _kAccent,
                trailing: task.totalBytes > 0
                    ? '${_fmt(task.downloadedBytes)} / ${_fmt(task.totalBytes)}'
                    : null,
              ),
            ],

            // ── Message / path ─────────────────────────────
            if (task.message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                task.message,
                style: TextStyle(
                  fontSize: 11,
                  color: task.state == TorBoxTaskState.error ? _kDanger : _kMuted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

// ─────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _StateIcon extends StatelessWidget {
  final TorBoxTaskState state;
  const _StateIcon(this.state);

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case TorBoxTaskState.queued:
        return const Icon(Icons.schedule, size: 18, color: _kMuted);
      case TorBoxTaskState.caching:
        return const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent2));
      case TorBoxTaskState.downloading:
        return const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent));
      case TorBoxTaskState.done:
        return const Icon(Icons.check_circle, size: 18, color: _kSuccess);
      case TorBoxTaskState.error:
        return const Icon(Icons.error_outline, size: 18, color: _kDanger);
    }
  }
}

class _StateChip extends StatelessWidget {
  final TorBoxTaskState state;
  const _StateChip(this.state);

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (state) {
      case TorBoxTaskState.queued:
        label = 'Queued';
        color = _kMuted;
        break;
      case TorBoxTaskState.caching:
        label = 'Caching';
        color = _kAccent2;
        break;
      case TorBoxTaskState.downloading:
        label = 'Downloading';
        color = _kAccent;
        break;
      case TorBoxTaskState.done:
        label = 'Done';
        color = _kSuccess;
        break;
      case TorBoxTaskState.error:
        label = 'Error';
        color = _kDanger;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String? trailing;

  const _ProgressRow({
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final pct = '${(value * 100).toStringAsFixed(1)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _kMuted)),
          Text(trailing ?? pct,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Log viewer screen
// ─────────────────────────────────────────

class _LogViewerScreen extends StatelessWidget {
  const _LogViewerScreen();

  @override
  Widget build(BuildContext context) {
    final log = TorBoxLog.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TorBox Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy all',
            onPressed: () {
              final text = log.entries
                  .map((e) => '[${e.timeStr}] ${e.levelTag} ${e.message}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: log.clear,
          ),
        ],
      ),
      body: Obx(() {
        final entries = log.entries.reversed.toList();
        if (entries.isEmpty) {
          return Center(
            child: Text('No log entries yet.',
                style: TextStyle(color: _kMuted.withOpacity(0.6))),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final e = entries[i];
            Color color;
            switch (e.level) {
              case TorBoxLogLevel.error:
                color = _kDanger;
                break;
              case TorBoxLogLevel.warning:
                color = const Color(0xFFFBBF24);
                break;
              case TorBoxLogLevel.info:
                color = _kMuted;
                break;
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  children: [
                    TextSpan(
                        text: '${e.timeStr} ',
                        style: TextStyle(color: _kMuted.withOpacity(0.5))),
                    TextSpan(
                        text: '${e.levelTag} ',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold)),
                    TextSpan(text: e.message, style: TextStyle(color: color)),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
