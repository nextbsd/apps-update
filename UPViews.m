/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "UPViews.h"

#include <math.h>

/* The mockup's colours. */
static NSColor *
UPColor (int rgb)
{
  return [NSColor colorWithCalibratedRed:((rgb >> 16) & 0xff) / 255.0
                                   green:((rgb >> 8) & 0xff) / 255.0
                                    blue:(rgb & 0xff) / 255.0
                                   alpha:1.0];
}

NSColor *
UPSecondaryColor (void)
{
  return UPColor (0xb8b8c0);
}

/* How tall `text` is wrapped at word breaks to `width`: GNUstep's
 * -cellSizeForBounds: measures one line. */
static CGFloat
UPTextHeight (NSString *text, NSFont *font, CGFloat width)
{
  NSDictionary *attrs = [NSDictionary dictionaryWithObject:font
                                                    forKey:NSFontAttributeName];
  NSEnumerator *e = [[text componentsSeparatedByString:@" "]
                      objectEnumerator];
  CGFloat space = [@" " sizeWithAttributes:attrs].width, x = 0, w;
  NSString *word;
  int lines = 1;

  /* The cell's own inset. */
  width -= 4;
  while ((word = [e nextObject]) != nil)
    {
      w = [word sizeWithAttributes:attrs].width;
      if (x > 0 && x + space + w > width)
        {
          lines++;
          x = w;
        }
      else
        x += (x > 0 ? space : 0) + w;
    }
  return ceil (lines * [font defaultLineHeightForFont]) + 2;
}

NSTextField *
UPLabel (NSString *text, NSFont *font, CGFloat width)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                20)]);

  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [[label cell] setWraps:YES];
  if (font != nil)
    [label setFont:font];
  [label setStringValue:text != nil ? text : @""];
  [label setFrameSize:NSMakeSize (width, UPTextHeight ([label stringValue],
                                                       [label font],
                                                       width))];
  return label;
}

/* A path in the mockup's 24-unit badge box, scaled into `r`. */
static NSAffineTransform *
UPBox (NSRect r, CGFloat units)
{
  NSAffineTransform *t = [NSAffineTransform transform];

  [t translateXBy:NSMinX (r) yBy:NSMinY (r)];
  [t scaleBy:NSWidth (r) / units];
  return t;
}

static void
UPStroke (NSBezierPath *p, NSAffineTransform *t, NSColor *color,
          CGFloat width)
{
  [p transformUsingAffineTransform:t];
  [p setLineWidth:width];
  [p setLineCapStyle:NSRoundLineCapStyle];
  [p setLineJoinStyle:NSRoundLineJoinStyle];
  [color set];
  [p stroke];
}

@implementation UPIconView

- (void)setBadge:(UPBadge)badge
{
  _badge = badge;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect
{
  NSImage *icon = [NSApp applicationIconImage];
  CGFloat height = NSHeight ([self bounds]), scale;
  NSRect badge;
  NSAffineTransform *t, *flip;
  NSBezierPath *p;

  /* Not flipped, since GNUstep would draw the image upside down; the
   * badge is drawn top down, as in the mockup, through `flip`. */
  if (icon != nil)
    [icon drawInRect:NSMakeRect (0, height - 64, 64, 64) fromRect:NSZeroRect
           operation:NSCompositeSourceOver fraction:1.0];
  if (_badge == UPBadgeNone)
    return;

  flip = [NSAffineTransform transform];
  [flip translateXBy:0 yBy:height];
  [flip scaleXBy:1 yBy:-1];
  [flip concat];

  /* 24 points at the icon's bottom right, 4 outside it. */
  badge = NSMakeRect (44, 44, 24, 24);
  t = UPBox (badge, 24);
  scale = NSWidth (badge) / 24;
  switch (_badge)
    {
    case UPBadgeOK:
      p = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (1.5, 1.5, 21, 21)];
      [p transformUsingAffineTransform:t];
      [UPColor (0x1d3a26) set];
      [p fill];
      [p setLineWidth:1.5 * scale];
      [UPColor (0x6fd38a) set];
      [p stroke];
      p = [NSBezierPath bezierPath];
      [p moveToPoint:NSMakePoint (7.5, 12.3)];
      [p lineToPoint:NSMakePoint (10.5, 15.3)];
      [p lineToPoint:NSMakePoint (16.5, 9)];
      UPStroke (p, t, UPColor (0x6fd38a), 2.2 * scale);
      break;
    case UPBadgeWarning:
      p = [NSBezierPath bezierPath];
      [p moveToPoint:NSMakePoint (12, 2.5)];
      [p lineToPoint:NSMakePoint (22, 20.5)];
      [p lineToPoint:NSMakePoint (2, 20.5)];
      [p closePath];
      [p transformUsingAffineTransform:t];
      [UPColor (0x3b2a12) set];
      [p fill];
      [p setLineWidth:1.5 * scale];
      [p setLineJoinStyle:NSRoundLineJoinStyle];
      [UPColor (0xffb454) set];
      [p stroke];
      p = [NSBezierPath bezierPath];
      [p moveToPoint:NSMakePoint (12, 9)];
      [p lineToPoint:NSMakePoint (12, 14.5)];
      UPStroke (p, t, UPColor (0xffb454), 2.2 * scale);
      p = [NSBezierPath bezierPathWithOvalInRect:
                          NSMakeRect (10.7, 16.3, 2.6, 2.6)];
      [p transformUsingAffineTransform:t];
      [p fill];
      break;
    case UPBadgeRestart:
      p = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (1.5, 1.5, 21, 21)];
      [p transformUsingAffineTransform:t];
      [UPColor (0x0d2f5c) set];
      [p fill];
      [p setLineWidth:1.5 * scale];
      [UPColor (0x5fb4ff) set];
      [p stroke];
      /* An arrow round most of a circle, its head at the top right. */
      p = [NSBezierPath bezierPath];
      [p appendBezierPathWithArcWithCenter:NSMakePoint (12, 12.2)
                                    radius:4.6
                                startAngle:0
                                  endAngle:-45
                                 clockwise:NO];
      UPStroke (p, t, [NSColor whiteColor], 1.8 * scale);
      p = [NSBezierPath bezierPath];
      [p moveToPoint:NSMakePoint (15.6, 6.2)];
      [p lineToPoint:NSMakePoint (15.6, 9.1)];
      [p lineToPoint:NSMakePoint (12.7, 9.1)];
      UPStroke (p, t, [NSColor whiteColor], 1.8 * scale);
      break;
    default:
      break;
    }
}

