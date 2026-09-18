# Spesifikasyonda Açık Formülü Verilmeyen Noktalar İçin Deterministik Kararlar

Ana katsayılar ve hard constraint kuralları değiştirilmemiştir. Aşağıdaki maddeler, master prompt'ta isim verilmiş fakat matematiksel tanımı tamamlanmamış alanları kodlanabilir hale getirir.

## 1. Outfield rol slotları

Her takımda tam 1 GK vardır. Kalan slotlar:

| Takım | DEF | OS | FOR |
|---|---:|---:|---:|
| 5 | 2 | 1 | 1 |
| 6 | 2 | 2 | 1 |
| 7 | 2 | 2 | 2 |
| 8 | 3 | 2 | 2 |
| 9 | 3 | 3 | 2 |
| 10 | 3 | 3 | 3 |
| 11 | 4 | 3 | 3 |

Rol ataması bu slotlar üzerinde exact dinamik programlama ile en iyi yerleşimi seçer.

## 2. Role fit ve formation quality

- Primary: 1.00
- Secondary: 0.95
- Emergency outfield: 0.82
- Temporary GK: 0.82

`roleFitGap`, iki takımın yalnızca ortalama role-fit farkıdır. Tie-break'te kullanılan `formationQuality` ayrıca oyuncunun atandığı roldeki OVR'ını içerir:

```text
slotQuality = 0.65 * roleFit + 0.35 * (assignedRoleOVR / 99)
formationQuality = mean(slotQuality)
```

Bu ek kalite sadece tie-break'te kullanılır; ana loss katsayılarını değiştirmez.

## 3. Matchup loss içindeki /196 signed normalizasyonu

Her eşleşmede iki yönlü avantaj farkı alınır:

```text
AD = abs((A.attack - B.defense) - (B.attack - A.defense)) / 196
BP = abs((A.buildUp - B.pressing) - (B.buildUp - A.pressing)) / 196
PC = abs((A.progression - B.containment) - (B.progression - A.containment)) / 196
matchup = 0.50*AD + 0.30*BP + 0.20*PC
```

Bu yorum `/196.0` şartının teorik aralığıyla doğrudan uyumludur.

## 4. goalkeeperLoss / overallLoss / tacticalProfileLoss normalizasyonu

Master prompt bu üç bileşenin adını verip ayrı normalizasyon formülü vermediği için aynı `normalizedGap` fonksiyonu kullanılır. Tactical profile, altı taktik metriğin normalized gap RMS'idir.

## 5. strengthCurveLoss

Her oyuncunun `effectiveOverall` değeri, çözümde atandığı roldeki form uygulanmış OVR'dır. Takımlar kendi içinde azalan sırada dizilir. Aynı rank'teki iki değer için `normalizedGap` uygulanır ve percentile ağırlıklarıyla ağırlıklı ortalama alınır.

## 6. Emergency GK form etkisi

`temporaryGoalkeeping` maç gününe ait bir stat kabul edilir ve diğer statlarla aynı form modifier + clamp işleminden geçer.

## 7. Diversity

Simetrik fark Team-A oyuncu kümeleri üzerinden hesaplanır. Eşit takım boyutunda bu, takım değiştiren oyuncu sayısını doğru verir. Üç çözüm de birbirleriyle eşik kadar farklı olmak zorundadır.
