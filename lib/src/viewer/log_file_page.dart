import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/vlog.dart';
import '../model/log_file_info.dart';
import '../model/log_level.dart';
import '../model/viewer_config.dart';
import 'file_chunk_reader.dart';
import 'log_copy_formatter.dart';
import 'log_file_controller.dart';
import 'log_line_parser.dart';
import 'log_search_service.dart';

/// Lazy, bounded-memory reader and search interface for one log file.
final class VLogFilePage extends StatefulWidget {
  const VLogFilePage({
    required this.file,
    super.key,
    this.controller,
    this.viewerConfig = const VLogViewerConfig(),
    this.searchService,
  });

  final LogFileInfo file;
  final LogFileController? controller;
  final VLogViewerConfig viewerConfig;
  final LogSearchService? searchService;

  @override
  State<VLogFilePage> createState() => _VLogFilePageState();
}

final class _VLogFilePageState extends State<VLogFilePage> {
  static const _parser = LogLineParser();
  static const _copyFormatter = LogCopyFormatter();

  late final bool _ownsController = widget.controller == null;
  late final LogFileController _controller = widget.controller ??
      LogFileController(
        filePath: widget.file.path,
        config: widget.viewerConfig,
        writeNotifications: VLog.writeNotifications,
      );
  late final LogSearchService _searchService =
      widget.searchService ?? LogSearchService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();

  LogSearchTask? _searchTask;
  StreamSubscription<double>? _progressSubscription;
  StreamSubscription<LogSearchResult>? _resultSubscription;
  List<LogSearchResult> _results = [];
  Set<LogLevel> _levels = {};
  DateTimeRange? _dateRange;
  bool _showSearch = false;
  bool _caseSensitive = false;
  bool _useRegex = false;
  bool _wrapLines = true;
  double _fontSize = 12;
  double _searchProgress = 0;
  int _selectedResult = -1;
  Object? _searchError;

