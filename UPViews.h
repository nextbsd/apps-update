/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Update's two drawn views, as in the mockup (mockups/update.html):
 *   - UPIconView: the app's icon, 64 points, with a corner badge that
 *     says how things stand: a green check (updated), an amber warning
 *     (something failed) or a blue restart arrow (a restart waits);
 *   - UPCalloutView: the bordered note under the window's head, a
 *     symbol (error, info, ok) beside a line of text and a smaller one.
 */

#import <AppKit/AppKit.h>

typedef enum
{
  UPBadgeNone,
  UPBadgeOK,
  UPBadgeWarning,
  UPBadgeRestart
} UPBadge;

@interface UPIconView : NSView
{
  UPBadge _badge;
}
- (void)setBadge:(UPBadge)badge;
@end

typedef enum
{
  UPCalloutError,
  UPCalloutInfo,
  UPCalloutOK
} UPCalloutKind;

@interface UPCalloutView : NSView
{
  UPCalloutKind _kind;
}
/* A callout `width` wide, as tall as its text needs. `detail` may be
 * nil; `bold` makes the first line bold. */
+ (UPCalloutView *)calloutWithKind:(UPCalloutKind)kind
                              text:(NSString *)text
                            detail:(NSString *)detail
                              bold:(BOOL)bold
                             width:(CGFloat)width;
@end

/* A label, wrapped to `width`, as tall as its text. */
NSTextField *UPLabel (NSString *text, NSFont *font, CGFloat width);
/* The theme's colour for secondary text. */
NSColor *UPSecondaryColor (void);
