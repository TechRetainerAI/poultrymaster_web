// System → Videos (app/poultry-videos/page.tsx, 28 Oct–2 Nov): the training
// playlist. Four figures (Videos, Watched, Total views, Latest video), the
// player with Previous / Next / YouTube and the description, and the playlist
// with Autoplay, search and All / Not watched / Watched.
//
// The list comes from the web's own route, `GET {webBase}/api/youtube-videos`.
// It reads our UNLISTED playlist through the YouTube Data API with a key that
// lives on the web server only, so the app asks the web rather than YouTube.
// The route answers 200 with an empty list when there is nothing to show
// ("No videos yet"); anything else that fails is "could not be loaded".
//
// Watched videos and the Autoplay choice are kept on this phone
// (SharedPreferences, the web's localStorage keys).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../config/env.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import '../shared/help/contact_support.dart' show openExternal;
import 'trackers/tracker_widgets.dart' show TColors;

class ChannelVideo {
  const ChannelVideo({required this.id, required this.title, this.description = '', this.published = '', this.views});
  final String id, title, description;

  /// ISO date the video went up.
  final String published;
  final int? views;

  factory ChannelVideo.fromJson(Map j) => ChannelVideo(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        description: '${j['description'] ?? ''}',
        published: '${j['published'] ?? ''}',
        views: j['views'] is num ? (j['views'] as num).toInt() : null,
      );
}

class ChannelFeed {
  const ChannelFeed({this.channelTitle = '', this.channelUrl = '', this.playlistUrl, this.videos = const []});
  final String channelTitle, channelUrl;
  final String? playlistUrl;
  final List<ChannelVideo> videos;

  factory ChannelFeed.fromJson(Map j) => ChannelFeed(
        channelTitle: '${j['channelTitle'] ?? ''}',
        channelUrl: '${j['channelUrl'] ?? ''}',
        playlistUrl: (j['playlistUrl'] as String?)?.isNotEmpty == true ? j['playlistUrl'] as String : null,
        videos: [for (final v in (j['videos'] as List? ?? const [])) if (v is Map) ChannelVideo.fromJson(v)],
      );
}

/// loadFeed: null (404) is "no videos"; any other failure throws.
Future<ChannelFeed?> Function() loadVideosFeed = () async {
  final res = await http.get(Uri.parse('${Env.webBase}/api/youtube-videos')).timeout(const Duration(seconds: 20));
  if (res.statusCode == 404) return null;
  if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('feed-unavailable');
  return ChannelFeed.fromJson(jsonDecode(res.body) as Map);
};

/// The player. Tests swap it: a WebView cannot run in a widget test.
Widget Function(String videoId, String title, VoidCallback onEnded) youtubePlayerBuilder =
    (id, title, onEnded) => YouTubePlayer(key: ValueKey('yt-$id'), videoId: id, title: title, onEnded: onEnded);

const watchedKey = 'poultry-videos-watched';
const autoplayKey = 'poultry-videos-autoplay';

String uploadedOn(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : DateFormat('d MMM y').format(d.toLocal());
}

/// "3 days ago", the way YouTube labels a video's age.
String timeAgo(String iso, {DateTime? now}) {
  final then = DateTime.tryParse(iso);
  if (then == null) return '';
  final days = (now ?? DateTime.now()).difference(then).inMilliseconds ~/ 86400000;
  if (days < 1) return 'Today';
  if (days < 2) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 30) return '${days ~/ 7} wk ago';
  if (days < 365) return '${days ~/ 30} mo ago';
  return '${days ~/ 365} yr ago';
}

/// Intl's compact, one decimal at most: 1,520 -> "1.5K".
final _compact = NumberFormat.compact()
  ..significantDigitsInUse = false
  ..maximumFractionDigits = 1;

String viewsLabel(ChannelVideo v) => v.views == null ? '' : '${_compact.format(v.views)} view${v.views == 1 ? '' : 's'}';

enum _Filter { all, unwatched, watched }

const _red50 = Tone.bg(0xFFFEF2F2);
const _red100 = Tone.bg(0xFFFEE2E2);
const _red700 = Tone.fg(0xFFB91C1C);

