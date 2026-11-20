# -*- coding: utf-8 -*-
"""Mevcut oyuncu havuzunu (Small_Database.db) liglerdeki takimlara dagitip oyun veritabani uretir.

Kullanim:
  python build_game_db.py --src Small_Database.db --out ../assets/game.db [--seed 42]

Sonradan isim degistirmek icin: game.db icindeki Teams.name / Players.name sutunlarini duzenlemek yeterli.
Yeni lig eklemek icin leagues.csv'ye satir ekleyip betigi tekrar calistirin.
"""
import argparse, csv, os, random, sqlite3

SQUAD = {'GK': 3, 'DEF': 8, 'MID': 8, 'FWD': 6}   # takim basi 25 oyuncu
HERE = os.path.dirname(os.path.abspath(__file__))


def pos_group(pos):
    p = (pos or '').strip().upper()
    if p.startswith('GK'):
        return 'GK'
    head = p.replace('/', ' ').split()[0] if p else ''
    if head in ('D', 'WB'):
        return 'DEF'
    if head == 'S':
        return 'FWD'
    return 'MID'  # DM, M, AM


def value_of(ca, age):
    f = 1.3 if age <= 23 else 1.0 if age <= 29 else 0.7 if age <= 32 else 0.4
    return int(round((ca / 100.0) ** 4 * 120_000_000 * f, -4))


def load_teams_for(league, rng):
    n = int(league['teams'])
    strength = int(league['strength'])
    names, budgets = [], []
    if league['name'] == 'Süper Lig':
        with open(os.path.join(HERE, 'teams_super_lig.csv'), encoding='utf-8') as f:
            rows = list(csv.DictReader(f))
        rows = rows[:n]
        for r in rows:
            names.append(r['name'].strip()); budgets.append(int(r['budget']))
    # eksikleri uret: yer tutucu isimler (sonradan DB'de degistirilir)
    base = strength * 6_000_000
    while len(names) < n:
        i = len(names) + 1
        names.append(f"{league['country']} Takım {i}")
        budgets.append(int(base * (1.6 - 1.2 * (i - 1) / max(n - 1, 1)) * rng.uniform(0.9, 1.1)))
    return names, budgets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--seed', type=int, default=42)
    a = ap.parse_args()
    rng = random.Random(a.seed)

    with open(os.path.join(HERE, 'leagues.csv'), encoding='utf-8') as f:
        leagues = list(csv.DictReader(f))
    leagues.sort(key=lambda l: -int(l['strength']))  # guclu ligler havuzun ustunden alir

    src = sqlite3.connect(a.src)
    pool = {g: [] for g in SQUAD}
    for name, age, pos, fin, pas, tak, vis, sta, ca in src.execute(
            "SELECT name,age,position,finishing,passing,tackling,vision,stamina,ca FROM Players"):
        pool[pos_group(pos)].append((int(ca), name, int(age), (pos or '').strip(), fin, pas, tak, vis, sta))
    for g in pool:
        pool[g].sort(key=lambda p: -p[0])
    used = {g: set() for g in SQUAD}

    if os.path.exists(a.out):
        os.remove(a.out)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    db = sqlite3.connect(a.out)
    db.executescript("""
    CREATE TABLE Leagues(id INTEGER PRIMARY KEY, country TEXT, name TEXT, strength INTEGER);
    CREATE TABLE Teams(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, league_id INTEGER REFERENCES Leagues(id), budget INTEGER);
    CREATE TABLE Players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER, team_id INTEGER REFERENCES Teams(id),
        position TEXT, grp TEXT, finishing INTEGER, passing INTEGER, tackling INTEGER, vision INTEGER, stamina INTEGER,
        ca INTEGER, pa INTEGER, value INTEGER, wage INTEGER);
    CREATE TABLE Competitions(id INTEGER PRIMARY KEY, name TEXT, kind TEXT, slots TEXT);
    CREATE INDEX idx_pl_team ON Players(team_id);
    CREATE INDEX idx_tm_league ON Teams(league_id);
    """)
    db.executemany("INSERT INTO Competitions VALUES(?,?,?,?)", [
        (1, 'UEFA Şampiyonlar Ligi', 'uefa', 'tablo:1-4 (güçlü ligler)'),
        (2, 'UEFA Avrupa Ligi', 'uefa', 'tablo:5-6'),
        (3, 'UEFA Konferans Ligi', 'uefa', 'tablo:7')])  # simulasyonu henuz yok

    n_teams = n_players = 0
    for lg in leagues:
        db.execute("INSERT INTO Leagues VALUES(?,?,?,?)", (int(lg['id']), lg['country'], lg['name'], int(lg['strength'])))
        names, budgets = load_teams_for(lg, rng)
        n = len(names)
        order = sorted(range(n), key=lambda i: -budgets[i])  # butceye gore guc sirasi
        ids = []
        for i in range(n):
            cur = db.execute("INSERT INTO Teams(name,league_id,budget) VALUES(?,?,?)", (names[i], int(lg['id']), budgets[i]))
            ids.append(cur.lastrowid)
        rank = {team: r for r, team in enumerate(order)}
        for g, quota in SQUAD.items():
            need = n * quota
            size = len(pool[g])
            start = int((10 - int(lg['strength'])) * 0.012 * size)
            width = max(need * 3, int(0.06 * size))
            avail = [i for i in range(start, min(size, start + width)) if i not in used[g]]
            if len(avail) < need:  # bant dolduysa alttan tamamla
                avail += [i for i in range(start + width, size) if i not in used[g]][:need - len(avail)]
            if len(avail) < need:
                raise SystemExit('Havuz yetersiz: ' + g)
            pick = sorted(rng.sample(avail, need))
            used[g].update(pick)
            chunk = [pool[g][i] for i in pick]
            cap = [quota] * n
            for p in chunk:  # iyiden kotuye: guclu takimlar daha yuksek olasiliklu
                cand = [t for t in range(n) if cap[t] > 0]
                w = [pow(2.718281828, -4.0 * rank[t] / n) for t in cand]
                t = rng.choices(cand, weights=w)[0]
                cap[t] -= 1
                ca, name, age, pos, fin, pas, tak, vis, sta = p
                pa = min(100, ca + (rng.randint(5, 20) if age < 23 else rng.randint(0, 5)))
                v = value_of(ca, age)
                db.execute("INSERT INTO Players(name,age,team_id,position,grp,finishing,passing,tackling,vision,stamina,ca,pa,value,wage) "
                           "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                           (name, age, ids[t], pos, g, fin, pas, tak, vis, sta, ca, pa, v, int(v * 0.12)))
                n_players += 1
        n_teams += n
    db.commit(); db.execute('VACUUM'); db.close()
    print(f'Lig: {len(leagues)} | Takim: {n_teams} | Oyuncu: {n_players} | Boyut: {os.path.getsize(a.out)/1e6:.2f} MB')


if __name__ == '__main__':
    main()
