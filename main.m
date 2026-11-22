/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Update.app: keeps NextBSD itself up to date, as a whole, from
 * NextBSD's own packages (nextbsd/nextbsd#661).
 */

#import <AppKit/AppKit.h>
#import "UPController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  UPController *controller = [[UPController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
