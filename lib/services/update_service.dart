import '../app/app_info.dart';
import '../core/failure.dart';
import '../core/http.dart';

enum UpdateState { notConfigured, upToDate, available, error }

class UpdateCheck {
  const UpdateCheck(this.state, {this.latest, this.url, this.message});

  final UpdateState state;
  final String? latest;
  final String? url;
  final String? message;
}

/// Yapılandırılabilir güncelleme denetimi. Yalnızca kullanıcı istediğinde
/// çalışır (arka planda istek yok). Uç nokta GitHub Releases biçimindedir
/// (`tag_name`, `html_url`); boş bırakılırsa denetim kapalıdır ve uygulama
/// çalışıyormuş gibi davranmaz.
class UpdateService {
  const UpdateService();

  /// "v1.2.0" > "1.0.0" karşılaştırması. a>b ise pozitif.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[.+-]')).take(3).map((s) => int.tryParse(s) ?? 0).toList()..addAll([0, 0, 0]);
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return 0;
  }

  Future<UpdateCheck> check(String? endpoint, {String current = AppInfo.version}) async {
    final ep = endpoint?.trim() ?? '';
    if (ep.isEmpty) {
      return const UpdateCheck(UpdateState.notConfigured, message: 'Güncelleme sunucusu yapılandırılmamış.');
    }
    try {
      final json = await Http.getJson(Uri.parse(ep), source: 'Güncelleme sunucusu', timeout: const Duration(seconds: 15));
      final tag = json is Map ? (json['tag_name'] ?? json['version'])?.toString() : null;
      if (tag == null) {
        return const UpdateCheck(UpdateState.error, message: 'Sunucu yanıtında sürüm bilgisi yok.');
      }
      final url = json is Map ? (json['html_url'] ?? json['url'])?.toString() : null;
      return compareVersions(tag, current) > 0
          ? UpdateCheck(UpdateState.available, latest: tag, url: url)
          : UpdateCheck(UpdateState.upToDate, latest: tag, url: url);
    } on AppFailure catch (f) {
      if (f.kind == FailureKind.notFound) {
        return const UpdateCheck(UpdateState.error, message: 'Sunucuda yayımlanmış bir sürüm bulunamadı.');
      }
      return UpdateCheck(UpdateState.error, message: f.message);
    } catch (e) {
      return UpdateCheck(UpdateState.error, message: AppFailure.from(e).message);
    }
  }
}
