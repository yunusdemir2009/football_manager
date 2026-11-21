# Futbol Menajer – Claude Code proje notları

Android için Flutter (Dart) ile yazılan futbol menajerlik oyunu. Dil: Türkçe (UI metinleri, commit mesajları, açıklamalar).

## Hedef ve kararlar
- Avrupa ulusal ligleri + UEFA kupaları. Oyuncu bir lig/takım seçer, hafta hafta oynar.
- Veri: `assets/game.db` (SQLite). Takım/oyuncu isimleri sadece bu veritabanından değiştirilir; kod isme bağlı olmamalı.
- Öncelik: küçük APK boyutu, sade ve hızlı arayüz. Gereksiz paket ekleme (şu an yalnızca `sqflite`, `path`).
- Gerçek kulüp isimleri kullanılıyor (kullanıcı kararı). Lisans riski kullanıcıya bildirilmiş durumda.

## Mimari
- `lib/core/engine.dart`: modeller (Player, Team, Fixture, Standing), fikstür (circle method), puan tablosu, değer formülü. Saf Dart.
- `lib/core/match.dart`: diziliş (6), mentalite (3), savunma anlayışı/baskı (3), `MatchSession` dakika dakika maç motoru: şut → gol/kurtarış/auta, sarı/kırmızı kart, sakatlık (zorunlu değişiklik), yorgunluk, 5 değişiklik, istatistikler (şut, isabet, topa sahip olma, kart). Saf Dart.
- `lib/core/game_state.dart`: oyun durumu; yönetilen lig bellekte, değişiklikler SQLite'a yazılır. `beginWeek` / `finishWeek` / `quickPlayWeek`, transfer, finans, yeni sezon.
- `lib/data/game_db.dart`: asset DB'yi yazılabilir konuma kopyalar; `Save`, `Fixtures`, `Lineup` (formation, mentality, press, xi), `PlayerStatus` (sakatlık/ceza/sarı kart) tablolarını oluşturur. "Yeni Oyun" DB'yi asset'ten sıfırlar.
- `lib/ui/`: `screens.dart` (başlangıç, lig/takım seçimi, 5 sekme: Maç/haberler/yaklaşan maçlar, Tablo/form, Taktik, Transfer, Finans), `live_match.dart` (canlı maç: skor tablosu, istatistik çubukları, olay akışı, hız, taktik), `widgets.dart` (takım rozeti, form noktaları, StatBar).
- `tools/build_game_db.py`: `Small_Database.db` (159 bin oyuncu havuzu, repoda yok) → `assets/game.db`. Girdi: `leagues.csv`, `teams_real.csv` (güçten zayıfa sıralı), `teams_super_lig.csv` (bütçeli).

## Maç motoru sabitleri (match.dart) – değiştirirsen dengeyi yeniden doğrula
BASE 1.34, HOME 1.12, AWAY 0.90, SPREAD 5.0, FATIGUE 0.12; olay sabitleri: kConversion 0.11 (şut/dk = (1−exp(−λ))/0.11, gol olasılığı korunur), sarı 0.022/dk, kırmızı 0.0002/dk, sakatlık 0.0006/dk, eksik oyuncu −1.2 CA. Hedef (Python eşdeğeriyle doğrulandı): ~2,7 gol, ~25 şut, ~4 sarı, ~0,17 kırmızı, ~0,1 sakatlık / maç; ~%45 ev galibiyeti, ~%23 beraberlik.

## Durum
- Kullanıcı kodu derleyip çalıştırdı; oyun oynanabiliyor ("çok düz ve tekdüze" geri bildirimi alındı).
- Bu aşamada eklenenler (Faz 1 – maç deneyimi + görünüm): şut/kurtarış/auta anlatımı, kartlar ve cezalar (5 sarı = 1 maç), sakatlıklar (hafta sayılı, kalıcı), baskı taktiği, istatistik çubukları, hız ayarı, haber kutusu, form noktaları, takım rozetleri. **Bu faz derlenmedi/çalıştırılmadı** (yalnızca Python eşdeğeriyle ve parantez dengesiyle kontrol edildi): önce `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`.
- Yol haritası (kullanıcı hepsini istedi): Faz 2 Kariyer ve hedefler (yönetim hedefleri, memnuniyet, görevden alınma, teklifler); Faz 3 Kadro gelişimi (antrenman, form/moral, sözleşmeler, AI transferleri, gençlik); Faz 4 UEFA kupaları (CL/EL/ECL, kalifikasyon); ayrıca canlı maçta diziliş değişikliği, ikon/ses.
- Yok: yukarıdaki fazlar, UEFA'nın kalan ligleri (32 lig var), kalıcı Android kimliği (`com.example.football_manager`).

## Çalışma kuralları
- Küçük, doğrulanabilir adımlarla ilerle; her adımdan sonra `flutter analyze` ve `flutter test` çalıştır.
- Veri şemasını değiştirirsen `tools/build_game_db.py` ve `README.md` da güncellenmeli; `assets/game.db`'yi betikle yeniden üret.
- Kod yorumları ve UI metinleri Türkçe.
- Her önemli değişiklikten sonra bu dosyanın "Durum" bölümünü güncelle.
