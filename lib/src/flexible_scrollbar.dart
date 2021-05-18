library flexible_scrollbar;

import 'package:flexible_scrollbar/src/bar_position.dart';
import 'package:flexible_scrollbar/src/nullable_edge_insets.dart';
import 'package:flexible_scrollbar/src/scrollbar_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef ScrollWidgetBuilder = Widget Function(ScrollbarInfo);

class FlexibleScrollbar extends StatefulWidget {
  final ScrollController controller;

  final Widget child;
  final ScrollWidgetBuilder? scrollThumbBuilder;
  final ScrollWidgetBuilder? scrollLineBuilder;
  final ScrollWidgetBuilder? scrollLabelBuilder;

  final bool isAlwaysVisible;
  final bool isJumpOnScrollLineTapped;
  final bool isDraggable;
  final bool autoPositionLabel;

  final double? scrollLineOffset;
  final double? thumbMainAxisMinSize;
  final double? scrollLineCrossAxisSize;
  final double scrollLabelOffset;

  final Duration? thumbFadeStartDuration;
  final Duration? thumbFadeDuration;

  final BarPosition barPosition;

  final Function(DragStartDetails details)? onDragStart;
  final Function(DragEndDetails details)? onDragEnd;
  final Function(DragUpdateDetails details)? onDragUpdate;

  FlexibleScrollbar({
    Key? key,
    required this.child,
    required this.controller,
    this.scrollThumbBuilder,
    this.scrollLineBuilder,
    this.scrollLabelBuilder,
    this.scrollLineOffset,
    this.onDragStart,
    this.onDragEnd,
    this.onDragUpdate,
    this.thumbMainAxisMinSize,
    this.thumbFadeStartDuration,
    this.thumbFadeDuration,
    this.scrollLineCrossAxisSize,
    this.barPosition = BarPosition.end,
    this.isAlwaysVisible = false,
    this.isJumpOnScrollLineTapped = true,
    this.isDraggable = true,
    this.autoPositionLabel = true,
    this.scrollLabelOffset = 4,
  }) : super(key: key);

  @override
  _FlexibleScrollbarState createState() => _FlexibleScrollbarState();
}

class _FlexibleScrollbarState extends State<FlexibleScrollbar> {
  final GlobalKey childKey = GlobalKey();
  final GlobalKey thumbKey = GlobalKey();
  final GlobalKey scrollLabelKey = GlobalKey();

  late final double scrollLineOffset;

  double barOffset = 0;
  double viewOffset = 0;
  double thumbCrossAxisSize = 0;

  double? barMaxScrollExtent;
  double? thumbMainAxisSize;
  double? childWidth;
  double? childHeight;

  int scrollThumbFadeCountDownCount = 0;
  int afterJumpScrollEndEventsCount = 0;

  bool isDragging = false;
  bool isScrollInProcess = false;
  bool isThumbNeeded = false;
  bool isJumpingTo = false;
  bool isJumpTapUp = true;
  bool isScrollable = false;
  bool isVertical = true;
  bool needsReCalculate = false;
  bool isScrollingBeforeJump = false;
  bool scrollFieldsInitialised = false;

  AxisDirection? scrollAxisDirection;

  Orientation? lastOrientation;

  Size? previousThumbSize;
  Size? scrollLabelSize = Size(0, 0);

  bool get isScrolling => isDragging || isScrollInProcess || !isJumpTapUp;

  bool get isReverse {
    if (isVertical && scrollAxisDirection == AxisDirection.up) {
      return true;
    }
    if (!isVertical && scrollAxisDirection == AxisDirection.left) {
      return true;
    }
    return false;
  }

  bool get isEnd => widget.barPosition == BarPosition.end;

  double? get mainAxisScrollAreaSize => isVertical ? childHeight : childWidth;

  double? get crossAxisScrollAreaSize => !isVertical ? childHeight : childWidth;

  double? get childWidthByKey {
    return childKey.currentContext?.size?.width;
  }