@end

@implementation UPCalloutView

+ (UPCalloutView *)calloutWithKind:(UPCalloutKind)kind
                              text:(NSString *)text
                            detail:(NSString *)detail
                              bold:(BOOL)bold
                             width:(CGFloat)width
{
  UPCalloutView *view;
  NSTextField *first, *second = nil;
  CGFloat textX = 12 + 18 + 10, textW = width - textX - 12, height;

  first = UPLabel (text, bold ? [NSFont boldSystemFontOfSize:13]
                              : [NSFont systemFontOfSize:13], textW);
  height = 9 + NSHeight ([first frame]);
  if (detail != nil)
    {
      second = UPLabel (detail, [NSFont systemFontOfSize:11], textW);
      [second setTextColor:UPSecondaryColor ()];
      height += 3 + NSHeight ([second frame]);
    }
  height += 9;
  view = AUTORELEASE ([[self alloc]
                        initWithFrame:NSMakeRect (0, 0, width, height)]);
  view->_kind = kind;
  [first setFrameOrigin:NSMakePoint (textX, 9)];
  [view addSubview:first];
  if (second != nil)
    {
      [second setFrameOrigin:NSMakePoint (textX, NSMaxY ([first frame]) + 3)];
      [view addSubview:second];
    }
  return view;
}

- (BOOL)isFlipped
{
  return YES;
}

- (void)drawRect:(NSRect)rect
{
  NSRect b = [self bounds];
  NSAffineTransform *t;
  NSBezierPath *p;
  NSColor *ink;

  /* A sunken panel, the theme's control colour within. */
  [[NSColor controlBackgroundColor] set];
  NSRectFill (b);
  [UPColor (0x0a0a0c) set];
  NSRectFill (NSMakeRect (0, 0, NSWidth (b), 1));
  NSRectFill (NSMakeRect (0, 0, 1, NSHeight (b)));
  [UPColor (0x55555f) set];
  NSRectFill (NSMakeRect (0, NSHeight (b) - 1, NSWidth (b), 1));
  NSRectFill (NSMakeRect (NSWidth (b) - 1, 0, 1, NSHeight (b)));

  /* The symbol, 18 points, in the mockup's 24-unit box. */
  t = UPBox (NSMakeRect (12, 9, 18, 18), 24);
  ink = _kind == UPCalloutError ? UPColor (0xff6b6b)
    : _kind == UPCalloutOK ? UPColor (0x6fd38a) : UPColor (0x5fb4ff);
  p = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (3, 3, 18, 18)];
  UPStroke (p, t, ink, 1.6);
  p = [NSBezierPath bezierPath];
  switch (_kind)
    {
    case UPCalloutError:
      [p moveToPoint:NSMakePoint (9, 9)];
      [p lineToPoint:NSMakePoint (15, 15)];
      [p moveToPoint:NSMakePoint (15, 9)];
      [p lineToPoint:NSMakePoint (9, 15)];
      break;
    case UPCalloutOK:
      [p moveToPoint:NSMakePoint (8, 12.3)];
      [p lineToPoint:NSMakePoint (10.8, 15.1)];
      [p lineToPoint:NSMakePoint (16, 9.5)];
      break;
    default:
      [p moveToPoint:NSMakePoint (12, 11)];
      [p lineToPoint:NSMakePoint (12, 17)];
      [p moveToPoint:NSMakePoint (12, 7.6)];
      [p lineToPoint:NSMakePoint (12, 7.7)];
      break;
    }
  UPStroke (p, t, ink, 1.6);
}

@end
