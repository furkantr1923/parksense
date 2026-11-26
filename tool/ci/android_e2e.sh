#!/usr/bin/env bash
# Android emülatöründe: kurulum, konum izni akışı (ret + kabul), açılış,
# bellek ölçümü ve gerçek veriyle tüm ekranların görüntüleri.
# Kullanım: android_e2e.sh <release.apk> <selftest.apk> <çıktı klasörü>
set -u
APK="$1"; CAP_APK="$2"; OUT="$3"; PKG=com.furkan.parksense
mkdir -p "$OUT"
REPORT="$OUT/android_e2e.txt"
log(){ echo "$*" | tee -a "$REPORT"; }

adb wait-for-device
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

log "== 1) Sürüm APK kurulumu"
if adb install -r "$APK" >> "$REPORT" 2>&1; then log "OK   APK kuruldu"; else log "FAIL APK kurulamadı"; fi
adb shell dumpsys package $PKG | grep -E "versionName|versionCode" | head -3 | tee -a "$REPORT"

log "== 2) Soğuk açılış (izin istenmeden açılmalı)"
START=$(date +%s%3N)
adb shell am start -W -n $PKG/.MainActivity | grep -E "TotalTime|WaitTime" | tee -a "$REPORT"
sleep 8
adb exec-out screencap -p > "$OUT/a01_acilis.png"
if adb shell pidof $PKG > /dev/null; then log "OK   uygulama açıldı"; else log "FAIL uygulama kapandı"; fi
# Açılışta izin penceresi ÇIKMAMALI (izin yalnızca konum özelliği kullanılınca istenir).
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
if adb shell cat /sdcard/ui.xml 2>/dev/null | grep -qiE "permissioncontroller|Allow .*location|konumuna eri"; then
  log "FAIL açılışta izin penceresi çıktı"
else
  log "OK   açılışta izin istenmedi"
fi

log "== 3) 'Konumumu kullan' → izin penceresi → REDDET → manuel arama"
tapText(){
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  B=$(adb shell cat /sdcard/ui.xml 2>/dev/null | tr '>' '\n' | grep -iE "(text|content-desc)=\"$1\"" | grep -o 'bounds="[^"]*"' | head -1 | grep -o '[0-9]\+' | tr '\n' ' ')
  if [ -n "$B" ]; then set -- $B; adb shell input tap $(( ($1+$3)/2 )) $(( ($2+$4)/2 )); return 0; fi
  return 1
}
if tapText "Konumumu kullan"; then log "OK   'Konumumu kullan' dokunuldu"; else log "UYARI düğme bulunamadı"; fi
sleep 3
adb exec-out screencap -p > "$OUT/a02_izin_istegi.png"
if tapText "Don.t allow" || tapText "İzin verme"; then log "OK   izin reddedildi"; else adb shell input keyevent KEYCODE_BACK; log "OK   izin reddedildi (geri)"; fi
sleep 3
adb exec-out screencap -p > "$OUT/a03_izin_reddedildi.png"
if adb shell pidof $PKG > /dev/null; then log "OK   izin reddedilince uygulama çalışmaya devam ediyor"; else log "FAIL izin reddedilince kapandı"; fi
if tapText "İstanbul"; then log "OK   konumsuz şehir seçimi (İstanbul)"; fi
sleep 15
adb exec-out screencap -p > "$OUT/a04_sehir_secimi_sonuc.png"
adb shell am force-stop $PKG
adb shell pm clear $PKG >/dev/null 2>&1

log "== 4) İzin verilmiş + GPS (Taksim) ile açılış"
adb emu geo fix 28.9850 41.0369 || true
sleep 2
adb emu geo fix 28.9850 41.0369 || true
adb shell pm grant $PKG android.permission.ACCESS_FINE_LOCATION
adb shell pm grant $PKG android.permission.ACCESS_COARSE_LOCATION
adb shell am start -W -n $PKG/.MainActivity | grep -E "TotalTime" | tee -a "$REPORT"
sleep 25
adb exec-out screencap -p > "$OUT/a05_gps_yakindakiler.png"
if adb shell pidof $PKG > /dev/null; then log "OK   GPS ile açılış: uygulama çalışıyor"; else log "FAIL GPS açılışında kapandı"; fi
adb shell dumpsys meminfo $PKG | grep -E "TOTAL PSS|TOTAL RSS|TOTAL:" | head -3 | sed 's/^/BELLEK /' | tee -a "$REPORT"
log "== 5) Yol tarifi bağlantısı (Google Maps yoksa tarayıcı)"
adb shell am start -a android.intent.action.VIEW -d "https://www.google.com/maps/dir/?api=1\&destination=41.0369,28.9850\&travelmode=driving" >> "$REPORT" 2>&1 && log "OK   evrensel Maps bağlantısı sistemce açılabiliyor"
sleep 3
adb shell am force-stop $PKG
adb logcat -d -s AndroidRuntime:E | tail -20 >> "$REPORT"
adb uninstall $PKG >/dev/null 2>&1 && log "OK   kaldırma"

log "== 6) Öz-sınama APK'sı: tüm ekranlar gerçek veriyle"
adb install -r "$CAP_APK" >> "$REPORT" 2>&1
adb logcat -c
adb shell am start -n $PKG/.MainActivity >/dev/null
seen=""
end=$(( $(date +%s) + 480 ))
while [ "$(date +%s)" -lt "$end" ]; do
  lines=$(adb logcat -d -s flutter:I | grep -o "PARKSENSE_CAPTURE step=[0-9A-Za-z_]*\|PARKSENSE_CAPTURE done" || true)
  for step in $(echo "$lines" | grep -o "step=[0-9A-Za-z_]*" | cut -d= -f2); do
    case " $seen " in *" $step "*) ;; *)
      sleep 0.6
      adb exec-out screencap -p > "$OUT/$step.png"
      seen="$seen $step"; log "EKRAN $step";;
    esac
  done
  if echo "$lines" | grep -q "PARKSENSE_CAPTURE done"; then break; fi
  sleep 0.7
done
adb logcat -d -s flutter:I | grep "PARKSENSE_SELFTEST" | sed 's/.*PARKSENSE_SELFTEST //' > "$OUT/android_selftest.txt"
cat "$OUT/android_selftest.txt" >> "$REPORT"
if adb shell pidof $PKG > /dev/null; then log "OK   öz-sınama sonunda uygulama çalışıyor"; else log "FAIL öz-sınama sırasında kapandı"; fi
adb logcat -d -s AndroidRuntime:E | tail -30 >> "$REPORT"
exit 0
