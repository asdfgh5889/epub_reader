import 'dart:convert';
import 'package:epub/epub.dart';
import 'package:epub_reader_example/content_server.dart';
import 'package:epub_reader_example/widget_deck.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:io' as io;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> implements WidgetDeckDataSource {
  EpubBook epubBook;
  Map<DeckItemType, DeckItem> epubPages = Map();
  Map<Key, InAppWebViewController> controllers = Map();
  Map<DeckItemType, Key> pageKeys = Map();

  @override
  void initState() {
    super.initState();
    this.pageKeys[DeckItemType.next] = UniqueKey();
    this.pageKeys[DeckItemType.top] = UniqueKey();
    this.pageKeys[DeckItemType.previous] = UniqueKey();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Demo"),
        actions: <Widget>[
          FlatButton(
            onPressed: () async {
              final path = await FilePicker.getFilePath(type: FileType.CUSTOM, fileExtension: 'epub');
              if (path != null) {
                final file = io.File(path);
                List<int> bytes = await file.readAsBytes();
                this.epubBook = await EpubReader.readBook(bytes);
                startWebServerFor(this.epubBook);
                setState(() {});
              }
            },
            child: Text("Open", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Container(
        alignment: Alignment.center,
        child: WidgetDeck(
          key: Key("epub_deck"),
          dataSource: this
        ),
      )
    );
  }

  Future<void> loadChapterContent(int index, InAppWebViewController controller) async {
    if (controller != null) {
      await controller.loadUrl(url: getContentUriFor(index))
          .catchError((error) {
            print(error);
          });
    }
    return;
  }

  String getContentUriFor(int index) {
    if (index < 0 || index >= numberOfItems()) {
      return 'about:blank';
    }

    final spineItem = this.epubBook.Schema.Package.Spine.Items[index];
    final manifestItems = this.epubBook.Schema.Package.Manifest.Items;
    final item = manifestItems.firstWhere((e) {
      return e.Id == spineItem.IdRef;
    });
    return Uri(host: 'localhost', path: item.Href, port: 8000, scheme: 'http').toString();
  }

  @override
  DeckItem itemAt(int index, BoxConstraints constraints, DeckItemType type, bool isCaching) {
    if (this.epubPages[type] == null) {
      print("WebView Creating");
      final key = UniqueKey();
      this.epubPages[type] = DeckItem(
        key: key,
        child: Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: Colors.black)
          ),
          child: InAppWebView(
            initialUrl: getContentUriFor(index),
            initialOptions: InAppWebViewWidgetOptions(
              crossPlatform: InAppWebViewOptions(
                javaScriptEnabled: true,
                debuggingEnabled: true
              )
            ),
            onLoadStart: this.onLoadStart,
            onLoadStop: this.onLoadStop,
            gestureRecognizers: Set()
              ..add(Factory<PlatformViewVerticalGestureRecognizer>(() => PlatformViewVerticalGestureRecognizer()))
              ..add(Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer())),
            onWebViewCreated: (InAppWebViewController controller) {
              this.controllers[key] = controller;
              print("WebView Controller Created");
            },
          ),
        ),
      );
    } else if (isCaching && (type == DeckItemType.next || type == DeckItemType.previous)) {
      loadChapterContent(index, this.controllers[this.epubPages[type].key]);
    }

    return this.epubPages[type];
  }

  Future<void> onLoadStart(InAppWebViewController controller, String url) async {
    return;
  }

  Future<void> onLoadStop(InAppWebViewController controller, String url) async {
    await controller.injectCSSCode(
        source: 'body {background-color: white !important; padding: 10px !important;} img { max-width: 100% !important; height: auto !important}'
    );
    return;
  }

  @override
  int numberOfItems() {
    return this.epubBook == null ? 0 : this.epubBook.Schema.Package.Spine.Items.length;
  }

  @override
  void prepareCache(DeckDirection direction, int top) {
    if (direction == DeckDirection.next) {
      final prev = this.epubPages[DeckItemType.previous];
      this.epubPages[DeckItemType.previous] =
      this.epubPages[DeckItemType.top];
      this.epubPages[DeckItemType.top] = this.epubPages[DeckItemType.next];
      this.epubPages[DeckItemType.next] = prev;
    } else if (direction == DeckDirection.previous) {
      final next = this.epubPages[DeckItemType.next];
      this.epubPages[DeckItemType.next] = this.epubPages[DeckItemType.top];
      this.epubPages[DeckItemType.top] =
      this.epubPages[DeckItemType.previous];
      this.epubPages[DeckItemType.previous] = next;
    }
  }
}

class PlatformViewVerticalGestureRecognizer
    extends VerticalDragGestureRecognizer {
  PlatformViewVerticalGestureRecognizer({PointerDeviceKind kind})
      : super(kind: kind);

  Offset _dragDistance = Offset.zero;

  @override
  void addPointer(PointerEvent event) {
    startTrackingPointer(event.pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    _dragDistance = _dragDistance + event.delta;
    if (event is PointerMoveEvent) {
      final double dy = _dragDistance.dy.abs();
      final double dx = _dragDistance.dx.abs();

      if (dy > dx && dy > kTouchSlop) {
        // vertical drag - accept
        resolve(GestureDisposition.accepted);
        _dragDistance = Offset.zero;
      } else if (dx > kTouchSlop && dx > dy) {
        // horizontal drag - stop tracking
        stopTrackingPointer(event.pointer);
        _dragDistance = Offset.zero;
      }
    }
  }

  @override
  String get debugDescription => 'horizontal drag (platform view)';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}