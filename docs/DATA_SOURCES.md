# PARKSENSE — Veri Kaynakları ve Lisans İncelemesi

Bu belge PARKSENSE'in kullandığı ve değerlendirdiği tüm veri kaynaklarını, erişilebilirliklerini,
kullanım koşullarını ve uygulamadaki rollerini açıklar.

> **Temel ilke:** Uygulama var olmayan bir API kullanmaz, doluluk/fiyat/kapasite **uydurmaz**,
> izinsiz web kazıma yapmaz ve demo veriyi gerçek veri gibi göstermez. Her kayıt kaynağı ve
> güncelleme zamanıyla birlikte saklanır ve kullanıcıya gösterilir.

---

## 1. Kullanılan otopark veri kaynakları

| Kaynak | Kapsam | Anlık doluluk | Fiyat | Anahtar | Lisans | Uygulamadaki modül |
|---|---|---|---|---|---|---|
| **İBB Açık Veri — İSPARK API** | İstanbul (İSPARK otoparkları) | ✅ Evet (resmî) | ✅ Tarife + abonelik | Gerekmez | İBB Açık Veri Lisansı | `lib/data/providers/ispark_provider.dart` |
| **OpenStreetMap — Overpass API** | Türkiye geneli (`amenity=parking`) | ❌ Yok | ⚠️ Yalnızca `fee` / `charge` etiketi varsa | Gerekmez | ODbL 1.0 | `lib/data/providers/osm_provider.dart` |
| **Yerel yönetim kayıtları** | Kullanıcının eklediği | ❌ Yok (elle girilemez) | ✅ Kullanıcı beyanı | — | Kullanıcı verisi | `lib/data/db/app_database.dart` |

### 1.1 İSPARK (İstanbul Büyükşehir Belediyesi)

- **Uç noktalar**
  - `GET https://api.ibb.gov.tr/ispark/Park` → tüm otoparklar: `parkID, parkName, lat, lng, capacity, emptyCapacity, workHours, parkType, freeTime, district, isOpen`
  - `GET https://api.ibb.gov.tr/ispark/ParkDetay?id={parkID}` → ek olarak `address, tariff, monthlyFee, updateDate, locationName, areaPolygon`
- **Erişim:** Herkese açık, anahtarsız, JSON. İBB Açık Veri Portalı (data.ibb.gov.tr) üzerinden yayımlanır.
- **Doluluk:** `capacity` ve `emptyCapacity` alanları İSPARK'ın kendi sisteminden gelir ve gerçek zamanlıdır. Uygulama bu değeri **yalnızca kapasite > 0 ise** gösterir.
- **Zaman damgası:** Detayda kaynağın bildirdiği `updateDate` (İstanbul saati, UTC+3) gösterilir. Listede bu alan olmadığından "veri alınma zamanı" olarak etiketlenir.
- **Tarife:** `tariff` metni ("0-1 Saat : 90 TL; …") yapılandırılmış kademelere ayrıştırılır. Ayrıştırılamayan kısım **kaynaktaki özgün ifadesiyle** gösterilir, tahmin yapılmaz.
- **Geriye dönük uyumluluk:** 2020 dönemi Türkçe alan adları (`ParkID`, `ParkAdi`, `BosKapasite`, `Kapasitesi`, `AylikAbonelikUcreti`) da desteklenir.
- **İstek yönetimi:** Liste 2 dakika bellekte önbelleklenir; arama bölgesi İstanbul dışındaysa İSPARK hiç sorgulanmaz.

### 1.2 OpenStreetMap — Overpass API

- **Sorgu:** Arama merkezi etrafında `nwr["amenity"="parking"]`; `access=private|no` ve kişisel garajlar (`parking=garage_boxes|carports`) hariç; en fazla 600 sonuç.
- **Sunucular:** `overpass-api.de` (birincil), `overpass.private.coffee` (yedek). Her ikisi de OSM topluluğunca listelenen herkese açık örneklerdir.
- **Kullanım politikası:** Kimlikli `User-Agent` (`PARKSENSE/1.0 (+repo)`), sınırlı sonuç, aynı bölge için 30 dakika önbellek, otomatik/periyodik sorgu yok.
- **Eşlenen etiketler:** `name`, `parking` (tür), `capacity`, `fee`, `charge`, `opening_hours`, `operator`, `phone`, `website`, `wheelchair`, `capacity:disabled`, `capacity:charging`, `supervised`, `covered`, `lit`, `maxstay`, `maxheight`, `addr:*`, `image`.
- **Güncelleme zamanı:** Overpass yanıtındaki `osm3s.timestamp_osm_base` (OSM veritabanının anlık görüntü zamanı).
- **Güvenilirlik:** Uygulamada "Topluluk verisi" olarak etiketlenir ve kullanıcıya "eksik veya güncel olmayabilir" uyarısı gösterilir.
- **Tekrarların ayıklanması:** Bir OSM kaydı bir İSPARK kaydına 40 m'den yakınsa resmî kaynak tutulur.
- **Atıf:** Haritada ve Hakkında ekranında "© OpenStreetMap katkıda bulunanlar" gösterilir (ODbL gereği).

### 1.3 Yerel yönetim kayıtları

