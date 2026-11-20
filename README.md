# Futbol Menajer (Android)

Flutter ile yazılmış, SQLite tabanlı futbol menajerlik oyunu.

## Çalıştırma
```
flutter create --platforms=android .   # android/ klasörünü üretir (lib/ ve pubspec.yaml korunur; git diff ile kontrol edin)
flutter pub get
flutter run
flutter build apk --release --split-per-abi
```

## Veri
`assets/game.db` oyunun veritabanıdır (32 lig, 479 takım, ~12 bin oyuncu). Üretmek için:
```
python tools/build_game_db.py --src Small_Database.db --out assets/game.db
```
- Takım/oyuncu isimlerini değiştirmek: `game.db` içindeki `Teams.name`, `Players.name` sütunlarını düzenleyin (veya `tools/leagues.csv` ve `tools/teams_super_lig.csv` ile yeniden üretin).
- Yeni lig: `tools/leagues.csv`'ye satır ekleyin.
- Uygulama DB'yi ilk açılışta asset'ten kopyalar; yeni `game.db` için uygulama verisini silin/yeniden kurun ("Yeni Oyun" da DB'yi asset'ten sıfırlar).

## Durum
Bkz. proje özeti. UEFA kupaları henüz simüle edilmiyor (veride `Competitions` tablosu var).
