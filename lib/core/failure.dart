import 'dart:async';
import 'dart:io';

enum FailureKind { offline, timeout, server, invalidResponse, permission, notFound, unknown }

/// Kullanıcıya gösterilebilir, türü belli hata.
class AppFailure implements Exception {
  const AppFailure(this.kind, {this.source, this.detail});

  final FailureKind kind;
  final String? source;
  final String? detail;

  factory AppFailure.from(Object e, {String? source}) {
    if (e is AppFailure) return e;
    if (e is TimeoutException) return AppFailure(FailureKind.timeout, source: source);
    if (e is SocketException || e is HandshakeException || e is HttpException) {
      return AppFailure(FailureKind.offline, source: source, detail: e.toString());
    }
    if (e is FormatException) return AppFailure(FailureKind.invalidResponse, source: source, detail: e.message);
    return AppFailure(FailureKind.unknown, source: source, detail: e.toString());
  }

  String get message => switch (kind) {
    FailureKind.offline => 'İnternet bağlantısı yok veya sunucuya ulaşılamıyor.',
    FailureKind.timeout => 'Sunucu zamanında yanıt vermedi.',
    FailureKind.server => 'Veri sağlayıcısı şu an hizmet veremiyor.',
    FailureKind.invalidResponse => 'Veri sağlayıcısından beklenmeyen yanıt alındı.',
    FailureKind.permission => 'Gerekli izin verilmedi.',
    FailureKind.notFound => 'Sonuç bulunamadı.',
    FailureKind.unknown => 'Beklenmeyen bir hata oluştu.',
  };

  @override
  String toString() => 'AppFailure($kind, $source, $detail)';
}
