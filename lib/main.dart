import 'package:flutter/material.dart';
import 'dart:math' as math;

void main() => runApp(MyApp());

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

abstract class WidgetDeckDataSource {
  int numberOfItems();
  Widget itemAt(int index);
}

enum DeckDirection {
  next,
  previous,
  neutralPrev,
  neutralNext
}

class DeckOffset {
  final DeckDirection direction;
  final double value;

  DeckOffset(this.direction, this.value);
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with TickerProviderStateMixin implements WidgetDeckDataSource {
  double _topOffset = 0;
  double _width = 300;
  double _previousOffset = 0;
  int _top = 0;

  DeckDirection _currentDirection;
  WidgetDeckDataSource _dataSource;
  AnimationController _dragController;
  Animation _dragAnimation;
  List<Color> _colors = List();

  @override
  void initState() {
    super.initState();
    _dataSource = this;

    _colors.add(Colors.amber);
    for (int i = 0; i < this._dataSource.numberOfItems() - 1; i++) {
      _colors.add(Color((math.Random().nextDouble() * 0xFFFFFF).toInt() << 0).withOpacity(1.0));
    }

    resetOffsets();
  }

  Widget buildSwiper({Key key, Widget child}) {
    return Positioned(
        key: key,
        left: this._topOffset,
        child: GestureDetector(
          onHorizontalDragUpdate: (drag) {
            setState(() {
              switch (this._currentDirection) {
                case DeckDirection.next:
                  final offset = this._topOffset + drag.delta.dx;
                  if (offset <= 0 && offset >= -this._width) {
                    this._topOffset = offset;
                  } else if (offset > 0) {
                    this._topOffset = 0;
                  } else if (offset < -300) {
                    this._topOffset = -this._width;
                  }
                  break;
                case DeckDirection.previous:
                  final offset = this._previousOffset + drag.delta.dx;
                  if (offset <= 0 && offset >= -this._width) {
                    this._previousOffset = offset;
                  } else if (offset > 0) {
                    this._previousOffset = 0;
                  } else if (offset < -300) {
                    this._previousOffset = -this._width;
                  }
                  break;
                default:
                  if (drag.delta.dx < 0 && this._top != this._dataSource.numberOfItems() - 1) {
                    this._currentDirection = DeckDirection.next;
                  } else if (this._top != 0){
                    this._currentDirection = DeckDirection.previous;
                  }
              }
            });
          },
          onHorizontalDragEnd: (dragEnd) {
            if (this._topOffset < 0) {
              initPageAnimation(
                width: this._width,
                leftOffset: this._topOffset,
                direction: this._topOffset.abs() / this._width > 0.25
                      ? DeckDirection.next : DeckDirection.neutralNext
              );
            } else {
              initPageAnimation(
                width: this._width,
                leftOffset: this._previousOffset,
                direction: (this._width - this._previousOffset.abs()) / this._width > 0.25
                    ? DeckDirection.previous : DeckDirection.neutralPrev
              );
            }

            this._currentDirection = null;
            this._dragController.forward(from: 0);
          },
          child: child
        )
    );
  }

  AnimationController initPageAnimation({
    double width,
    double leftOffset,
    DeckDirection direction,
    double velocityX = 450,
  }) {
    double distance = 0;
    switch (direction) {
      case DeckDirection.next:
      case DeckDirection.neutralPrev:
        distance = width - leftOffset.abs();
        break;
      case DeckDirection.previous:
      case DeckDirection.neutralNext:
        distance = leftOffset;
        break;
    }

    return initBaseAnimation(
      duration: Duration(milliseconds: (distance/velocityX * 1000).abs().round()),
      listener: (value) {
        double offset = 0;

        switch (direction) {
          case DeckDirection.next:
          case DeckDirection.neutralPrev:
            offset = leftOffset - (width + leftOffset) * value;
            break;
          case DeckDirection.previous:
          case DeckDirection.neutralNext:
            offset = leftOffset * (1 - value);
            break;
        }

        return DeckOffset(direction, offset);
      },
      completion: (status) {
        if (direction == DeckDirection.previous) {
          return getPrevious();
        } else if (direction == DeckDirection.next) {
          return getNext();
        }

        return null;
      }
    );
  }

  AnimationController initBaseAnimation({
    Duration duration,
    DeckOffset Function(double value) listener,
    int Function(AnimationStatus) completion
  }) {
    if(this._dragController != null) {
      this._dragController.stop();
      this._dragController.dispose();
    }

    this._dragController = AnimationController(
        vsync: this,
        duration: duration
    );

    this._dragAnimation = Tween<double>(
        begin: 0,
        end: 1
    ).animate(CurvedAnimation(
        curve: Curves.easeOutExpo,
        parent: this._dragController
    ))..addListener(() {
      final result = listener(this._dragAnimation.value);

      setState(() {
        switch (result.direction) {
          case DeckDirection.next:
          case DeckDirection.neutralNext:
            this._topOffset = result.value;
            break;
          case DeckDirection.previous:
          case DeckDirection.neutralPrev:
            this._previousOffset = result.value;
            break;
        }
      });
    })..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final result = completion(status);
        if (result != null) {
          setState(() {
            this._top = result;
            resetOffsets();
          });
        }
      }
    });

    return this._dragController;
  }

  void resetOffsets() {
    this._currentDirection = null;
    this._topOffset = 0;
    this._previousOffset = -this._width;
  }

  int getNext() {
    if (this._top != this._dataSource.numberOfItems() - 1)
      return this._top += 1;

    return this._top;
  }

  int getPrevious() {
    if (this._top != 0)
      return this._top -= 1;

    return this._top;
  }

  Widget buildPrevious({Widget child}) {
    return Positioned(
      left: this._previousOffset,
      child: child
    );
  }

  List<Widget> buildStackChildren() {
    List<Widget> children = List();
    final last = this._dataSource.numberOfItems() - 1;
    if (this._top < last) {
      children.add(this._dataSource.itemAt(this._top + 1));
    }

    children.add(
      buildSwiper(child: this._dataSource.itemAt(this._top))
    );

    if (this._top != 0) {
      children.add(
        buildPrevious(child: this._dataSource.itemAt(this._top - 1))
      );
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Demo"),
      ),
      body: Container(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              height: 400,
              width: this._width,
              color: Colors.black12,
              child: Stack(
                overflow: Overflow.clip,
                children: buildStackChildren(),
              ),
            ),
            SizedBox(height: 30,),
            RaisedButton(
              onPressed: () {
                setState(() {
                  this._top = 0;
                  resetOffsets();
                });
              },
              child: Text("Reset", style: TextStyle(color: Colors.white),),
              color: Colors.blue,
            )
          ],
        ),
      )
    );
  }

  @override
  Widget itemAt(int index) {
    return Container(
      height: 400,
      width: 300,
      color: this._colors[index],
      alignment: Alignment.center,
      child: Text(index.toString(), style: TextStyle(color: Colors.white, fontSize: 30)),
    );
  }

  @override
  int numberOfItems() {
    return 6;
  }
}

