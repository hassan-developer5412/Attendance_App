/// Web implementation of CSV export.
///
/// Downloads the CSV via a `dart:html` anchor click. Never touches `dart:io`,
/// so it is safe to compile for browsers.
import 'dart:async';

import 'dart:html' as html;

/// Saves [content] as a CSV file named [fileName] by triggering a browser
/// download. Returns `null` (no local path on Web).
Future<String?> saveCsvFile({
  required String fileName,
  required String content,
}) {
  final blob = html.Blob([content], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrl(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  final body = html.document.body;
  if (body == null) {
    html.Url.revokeObjectUrl(url);
    throw StateError('CSV export failed: document.body is not available.');
  }

  body.append(anchor);
  anchor.click();
  anchor.remove();

  // Revoke the blob URL once the browser has started the download. Revoking
  // immediately after `click()` can cancel an in-flight download.
  Timer(const Duration(milliseconds: 100), () => html.Url.revokeObjectUrl(url));

  return Future.value(null);
}