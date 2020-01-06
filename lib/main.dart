import 'dart:async';
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

class EpubPageStyle {
  int padding;
  Color backgroundColor;
  double fontScale;
  int width;

  EpubPageStyle({
    this.padding = 40,
    this.fontScale = 1,
    this.backgroundColor = Colors.white,
    this.width = 0
  });

  @override
  String toString() {
    String bodyStyle = '';

    getBodyStyle().forEach((k, v) {
      bodyStyle += '$k: $v; ';
    });

    final colorString = this.backgroundColor.value.toRadixString(16);
    final alpha = colorString.substring(0, 2);
    final color = colorString.substring(2);

    return """
      html, body {
        height: 100% !important;
        width: 100% !important;
        box-sizing: border-box !important;
        padding: 0 !important;
        margin: 0 !important;
        overflow: visible !important;
      }
      
      html {
        background-color: '#$color$alpha !important';
      }
      
      body {$bodyStyle;}
      
      img { 
        max-width: 100% !important; 
        height: auto !important
      }
      
      body::after {
          content: "";
          display: block;
          position: absolute;
          width: 100%;
          height: 1px;
      }
     """;
  }

  String initialJavaScript() {
    return """
    function initColumns() {
//      console.log("Init Columns");
      var screenWidth = document.body.offsetWidth;
      document.body.style.columnWidth = (screenWidth - ${this.padding * 2} ) + "px";
    }
        
    function toSubPage(page) {
      var screenWidth = document.body.offsetWidth;
      document.body.setAttribute('style', document.body.attributes.style.textContent + ' margin-left: -' + (screenWidth * page) + 'px !important');
      console.log(document.body.attributes.style.textContent);
//      window.scrollBy(screenWidth * page, 0);
//      console.log(window.location.href + " W: " + document.body.scrollWidth +" P: " + page + " Offset: " + screenWidth * page);
    }
    
    function getNumColumns() {
      var screenWidth = document.body.offsetWidth;
      var scrollWidth = document.body.scrollWidth + $padding;
      var result = Math.floor(scrollWidth / screenWidth);
//      console.log("SRL: " + scrollWidth + " SCR: " + screenWidth + " C: " + result);
      return result;
    }
    """;
  }

  Future<int> getNumberOfColumns(InAppWebViewController controller) async {
    return (await controller.evaluateJavascript(source: "${initialJavaScript()} getNumColumns()")) ?? 1;
  }

  Map<String, String> getBodyStyle() {
    final Map<String, String> style = Map();
    final colorString = this.backgroundColor.value.toRadixString(16);
    final alpha = colorString.substring(0, 2);
    final color = colorString.substring(2);

    style['background-color'] = '#$color$alpha !important';
    style['padding'] = '${this.padding}px !important';
    style['font-size'] = '${this.fontScale * 100}% !important';
    style['column-gap'] = '${this.padding * 2}px !important';

    return style;
  }

  String toJavaScript() {
    String bodyStyle = '';

    getBodyStyle().forEach((k, v) {
      bodyStyle += '$k: $v;';
    });

    return """
    document.body.setAttribute("style", "$bodyStyle");
    """;
  }
}

class Settings extends StatefulWidget {
  final EpubPageStyle pageStyle;
  final Function(EpubPageStyle pageStyle) onChange;

  const Settings({Key key, this.pageStyle, this.onChange}) : super(key: key);

  @override
  State<StatefulWidget> createState() => SettingsState();
}

class SettingsState extends State<Settings> {
  EpubPageStyle pageStyle;

  @override
  void initState() {
    super.initState();
    this.pageStyle = this.widget.pageStyle;
  }


