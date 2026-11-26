# PARKSENSE 1.0.0 — Test Raporu

**Tarih:** 26 Kasım 2026 · **Flutter:** 3.50.1 · **Dart:** 3.x · **Ortam:** Linux (x86_64) geliştirme sunucusu

Bu rapor yalnızca **gerçekten çalıştırılan** testleri sonuçlarıyla listeler. Çalıştırılamayan testler
nedenleriyle birlikte ayrıca belirtilmiştir.

---

## 1. Özet

| Alan | Durum |
|---|---|
| Statik analiz (`flutter analyze`) | ✅ **0 sorun** |
| Otomatik testler (`flutter test`) | ✅ **69 / 69 geçti** |
| Android sürüm APK derlemesi | ✅ Derlendi, imzalandı, manifest doğrulandı |
| Arayüz görüntü testleri (`tool/screenshots`) | ✅ 10 ekran Android + Windows yerleşiminde çizildi |
| Windows EXE / Setup / Portable derlemesi | ⏳ **Yapılamadı** — bkz. §5 |
| Android emülatör / gerçek cihaz testi | ⏳ **Yapılamadı** — bkz. §5 |
| Canlı veri kaynaklarına bağlantı | ⏳ Geliştirme sunucusundan erişim yok — bkz. §5 |

---

## 2. Birim testleri (`test/domain_test.dart`, `test/database_test.dart`, `test/data_test.dart`)

| Konu | Test edilenler | Sonuç |
|---|---|---|
| **Fiyat hesaplama** | İSPARK tarife metni → saatlik/günlük/aylık/kademeler; ayrıştırılamayan kısmın özgün metin olarak korunması; OSM `fee`/`charge` (TRY/hour, TL/saat, day); veri yoksa `null` (uydurma yok); ₺ biçimi (₺45, ₺42,50, ₺1.250); TR/EN sayı ayrıştırma | ✅ |
| **Filtreleme** | Tür, mesafe, fiyat (bilinmeyen fiyat varsayılan hariç / isteğe bağlı dahil), yalnızca ücretsiz, doluluk (anlık / boş yer / <%70), metin; **filtrelerin birlikte çalışması**; sonuç yoksa boş liste; fiyat ve boş yere göre sıralama | ✅ |
| **Mesafe hesaplama** | Haversine (Taksim→Kadıköy ≈ 6,3 km), sıfır/simetri, Türkiye ve İstanbul sınır kutuları | ✅ |
| **Veritabanı işlemleri** | 8 tablolu şema, `user_version`, yabancı anahtarlar açık; gidiş-dönüş okuma/yazma; CHECK kısıtları ve işlemin bütün olarak geri alınması; ayarlar; dosya veritabanında kalıcılık | ✅ |
| **Favori işlemleri** | Ekle / çoğaltmama / kaldır; **kaynak verisi yeniden yazılınca favori, ziyaret ve puanın korunması** (veri kaybı önlemi); önbellek temizliğinin favoriye dokunmaması | ✅ |
| **Geçmiş / puan** | Son görüntülenenler üst sınırı (30), ziyaret ekle/sil/temizle, puan 1–5 / 0 kaldırır / aralık dışı reddedilir | ✅ |
| **Yerel yönetim** | Ekle, düzenle (fiyat + kapasite güncelle), kaynak notu, fiyatın temizlenmesi, bağlı kayıt sayımı + kaskad silme, uzak kayıtların değiştirilememesi | ✅ |
| **Veri doğrulama** | Ad, enlem/boylam, Türkiye sınırı, fiyat, kapasite, telefon, URL, zorunlu kaynak notu | ✅ |
| **Kümeleme** | Hiçbir otoparkın kaybolmaması, yakın yakınlaştırmada kümelemenin kapanması | ✅ |

## 3. Entegrasyon testleri (`test/data_test.dart`)

Gerçek servislerin **yanıt biçimini** taklit eden test verileriyle (ağsız):

| Konu | Sonuç |
|---|---|
| İSPARK liste ayrıştırma (güncel + 2020 Türkçe alan adları), geçersiz/koordinatsız/yurt dışı kayıtların ayıklanması, kapasite 0 iken doluluk **uydurulmaması** | ✅ |
| İSPARK detay: tarife, abonelik, adres, kaynağın güncelleme zamanı (TSİ → UTC) | ✅ |
| Overpass ayrıştırma: tür, kapasite, fiyat, saatler, erişilebilirlik, olanaklar, adres, OSM veri zamanı; adsız kayıt işaretleme; sorgu (özel otoparklar hariç, sonuç sınırı) | ✅ |
| Nominatim ayrıştırma | ✅ |
| Depo: kaynakların birleştirilmesi + İSPARK/OSM tekrarının ayıklanması + SQLite önbelleğe yazma | ✅ |
| Bir kaynak çökünce diğerinin gösterilmesi ve uyarı | ✅ |
| **İnternet yokken** önbellekten gösterim ve **doluluğun gösterilmemesi** | ✅ |
| İstanbul dışında İSPARK'ın hiç sorgulanmaması (gereksiz istek yok) | ✅ |
| Detay zenginleştirmesinin kalıcılığı; sonraki liste güncellemesinin tarifeyi silmemesi | ✅ |
| **Navigasyon bağlantıları:** Google Maps evrensel URL'si ve `google.navigation:` şeması; telefon/web bağlantıları | ✅ |
| Güncelleme denetimi: sürüm karşılaştırma; uç nokta yoksa "yapılandırılmamış" | ✅ |

