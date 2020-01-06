import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';


abstract class WidgetDeckDataSource {
  int numberOfItems();
  DeckItem itemAt(int index, BoxConstraints constraints, DeckItemType type, bool isCaching);
  void prepareCache(DeckDirection direction, int top);
  bool isEnd(int index);
}

enum DeckDirection {
  next,
  previous,
  neutralPrev,
  neutralNext
}

enum DeckItemType {
  previous, top, next
}

class DeckOffset {
  final DeckDirection direction;
  final double value;

  DeckOffset(this.direction, this.value);
}

//Deck item class
class DeckItem {
  final Widget child;
  final Key key;
  DeckItem({this.key, this.child});
}

class WidgetDeck extends StatefulWidget {
  final WidgetDeckDataSource dataSource;

  const WidgetDeck({Key key, @required this.dataSource}) : super(key: key);

  @override
  State<StatefulWidget> createState() => WidgetDeckState();
}

class WidgetDeckState extends State<WidgetDeck> with TickerProviderStateMixin {
  double _topOffset = 0;
  int _top = 0;
  bool isCaching = false;

  DeckDirection _currentDirection;
  WidgetDeckDataSource _dataSource;
  AnimationController _dragController;
  Animation _dragAnimation;

  @override
  void initState() {
    super.initState();
    this._dataSource = this.widget.dataSource;
    resetOffsets();
  }

  Widget buildSwiper({Key key, Widget child, BoxConstraints constraints}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (drag) {
          if (this._currentDirection == null) {
            if (drag.delta.dx < 0 && !this._dataSource.isEnd(this._top)) {
              this._currentDirection = DeckDirection.next;
              this._topOffset = 0;
            } else if (this._top != 0) {
              this._currentDirection = DeckDirection.previous;
              this._topOffset = -constraints.maxWidth;
            }
          }

          setState(() {
            final offset = this._topOffset + drag.delta.dx;
            if (offset <= 0 && offset >= -constraints.maxWidth) {
              this._topOffset = offset;
            } else if (offset > 0) {
              this._topOffset = 0;
            } else if (offset < -300) {
              this._topOffset = -constraints.maxWidth;
            }
          });
        },
        onHorizontalDragEnd: (dragEnd) {
          final thresholdConstant = this._currentDirection == DeckDirection.next ? 0 : constraints.maxWidth;
          final thresholdOffset = thresholdConstant - this._topOffset.abs();
          final threshold = thresholdOffset.abs() / constraints.maxWidth > 0.25;
          final neutralDirection = this._currentDirection == DeckDirection.next
              ? DeckDirection.neutralNext : DeckDirection.neutralPrev;
          final direction = threshold ? this._currentDirection : neutralDirection ;
          this._currentDirection = direction;

          initPageAnimation(
              width: constraints.maxWidth,
              leftOffset: this._topOffset,
              direction: direction
          );
          this._dragController.forward(from: 0);
        },
        child: child
    );
  }

  AnimationController initPageAnimation({
    double width,
    double leftOffset,
    DeckDirection direction,
    double velocityX = 850,
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
        curve: Curves.linearToEaseOut,
        parent: this._dragController
    ))..addListener(() {
      final result = listener(this._dragAnimation.value);
      setState(() {
        this._topOffset = result.value;
      });
    })..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final result = completion(status);
        setState(() {
          if (result != null) {
            this._top = result;
            this._dataSource.prepareCache(this._currentDirection, this._top);
          }
          resetOffsets();
        });
      }
    });

    return this._dragController;
  }

  void resetOffsets() {
    this.isCaching = this._currentDirection == DeckDirection.next ||
        this._currentDirection == DeckDirection.previous;

    this._currentDirection = null;
  }

  int getNext() {
    if (!this._dataSource.isEnd(this._top))
      return this._top + 1;

    return this._top;
  }

  int getPrevious() {
    if (this._top != 0)
      return this._top - 1;

    return this._top;
  }

  Widget buildPrevious({Key key, Widget child, BoxConstraints constraints}) {
    return Positioned(
      key: key,
      left: this._currentDirection == DeckDirection.previous
          ? this._topOffset : -constraints.maxWidth,
      child: child
    );
  }

  List<Widget> buildStackChildren(BoxConstraints constraints) {
    List<Widget> children = List();
    final deckItemNext = this._dataSource.itemAt(
        getNext(),
        constraints,
        DeckItemType.next,
        this.isCaching
    );

    children.add(
        Positioned(
          key: deckItemNext.key,
          child: deckItemNext.child,
        )
    );

    final deckItem = this._dataSource.itemAt(
        this._top,
        constraints,
        DeckItemType.top,
        this.isCaching
    );

    children.add(
      Positioned(
        key: deckItem.key,
        left: this._currentDirection == DeckDirection.next ? this._topOffset : 0,
        child: deckItem.child,
      )
    );

    final deckItemPrevious = this._dataSource.itemAt(
        getPrevious(),
        constraints,
        DeckItemType.previous,
        this.isCaching
    );

    children.add(
        Positioned(
          key: deckItemPrevious.key,
          left: this._currentDirection == DeckDirection.previous
              ? this._topOffset : -constraints.maxWidth,
          child: deckItemPrevious.child,
        )
    );
    this.isCaching = false;
    return children;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: this._dataSource.numberOfItems() != 0 ? buildSwiper(
            constraints: constraints,
            child: Stack(
              overflow: Overflow.clip,
              alignment: Alignment.center,
              children: buildStackChildren(constraints),
            )
          ) : Container()
        );
      },
    );
  }
}