  Widget buildColorButton({@required Color color}) {
    return SizedBox(
      width: 30,
      height: 30,
      child: FlatButton(
        onPressed: () {
          this.pageStyle.backgroundColor = color;
          this.widget.onChange(this.pageStyle);
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.black)
        ),
        color: color,
        child: Container(
          height: 20,
          width: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        children: <Widget>[
          Slider(
            label: 'Font size',
            value: this.pageStyle.fontScale,
            min: 0.1,
            max: 3,
            onChanged: (double value) {
              setState(() {
                this.pageStyle.fontScale = value;
              });

              this.widget.onChange(this.pageStyle);
            },
          ),
          SizedBox(height: 20,),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              buildColorButton(color: Colors.amber),
              buildColorButton(color: Colors.black),
              buildColorButton(color: Colors.white),
              buildColorButton(color: Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }
}

class _MyHomePageState extends State<MyHomePage> implements WidgetDeckDataSource {
  EpubBook epubBook;
  Map<DeckItemType, DeckItem> epubPages = Map();
  Map<Key, InAppWebViewController> controllers = Map();
  Map<DeckItemType, Key> pageKeys = Map();
  EpubPageStyle pageStyle;
  int currentSpineIndex = 0;
  int currentSubPageIndex = 0;
  Map<String, int> subPages = Map();
  int deckKey = 0;
  final _blank = Uri.parse('about:blank');

  @override
  void initState() {
    super.initState();
    this.pageKeys[DeckItemType.next] = UniqueKey();
    this.pageKeys[DeckItemType.top] = UniqueKey();
    this.pageKeys[DeckItemType.previous] = UniqueKey();
  }

  @override
  Widget build(BuildContext context) {
    this.pageStyle = EpubPageStyle(width: MediaQuery.of(context).size.width.floor());
    return Scaffold(
      appBar: AppBar(
        title: Text("Demo"),
        actions: <Widget>[
          FlatButton(
            onPressed: () {
              this.controllers[this.pageKeys[DeckItemType.top]]
                  .evaluateJavascript(source: """
                    document.body.setAttribute('style', 'column-width: 330px; margin-left: -0px !important');
                  """);
            },
            child: Text("Test", style: TextStyle(color: Colors.white)),
          ),
          FlatButton(
            onPressed: () {
              this.currentSpineIndex = 0;
              this.currentSubPageIndex = 0;
              this.epubBook = null;
              this.subPages.clear();
              this.epubPages.clear();
              this.controllers.clear();
              this.pageKeys.clear();
              this.pageKeys[DeckItemType.next] = UniqueKey();
              this.pageKeys[DeckItemType.top] = UniqueKey();
              this.pageKeys[DeckItemType.previous] = UniqueKey();
              this.deckKey += 1;
              setState(() {}
              );
            },
            child: Text("Reset", style: TextStyle(color: Colors.white)),
          ),
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
          PopupMenuButton(
            child: Icon(Icons.more_vert),
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<int>(
                  value: 0,
                  enabled: false,
                  child: Settings(pageStyle: this.pageStyle, onChange: (s) {
                    applyPageStyle(s, this.controllers);
                  }),
                ),
                PopupMenuItem<int>(
                  value: 1,
                  child: Text("Apply")
                )
              ];
            },
            onSelected: (value) {
              if (value == 1) {
                this.applyPageStyle(this.pageStyle, this.controllers);
              }
            },
          )
        ],
      ),
      body: Container(
        alignment: Alignment.center,
        child: WidgetDeck(
          key: Key("epub_deck_${this.deckKey}"),
          dataSource: this
        ),
      )
    );
  }

  void applyPageStyle(EpubPageStyle style, Map<Key, InAppWebViewController> controllers) {
    this.pageStyle = style;
    controllers.forEach((k, c) {
      c.evaluateJavascript(source: style.toJavaScript());
    });
  }

  Uri getContentUriFor(int index, {int subPage = 0}) {
    if (index < 0 || index >= numberOfItems()) {
      return this._blank;
    }

    final spineItem = this.epubBook.Schema.Package.Spine.Items[index];
    final manifestItems = this.epubBook.Schema.Package.Manifest.Items;
    final item = manifestItems.firstWhere((e) {
      return e.Id == spineItem.IdRef;
    });

    String path = item.Href;

    return Uri(scheme: 'http', host: 'localhost',port: 8000, path: path, query: 'p=$subPage');
  }

  @override
  DeckItem itemAt(int index, BoxConstraints constraints, DeckItemType type, bool isCaching) {
    if (this.epubPages[type] == null) {
      print("WebView Creating");
      final key = this.pageKeys[type];
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
            initialUrl: "about:blank",
            initialOptions: InAppWebViewWidgetOptions(
              crossPlatform: InAppWebViewOptions(
                javaScriptEnabled: true,
                debuggingEnabled: true,
                disableHorizontalScroll: false,
                disableVerticalScroll: false
              )
            ),
            onLoadStart: this.onLoadStart,
            onLoadStop: (c, u) {
              DeckItemType type;

              this.pageKeys.forEach((t, v) {
                if (v == key)
                  type = t;
              });

              onLoadStop(
                controller: c,
                type: type,
                pageStyle: this.pageStyle,
                currentIndex: this.currentSpineIndex,
                subPage: this.currentSubPageIndex,
                loadedUri: Uri.parse(u)
              );
            },
            onConsoleMessage: (controller, message) {
              print("Console: ${message.message}");
            },
            gestureRecognizers: Set()
              ..add(Factory<PlatformViewVerticalGestureRecognizer>(() => PlatformViewVerticalGestureRecognizer()))
              ..add(Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer())),
            onWebViewCreated: (InAppWebViewController controller) {
              this.controllers[key] = controller;
              if (this.controllers.length == 3) {
                loadChapterContent(
                    currentIndex: this.currentSpineIndex,
                    controller: this.controllers[this.pageKeys[DeckItemType.top]],
                    type: DeckItemType.top,
                    pageStyle: this.pageStyle,
                    subPage: this.currentSubPageIndex
                );
              }
              print("WebView Controller Created");
            },
          ),
        ),
      );
    } else if (isCaching && type != DeckItemType.top) {
      loadChapterContent(
          currentIndex: this.currentSpineIndex,
          controller: this.controllers[this.pageKeys[type]],
          type: type,
          pageStyle: this.pageStyle,
          subPage: this.currentSubPageIndex
      );
    }

    return this.epubPages[type];
  }

  Future<void> onLoadStart(InAppWebViewController controller, String url) async {
    await controller.injectCSSCode(
        source: this.pageStyle.toString()
    );
    return;
  }

  Future<void> loadChapterContent({
    @required int currentIndex,
    @required InAppWebViewController controller,
    @required DeckItemType type,
    @required EpubPageStyle pageStyle,
    @required subPage
  }) async {
    if (controller != null) {
      final uri = getContentUriFor(currentIndex);
      final count = this.subPages[uri.path];

      if (count == null && type != DeckItemType.top) {
        await controller.loadUrl(url: this._blank.toString());
        return;
      }

      switch (type) {
        case DeckItemType.next:
          if (count <= subPage + 1) {
            await controller.loadUrl(url: getContentUriFor(currentIndex + 1).toString());
          } else {
            await controller.loadUrl(url: getContentUriFor(currentIndex).toString());
          }
          break;
        case DeckItemType.top:
          await controller.loadUrl(url: getContentUriFor(currentIndex).toString());
          break;
        case DeckItemType.previous:
          if (subPage - 1 < 0) {
            await controller.loadUrl(url: getContentUriFor(currentIndex - 1).toString());
          } else {
            await controller.loadUrl(url: getContentUriFor(currentIndex).toString());
          }
          break;
      }
    }
    return;
  }


  Future<void> onLoadStop({
    @required int currentIndex,
    @required InAppWebViewController controller,
    @required DeckItemType type,
    @required EpubPageStyle pageStyle,
    @required int subPage,
    @required Uri loadedUri
  }) async {
    if (loadedUri == this._blank)
      return;

    final uri = getContentUriFor(currentIndex);

    await controller.evaluateJavascript(
        source: '${pageStyle.initialJavaScript()} initColumns();');

    if (this.subPages[loadedUri.path] == null) {
      this.subPages[loadedUri.path] = await pageStyle.getNumberOfColumns(controller);
    }

    final count = this.subPages[uri.path];

    switch (type) {
      case DeckItemType.next:
        if (count <= subPage + 1) {
          await controller.evaluateJavascript(
              source: '${pageStyle.initialJavaScript()} toSubPage(0)');
        } else {
          await controller.evaluateJavascript(
              source: '${pageStyle.initialJavaScript()} toSubPage(${subPage + 1})');
        }

        break;
      case DeckItemType.top:
        controller.evaluateJavascript(
            source: '${pageStyle.initialJavaScript()} toSubPage($subPage)');

        loadChapterContent(
            currentIndex: currentIndex,
            controller: this.controllers[this.pageKeys[DeckItemType.next]],
            type: DeckItemType.next,
            pageStyle: pageStyle,
            subPage: subPage
        );
        loadChapterContent(
            currentIndex: currentIndex,
            controller: this.controllers[this.pageKeys[DeckItemType.previous]],
            type: DeckItemType.previous,
            pageStyle: pageStyle,
            subPage: subPage
        );

        break;
      case DeckItemType.previous:
        if (subPage - 1 < 0) {
          await controller.evaluateJavascript(
              source: '${pageStyle.initialJavaScript()} toSubPage(${count - 1})');
        } else {
          await controller.evaluateJavascript(
              source: '${pageStyle.initialJavaScript()} toSubPage(${subPage - 1})');
        }

        break;
    }
    return;
  }

  @override
  int numberOfItems() {
    return this.epubBook == null ? 0 : this.epubBook.Schema.Package.Spine.Items.length;
  }

  @override
  void prepareCache(DeckDirection direction, int top) {
    if (direction == DeckDirection.next) {
      final uri = getContentUriFor(this.currentSpineIndex);
      if (this.subPages[uri.path] != null) {
        if (this.currentSubPageIndex + 1 < this.subPages[uri.path]) {
          this.currentSubPageIndex += 1;
        } else {
          this.currentSpineIndex += 1;
          this.currentSubPageIndex = 0;
        }
      }

      final prev = this.epubPages[DeckItemType.previous];
      this.epubPages[DeckItemType.previous] = this.epubPages[DeckItemType.top];
      this.epubPages[DeckItemType.top] = this.epubPages[DeckItemType.next];
      this.epubPages[DeckItemType.next] = prev;

      this.pageKeys[DeckItemType.top] = this.epubPages[DeckItemType.top].key;
      this.pageKeys[DeckItemType.next] = this.epubPages[DeckItemType.next].key;
      this.pageKeys[DeckItemType.previous] = this.epubPages[DeckItemType.previous].key;
    } else if (direction == DeckDirection.previous) {
      final uri = getContentUriFor(this.currentSpineIndex);
      if (this.subPages[uri.path] != null) {
        if (this.currentSubPageIndex - 1 < 0) {
          this.currentSpineIndex -= 1;
          this.currentSubPageIndex = this.subPages[uri.path] - 1;
        } else {
          this.currentSubPageIndex -= 1;
        }
      }

      final next = this.epubPages[DeckItemType.next];
      this.epubPages[DeckItemType.next] = this.epubPages[DeckItemType.top];
      this.epubPages[DeckItemType.top] = this.epubPages[DeckItemType.previous];
      this.epubPages[DeckItemType.previous] = next;

      this.pageKeys[DeckItemType.top] = this.epubPages[DeckItemType.top].key;
      this.pageKeys[DeckItemType.next] = this.epubPages[DeckItemType.next].key;
      this.pageKeys[DeckItemType.previous] = this.epubPages[DeckItemType.previous].key;
    }
  }

  @override
   bool isEnd(int index) {
    final uri = getContentUriFor(this.currentSpineIndex);
    if (index != 0 && this.subPages[uri.path] == null) {
      return true;
    }

    return this.numberOfItems() - 1 == this.currentSpineIndex
        && this.subPages[uri.path] == this.currentSubPageIndex;
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