## 4. Arayüz testleri (`test/widget_test.dart`)

| Senaryo | Sonuç |
|---|---|
| Android açılış: logo, arama, konum kartı; **konum izni reddedilince açıklayıcı mesaj** ve şehir seçimiyle devam | ✅ |
| Harita ↔ liste geçişi; filtre sonucu yoksa "Filtrelere uyan otopark yok" + temizleme | ✅ |
| Detay: eksik alanlar "Bilgi mevcut değil", doluluk yoksa "Anlık doluluk bilgisi mevcut değil", fiyat yoksa açıklama, kaynak güvenilirliği; favoriye ekleme; son görüntülenene kayıt | ✅ |
| Windows yerleşimi: yan menü, Yönetim ekranındaki "diğer cihazlara aktarılmaz" uyarısı, Hakkında'da geliştirici **Furkan** | ✅ |

Arayüz testleri sırasında **3 gerçek taşma (overflow) hatası** bulundu ve düzeltildi (logo yazısı, doluluk satırı,
yatay kart başlığı, harita atfı dar ekranda).

## 5. Gerçekleştirilemeyen testler ve nedenleri

| Test | Neden | Çözüm |
|---|---|---|
| **Windows derlemesi, açılış süresi, bellek, Setup kurulum/kaldırma, Portable çalıştırma** | Flutter Windows uygulamaları yalnızca Windows'ta (MSVC) derlenebilir; geliştirme ortamı Linux. Otomatik Windows derlemesi için GitHub deposu (`furkantr1923/parksense`) henüz oluşturulmadı. | `.github/workflows/build.yml` hazır: depo oluşturulup kod gönderildiğinde Windows sunucusunda derleme, öz-sınama, ekran görüntüsü, Setup sessiz kurulum → kısayol → çalıştırma → kaldırma ve Portable çalıştırma testleri **otomatik** yapılır. |
| **Android emülatör / gerçek cihaz** (kurulum, konum izni, açılış süresi, bellek) | Geliştirme sunucusunda donanım sanallaştırması (KVM) yok. | Aynı iş akışındaki `emulator` işi (Android 14, Pixel 6) `tool/ci/android_e2e.sh` ile kurulum, izin reddetme/verme, GPS, bellek ve tüm ekranları test eder. |
| **Canlı veri kaynakları** (İSPARK, Overpass, Nominatim, harita döşemeleri) | Geliştirme sunucusunun ağ izin listesi bu alan adlarına çıkışa izin vermiyor. Ayrıştırıcılar belgelenmiş yanıt biçimine göre test edildi. | Uygulamanın öz-sınama modu (`lib/capture/capture_runner.dart`) CI'da her kaynağa **gerçek istek** atar, ham alan adlarını ve sonuçları rapora yazar. |
| **İnternet yokken gerçek cihazda** | Cihaz yok | Depo + birim/entegrasyon testleriyle doğrulandı; CI öz-sınaması kapalı bağlantı noktasıyla gerçek bağlantı hatası üretip doğrular. |

## 6. Android paket doğrulaması

```
package: com.furkan.parksense   versionName 1.0.0   versionCode 1
targetSdk 36   application-label: PARKSENSE
izinler: INTERNET, ACCESS_COARSE_LOCATION, ACCESS_FINE_LOCATION
yerel kütüphaneler: arm64-v8a, armeabi-v7a, x86_64 (libflutter, libapp, libsqlite3)
imza: sürüm anahtarı (CN=Furkan, O=PARKSENSE) — anahtar kaynak koduna dahil değil
```

## 7. Performans tasarımı (ölçüm CI'da yapılacak)

- Harita işaretleri yalnızca görünen alan için ve yakınlaştırmaya göre kümelenerek çizilir.
- İSPARK listesi 2 dk, OSM sorguları 30 dk, adres aramaları 6 saat önbelleklenir.
- Arka planda hiçbir istek / zamanlayıcı yok; güncelleme denetimi yalnızca kullanıcı isteğiyle.
- Görüntü önbelleği 64 MB ile sınırlı; liste 30'arlı sayfalanır.
- Windows CI adımı: pencere açılış süresi (ms) ve 10 sn sonra bellek (MB) ölçer.

## 8. Testleri çalıştırma

```bash
flutter analyze
flutter test                                       # 69 test
flutter test tool/screenshots --update-goldens     # arayüz önizleme görüntüleri
```
