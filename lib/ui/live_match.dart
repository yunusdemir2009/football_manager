import 'dart:async';

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/game_state.dart';
import '../core/match.dart';
import 'widgets.dart';

/// Canli mac: dakika dakika ilerler; duraklatip taktik ve oyuncu degisikligi yapilabilir.
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
  bool showAll = false;
  int speedMs = 130;

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
    _timer = Timer.periodic(Duration(milliseconds: speedMs), (_) {
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

  void _toggleSpeed() {
    speedMs = speedMs == 130 ? 50 : speedMs == 50 ? 300 : 130;
    if (playing) _play();
    setState(() {});
  }

  String get _speedLabel => speedMs == 50 ? 'Hızlı' : speedMs == 300 ? 'Yavaş' : 'Normal';

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
                if (list.isEmpty) const ListTile(title: Text('Bu mevkide yedek yok')),
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

  Widget _scoreboard() {
    final scheme = Theme.of(context).colorScheme;
    Widget side(MatchSide t) => Expanded(
          child: Column(children: [
            TeamBadge(name: t.teamName, size: 44),
            const SizedBox(height: 6),
            Text(t.teamName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(t.formation.name, style: TextStyle(fontSize: 11, color: scheme.outline)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            side(s.home),
            Column(children: [
              Text('${s.hg} - ${s.ag}', style: Theme.of(context).textTheme.displaySmall),
              Text(
                s.finished ? 'Maç bitti' : s.minute == 0 ? 'Başlamadı' : "${s.minute}'",
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold),
              ),
              if (s.minute == 45 && !playing && !s.finished) const Text('Devre arası', style: TextStyle(fontSize: 12)),
            ]),
            side(s.away),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: s.minute / 90.0),
        ]),
      ),
    );
  }

  Widget _stats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Column(children: [
          StatBar(label: 'Topa sahip olma', home: s.possessionHome, away: 100 - s.possessionHome, suffix: '%'),
          StatBar(label: 'Şut', home: s.home.shots, away: s.away.shots),
          StatBar(label: 'İsabetli şut', home: s.home.onTarget, away: s.away.onTarget),
          StatBar(label: 'Sarı kart', home: s.home.yellows, away: s.away.yellows),
          if (s.home.reds + s.away.reds > 0) StatBar(label: 'Kırmızı kart', home: s.home.reds, away: s.away.reds),
        ]),
      ),
    );
  }

  Widget _tactics() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        Wrap(spacing: 6, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Mentalite:', style: TextStyle(fontSize: 12)),
          for (final m in Mentality.values)
            ChoiceChip(
              label: Text(m.label),
              visualDensity: VisualDensity.compact,
              selected: mine.mentality == m,
              onSelected: s.finished
                  ? null
                  : (_) {
                      s.setMentality(mine, m);
                      setState(() {});
                    },
            ),
        ]),
        Wrap(spacing: 6, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Savunma:', style: TextStyle(fontSize: 12)),
          for (final p in Pressing.values)
            ChoiceChip(
              label: Text(p.label),
              visualDensity: VisualDensity.compact,
              selected: mine.pressing == p,
              onSelected: s.finished
                  ? null
                  : (_) {
                      s.setPressing(mine, p);
                      setState(() {});
                    },
            ),
        ]),
      ]),
    );
  }

  Color? _eventColor(MatchEvent e) {
    switch (e.kind) {
      case EventKind.goal:
        return Theme.of(context).colorScheme.primary;
      case EventKind.red:
        return Colors.redAccent;
      case EventKind.yellow:
        return Colors.amber;
      case EventKind.injury:
        return Colors.orangeAccent;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = s.events.where((e) => showAll || e.important).toList().reversed.toList();
    return PopScope(
      canPop: s.finished && !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Canlı Maç'), automaticallyImplyLeading: false),
        body: ListView(children: [
          _scoreboard(),
          _stats(),
          _tactics(),
          const SizedBox(height: 6),
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
            if (!s.finished) OutlinedButton(onPressed: _toggleSpeed, child: Text('Hız: $_speedLabel')),
            if (!s.finished) OutlinedButton(onPressed: _skipToEnd, child: const Text('Sona kadar')),
            if (s.finished)
              FilledButton(
                onPressed: saving ? null : _finish,
                child: const Text('Maçı Bitir'),
              ),
          ]),
          SwitchListTile(
            dense: true,
            title: const Text('Tüm pozisyonları göster'),
            value: showAll,
            onChanged: (v) => setState(() => showAll = v),
          ),
          for (final e in events)
            ListTile(
              dense: true,
              title: Text(
                e.text,
                style: TextStyle(
                  color: _eventColor(e),
                  fontWeight: e.isGoal ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
