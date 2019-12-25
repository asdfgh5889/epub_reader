import 'dart:async';
import 'dart:io';
import 'package:epub/epub.dart';
import 'package:http_server/http_server.dart';

bool serverIsRunning = false;
EpubBook _openedBook;

Future startWebServerFor(EpubBook book) async {
  _openedBook = book;

  if (!serverIsRunning) {
    runZoned(() {
      HttpServer.bind(InternetAddress.loopbackIPv4, 8000).then((server) {
        serverIsRunning = true;
        print('Server running at: ${server.address.address}');
        print('Server running at host: ${server.address}');
        server.transform(HttpBodyHandler()).listen((
            HttpRequestBody body) async {
          print('Request URI: ${body.request.uri.path}');
          final result = _openedBook != null ? getContentFor(body.request, _openedBook) : null;
          if (result != null) {
            body.request.response.statusCode = 200;
            body.request.response.headers.set("Content-Type", "${result.ContentMimeType}; charset=utf-8");
            if (result is EpubByteContentFile) {
              body.request.response.add(result.Content);
            } else if (result is EpubTextContentFile) {
              body.request.response.write(result.Content);
            } else {
              body.request.response.write("Content is not text nor byte");
            }
            body.request.response.close();
          } else {
            print('Not found');
            body.request.response.statusCode = 404;
            body.request.response.write('Not found');
            body.request.response.close();
          }
        });
      });
    }, onError: (e, stackTrace) => print('Oh noes! $e $stackTrace'));
  }

  return;
}

EpubContentFile getContentFor(HttpRequest request, EpubBook book) {
  final path = request.uri.path.substring(1);
  return book.Content.AllFiles[path];
}