- Yönetim ekranından eklenen otoparklar yalnızca cihazdaki SQLite veritabanında tutulur.
- Her kayıtta **zorunlu "veri kaynağı" notu** bulunur (ör. "İşletme beyanı").
- "Yerel kayıt (doğrulanmamış)" etiketiyle gösterilir; diğer cihazlara aktarılmaz (ekranda açıkça yazar).
- **Anlık doluluk elle girilemez** — doluluk yalnızca doğrulanmış kaynaklardan gösterilir.

---

## 2. Harita, arama ve navigasyon

| Hizmet | Kullanım | Anahtar | Koşullar | Karar |
|---|---|---|---|---|
| **CARTO Voyager raster** | Varsayılan harita altlığı | Gerekmez | Ücretsiz katman; OSM + CARTO atfı zorunlu; ticari olmayan / düşük hacim kullanımı | ✅ Varsayılan |
| **OSM Vakfı döşeme sunucusu** | Alternatif altlık (Ayarlar) | Gerekmez | Tile Usage Policy: kimlikli UA, önbellek, ağır kullanım yok | ✅ Seçenek |
| **Mapbox** | Değerlendirildi | **Gerekir** | Ücretli kota, anahtar yönetimi; anahtar yoksa uygulama çalışmaz | ❌ Seçilmedi |
| **Google Maps SDK** | Değerlendirildi | **Gerekir** | Faturalandırma hesabı; Windows masaüstü SDK'sı yok | ❌ Seçilmedi |
| **MapLibre GL (vektör)** | Değerlendirildi | Sağlayıcıya göre | Flutter Windows desteği olgun değil; düşük donanımda GPU gereksinimi | ❌ Seçilmedi |
| **Nominatim** | Adres/şehir arama | Gerekmez | Saniyede ≤1 istek, otomatik tamamlama yasak, kimlikli UA | ✅ Yalnızca "Ara" ile |
| **Google Maps URL'leri** | Yol tarifi | Gerekmez | Belgelenmiş "Maps URLs" biçimi | ✅ |

**Neden flutter_map + raster döşeme?** Tek kod tabanıyla Android ve Windows'ta aynı şekilde çalışır,
API anahtarı gerektirmez (anahtar olmadığında uygulama bozulmaz), GPU gerektirmediği için düşük
donanımlı bilgisayarlarda akıcıdır ve döşemeler diske önbelleklenir.

**Yedekleme (fallback):** Harita döşemesi yüklenemezse harita üzerinde "Harita görüntüsü yüklenemedi"
uyarısı ve "Tekrar dene" düğmesi gösterilir; kullanıcı Ayarlar'dan diğer altlığa geçebilir. Otopark
listesi harita olmadan da çalışır.

**Navigasyon:** Android'de önce Google Maps uygulamasının `google.navigation:` şeması denenir;
uygulama yoksa `https://www.google.com/maps/dir/?api=1&destination=…` tarayıcıda açılır. İkisi de
açılamazsa anlaşılır bir hata mesajı gösterilir.

---

## 3. Araştırılan ancak ilk sürüme alınmayan kaynaklar

| Kaynak | Durum | Neden ilk sürümde yok |
|---|---|---|
| **İzmir Büyükşehir Açık Veri — "Otopark Doluluk ve Lokasyon Bilgileri" (API)** | Portalda mevcut, lisans CC BY 4.0 | Servis belgeleri ve anahtar gereksinimi doğrulanmadan entegre edilmedi. Mimari hazır: yeni bir `ParkingProvider` modülü eklenerek v1.1'de bağlanabilir. |
| **İzmir — İzelman otopark konum/kapasite CSV'si** | Portalda mevcut (son güncelleme 2022) | Veri güncel değil; kapasite statik. Güncellik doğrulanınca eklenebilir. |
| **İzmir — Otopark Ücretleri CSV'si** | Portalda mevcut | Otopark kimlikleri konum verisiyle eşleştirilmeden fiyat gösterilmesi yanlış eşleşme riski taşır. |
| Diğer büyükşehirler (Ankara, Bursa, Antalya, Konya…) | Genel açık veri portallarında makine tarafından okunabilir, güncel otopark doluluk API'si bulunamadı | Var olmayan API kullanılmaz. |
| Özel işletme siteleri | Kullanım izni / açık API yok | İzinsiz kazıma yapılmaz. |

---

## 4. Kapsam beyanı

PARKSENSE 1.0 **tüm Türkiye'yi eksiksiz kapsadığını iddia etmez.**

- Türkiye geneli: OSM'de işaretlenmiş otoparklar (yoğunluk il ve ilçeye göre değişir).
- İstanbul: İSPARK otoparkları için resmî anlık doluluk ve tarife.
- Diğer tüm otoparklar için ekranda **"Anlık doluluk bilgisi mevcut değil"** yazar.
- Fiyatı kaynakta olmayan otoparklarda **"Fiyat bilgisi mevcut değil"** yazar; tahmini ücret gösterilmez.

## 5. Yeni veri sağlayıcısı ekleme

```dart
class BelediyeXProvider implements ParkingProvider {
  @override DataSourceInfo get info => DataSources.belediyeX; // kaynak + lisans + güvenilirlik
  @override bool covers(SearchArea a) => belediyeXBounds.intersectsCircle(a.center, a.radiusM);
  @override Future<ProviderResult> fetch(SearchArea a) async { /* resmî API → List<Parking> */ }
}
```

`ParkingRepository.remoteProviders` listesine eklemek yeterlidir; birleştirme, tekrar ayıklama,
önbellek, çevrimdışı yedek ve arayüz otomatik çalışır.
