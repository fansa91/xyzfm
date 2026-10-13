/// API 返回的图片多为 http 链接，https 页面 / App 内统一转成 https，
/// 避免 Web 端 Mixed Content 被拦截。
String httpsUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http://')) {
    return 'https://${url.substring(7)}';
  }
  return url;
}

/// 网易云图片裁剪参数：空 URL 或已带参数时原样返回，避免拼出坏链接
String thumb(String url, int size) {
  if (url.isEmpty || url.contains('?')) return url;
  return '$url?param=${size}y$size';
}

String formatPlayCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
  return '$count';
}

String formatDuration(int ms) {
  if (ms <= 0) return '--:--';
  final totalSec = ms ~/ 1000;
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatDate(int msEpoch) {
  if (msEpoch <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(msEpoch);
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}

int intOf(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
