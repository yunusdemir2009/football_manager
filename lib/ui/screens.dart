import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/game_state.dart';
import '../core/match.dart';
import '../data/game_db.dart';
import 'live_match.dart';
import 'widgets.dart';

String money(int v) {
  final a = v.abs();
  final s = a >= 1000000
      ? '${(a / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)}M €'
      : a >= 1000
          ? '${(a / 1000).round()}K €'
          : '$a €';
  return v < 0 ? '-$s' : s;
}

void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

// ---------------- Baslangic ----------------
class StartScreen extends StatelessWidget {
  final GameDb gdb;
  final GameState? saved;
  const StartScreen({super.key, required this.gdb, this.saved});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⚽ Futbol Menajer', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            if (saved != null)
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => HomeScreen(game: saved!))),
                child: const Text('Devam Et'),
              ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => LeagueSelectScreen(gdb: gdb))),
              child: const Text('Yeni Oyun'),
            ),
          ]),
        ),
      ),
    );
  }
}

class LeagueSelectScreen extends StatelessWidget {
  final GameDb gdb;
  const LeagueSelectScreen({super.key, required this.gdb});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lig Seç')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: gdb.leagues(),
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final l = snap.data!;
          return ListView.builder(
            itemCount: l.length,
            itemBuilder: (c, i) => ListTile(
              title: Text('${l[i]['country']} – ${l[i]['name']}'),
              subtitle: Text('${l[i]['teams']} takım'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TeamSelectScreen(gdb: gdb, leagueId: l[i]['id'] as int))),
            ),
          );
        },
      ),
    );
  }
}

class TeamSelectScreen extends StatefulWidget {
  final GameDb gdb;
  final int leagueId;
  const TeamSelectScreen({super.key, required this.gdb, required this.leagueId});

  @override
  State<TeamSelectScreen> createState() => _TeamSelectScreenState();
}

class _TeamSelectScreenState extends State<TeamSelectScreen> {
  bool busy = false;

