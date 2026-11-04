// The 26 Oct – 2 Nov web pull, part 1 (Report 30): the rebuilt Help Center,
// the Contact support card (Help Center and Business Office) and the new
// System → Videos page, at phone width.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/videos_screen.dart';
import 'package:poultrycore_mobile/pages/shared/help/contact_support.dart';
import 'package:poultrycore_mobile/pages/shared/help/help_search.dart';
import 'package:poultrycore_mobile/pages/shared/help/help_types.dart';
import 'package:poultrycore_mobile/pages/shared/help/poultry_help_content.dart';
import 'package:poultrycore_mobile/pages/shared/help_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

/// Scrolls the page until [f] is built, then centres it.
Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 150 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 150 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 500));
    await tester.pumpAndSettle();
  }
  expect(f, findsWidgets);
  Scrollable.ensureVisible(tester.element(f.first), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

/// Records what the external links would open.
List<String> recordLinks() {
  final opened = <String>[];
  final before = openExternalLink;
  openExternalLink = (url) async {
    opened.add(url);
    return true;
  };
  addTearDown(() => openExternalLink = before);
  return opened;
}

Future<void> openHelp(WidgetTester tester, {Company? as}) async {
  final s = await sessionFor(FakeApi());
  await open(tester, HelpCenterScreen(session: s, company: as ?? company), size: phone);
}

const _feed = {
  'channelTitle': 'VisibilityCore',
  'channelUrl': '',
  'playlistUrl': 'https://www.youtube.com/playlist?list=PLtest12345',
  'videos': [
    {'id': 'aaaaaaaaaaa', 'title': 'Getting started', 'description': 'Set up your farm.\nLine two\nLine three\nLine four', 'published': '2026-10-30T10:00:00Z', 'views': 1500},
    {'id': 'bbbbbbbbbbb', 'title': 'Recording a sale', 'description': 'Eggs and birds.', 'published': '2026-09-01T10:00:00Z', 'views': 20},
    {'id': 'ccccccccccc', 'title': 'Daily Closing', 'description': '', 'published': '2025-01-01T10:00:00Z'},
  ],
};

void main() {
  group('Help search (help-search.ts / fuzzy.ts)', () {
    final index = prepareHelpIndex(helpEntries);

    test('the content came across whole', () {
      expect(helpEntries.where((e) => e.kind == HelpKind.faq).length, 23);
      expect(helpEntries.where((e) => e.kind == HelpKind.fix).length, 8);
      expect(helpEntries.where((e) => e.kind == HelpKind.term).length, 19);
      expect(featureGuides.length, 11);
      expect({for (final e in helpEntries) e.id}.length, helpEntries.length, reason: 'ids are unique anchors');
      final reverse = helpEntries.firstWhere((e) => e.id == 'reverse-sale');
      expect(reverse.title, isNotEmpty);
      expect(reverse.links, isNotEmpty);
    });

    test('a question finds its answer, typos included', () {
      expect(searchHelp('how do I reverse a sale?', index).first.entry.id, 'reverse-sale');
      expect(searchHelp('how do i reverse a sael', index).map((h) => h.entry.id), contains('reverse-sale'));
      expect(searchHelp('eggs per crate', index).map((h) => h.entry.id), contains('eggs-per-crate'));
      expect(searchHelp('zzzz qqqq', index), isEmpty);
      expect(meaningfulWords('how do I reverse a sale'), ['reverse', 'sale']);
      expect(meaningfulWords('how do i'), ['how', 'do', 'i'], reason: 'only question words: keep them');
    });

    test('the matcher tiers', () {
      expect(scoreText('sales', 'Sales'), 100);
      expect(scoreText('sal', 'Sales'), 90);
      expect(scoreText('cust bal', 'Customer Balances'), 80);
      expect(scoreText('pl', 'Profit & Loss'), 65);
      expect(scoreText('expences', 'Expenses'), 55);
      expect(editDistance('slaes', 'sales'), 1, reason: 'a transposition is one edit');
    });

    test('highlighting matches word starts only', () {
      final runs = highlightRuns('Sales and wholesale', ['sale']);
      expect(runs.where((r) => r.hit).map((r) => r.text), ['Sales']);
    });

    test('Go to page: verbs stripped, synonyms used', () {
      expect(parseQuery('new sale'), 'sale');
      expect(parseQuery('go to cash flow'), 'cash flow');
      const pages = [
        (title: 'Customer Balances', href: '/customer-balances', group: 'Sales'),
        (title: 'Cash Flow', href: '/poultry-cash-flow', group: 'Money'),
        (title: 'Cash Account', href: '/poultry-cash-account', group: 'Money'),
        (title: 'Account', href: '/profile', group: 'Your account'),
      ];
      expect(rankPages('who owes', pages).first.href, '/customer-balances');
      expect(rankPages('go to cash flow', pages).first.href, '/poultry-cash-flow');
      expect(pageKeywords('Account'), contains('password'));
      expect(pageKeywords('Cash Account'), isNot(contains('password')), reason: '"=account" is the whole title only');
    });

    test('support links carry only the message', () {
      expect(supportPhones.first, '+1 (917) 420-2946', reason: 'USA line first');
      expect(supportPhones, contains('+233 50 363 8419'));
      expect(mailtoLink(''), 'mailto:techretainer@gmail.com');
      expect(mailtoLink(' Sale missing '), 'mailto:techretainer@gmail.com?body=Sale%20missing');
      expect(whatsappLink('Hi & bye'), 'https://wa.me/19174202946?text=Hi%20%26%20bye');
      expect(telLink('+233 50 363 8419'), 'tel:+233503638419');
    });
  });

  group('Help Center screen (app/help/page.tsx)', () {
    testWidgets('header, suggestions, Feature Guide, the three tabs', (tester) async {
      await openHelp(tester);
      expect(find.text('e.g. how do I reverse a sale?'), findsOneWidget);
      expect(find.text('who owes me'), findsOneWidget);
      expect(find.text('Feature Guide'), findsOneWidget);
      await see(tester, find.byKey(const ValueKey('help-guide-/poultry-company-setup')));
      await see(tester, find.byKey(const ValueKey('help-tab-faq')));
      expect(find.text('23'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);

      // Questions: open by default; a category narrows; Collapse / Expand all.
      await see(tester, find.text('How do I set up my farm?'));
      await tap(tester, find.byKey(const ValueKey('faq-cat-Flocks & Birds')));
      expect(find.text('How do I set up my farm?'), findsNothing);
      await tap(tester, find.text('Collapse all'));
      expect(find.text('Expand all'), findsOneWidget);
      await tap(tester, find.text('Expand all'));
      expect(find.text('Collapse all'), findsOneWidget);

      // Troubleshooting: closed until opened.
      await tap(tester, find.byKey(const ValueKey('help-tab-fix')));
      expect(find.text('Something looks wrong? Find the symptom, open it, and work through the checks in order.'), findsOneWidget);
      final fix = helpEntries.firstWhere((e) => e.id == 'cash-vs-profit');
      expect(find.text('Copy link'), findsNothing);
      await tap(tester, find.text(fix.title));
      await see(tester, find.text('Copy link'));

      // Glossary: A-Z letters and every term.
      await tap(tester, find.byKey(const ValueKey('help-tab-term')));
      final first = (helpEntries.where((e) => e.kind == HelpKind.term).toList()..sort((a, b) => a.title.compareTo(b.title))).first;
      expect(find.byKey(ValueKey('help-letter-${first.title[0].toUpperCase()}')), findsOneWidget);
      await see(tester, find.text(first.title));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a numbered answer, its page link and Copy link', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await openHelp(tester);
      // "How do I set up my farm?" is four numbered steps.
      await see(tester, find.text('Company Setup: farm name, address, currency and time zone.'));
      await see(tester, find.byKey(const ValueKey('help-copy-set-up-farm')));
      await tester.tap(find.byKey(const ValueKey('help-copy-set-up-farm')));
      await tester.pump();
      expect(copied, endsWith('/help#set-up-farm'));
      expect(find.text('Link copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-link-set-up-farm-/poultry-company-setup')), findsOneWidget);
    });

    testWidgets('search: suggestion, Go to page, kinds, Ask support', (tester) async {
      final opened = recordLinks();
      await openHelp(tester);
      await tester.tap(find.text('who owes me'));
      await tester.pumpAndSettle();
      expect(find.textContaining('for “who owes me”'), findsOneWidget);
      expect(find.text('GO TO PAGE'), findsOneWidget);
      expect(find.text('Feature Guide'), findsNothing, reason: 'results replace the browse view');
      await see(tester, find.text('Not what you needed? '));

      await see(tester, find.byKey(const ValueKey('help-search')));
      await tester.enterText(find.byKey(const ValueKey('help-search')), 'zzzz qqqq');
      await tester.pumpAndSettle();
      expect(find.text('No answer matches “zzzz qqqq” yet.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('help-ask-support')));
      await tester.pumpAndSettle();
      final box = tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('support-message')), matching: find.byType(TextField)));
      expect(box.controller!.text, 'zzzz qqqq');
      await see(tester, find.byKey(const ValueKey('support-whatsapp')));
      await tester.tap(find.byKey(const ValueKey('support-whatsapp')));
      await tester.pumpAndSettle();
      expect(opened.last, 'https://wa.me/19174202946?text=zzzz%20qqqq');

      await see(tester, find.byKey(const ValueKey('help-search-clear')));
      await tester.tap(find.byKey(const ValueKey('help-search-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Feature Guide'), findsOneWidget);
    });

    testWidgets('Contact support: email and the three call lines, USA first', (tester) async {
      final opened = recordLinks();
      await openHelp(tester);
      await see(tester, find.text('Contact support'));
      expect(find.text('Describe what you were doing and what went wrong. Only your message is sent.'), findsOneWidget);
      for (final p in supportPhones) {
        expect(find.text(p), findsOneWidget);
      }
      await tap(tester, find.byKey(const ValueKey('support-call-+233 50 363 8419')));
      expect(opened.last, 'tel:+233503638419');
      await tap(tester, find.byKey(const ValueKey('support-email')));
      expect(opened.last, 'mailto:techretainer@gmail.com');
      await tap(tester, find.byKey(const ValueKey('support-mail')));
      expect(opened.last, 'mailto:techretainer@gmail.com', reason: 'an empty message sends no body');
      expect(tester.takeException(), isNull);
    });

    testWidgets('staff: answers do not link to Setup pages', (tester) async {
      await openHelp(tester, as: Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, role: 'Staff'));
      await see(tester, find.byKey(const ValueKey('help-guide-/sales')));
      expect(find.byKey(const ValueKey('help-guide-/poultry-company-setup')), findsNothing);
      await see(tester, find.text('Company Setup: farm name, address, currency and time zone.'));
      expect(find.byKey(const ValueKey('help-link-set-up-farm-/poultry-company-setup')), findsNothing);
    });
  });

  group('Videos (app/poultry-videos/page.tsx)', () {
    late Widget Function(String, String, VoidCallback) beforePlayer;
    late Future<ChannelFeed?> Function() beforeFeed;
    VoidCallback? ended;
    setUp(() {
      beforePlayer = youtubePlayerBuilder;
      beforeFeed = loadVideosFeed;
      youtubePlayerBuilder = (id, title, onEnded) {
        ended = onEnded;
        return Text('PLAYER $id', key: const ValueKey('fake-player'));
      };
    });
    tearDown(() {
      youtubePlayerBuilder = beforePlayer;
      loadVideosFeed = beforeFeed;
    });

    Future<void> openVideos(WidgetTester tester, Future<ChannelFeed?> Function() feed) async {
      loadVideosFeed = feed;
      final s = await sessionFor(FakeApi());
      await open(tester, PoultryVideosScreen(session: s, company: company), size: phone);
    }

    test('System menu row, route and the feed shape', () {
      final system = webNavGroups['poultry']!.firstWhere((g) => g.title == 'System');
      final labels = [for (final s in system.subGroups) for (final l in s.links) l.label];
      expect(labels.indexOf('Videos'), labels.indexOf('Help Center') + 1);
      expect(pageScreens.containsKey('/poultry-videos'), isTrue);
      final f = ChannelFeed.fromJson(_feed);
      expect(f.videos.length, 3);
      expect(f.videos.last.views, isNull);
      expect(viewsLabel(f.videos.first), '1.5K views');
      final now = DateTime.utc(2026, 11, 3);
      expect(timeAgo('2026-11-03T01:00:00Z', now: now), 'Today');
      expect(timeAgo('2026-10-31T00:00:00Z', now: now), '3 days ago');
      expect(timeAgo('2026-09-01T00:00:00Z', now: now), '2 mo ago');
      expect(timeAgo('2025-01-01T00:00:00Z', now: now), '1 yr ago');
    });

    testWidgets('figures, play, Next, autoplay, watched, filters, search', (tester) async {
      final opened = recordLinks();
      await openVideos(tester, () async => ChannelFeed.fromJson(_feed));
      expect(find.text('Step-by-step guide videos to help you get the most out of the system.'), findsOneWidget);
      expect(find.text('Open on YouTube'), findsOneWidget);
      expect(find.text('In the playlist'), findsOneWidget);
      expect(find.text('0 of 3'), findsOneWidget, reason: 'Watched');
      expect(find.text('1.5K'), findsOneWidget, reason: 'total views 1,520');
      expect(find.byKey(const ValueKey('fake-player')), findsNothing, reason: 'nothing plays until asked');

      // The newest is up next; the description folds at three lines.
      await see(tester, find.text('...more'));
      expect(find.text('Getting started'), findsWidgets);
      await tester.tap(find.text('...more'));
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);

      await tap(tester, find.byKey(const ValueKey('videos-play')));
      expect(find.text('PLAYER aaaaaaaaaaa'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('videos-next')));
      expect(find.text('PLAYER bbbbbbbbbbb'), findsOneWidget);

      // A video ending plays the next one while Autoplay is on.
      ended!();
      await tester.pumpAndSettle();
      expect(find.text('PLAYER ccccccccccc'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(watchedKey)!), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);

      // Autoplay off: the end of a video stays put, and is remembered.
      await tap(tester, find.byKey(const ValueKey('videos-autoplay')));
      expect(prefs.getString(autoplayKey), 'off');
      await tap(tester, find.byKey(const ValueKey('videos-prev')));
      ended!();
      await tester.pumpAndSettle();
      expect(find.text('PLAYER bbbbbbbbbbb'), findsOneWidget);

      await tap(tester, find.byKey(const ValueKey('videos-youtube')));
      expect(opened.last, 'https://www.youtube.com/watch?v=bbbbbbbbbbb');

      // Filters and search over the playlist.
      await tap(tester, find.byKey(const ValueKey('videos-filter-unwatched')));
      expect(find.text('No videos match.'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('videos-filter-all')));
      await see(tester, find.byKey(const ValueKey('videos-search')));
      await tester.enterText(find.byKey(const ValueKey('videos-search')), 'eggs');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('videos-row-bbbbbbbbbbb')), findsOneWidget, reason: 'matches the description');
      expect(find.byKey(const ValueKey('videos-row-aaaaaaaaaaa')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no videos yet', (tester) async {
      await openVideos(tester, () async => const ChannelFeed());
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.text('New videos will show here as soon as we post them.'), findsOneWidget);
      expect(find.text('Open on YouTube'), findsNothing);
    });

    testWidgets('could not be loaded, then Try again', (tester) async {
      var fail = true;
      await openVideos(tester, () async {
        if (fail) throw Exception('offline');
        return ChannelFeed.fromJson(_feed);
      });
      expect(find.text('The videos could not be loaded'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('videos-retry')));
      await tester.pumpAndSettle();
      expect(find.text('In the playlist'), findsOneWidget);
    });
  });
}
