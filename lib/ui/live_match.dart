import 'dart:async';

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/game_state.dart';
import '../core/match.dart';

/// Canli mac: dakika dakika ilerler; duraklatip mentalite ve oyuncu degisikligi yapilabilir.
class LiveMatchScreen extends StatefulWidget {
  final GameState game;
  final MatchSession session;
  const LiveMatchScreen({super.key, required this.game, required this.session});

  @override
  State<LiveMatchScreen> createState() => _LiveMatchScreenState();
}

class _LiveMatchScreenState extends State<LiveMatchScreen> {
  Timer? _timer;
  bool playing = false;
  bool saving = false;

  MatchSession get s => widget.session;
  MatchSide get mine => s.home.isUser ? s.home : s.away;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    if (s.finished) return;
    _timer?.cancel();
    setState(() => playing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 130), (_) {
      if (!mounted) return;
      s.step();
      if (s.minute == 45 || s.finished) {
        _timer?.cancel();
        playing = false;
      }
      setState(() {});
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => playing = false);
  }

  void _skipToEnd() {
    _timer?.cancel();
    s.simulateToEnd();
    setState(() => playing = false);
  }

  Future<void> _finish() async {
    setState(() => saving = true);
    await widget.game.finishWeek();
    if (mounted) Navigator.of(context).pop();
  }

  void _openSubs() {
    _pause();
    Player? out;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final list = out == null ? mine.xi : mine.bench.where((p) => p.grp == out!.grp).toList();
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(out == null ? 'Çıkacak oyuncuyu seç' : '${out!.name} yerine girecek oyuncu'),
              subtitle: Text('Kalan değişiklik: ${kMaxSubs - mine.subsUsed}'),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final p in list)
                  ListTile(
                    dense: true,
                    leading: Text(p.grp),
                    title: Text(p.name),
                    trailing: Text('CA ${p.ca} • Kond. ${p.stamina}'),
                    onTap: () {
                      if (out == null) {
                        setSheet(() => out = p);
                      } else {
                        final err = s.substitute(mine, out!, p);
                        Navigator.of(ctx).pop();
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                        }
                        setState(() {});
                      }
                    },
                  ),
              ]),
            ),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = s.events.reversed.toList();
    return PopScope(
      canPop: s.finished && !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Canlı Maç'), automaticallyImplyLeading: false),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(s.home.teamName, textAlign: TextAlign.center)),
                Text('${s.hg} - ${s.ag}', style: Theme.of(context).textTheme.headlineMedium),
                Expanded(child: Text(s.away.teamName, textAlign: TextAlign.center)),
              ]),
              const SizedBox(height: 4),
              Text(s.finished ? 'Maç bitti' : "${s.minute}'"),
              if (s.minute == 45 && !playing && !s.finished) const Text('Devre arası'),
            ]),
          ),
          Wrap(spacing: 6, children: [
            for (final m in Mentality.values)
              ChoiceChip(
                label: Text(m.label),
                selected: mine.mentality == m,
                onSelected: s.finished
                    ? null
                    : (_) {
                        s.setMentality(mine, m);
                        setState(() {});
                      },
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (!s.finished)
              FilledButton.icon(
                onPressed: playing ? _pause : _play,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                label: Text(playing ? 'Duraklat' : (s.minute == 0 ? 'Başlat' : 'Devam')),
              ),
            if (!s.finished)
              FilledButton.tonal(
                onPressed: s.minute == 0 ? null : _openSubs,
                child: Text('Değişiklik (${kMaxSubs - mine.subsUsed})'),
              ),
            if (!s.finished) OutlinedButton(onPressed: _skipToEnd, child: const Text('Sona kadar')),
            if (s.finished)
              FilledButton(
                onPressed: saving ? null : _finish,
                child: const Text('Maçı Bitir'),
              ),
          ]),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: events.length,
              itemBuilder: (c, i) => ListTile(
                dense: true,
                title: Text(events[i].text),
                textColor: events[i].isGoal ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