  Future<void> _start(int teamId) async {
    setState(() => busy = true);
    final g = await GameState.create(widget.gdb, widget.leagueId, teamId);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen(game: g)), (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Takım Seç')),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Map<String, Object?>>>(
              future: widget.gdb.teamsOf(widget.leagueId),
              builder: (c, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final t = snap.data!;
                return ListView.builder(
                  itemCount: t.length,
                  itemBuilder: (c, i) => ListTile(
                    title: Text(t[i]['name'] as String),
                    trailing: Text(money(t[i]['budget'] as int)),
                    onTap: () => _start(t[i]['id'] as int),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------- Ana ekran ----------------
class HomeScreen extends StatefulWidget {
  final GameState game;
  const HomeScreen({super.key, required this.game});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  bool busy = false;
  GameState get g => widget.game;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    await f();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_matchTab(), _tableTab(), _tacticTab(), _transferTab(), _financeTab()];
    return Scaffold(
      appBar: AppBar(
        title: Text('${g.myTeam.name} • Sezon ${g.season}'),
        bottom: busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator()) : null,
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_soccer), label: 'Maç'),
          NavigationDestination(icon: Icon(Icons.leaderboard), label: 'Tablo'),
          NavigationDestination(icon: Icon(Icons.dashboard_customize), label: 'Taktik'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Transfer'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Finans'),
        ],
      ),
    );
  }

  Future<void> _playLive() async {
    final session = g.beginWeek();
    if (session == null) {
      await _run(g.finishWeek);
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LiveMatchScreen(game: g, session: session)));
    if (mounted) setState(() {});
  }

  // ---- Mac ----
  Widget _matchTab() {
    if (g.seasonOver) {
      final st = g.standings();
      final champ = g.teamName(st.first.teamId);
      final pos = st.indexWhere((s) => s.teamId == g.teamId) + 1;
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.emoji_events, size: 64),
          Text('Sezon bitti', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Şampiyon: $champ'),
          Text('Sizin sıranız: $pos.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : () => _run(g.newSeason),
            child: const Text('Yeni Sezon'),
          ),
        ]),
      );
    }
    final next = g.myFixture(g.week);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Hafta ${g.week} / ${g.totalWeeks}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (next == null)
        const Text('Bu hafta maçınız yok (bay).')
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(children: [
                  TeamBadge(name: g.teamName(next.home), size: 44),
                  const SizedBox(height: 6),
                  Text(g.teamName(next.home), textAlign: TextAlign.center),
                  FormDots(form: g.formOf(next.home)),
                ]),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('VS')),
              Expanded(
                child: Column(children: [
                  TeamBadge(name: g.teamName(next.away), size: 44),
                  const SizedBox(height: 6),
                  Text(g.teamName(next.away), textAlign: TextAlign.center),
                  FormDots(form: g.formOf(next.away)),
                ]),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : _playLive,
        icon: const Icon(Icons.play_arrow),
        label: Text(next == null ? 'Haftayı Geç' : 'Maça Çık (canlı)'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: busy ? null : () => _run(g.quickPlayWeek),
        icon: const Icon(Icons.fast_forward),
        label: const Text('Hızlı Simüle'),
      ),
      const SizedBox(height: 20),
      if (g.news.isNotEmpty) ...[
        Text('Haberler', style: Theme.of(context).textTheme.titleMedium),
        const Divider(),
        ...g.news.map((n) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(n))),
        const SizedBox(height: 16),
      ],
      Builder(builder: (context) {
        final up = g.upcoming(6);
        if (up.length <= 1) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Yaklaşan maçlar', style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          for (final f in up.skip(1))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('Hafta ${f.week}:  ${g.teamName(f.home)} – ${g.teamName(f.away)}'),
            ),
          const SizedBox(height: 16),
        ]);
      }),
      if (g.lastResults.isNotEmpty) ...[
        Text('Son hafta sonuçları', style: Theme.of(context).textTheme.titleMedium),
        const Divider(),
        ...g.lastResults.map((r) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(r))),
      ],
    ]);
  }

  // ---- Tablo ----
  Widget _tableTab() {
    final st = g.standings();
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: const [
          SizedBox(width: 24, child: Text('#')),
          SizedBox(width: 32),
          Expanded(child: Text('Takım')),
          SizedBox(width: 28, child: Text('O')),
          SizedBox(width: 38, child: Text('AV')),
          SizedBox(width: 32, child: Text('P')),
        ]),
      ),
      const Divider(),
      for (int i = 0; i < st.length; i++)
        Container(
          color: st[i].teamId == g.teamId ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            SizedBox(width: 24, child: Text('${i + 1}')),
            TeamBadge(name: g.teamName(st[i].teamId), size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.teamName(st[i].teamId), overflow: TextOverflow.ellipsis),
                FormDots(form: g.formOf(st[i].teamId)),
              ]),
            ),
            SizedBox(width: 28, child: Text('${st[i].played}')),
            SizedBox(width: 38, child: Text('${st[i].gd}')),
            SizedBox(width: 32, child: Text('${st[i].points}', style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
        ),
    ]);
  }

  // ---- Taktik / Kadro ----
  Future<void> _pickStarter(Player out) async {
    final xiIds = g.myXI.map((p) => p.id).toSet();
    final cands = g.squad(g.teamId).where((p) => p.grp == out.grp && !xiIds.contains(p.id)).toList()
      ..sort((a, b) {
        final c = (b.available ? 1 : 0).compareTo(a.available ? 1 : 0);
        return c != 0 ? c : b.ca.compareTo(a.ca);
      });
    final picked = await showModalBottomSheet<Player>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text('${out.name} yerine'), subtitle: const Text('Aynı mevkiden bir oyuncu seçin')),
          if (cands.isEmpty) const ListTile(title: Text('Başka oyuncu yok')),
          for (final p in cands)
            ListTile(
              dense: true,
              title: Text(p.name),
              subtitle: Text('${p.position} • ${p.age} yaş • Kond. ${p.stamina}${_statusText(p)}'),
              trailing: Text('${p.ca}', style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.of(ctx).pop(p),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    final err = await g.swapStarter(out, picked);
    if (!mounted) return;
    if (err != null) snack(context, err);
    setState(() {});
  }

  String _statusText(Player p) {
    if (p.injuryWeeks > 0) return '  🩹 sakat (${p.injuryWeeks} hf)';
    if (p.banWeeks > 0) return '  🟥 cezalı (${p.banWeeks} maç)';
    if (p.yellows > 0) return '  🟨 ${p.yellows}';
    return '';
  }

  Widget _tacticTab() {
    final xi = g.myXI;
    final xiIds = xi.map((p) => p.id).toSet();
    final bench = g.myBench;
    final benchIds = bench.map((p) => p.id).toSet();
    final reserves = g.squad(g.teamId).where((p) => !xiIds.contains(p.id) && !benchIds.contains(p.id)).toList()
      ..sort((a, b) => b.ca.compareTo(a.ca));
    const order = {'GK': 0, 'DEF': 1, 'MID': 2, 'FWD': 3};
    final xiSorted = [...xi]..sort((a, b) => (order[a.grp] ?? 9).compareTo(order[b.grp] ?? 9));

    Widget row(Player p, {bool tappable = false}) => ListTile(
          dense: true,
          leading: CircleAvatar(radius: 16, child: Text(p.grp, style: const TextStyle(fontSize: 10))),
          title: Text(p.name),
          subtitle: Text('${p.position} • ${p.age} yaş • Kond. ${p.stamina}${_statusText(p)}'),
          trailing: Text('${p.ca}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          onTap: tappable ? () => _pickStarter(p) : null,
        );

    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          const Text('Diziliş: '),
          DropdownButton<String>(
            value: g.formation.name,
            items: [for (final f in kFormations) DropdownMenuItem(value: f.name, child: Text(f.name))],
            onChanged: (v) async {
              if (v == null) return;
              await g.setFormation(formationByName(v));
              if (mounted) setState(() {});
            },
          ),
          const Spacer(),
          TextButton(
            onPressed: () async {
              await g.autoPickLineup();
              if (mounted) setState(() {});
            },
            child: const Text('Otomatik seç'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<Mentality>(
          segments: [for (final m in Mentality.values) ButtonSegment(value: m, label: Text(m.label))],
          selected: {g.mentality},
          onSelectionChanged: (v) async {
            await g.setMentality(v.first);
            if (mounted) setState(() {});
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SegmentedButton<Pressing>(
          segments: [for (final p in Pressing.values) ButtonSegment(value: p, label: Text(p.label))],
          selected: {g.pressing},
          onSelectionChanged: (v) async {
            await g.setPressing(v.first);
            if (mounted) setState(() {});
          },
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('İlk 11 (değiştirmek için oyuncuya dokunun)', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      for (final p in xiSorted) row(p, tappable: true),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('Yedekler', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      for (final p in bench) row(p),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('Kadro dışı', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      for (final p in reserves) row(p),
    ]);
  }

  // ---- Transfer ----
  String filter = 'ALL';
  Widget _transferTab() {
    final others = g.players.where((p) => p.teamId != g.teamId && (filter == 'ALL' || p.grp == filter)).toList()
      ..sort((a, b) => b.ca.compareTo(a.ca));
    final list = others.take(60).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 6, children: [
          for (final f in ['ALL', 'GK', 'DEF', 'MID', 'FWD'])
            ChoiceChip(label: Text(f), selected: filter == f, onSelected: (_) => setState(() => filter = f)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.centerLeft, child: Text('Bütçe: ${money(g.myTeam.budget)}')),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (c, i) {
            final p = list[i];
            return ListTile(
              dense: true,
              title: Text('${p.name}  (${p.ca})'),
              subtitle: Text('${p.grp} • ${p.age} yaş • ${g.teamName(p.teamId)}'),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  final err = await g.buy(p);
                  if (!mounted) return;
                  setState(() {});
                  snack(context, err ?? '${p.name} transfer edildi');
                },
                child: Text(money(g.buyPrice(p))),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ---- Finans ----
  Widget _financeTab() {
    final squad = g.squad(g.teamId)..sort((a, b) => b.value.compareTo(a.value));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(title: const Text('Bütçe'), trailing: Text(money(g.myTeam.budget))),
      ),
      Card(
        child: ListTile(title: const Text('Kadro değeri'), trailing: Text(money(g.squadValue(g.teamId)))),
      ),
      Card(
        child: ListTile(title: const Text('Yıllık maaş gideri'), trailing: Text(money(g.squadWages(g.teamId)))),
      ),
      const SizedBox(height: 12),
      Text('Oyuncu sat (değerin %80\'i)', style: Theme.of(context).textTheme.titleMedium),
      const Divider(),
      for (final p in squad)
        ListTile(
          dense: true,
          title: Text('${p.name}  (${p.ca})'),
          subtitle: Text('${p.grp} • ${p.age} yaş'),
          trailing: OutlinedButton(
            onPressed: () async {
              final err = await g.sell(p);
              if (!mounted) return;
              setState(() {});
              snack(context, err ?? '${p.name} satıldı');
            },
            child: Text(money(g.sellPrice(p))),
          ),
        ),
    ]);
  }
}