  @override
  void initState() {
    super.initState();
    _wrapLines = widget.viewerConfig.wrapLines;
    _controller.addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);
    unawaited(_controller.open());
  }

  @override
  void dispose() {
    _searchTask?.cancel();
    _progressSubscription?.cancel();
    _resultSubscription?.cancel();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _queryController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _controller.isLoading) return;
    final position = _scrollController.position;
    if (position.userScrollDirection == ScrollDirection.idle) return;
    if (position.pixels <= 80 && _controller.hasMoreBefore) {
      unawaited(_controller.loadOlder());
    } else if (position.maxScrollExtent - position.pixels <= 80 &&
        _controller.hasMoreAfter) {
      unawaited(_controller.loadNewer());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.file.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${_controller.lines.length} lines in memory · ${_size(_controller.decodedBytes)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('toggle-log-search'),
              tooltip: 'Search',
              onPressed: () => setState(() => _showSearch = !_showSearch),
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            ),
            IconButton(
              key: const Key('toggle-line-wrap'),
              tooltip: 'Toggle line wrapping',
              onPressed: () => setState(() => _wrapLines = !_wrapLines),
              icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
            ),
            IconButton(
              key: const Key('toggle-live-follow'),
              tooltip: _controller.isFollowing
                  ? 'Pause live follow'
                  : 'Resume live follow',
              onPressed: () => _controller.setFollow(!_controller.isFollowing),
              icon: Icon(
                _controller.isFollowing
                    ? Icons.pause_circle
                    : Icons.play_circle,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'start') unawaited(_controller.jumpToStart());
                if (value == 'end') unawaited(_controller.jumpToEnd());
                if (value == 'smaller') {
                  setState(() => _fontSize = (_fontSize - 1).clamp(9, 24));
                }
                if (value == 'larger') {
                  setState(() => _fontSize = (_fontSize + 1).clamp(9, 24));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'start', child: Text('Jump to start')),
                PopupMenuItem(value: 'end', child: Text('Jump to end')),
                PopupMenuItem(
                  value: 'smaller',
                  child: Text('Decrease font size'),
                ),
                PopupMenuItem(
                  key: Key('increase-log-font'),
                  value: 'larger',
                  child: Text('Increase font size'),
                ),
              ],
            ),
            // Always-present compact target makes font adjustment accessible
            // without opening the overflow menu on wide desktop layouts.
            IconButton(
              key: const Key('increase-log-font'),
              tooltip: 'Increase font size',
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize + 1).clamp(9, 24)),
              icon: const Icon(Icons.text_increase),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_showSearch) _searchPanel(),
            if (!_controller.isFollowing)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.tertiaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                child: const Text('Live follow paused'),
              ),
            if (_controller.error != null)
              MaterialBanner(
                content: Text('Read failed: ${_controller.error}'),
                actions: [
                  TextButton(
                    onPressed: _controller.refreshTail,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(child: _logList()),
          ],
        ),
      );

  Widget _searchPanel() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('log-search-field'),
                    controller: _queryController,
                    onSubmitted: (_) => _startSearch(),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.manage_search),
                      hintText: 'Keyword or regular expression',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('submit-log-search'),
                  tooltip: 'Start search',
                  onPressed: _startSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: 'Search filters',
                  onPressed: _showFilters,
                  icon: Badge(
                    isLabelVisible: _levels.isNotEmpty ||
                        _tagController.text.isNotEmpty ||
                        _dateRange != null,
                    child: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                FilterChip(
                  label: const Text('Case sensitive'),
                  selected: _caseSensitive,
                  onSelected: (value) => setState(() => _caseSensitive = value),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Regex'),
                  selected: _useRegex,
                  onSelected: (value) => setState(() => _useRegex = value),
                ),
                const Spacer(),
                if (_searchTask != null)
                  IconButton(
                    tooltip: 'Cancel search',
                    onPressed: _cancelSearch,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
              ],
            ),
            if (_searchTask != null)
              LinearProgressIndicator(value: _searchProgress),
            if (_searchError != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Search failed: $_searchError',
                  style: TextStyle(color: colors.error),
                ),
              ),
            if (_results.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    '${_results.length} '
                    '${_results.length == 1 ? 'result' : 'results'}',
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Previous result',
                    onPressed: () => _moveResult(-1),
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: 'Next result',
                    onPressed: () => _moveResult(1),
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) => ActionChip(
                    key: Key('search-result-$index'),
                    avatar: Text('${index + 1}'),
                    label: SizedBox(
                      width: 220,
                      child: Text(
                        _results[index].snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onPressed: () => _selectResult(index),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _logList() {
    if (_controller.isLoading && _controller.lines.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.lines.isEmpty) {
      return const Center(child: Text('The file is empty'));
    }
    final extraBefore = _controller.hasMoreBefore ? 1 : 0;
    final extraAfter = _controller.hasMoreAfter ? 1 : 0;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
      itemCount: _controller.lines.length + extraBefore + extraAfter,
      itemBuilder: (context, index) {
        if (extraBefore == 1 && index == 0) {
          return TextButton.icon(
            key: const Key('load-older-logs'),
            onPressed: _controller.loadOlder,
            icon: const Icon(Icons.expand_less),
            label: const Text('Load older logs'),
          );
        }
        final lineIndex = index - extraBefore;
        if (lineIndex >= _controller.lines.length) {
          return TextButton.icon(
            key: const Key('load-newer-logs'),
            onPressed: _controller.loadNewer,
            icon: const Icon(Icons.expand_more),
            label: const Text('Load newer logs'),
          );
        }
        return _logRow(_controller.lines[lineIndex], lineIndex);
      },
    );
  }

  Widget _logRow(LogFileLine line, int index) {
    final parsed = _parser.parse(line.text);
    final color = _levelColor(parsed.level, Theme.of(context).colorScheme);
    final isExpandable = _isJson(parsed.message) ||
        parsed.level == LogLevel.error ||
        parsed.level == LogLevel.fatal ||
        parsed.message.startsWith('stackTrace:');
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: 1.45,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final title = SelectableText(
      line.text,
      maxLines: _wrapLines ? null : 1,
      style: textStyle,
    );
    final content = isExpandable
        ? ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            title: title,
            children: [
              if (_isJson(parsed.message))
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    _prettyJson(parsed.message),
                    style: textStyle.copyWith(color: color),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Long-press the line to copy error context',
                    style: textStyle,
                  ),
                ),
            ],
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: title,
          );
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(7),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _showCopyActions(index),
            child: content,
          ),
          if (parsed.level != null)
            SizedBox(
              key: Key('log-level-${parsed.level!.name}'),
              width: 1,
              height: 1,
            ),
        ],
      ),
    );
  }

  Future<void> _startSearch() async {
    await _cancelSearch();
    setState(() {
      _results = [];
      _selectedResult = -1;
      _searchProgress = 0;
      _searchError = null;
    });
    try {
      final task = _searchService.search(
        widget.file.path,
        LogSearchQuery(
          text: _queryController.text,
          caseSensitive: _caseSensitive,
          useRegex: _useRegex,
          levels: _levels,
          tags: _tagController.text.trim().isEmpty
              ? const {}
              : {_tagController.text.trim()},
          startTime: _dateRange?.start,
          endTime: _dateRange?.end
              .add(const Duration(days: 1))
              .subtract(const Duration(microseconds: 1)),
          maximumResults: widget.viewerConfig.maximumSearchResults,
        ),
      );
      _searchTask = task;
      _progressSubscription = task.progress.listen((value) {
        if (mounted) setState(() => _searchProgress = value);
      });
      _resultSubscription = task.results.listen((result) {
        if (mounted) setState(() => _results.add(result));
      });
      unawaited(task.done.then((_) {
        if (mounted && identical(_searchTask, task)) {
          setState(() => _searchTask = null);
        }
      }).catchError((Object error) {
        if (mounted) {
          setState(() {
            _searchError = error;
            _searchTask = null;
          });
        }
      }));
    } catch (error) {
      setState(() => _searchError = error);
    }
  }

  Future<void> _cancelSearch() async {
    final task = _searchTask;
    _searchTask = null;
    await task?.cancel();
    await _progressSubscription?.cancel();
    await _resultSubscription?.cancel();
    _progressSubscription = null;
    _resultSubscription = null;
    if (mounted) setState(() {});
  }

  void _selectResult(int index) {
    if (index < 0 || index >= _results.length) return;
    setState(() => _selectedResult = index);
    unawaited(_controller.jumpToOffset(_results[index].startOffset));
  }

  void _moveResult(int delta) {
    if (_results.isEmpty) return;
    final next = _selectedResult < 0
        ? (delta > 0 ? 0 : _results.length - 1)
        : (_selectedResult + delta) % _results.length;
    _selectResult(next < 0 ? next + _results.length : next);
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  children: LogLevel.values.map((level) {
                    return FilterChip(
                      label: Text(level.label),
                      selected: _levels.contains(level),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _levels = {..._levels, level};
                          } else {
                            _levels = {..._levels}..remove(level);
                          }
                        });
                        setSheetState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _tagController,
                  decoration: const InputDecoration(
                    labelText: 'Tag (exact match)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDateRangePicker(
                      context: context,
                      locale: const Locale('en'),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDateRange: _dateRange,
                    );
                    if (selected != null) {
                      setState(() => _dateRange = selected);
                      setSheetState(() {});
                    }
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _dateRange == null ? 'Select date range' : 'Date range set',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showCopyActions(int index) async {
    final start = (index - 5).clamp(0, _controller.lines.length);
    final end = (index + 6).clamp(0, _controller.lines.length);
    final contextLines =
        _controller.lines.sublist(start, end).map((line) => line.text).toList();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy current line'),
              onTap: () => _copyAndClose(_controller.lines[index].text),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy 5 surrounding lines'),
              onTap: () => _copyAndClose(contextLines.join('\n')),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Copy payload only'),
              onTap: () => _copyAndClose(
                _copyFormatter.payloadOnly(contextLines),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAndClose(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) Navigator.pop(context);
  }

  bool _isJson(String value) {
    try {
      jsonDecode(value);
      return value.trimLeft().startsWith('{') ||
          value.trimLeft().startsWith('[');
    } catch (_) {
      return false;
    }
  }

  String _prettyJson(String value) =>
      const JsonEncoder.withIndent('  ').convert(jsonDecode(value));

  Color _levelColor(LogLevel? level, ColorScheme colors) => switch (level) {
        LogLevel.verbose => colors.outline,
        LogLevel.debug => Colors.cyan.shade700,
        LogLevel.info => Colors.green.shade700,
        LogLevel.warning => Colors.orange.shade800,
        LogLevel.error => colors.error,
        LogLevel.fatal => Colors.purple.shade700,
        null => colors.outlineVariant,
      };

  String _size(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';
}