class PoultryVideosScreen extends StatefulWidget {
  const PoultryVideosScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<PoultryVideosScreen> createState() => _PoultryVideosScreenState();
}

class _PoultryVideosScreenState extends State<PoultryVideosScreen> {
  final _playerKey = GlobalKey();
  ChannelFeed? _feed;
  bool _loading = true, _error = false, _fetching = false;
  String _q = '';
  _Filter _filter = _Filter.all;
  String? _currentId;

  // The player loads only once someone presses play, so opening the page
  // does not start a video with sound.
  bool _started = false;
  bool _autoplayNext = true;
  List<String> _watched = [];
  bool _showMore = false;

  List<ChannelVideo> get _videos => _feed?.videos ?? const [];

  @override
  void initState() {
    super.initState();
    _restore();
    _load();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = jsonDecode(p.getString(watchedKey) ?? '[]');
      if (!mounted) return;
      setState(() {
        _watched = raw is List ? [for (final x in raw) if (x is String) x] : [];
        if (p.getString(autoplayKey) == 'off') _autoplayNext = false;
      });
    } catch (_) {
      // Defaults stand.
    }
  }

  Future<void> _load() async {
    setState(() => _fetching = true);
    try {
      final feed = await loadVideosFeed();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _error = false;
        // The newest one (the web also honours ?v= from a shared link).
        if (_currentId == null && _videos.isNotEmpty) _currentId = _videos.first.id;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetching = false;
        });
      }
    }
  }

  Future<void> _markWatched(String id) async {
    if (_watched.contains(id)) return;
    setState(() => _watched = [..._watched, id]);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(watchedKey, jsonEncode(_watched));
    } catch (_) {
      // Not remembered this time; nothing else depends on it.
    }
  }

  void _play(String id) {
    setState(() {
      _currentId = id;
      _started = true;
      _showMore = false;
    });
    _markWatched(id);
    // The playlist sits under the player on a phone: bring the player back.
    final ctx = _playerKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
  }

  void _ended() {
    if (!_autoplayNext) return;
    final i = _videos.indexWhere((v) => v.id == _currentId);
    if (i >= 0 && i + 1 < _videos.length) _play(_videos[i + 1].id);
  }

  Future<void> _toggleAutoplay(bool on) async {
    setState(() => _autoplayNext = on);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(autoplayKey, on ? 'on' : 'off');
    } catch (_) {
      // Applies to this visit only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-videos');
    final feed = _feed;
    final link = feed?.playlistUrl ?? (feed?.channelUrl.isNotEmpty == true ? feed!.channelUrl : null);
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Videos')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(key: const ValueKey('videos-list'), padding: const EdgeInsets.fromLTRB(14, 16, 14, 28), children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: _red100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.play_circle_outline, color: Tone.fg(0xFFDC2626)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Videos', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Tone.fg(0xFF0F172A))),
                Text('Step-by-step guide videos to help you get the most out of the system.',
                    style: TextStyle(fontSize: 13.5, color: Tone.fg(0xFF475569))),
              ]),
            ),
          ]),
          if (link != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('videos-open-youtube'),
                style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)), foregroundColor: Tone.fg(0xFF1E293B)),
                onPressed: () => openExternal(context, link),
                icon: const Icon(Icons.smart_display_outlined, size: 18, color: Tone.fg(0xFFDC2626)),
                label: Text(feed?.playlistUrl != null ? 'Open on YouTube' : 'Visit our channel'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          ..._content(),
        ]),
      ),
    );
  }

  List<Widget> _content() {
    if (_loading) {
      return [
        _grid([for (var i = 0; i < 4; i++) _skeleton(96)]),
        const SizedBox(height: 18),
        AspectRatio(aspectRatio: 16 / 9, child: _skeleton(null)),
      ];
    }
    if (_error) {
      return [
        _emptyCard([
          const Text('The videos could not be loaded', style: TextStyle(fontWeight: FontWeight.w500, color: Tone.fg(0xFF334155))),
          const SizedBox(height: 8),
          const Text('Check your internet connection and try again.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: TColors.slate500)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('videos-retry'),
            style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)), foregroundColor: Tone.fg(0xFF1E293B)),
            onPressed: _fetching ? null : _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try again'),
          ),
        ]),
      ];
    }
    if (_videos.isEmpty) {
      return [
        _emptyCard(const [
          Icon(Icons.play_circle_outline, size: 40, color: Tone.fg(0xFFCBD5E1)),
          SizedBox(height: 8),
          Text('No videos yet', style: TextStyle(fontWeight: FontWeight.w500, color: Tone.fg(0xFF334155))),
          SizedBox(height: 6),
          Text('New videos will show here as soon as we post them.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: TColors.slate500)),
        ]),
      ];
    }
    return [_stats(), const SizedBox(height: 18), ..._watch(), const SizedBox(height: 18), _playlist()];
  }

  // -------------------------------------------------------------- figures

  Widget _stats() {
    final videos = _videos;
    final watchedCount = videos.where((v) => _watched.contains(v.id)).length;
    final hasViews = videos.any((v) => v.views != null);
    final totalViews = videos.fold<int>(0, (s, v) => s + (v.views ?? 0));
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final recent = videos.where((v) => (DateTime.tryParse(v.published) ?? DateTime(0)).isAfter(monthAgo)).length;
    final pct = videos.isEmpty ? 0.0 : watchedCount / videos.length;
    return _grid([
      _stat(Icons.movie_outlined, _red50, Tone.fg(0xFFDC2626), 'Videos', Text('${videos.length}', style: _big), 'In the playlist'),
      _stat(
        Icons.check_circle_outline,
        const Tone.bg(0xFFECFDF5),
        const Tone.fg(0xFF059669),
        'Watched',
        Text.rich(TextSpan(children: [
          TextSpan(text: '$watchedCount ', style: _big),
          TextSpan(text: 'of ${videos.length}', style: const TextStyle(fontSize: 15, color: TColors.slate500)),
        ])),
        null,
        progress: pct,
      ),
      _stat(Icons.visibility_outlined, const Tone.bg(0xFFEFF6FF), const Tone.fg(0xFF2563EB), 'Total views',
          Text(hasViews ? _compact.format(totalViews) : '—', style: _big), 'Across all videos'),
      _stat(Icons.calendar_today_outlined, const Tone.bg(0xFFFFFBEB), const Tone.fg(0xFFD97706), 'Latest video',
          Text(timeAgo(videos.first.published).isEmpty ? '—' : timeAgo(videos.first.published), style: _big), '$recent new in the last 30 days'),
    ]);
  }

  static const _big = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Tone.fg(0xFF0F172A));

  Widget _grid(List<Widget> tiles) => Column(children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
            ]),
          ),
        ],
      ]);

  Widget _stat(IconData icon, Color bg, Color fg, String label, Widget value, String? sub, {double? progress}) => Container(
        key: ValueKey('videos-stat-$label'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: Tone.line(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: TColors.slate500))),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: fg),
            ),
          ]),
          const SizedBox(height: 4),
          value,
          const SizedBox(height: 4),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: progress, minHeight: 6, color: Tone.fg(0xFF0F172A), backgroundColor: Tone.bg(0xFFE2E8F0)),
            )
          else if (sub != null)
            Text(sub, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
        ]),
      );

  Widget _skeleton(double? height) => Container(
        height: height,
        decoration: BoxDecoration(color: Tone.bg(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
      );

  Widget _emptyCard(List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: Tone.line(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
        child: Column(children: children),
      );

  // --------------------------------------------------------------- player

  List<Widget> _watch() {
    final videos = _videos;
    final i = videos.indexWhere((v) => v.id == _currentId);
    final current = i >= 0 ? videos[i] : null;
    final prev = i > 0 ? videos[i - 1] : null;
    final next = i >= 0 && i + 1 < videos.length ? videos[i + 1] : null;
    if (current == null) return const [];
    final meta = [viewsLabel(current), uploadedOn(current.published)].where((s) => s.isNotEmpty).join(' · ');
    final longText = current.description.length > 200 || current.description.split('\n').length > 3;
    return [
      ClipRRect(
        key: _playerKey,
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: Colors.black,
            child: _started
                ? youtubePlayerBuilder(current.id, current.title, _ended)
                : InkWell(
                    key: const ValueKey('videos-play'),
                    onTap: () => _play(current.id),
                    child: Stack(fit: StackFit.expand, children: [
                      Opacity(
                        opacity: .9,
                        child: Image.network('https://i.ytimg.com/vi/${current.id}/hqdefault.jpg', fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                      const ColoredBox(color: Tone.bg(0x33000000)),
                      Center(
                        child: Container(
                          width: 72,
                          height: 50,
                          decoration: BoxDecoration(color: Tone.bg(0xFFDC2626), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.play_arrow, size: 34, color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(current.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, color: Tone.fg(0xFF0F172A))),
      if (meta.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(meta, style: const TextStyle(fontSize: 13.5, color: TColors.slate500)),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _pill('videos-prev', Icons.chevron_left, 'Previous', prev == null ? null : () => _play(prev.id)),
        _pill('videos-next', Icons.chevron_right, 'Next', next == null ? null : () => _play(next.id), iconAfter: true),
        // The web hides the word below sm:, leaving the icon; a phone has room.
        _pill('videos-youtube', Icons.open_in_new, 'YouTube', () => openExternal(context, 'https://www.youtube.com/watch?v=${current.id}')),
      ]),
      if (current.description.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('videos-description'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Tone.bg(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(current.description,
                maxLines: _showMore ? null : 3,
                overflow: _showMore ? null : TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Tone.fg(0xFF334155))),
            if (longText) ...[
              const SizedBox(height: 6),
              InkWell(
                key: const ValueKey('videos-more'),
                onTap: () => setState(() => _showMore = !_showMore),
                child: Text(_showMore ? 'Show less' : '...more',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A))),
              ),
            ],
          ]),
        ),
      ],
    ];
  }

  Widget _pill(String key, IconData icon, String label, VoidCallback? onTap, {bool iconAfter = false}) => OutlinedButton(
        key: ValueKey(key),
        style: OutlinedButton.styleFrom(
          backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)),
          foregroundColor: Tone.fg(0xFF1E293B),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!iconAfter) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
          Text(label),
          if (iconAfter) ...[const SizedBox(width: 4), Icon(icon, size: 16)],
        ]),
      );

  // ------------------------------------------------------------- playlist

  Widget _playlist() {
    final videos = _videos;
    final i = videos.indexWhere((v) => v.id == _currentId);
    final words = _q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final shown = [
      for (final v in videos)
        if (!(_filter == _Filter.watched && !_watched.contains(v.id)) &&
            !(_filter == _Filter.unwatched && _watched.contains(v.id)) &&
            words.every('${v.title} ${v.description}'.toLowerCase().contains))
          v,
    ];
    return Container(
      key: const ValueKey('videos-playlist'),
      decoration: BoxDecoration(color: Tone.bg(0xFFFFFFFF), border: Border.all(color: Tone.line(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.playlist_play, size: 18, color: Tone.fg(0xFFDC2626)),
                    SizedBox(width: 6),
                    Text('Playlist', style: TextStyle(fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A))),
                  ]),
                  Text(i >= 0 ? '${i + 1} / ${videos.length}' : '${videos.length} videos',
                      style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ]),
              ),
              const Text('Autoplay', style: TextStyle(fontSize: 12, color: Tone.fg(0xFF475569))),
              Switch(key: const ValueKey('videos-autoplay'), value: _autoplayNext, onChanged: _toggleAutoplay),
            ]),
            const SizedBox(height: 10),
            AppInput(
              key: const ValueKey('videos-search'),
              hintText: 'Search videos',
              prefixIcon: const Icon(Icons.search, color: Tone.fg(0xFF7F8EA3)),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (f, label) in const [(_Filter.all, 'All'), (_Filter.unwatched, 'Not watched'), (_Filter.watched, 'Watched')])
                InkWell(
                  key: ValueKey('videos-filter-${f.name}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _filter = f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: _filter == f ? Tone.button(Tone.bg(0xFF0F172A))! : Tone.bg(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                    child: Text(label,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: _filter == f ? Colors.white : Tone.fg(0xFF334155))),
                  ),
                ),
            ]),
          ]),
        ),
        const Divider(height: 1, color: Tone.line(0xFFE2E8F0)),
        Padding(
          padding: const EdgeInsets.all(6),
          child: shown.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No videos match.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: TColors.slate500)),
                )
              : Column(children: [for (final v in shown) _row(v)]),
        ),
      ]),
    );
  }

  Widget _row(ChannelVideo v) {
    final isCurrent = v.id == _currentId;
    final seen = _watched.contains(v.id);
    final meta = [viewsLabel(v), timeAgo(v.published)].where((s) => s.isNotEmpty).join(' · ');
    return Material(
      color: isCurrent ? _red50 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey('videos-row-${v.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _play(v.id),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 140,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(fit: StackFit.expand, children: [
                    ColoredBox(
                      color: Tone.bg(0xFFE2E8F0),
                      child: Image.network('https://i.ytimg.com/vi/${v.id}/mqdefault.jpg', fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox()),
                    ),
                    if (isCurrent)
                      ColoredBox(
                        color: const Tone.bg(0x80000000),
                        child: Center(
                          child: Text(_started ? 'NOW PLAYING' : 'UP NEXT',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .5, color: Colors.white)),
                        ),
                      ),
                    if (seen && !isCurrent)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Tone.bg(0xBF000000), borderRadius: BorderRadius.circular(4)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_outline, size: 11, color: Colors.white),
                            SizedBox(width: 3),
                            Text('Watched', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3, color: isCurrent ? _red700 : Tone.fg(0xFF0F172A))),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// components/videos/youtube-player.tsx: YouTube's IFrame Player API in a
