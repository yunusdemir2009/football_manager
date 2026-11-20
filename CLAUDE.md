# Futbol Menajer – Claude Code proje notları

Android için Flutter (Dart) ile yazılan futbol menajerlik oyunu. Dil: Türkçe (UI metinleri, commit mesajları, açıklamalar).

## Hedef ve kararlar
- Avrupa ulusal ligleri + UEFA kupaları. Oyuncu bir lig/takım seçer, hafta hafta oynar.
- Veri: `assets/game.db` (SQLite). Takım/oyuncu isimleri sadece bu veritabanından değiştirilir; kod isme bağlı olmamalı.
- Öncelik: küçük APK boyutu, sade ve hızlı arayüz. Gereksiz paket ekleme (şu an yalnızca `sqflite`, `path`).
- Gerçek kulüp isimleri kullanılıyor (kullanıcı kararı). Lisans riski kullanıcıya bildirilmiş durumda.

## Mimari
- `lib/core/engine.dart`: modeller (Player, Team, Fixture, Standing), fikstür (circle method), puan tablosu, değer formülü. Saf Dart.
- `lib/core/match.dart`: diziliş (6), mentalite (3), `MatchSession` dakika dakika maç motoru (yorgunluk, 5 değişiklik, gol atan seçimi). Saf Dart.
- `lib/core/game_state.dart`: oyun durumu; yönetilen lig bellekte, değişiklikler SQLite'a yazılır. `beginWeek` / `finishWeek` / `quickPlayWeek`, transfer, finans, yeni sezon.
- `lib/data/game_db.dart`: asset DB'yi yazılabilir konuma kopyalar; `Save`, `Fixtures`, `Lineup` tablolarını oluşturur. "Yeni Oyun" DB'yi asset'ten sıfırlar.
- `lib/ui/`: `screens.dart` (başlangıç, lig/takım seçimi, 5 sekme), `live_match.dart` (canlı maç).
- `tools/build_game_db.py`: `Small_Database.db` (159 bin oyuncu havuzu, repoda yok) → `assets/game.db`. Girdi: `leagues.csv`, `teams_real.csv` (güçten zayıfa sıralı), `teams_super_lig.csv` (bütçeli).

## Maç motoru sabitleri (match.dart) – değiştirirsen dengeyi yeniden doğrula
BASE 1.34, HOME 1.12, AWAY 0.90, SPREAD 5.0, FATIGUE 0.12. Hedef: ~2,7 gol/maç, ~%44 ev galibiyeti, ~%24 beraberlik.

## Durum
- Kod Claude'un bulut ortamında yazıldı; orada Flutter yoktu, bu yüzden Dart kodu **hiç derlenmedi**. İlk adım: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run` ve çıkan hataları düzeltmek.
- Yok: UEFA kupaları (şemada `Competitions` tablosu sadece tanım), sakatlık/kart, AI transferleri, baskı/tempo taktikleri, ikon, ses, UEFA'nın kalan ligleri (32 lig var).
- Canlı maçta diziliş değiştirilemez (maç öncesi); sadece mentalite + aynı mevkiden değişiklik.

## Çalışma kuralları
- Küçük, doğrulanabilir adımlarla ilerle; her adımdan sonra `flutter analyze` ve `flutter test` çalıştır.
- Veri şemasını değiştirirsen `tools/build_game_db.py` ve `README.md` da güncellenmeli; `assets/game.db`'yi betikle yeniden üret.
- Kod yorumları ve UI metinleri Türkçe.
- Her önemli değişiklikten sonra bu dosyanın "Durum" bölümünü güncelle.
