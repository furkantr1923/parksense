# PARKSENSE — Kurulum

## 🪟 Windows 10 / 11

İndirilen `PARKSENSE-Windows-1.0.0.zip` içinde iki dosya vardır:

| Dosya | Ne zaman kullanılır |
|---|---|
| `PARKSENSE-Setup.exe` | Kalıcı kurulum: kurulum sihirbazı, klasör seçimi, Başlat menüsü ve masaüstü kısayolu, Denetim Masası'ndan kaldırma |
| `PARKSENSE-Portable.exe` | Kurulum yapmadan çalıştırma (USB bellek vb.). Tek dosyadır; açılışta uygulamayı geçici klasöre çıkarır, kapanınca temizler |

### Setup ile kurulum
1. `PARKSENSE-Setup.exe` dosyasını çalıştırın.
2. Lisansı kabul edin → kurulum klasörünü seçin → isterseniz "Masaüstü simgesi oluştur"u işaretleyin.
3. **Kur**'a basın. Yönetici izni gerekmez (yalnızca kendi kullanıcınız için kurulur; isterseniz tüm kullanıcılar için kurulumu seçebilirsiniz).
4. Kaldırmak için: *Ayarlar → Uygulamalar → PARKSENSE → Kaldır* veya Başlat menüsündeki **PARKSENSE kaldır**.

### Windows SmartScreen uyarısı
Dosyalar kod imzalama sertifikasıyla imzalanmadığı için ilk çalıştırmada "Windows bilgisayarınızı korudu"
uyarısı görülebilir: **Ek bilgi → Yine de çalıştır**. Dosyaların bütünlüğünü `SHA256SUMS-windows.txt`
içindeki özetlerle doğrulayabilirsiniz:

```powershell
Get-FileHash .\PARKSENSE-Setup.exe -Algorithm SHA256
```

### Sistem gereksinimleri
- Windows 10 (64 bit) veya Windows 11
- 4 GB RAM önerilir (uygulama tipik olarak ~150–250 MB kullanır), GPU gerekmez
- Harita ve otopark verisi için internet bağlantısı (çevrimdışıyken önbellekteki otoparklar gösterilir)

### Veriler nerede saklanır?
`%APPDATA%\com.furkan\parksense\parksense.db` — favoriler, geçmiş, puanlar, yerel otoparklar ve ayarlar.
Kaldırma işlemi bu dosyayı silmez (yeniden kurulumda verileriniz korunur); tamamen silmek için klasörü elle silin.

---

## 🤖 Android

1. `PARKSENSE.apk` dosyasını telefona indirin.
2. Açın; "Bilinmeyen kaynaklardan yükleme" izni istenirse tarayıcınıza / dosya yöneticinize izin verin.
3. **Yükle**'ye basın.

- **Gereksinim:** Android 7.0 (API 24) ve üzeri.
- **İzinler:** İnternet; konum (yalnızca "Konumumu kullan"a dokunduğunuzda istenir, arka planda kullanılmaz).
- Konum izni vermezseniz şehir/adres arayarak tüm özellikleri kullanabilirsiniz.

> **İmza notu:** GitHub Secrets'ta kalıcı imza anahtarı tanımlanmamışsa CI her derleme için geçici bir
> anahtar üretir. Bu durumda yeni bir sürümü kurmadan önce eski sürümü kaldırmanız gerekir. Kalıcı anahtar
> için aşağıdaki "Sürüm imzalama" bölümüne bakın.

---

## 🛠️ Kaynaktan derleme

### Gereksinimler
| Araç | Sürüm |
|---|---|
| Flutter | 3.50.1 (stable) |
| Dart | Flutter ile gelir (≥ 3.9) |
| Android | Android SDK 36, JDK 17 |
| Windows | Visual Studio 2022 — "C++ ile masaüstü geliştirme" iş yükü |
| Setup | Inno Setup 6 |

```bash
git clone https://github.com/furkantr1923/parksense.git
cd parksense
flutter pub get
flutter analyze
flutter test

flutter run -d windows            # Windows'ta çalıştır
flutter build windows --release   # build\windows\x64\runner\Release\PARKSENSE.exe
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
```

Setup dosyası:
```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\parksense.iss   # dist\PARKSENSE-Setup.exe
```

SQLite yerel kütüphanesi `sqlite3` paketinin derleme kancalarıyla (build hooks) otomatik paketlenir;
ayrıca DLL kopyalamanız gerekmez.

### Otomatik derleme (GitHub Actions)
`main` dalına her gönderimde `.github/workflows/build.yml`:
1. Analiz + 69 test
2. Windows derlemesi → gerçek uygulamayla öz-sınama + ekran görüntüleri → Setup.exe → sessiz kurulum/kaldırma testi → Portable.exe → çalıştırma testi
3. Android APK (imzalı) → emülatörde kurulum, izin akışı, açılış, gerçek veriyle ekranlar
4. Çıktılar `builds` dalına; `v*` etiketlerinde GitHub Release

---

## 🔐 Sürüm imzalama (Android)

İmza anahtarı ve parolası **kaynak koduna konmaz** (`.gitignore`: `*.jks`, `android/key.properties`).

1. Anahtarı bir kez üretin (güvenli bir yerde saklayın, kaybederseniz güncelleme yayımlayamazsınız):
   ```bash
   keytool -genkeypair -v -keystore parksense-release.jks -alias parksense \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. GitHub deposunda *Settings → Secrets and variables → Actions*:
   - `ANDROID_KEYSTORE_BASE64` → `base64 -w0 parksense-release.jks` çıktısı
   - `ANDROID_KEYSTORE_PASSWORD` → anahtar parolası
3. Yerel derleme için `android/key.properties`:
   ```properties
   storeFile=/tam/yol/parksense-release.jks
   storePassword=…
   keyAlias=parksense
   keyPassword=…
   ```

---

## 🔄 Güncelleme altyapısı

- Sürüm numarası tek yerde: `pubspec.yaml` (`version`) ve `lib/app/app_info.dart`.
- *Ayarlar → Güncelleme* ekranı, yapılandırılabilir bir uç noktayı **yalnızca kullanıcı istediğinde** denetler.
  Varsayılan uç nokta GitHub Releases API'sidir (`/repos/furkantr1923/parksense/releases/latest`).
- Uç nokta boş bırakılırsa denetim kapalıdır ve uygulama "Güncelleme sunucusu yapılandırılmamış" der —
  çalışıyormuş gibi davranmaz.
- Yeni sürüm yayımlamak: `pubspec.yaml` ve `app_info.dart` sürümünü artırın → `git tag v1.1.0 && git push --tags`.