/// WebView, asking for 720p as it starts and reporting the end of a video
/// (for Autoplay). If the API script cannot load it falls back to a plain
/// embed. The page is given the web's address as its origin, which YouTube
/// requires of an embed.
class YouTubePlayer extends StatefulWidget {
  const YouTubePlayer({super.key, required this.videoId, required this.title, required this.onEnded});
  final String videoId, title;
  final VoidCallback onEnded;
  @override
  State<YouTubePlayer> createState() => _YouTubePlayerState();
}

class _YouTubePlayerState extends State<YouTubePlayer> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final PlatformWebViewControllerCreationParams params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true, mediaTypesRequiringUserAction: const {})
        : const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('VideoChannel', onMessageReceived: (m) {
        if (m.message == 'ended') widget.onEnded();
      });
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) platform.setMediaPlaybackRequiresUserGesture(false);
    _controller.loadHtmlString(_html(widget.videoId), baseUrl: Env.webBase);
  }

  static String _html(String id) => '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p,iframe{width:100%;height:100%;border:0}</style></head>
<body><div id="p"></div>
<script>
var asked = false;
function hd(p){ try { p.setPlaybackQualityRange && p.setPlaybackQualityRange('hd720','hd720'); p.setPlaybackQuality && p.setPlaybackQuality('hd720'); } catch (e) {} }
function onYouTubeIframeAPIReady(){
  new YT.Player('p', {
    host: 'https://www.youtube-nocookie.com', videoId: '$id', width: '100%', height: '100%',
    playerVars: { autoplay: 1, rel: 0, playsinline: 1, vq: 'hd720' },
    events: {
      onReady: function(e){ hd(e.target); e.target.playVideo(); },
      onStateChange: function(e){
        if (e.data === YT.PlayerState.PLAYING && !asked) { asked = true; hd(e.target); }
        if (e.data === YT.PlayerState.ENDED) VideoChannel.postMessage('ended');
      }
    }
  });
}
function fallback(){
  document.getElementById('p').innerHTML = '<iframe src="https://www.youtube-nocookie.com/embed/$id?autoplay=1&rel=0&playsinline=1&vq=hd720" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>';
}
</script>
<script src="https://www.youtube.com/iframe_api" onerror="fallback()"></script>
</body></html>''';

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
