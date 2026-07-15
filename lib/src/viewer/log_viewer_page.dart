import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/vlog.dart';
import '../model/log_file_info.dart';
import 'log_file_page.dart';

/// Storage actions consumed by [VLogViewerPage].
abstract interface class LogViewerRepository {
  Future<List<LogFileInfo>> listFiles();
  Future<void> deleteFiles(Iterable<String> paths);
  Future<void> cleanup();
  Future<void> shareFiles(Iterable<String> paths);
}

/// Default repository backed by the active [VLog] session.
final class DefaultLogViewerRepository implements LogViewerRepository {
  const DefaultLogViewerRepository();

  @override
  Future<void> cleanup() => VLog.cleanupLogs();

  @override
  Future<void> deleteFiles(Iterable<String> paths) =>
      VLog.deleteLogFiles(paths);

  @override
  Future<List<LogFileInfo>> listFiles() => VLog.getLogFiles();

  @override
  Future<void> shareFiles(Iterable<String> paths) async {
    final files = paths.map(XFile.new).toList();
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: files, subject: 'VLog files'),
    );
  }
}

typedef VLogFilePageBuilder = Widget Function(
    BuildContext context, LogFileInfo file);

/// Embeddable file browser for logs owned by the current VLog configuration.
final class VLogViewerPage extends StatefulWidget {
  const VLogViewerPage({
    super.key,
    this.repository,
    this.filePageBuilder,
  });

  final LogViewerRepository? repository;
  final VLogFilePageBuilder? filePageBuilder;

  @override
  State<VLogViewerPage> createState() => _VLogViewerPageState();
}

final class _VLogViewerPageState extends State<VLogViewerPage> {
  late final LogViewerRepository _repository =
      widget.repository ?? const DefaultLogViewerRepository();
  final Set<String> _selected = {};
  List<LogFileInfo> _files = const [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await _repository.listFiles();
      files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      if (!mounted) return;
      setState(() {
        _files = files;
        _selected.removeWhere(
          (path) => !files.any((file) => file.path == path),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                onPressed: () => setState(_selected.clear),
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(selecting ? '已选择 ${_selected.length} 个文件' : 'VLog 日志'),
        actions: selecting
            ? [
                IconButton(
                  key: const Key('share-selected-logs'),
                  tooltip: '分享',
                  onPressed: () => _repository.shareFiles(_selected),
                  icon: const Icon(Icons.ios_share_outlined),
                ),
                IconButton(
                  key: const Key('delete-selected-logs'),
                  tooltip: '删除',
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ]
            : [
                IconButton(
                  tooltip: '清理过期日志',
                  onPressed: () async {
                    await _repository.cleanup();
                    await _reload();
                  },
                  icon: const Icon(Icons.auto_delete_outlined),
                ),
                IconButton(
                  key: const Key('refresh-log-files-action'),
                  tooltip: '刷新',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.warning_amber_rounded,
        title: '读取日志失败',
        detail: _error.toString(),
        onRetry: _reload,
      );
    }
    if (_files.isEmpty) {
      return _MessageState(
        icon: Icons.article_outlined,
        title: '暂无日志文件',
        detail: '产生第一条文件日志后会显示在这里',
        onRetry: _reload,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _files.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _fileTile(_files[index]),
      ),
    );
  }

  Widget _fileTile(LogFileInfo file) {
    final selected = _selected.contains(file.path);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colors.primaryContainer
          : colors.surfaceContainerHighest.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: () => _toggle(file.path),
        onTap: () {
          if (_selected.isNotEmpty) {
            _toggle(file.path);
          } else {
            _open(file);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: file.isActive
                      ? colors.tertiaryContainer
                      : colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  file.isActive ? Icons.bolt : Icons.description_outlined,
                  color: file.isActive
                      ? colors.onTertiaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (file.isActive)
                          Container(
                            key: const Key('active-log-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.tertiary,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '写入中',
                              style: TextStyle(
                                color: colors.onTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_size(file.sizeBytes)}  ·  ${_time(file.modifiedAt)}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '复制路径',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: file.path));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路径已复制')),
                    );
                  }
                },
                icon: selected
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(String path) {
    setState(() {
      if (!_selected.add(path)) _selected.remove(path);
    });
  }

  void _open(LogFileInfo file) {
    final page =
        widget.filePageBuilder?.call(context, file) ?? VLogFilePage(file: file);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日志文件？'),
        content: Text('将永久删除选中的 ${_selected.length} 个文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteFiles(_selected);
    _selected.clear();
    await _reload();
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _time(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

final class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(detail, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('refresh-log-files'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
      );
}
