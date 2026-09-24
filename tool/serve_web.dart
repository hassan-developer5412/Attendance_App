import 'dart:io';

Future<void> main() async {
  final webDir = Directory('build/web');
  if (!await webDir.exists()) {
    print('Error: build/web directory not found. Run "flutter build web" first.');
    exit(1);
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  print('Serving Flutter web app at http://localhost:${server.port}');
  print('Press Ctrl+C to stop.');

  await for (final request in server) {
    var path = request.uri.path;
    if (path == '/') path = '/index.html';

    final file = File('build/web$path');
    if (await file.exists()) {
      final ext = path.split('.').last.toLowerCase();
      final contentType = _mimeType(ext);
      request.response.headers.contentType = ContentType.parse(contentType);
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      await request.response.addStream(file.openRead());
    } else {
      // For SPA routing, serve index.html for non-file paths
      final indexFile = File('build/web/index.html');
      request.response.headers.contentType = ContentType.html;
      await request.response.addStream(indexFile.openRead());
    }
    await request.response.close();
  }
}

String _mimeType(String ext) {
  switch (ext) {
    case 'html':
      return 'text/html; charset=utf-8';
    case 'js':
      return 'application/javascript; charset=utf-8';
    case 'json':
      return 'application/json; charset=utf-8';
    case 'css':
      return 'text/css; charset=utf-8';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'svg':
      return 'image/svg+xml';
    case 'ico':
      return 'image/x-icon';
    case 'woff':
      return 'font/woff';
    case 'woff2':
      return 'font/woff2';
    case 'ttf':
      return 'font/ttf';
    case 'otf':
      return 'font/otf';
    case 'map':
      return 'application/json';
    case 'wasm':
      return 'application/wasm';
    default:
      return 'application/octet-stream';
  }
}
