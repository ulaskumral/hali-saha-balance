# Halı Saha Kadro ve Akıllı Takım Dengeleme

Offline-first Flutter/Dart uygulaması. Riverpod + Drift/SQLite kullanır; takım araması ağır iş olarak `Isolate.run` içinde yürütülür. Sunucu, üyelik, cloud DB, LLM/API veya online rating yoktur.

## Uygulanan çekirdek kurallar

- Oyuncu statları 1-99, nullable kalecilik, primary/secondary `KL/DEF/OS/FOR`.
- DEF / OS / FOR / KL OVR formülleri doğrudan spesifikasyondaki katsayılarla türetilir.
- Maç formu: -15%, 0%, +10%; statlar 1..99 clamp edilir.
- 5v5-11v11. 7v7 dahil 5-9 full exact. 10-11 exact arama + admissible lower-bound pruning.
- Same-Team: transitive Union-Find. Separate-Team: birleşmiş gruplar üzerinde bipartite constraint graph.
- Pinned A/B, eşit takım boyutu ve duplicate kontrolü aramadan önce feasibility aşamasında ele alınır.
- Emergency GK maça özel `temporaryGoalkeeping` ile oyuncu bazında verilir. Her çözümde iki takımda da geçerli bir GK yerleşimi zorunludur.
- Attack, Defense, Build-Up, Pressing, Progression, Containment, GK Strength formülleri uygulanır.
- Loss: raw stat, matchup, role balance, strength curve, GK, overall, tactical; base + critical birleşimi spesifikasyondaki ağırlıklardır.
- Deterministik tie-break: final -> critical -> matchup -> role -> strength -> formation quality -> UUID.
- Top-3 çözüm çiftler arası diversity eşiğiyle seçilir (7v7+ için 4, 5v5/6v6 için 2).
- Maç onayı immutable JSON snapshot üretir; gelecekteki oyuncu profil güncellemeleri geçmiş maçı değiştirmez.
- Paylaşım kartı ayrı canvas üzerinde PNG olarak render edilir; native share sheet kullanılır. Sayısal skorlar varsayılan kapalıdır.
- `.takimbackup`: `manifest.json`, `database.json`, `players/`. Zip-slip ve symlink reddi, staging ve DB transaction rollback uygulanır.

## İlk kurulum

Bu ortamda Flutter SDK bulunmadığı için Android/iOS platform klasörleri ve Drift'in üretilen `app_database.g.dart` dosyası burada üretilemedi. Flutter kurulu bir makinede proje kökünde:

```bash
./tool/bootstrap.sh
```

Script eksikse Android/iOS scaffolding'i ayrı bir geçici projede üretip yalnızca platform klasörlerini kopyalar; mevcut `lib/` kaynaklarını ezmez. Ardından bağımlılıkları indirir, Drift codegen çalıştırır, `flutter analyze` ve `flutter test` çağırır.

Manuel kurulum gerekiyorsa platform scaffold’ını bu proje klasöründe üretmeyin. Ayrı bir geçici Flutter projesinde oluşturup yalnızca `android/`, `ios/` ve `.metadata` dosyasını buraya kopyalayın. Ardından:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```


## iOS 14+ ve fotoğraf izni

Bootstrap script iOS deployment target'ını 14.0'a çeker ve `NSPhotoLibraryUsageDescription` anahtarını ekler. Kamera kullanılmıyor.

## Mimari

```text
lib/
  core/
  domain/
    models.dart
    balance_engine.dart
  database/
    app_database.dart
    repositories.dart
  features/
    players/
    matches/
    team_generator/
    balance_analysis/
    backup_restore/
    settings/
```

## Algoritma notları

### Matchup loss

196 normalizasyonu, iki yönlü signed avantaj farkına uygulanır:

```text
attackDefense = abs((A.attack - B.defense) - (B.attack - A.defense)) / 196
buildPress   = abs((A.buildUp - B.pressing) - (B.buildUp - A.pressing)) / 196
progressCont = abs((A.progression - B.containment) - (B.progression - A.containment)) / 196
```

Bu tanım her bileşeni teorik olarak 0..1 aralığında tutar ve spesifikasyondaki `/196.0` ifadesiyle tutarlıdır.

### Formation quality

Spesifikasyon tie-break'te `combinedFormationQuality` adını veriyor fakat formül vermiyor. Bu repo bunu yalnızca tie-break amacıyla deterministik biçimde tanımlar:

```text
slotQuality = 0.65 * rolePreferenceFit + 0.35 * (roleOVR / 99)
formationQuality = average(slotQuality)
```

Role-balance loss içindeki `roleFitGap` ise bu karma kaliteyi değil, yalnızca rol tercih fit ortalamasını kullanır. Emergency outfield ataması Primary/Secondary dışı rol olup 0.82 fit sayılır.

### Bounded-exact lower bound

10v10/11v11 aramasında budama yalnızca ispatlanabilir alt sınır üzerinden yapılır. Kalan bileşenlerin stat katkıları için mümkün aralık genişletilir; GK'nın outfield ortalamasından çıkarılması da `[1,99]` aralığıyla konservatif biçimde hesaba katılır. Sonra:

```text
finalLoss >= (0.75 * 0.18 + 0.25) * rawStatLowerBound
          >= 0.385 * rawStatLowerBound
```

Bu sınır zayıf olabilir ama admissible'dır; optimum çözümü budamaz.

## Güncel paket tercihi

`sqlite3_flutter_libs` artık yeni sqlite3/Drift düzeninde gerekli değil. Bu proje `drift_flutter` kullanır. `pubspec.yaml` 2026-09 itibarıyla güncel ana paket sürümlerine göre yazılmıştır.

## Spesifikasyon kararları

Master prompt'ta adı verilmiş ama matematiksel formülü tamamlanmamış noktalar `docs/SPEC_DECISIONS.md` içinde açıkça listelenmiştir. Böylece davranış gizli varsayımlara değil, sürümlenebilir kurallara bağlıdır.