  double? get childHeightByKey {
    return childKey.currentContext?.size?.height;
  }

  double? viewMaxScrollExtent;

  double get maxExtentToAreaHeightRatio =>
      (childHeight! + viewMaxScrollExtent!) / childHeight!;

  double get maxExtentToAreaWidthRatio =>
      (childWidth! + viewMaxScrollExtent!) / childWidth!;

  ScrollbarInfo get scrollInfo {
    return ScrollbarInfo(
      isScrolling: isScrollInProcess,
      isDragging: isDragging,
      scrollDirection: isScrolling
          ? widget.controller.position.axisDirection
          : scrollAxisDirection!,
      thumbMainAxisSize: thumbMainAxisSize!,
      thumbMainAxisOffset: barOffset,
    );
  }

  NullableEdgeInsets get thumbOffset {
    return NullableEdgeInsets(
      top: isVertical && !isReverse ? barOffset : null,
      bottom: isVertical && isReverse ? barOffset : null,
      left: !isVertical && !isReverse ? barOffset : null,
      right: !isVertical && isReverse ? barOffset : null,
    );
  }

  @override
  void initState() {
    scrollLineOffset = widget.scrollLineOffset ?? 0;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final double scrollLineCrossAxisSize =
        widget.scrollLineCrossAxisSize ?? thumbCrossAxisSize;

    final double labelOffset =
        scrollLineCrossAxisSize + widget.scrollLabelOffset;

    final bool hasLabel = widget.scrollLabelBuilder != null;
    Widget? scrollLabel;
    if (hasLabel) {
      scrollLabel = Container(
        key: scrollLabelKey,
        child: scrollFieldsInitialised
            ? fadeAnimationWrapper(
                child: widget.scrollLabelBuilder!(scrollInfo),
              )
            : Container(),
      );
      if (widget.autoPositionLabel && scrollFieldsInitialised) {
        final double thumbMainAxisSizeHalf = (thumbMainAxisSize ?? 0) / 2;
        final double verticalOffset =
            thumbMainAxisSizeHalf - scrollLabelSize!.height / 2;
        final double horizontalOffset =
            thumbMainAxisSizeHalf - scrollLabelSize!.width / 2;

        final offset = NullableEdgeInsets(
          top: !isVertical && !isEnd ? labelOffset : null,
          bottom: !isVertical && isEnd ? labelOffset : null,
          left: isVertical && !isEnd ? labelOffset : null,
          right: isVertical && isEnd ? labelOffset : null,
        );

        final adjustedThumbOffset = NullableEdgeInsets(
          top: thumbOffset.top != null
              ? thumbOffset.top! + verticalOffset
              : null,
          bottom: thumbOffset.bottom != null
              ? thumbOffset.bottom! + verticalOffset
              : null,
          left: thumbOffset.left != null
              ? thumbOffset.left! + horizontalOffset
              : null,
          right: thumbOffset.right != null
              ? thumbOffset.right! + horizontalOffset
              : null,
        );

        scrollLabel = Positioned(
          top: !isVertical && !isEnd ? offset.top : adjustedThumbOffset.top,
          bottom:
              !isVertical && isEnd ? offset.bottom : adjustedThumbOffset.bottom,
          left: isVertical && !isEnd ? offset.left : adjustedThumbOffset.left,
          right: isVertical && isEnd ? offset.right : adjustedThumbOffset.right,
          child: scrollLabel,
        );
      }
    }
    return OrientationBuilder(
      builder: (_, Orientation orientation) {
        WidgetsBinding.instance!.addPostFrameCallback((_) {
          calculateScrollAreaFields(orientation);
        });

        Alignment scrollLineAlignment;
        if (widget.barPosition == BarPosition.start) {
          if (isReverse) {
            if (isVertical) {
              scrollLineAlignment = Alignment.bottomLeft;
            } else {
              scrollLineAlignment = Alignment.topRight;
            }
          } else {
            scrollLineAlignment = Alignment.topLeft;
          }
        } else {
          if (isReverse) {
            scrollLineAlignment = Alignment.bottomRight;
          } else {
            if (isVertical) {
              scrollLineAlignment = Alignment.topRight;
            } else {
              scrollLineAlignment = Alignment.bottomLeft;
            }
          }
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification is ScrollEndNotification) {
              isScrollInProcess = false;
              if (isJumpingTo) {
                if (isScrollingBeforeJump) {
                  afterJumpScrollEndEventsCount++;
                  if (afterJumpScrollEndEventsCount == 2) {
                    isJumpingTo = false;
                    afterJumpScrollEndEventsCount = 0;
                  }
                } else {
                  isJumpingTo = false;
                }
              }
              startHideThumbCountdown();
            } else if (notification is ScrollStartNotification) {
              isScrollInProcess = true;
              if (!isThumbNeeded) {
                setState(() {
                  isThumbNeeded = true;
                });
              }
            }
            if (isJumpingTo) {
              return true;
            }
            return changePosition(notification);
          },
          child: Stack(
            alignment: scrollLineAlignment,
            children: [
              Container(
                key: childKey,
                child: widget.child,
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: isVertical && !isEnd ? scrollLineOffset : 0,
                  right: isVertical && isEnd ? scrollLineOffset : 0,
                  top: !isVertical && !isEnd ? scrollLineOffset : 0,
                  bottom: !isVertical && isEnd ? scrollLineOffset : 0,
                ),
                child: Container(
                  width: isVertical ? scrollLineCrossAxisSize : null,
                  height: !isVertical ? scrollLineCrossAxisSize : null,
                  child: GestureDetector(
                    behavior:
                        widget.isDraggable && widget.isJumpOnScrollLineTapped
                            ? HitTestBehavior.opaque
                            : HitTestBehavior.translucent,
                    onVerticalDragStart:
                        isVertical && widget.isDraggable ? onDragStart : null,
                    onVerticalDragUpdate:
                        isVertical && widget.isDraggable ? onDragUpdate : null,
                    onVerticalDragEnd:
                        isVertical && widget.isDraggable ? onDragEnd : null,
                    onHorizontalDragStart:
                        !isVertical && widget.isDraggable ? onDragStart : null,
                    onHorizontalDragUpdate:
                        !isVertical && widget.isDraggable ? onDragUpdate : null,
                    onHorizontalDragEnd:
                        !isVertical && widget.isDraggable ? onDragEnd : null,
                    onTapDown: onScrollLineTapDown,
                    onTapUp: onScrollLineTapUp,
                    child: fadeAnimationWrapper(
                      child: Container(
                        height: isVertical && isScrollable ? childHeight : null,
                        width: !isVertical && isScrollable ? childWidth : null,
                        alignment: scrollLineAlignment,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: isVertical
                              ? isEnd
                                  ? Alignment.topRight
                                  : Alignment.topLeft
                              : isEnd
                                  ? Alignment.bottomLeft
                                  : Alignment.topLeft,
                          children: [
                            if (widget.scrollLineBuilder != null)
                              widget.scrollLineBuilder!(scrollInfo),
                            Positioned(
                              top: thumbOffset.top,
                              bottom: thumbOffset.bottom,
                              left: thumbOffset.left,
                              right: thumbOffset.right,
                              child: buildScrollThumb(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasLabel) scrollLabel!,
            ],
          ),
        );
      },
    );
  }

  Widget fadeAnimationWrapper({required Widget child}) {
    return AnimatedOpacity(
      duration: widget.thumbFadeDuration ?? const Duration(milliseconds: 200),
      opacity: widget.isAlwaysVisible
          ? 1.0
          : isThumbNeeded
              ? 1.0
              : 0.0,
      child: child,
    );
  }

  Widget buildScrollThumb() {
    final noThumbBuilder = widget.scrollThumbBuilder == null;
    return Container(
      key: thumbKey,
      height: isVertical && noThumbBuilder ? thumbMainAxisSize : null,
      width: !isVertical && noThumbBuilder ? thumbMainAxisSize : null,
      color: noThumbBuilder ? Colors.grey.withOpacity(0.8) : null,
      child: !scrollFieldsInitialised
          ? Container()
          : widget.scrollThumbBuilder!(scrollInfo),
    );
  }

  void calculateScrollAreaFields(Orientation newOrientation) {
    final thumbSize = thumbKey.currentContext!.size;
    final hasScrollLabel = widget.scrollLabelBuilder != null;

    Size? scrollLabelSize;

    if (hasScrollLabel) {
      scrollLabelSize = scrollLabelKey.currentContext!.size;
    }

    if (newOrientation != lastOrientation ||
        scrollAxisDirection != widget.controller.position.axisDirection ||
        (thumbSize != previousThumbSize &&
            widget.scrollLineCrossAxisSize == null) ||
        (hasScrollLabel && scrollLabelSize != this.scrollLabelSize) ||
        widget.controller.position.maxScrollExtent != viewMaxScrollExtent) {
      setState(() {
        previousThumbSize = thumbSize;
        this.scrollLabelSize = scrollLabelSize;

        thumbCrossAxisSize = isVertical ? thumbSize!.width : thumbSize!.height;

        lastOrientation = newOrientation;

        scrollAxisDirection = widget.controller.position.axisDirection;
        isVertical = scrollAxisDirection == AxisDirection.up ||
            scrollAxisDirection == AxisDirection.down;

        childWidth = childWidthByKey ?? MediaQuery.of(context).size.width;
        childHeight = childHeightByKey ?? MediaQuery.of(context).size.height;

        viewMaxScrollExtent = widget.controller.position.maxScrollExtent;

        if (viewMaxScrollExtent != 0.0) {
          isScrollable = true;
          double? thumbMinSize;
          if (widget.thumbMainAxisMinSize != null) {
            thumbMinSize = thumbMinSize;
          } else {
            thumbMinSize = mainAxisScrollAreaSize! * 0.1;
          }
          thumbMainAxisSize = mainAxisScrollAreaSize! /
              (isVertical
                  ? maxExtentToAreaHeightRatio
                  : maxExtentToAreaWidthRatio);
          if (thumbMainAxisSize! < thumbMinSize!) {
            thumbMainAxisSize = thumbMinSize;
          }
          barMaxScrollExtent = mainAxisScrollAreaSize! - thumbMainAxisSize!;
          if (!scrollFieldsInitialised) {
            isThumbNeeded = widget.isAlwaysVisible;
          }
        } else {
          isScrollable = false;
        }
        if (barOffset > 0) {
          final double scrollOffset = widget.controller.offset;
          final double mainAxisSize =
              isVertical ? childHeightByKey! : childWidthByKey!;
          barOffset = mainAxisSize /
              (viewMaxScrollExtent! + mainAxisSize) *
              scrollOffset;
        }
        if (!scrollFieldsInitialised) {
          scrollFieldsInitialised = true;
        }
      });
    }
  }

  bool changePosition(ScrollNotification notification) {
    if (isDragging) {
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      setState(() {
        final barDelta = getBarDelta(notification.scrollDelta!);
        barOffset += barDelta;

        viewOffset += notification.scrollDelta!;
        if (viewOffset < widget.controller.position.minScrollExtent) {
          viewOffset = widget.controller.position.minScrollExtent;
        }
        if (viewOffset > viewMaxScrollExtent!) {
          viewOffset = viewMaxScrollExtent!;
        }
      });
    }
    return true;
  }

  double getBarDelta(double scrollViewDelta) {
    return scrollViewDelta * barMaxScrollExtent! / viewMaxScrollExtent!;
  }

  void onDragStart(DragStartDetails details) {
    widget.onDragStart?.call(details);
  }

  void onDragUpdate(DragUpdateDetails details) {
    setState(() {
      final double mainAxisCoordinate =
          isVertical ? details.delta.dy : details.delta.dx;

      barOffset += isReverse ? -mainAxisCoordinate : mainAxisCoordinate;

      if (barOffset < 0) {
        barOffset = 0;
      }
      if (barOffset > barMaxScrollExtent!) {
        barOffset = barMaxScrollExtent!;
      }

      double viewDelta = getScrollViewDelta(mainAxisCoordinate);

      viewOffset = widget.controller.position.pixels +
          (isReverse ? -viewDelta : viewDelta);
      if (viewOffset < widget.controller.position.minScrollExtent) {
        viewOffset = widget.controller.position.minScrollExtent;
      }
      if (viewOffset > viewMaxScrollExtent!) {
        viewOffset = viewMaxScrollExtent!;
      }
      widget.controller.jumpTo(viewOffset);
    });
    if (widget.onDragUpdate != null) {
      widget.onDragUpdate!(details);
    }
  }

  void onDragEnd(DragEndDetails details) {
    setState(() {
      isJumpTapUp = true;
      if (isDragging) {
        isDragging = false;
      }
    });
    startHideThumbCountdown();
    widget.onDragEnd?.call(details);
  }

  void startHideThumbCountdown() {
    if (widget.isAlwaysVisible) {
      return;
    }
    final currentCountdownNumber = ++scrollThumbFadeCountDownCount;
    Future.delayed(
        widget.thumbFadeStartDuration ?? const Duration(milliseconds: 1000),
        () {
      if (currentCountdownNumber == scrollThumbFadeCountDownCount &&
          !isScrolling &&
          mounted) {
        setState(() {
          isThumbNeeded = false;
          scrollThumbFadeCountDownCount = 0;
        });
      }
    });
  }

  double getScrollViewDelta(double barDelta) {
    return barDelta * viewMaxScrollExtent! / barMaxScrollExtent!;
  }

  void onScrollLineTapDown(TapDownDetails details) {
    isScrollingBeforeJump = isScrolling;
    if (widget.isJumpOnScrollLineTapped) {
      setState(() {
        isThumbNeeded = true;
        isJumpTapUp = false;
        if (widget.isDraggable) {
          isDragging = true;
        }
        final mainAxisCoordinate =
            isVertical ? details.localPosition.dy : details.localPosition.dx;

        if (isReverse &&
            mainAxisCoordinate < mainAxisScrollAreaSize! - barOffset &&
            mainAxisCoordinate >
                mainAxisScrollAreaSize! - (barOffset + thumbMainAxisSize!)) {
          return;
        } else if (mainAxisCoordinate > barOffset &&
            mainAxisCoordinate < barOffset + thumbMainAxisSize!) {
          return;
        }

        double offset;
        if (isReverse) {
          offset = mainAxisScrollAreaSize! -
              mainAxisCoordinate -
              (thumbMainAxisSize! / 2);
        } else {
          offset = mainAxisCoordinate - (thumbMainAxisSize! / 2);
        }
        if (offset.isNegative) {
          offset = 0;
        } else if (offset + thumbMainAxisSize! > mainAxisScrollAreaSize!) {
          offset = mainAxisScrollAreaSize! - thumbMainAxisSize!;
        }

        barOffset = offset;

        final maxOffset = mainAxisScrollAreaSize! - thumbMainAxisSize!;
        final offsetToSizeRatio = maxOffset / viewMaxScrollExtent!;

        final scrollPosition = offset / offsetToSizeRatio;
        isJumpingTo = true;
        widget.controller.jumpTo(scrollPosition);
      });
    }
  }

  void onScrollLineTapUp(TapUpDetails details) {
    startHideThumbCountdown();
    isJumpTapUp = true;
    if (isDragging) {
      setState(() {
        isDragging = false;
      });
    }
  }
}
