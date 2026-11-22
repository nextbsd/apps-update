/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * UPController: Update's app delegate and its one window
 * (nextbsd/nextbsd#661), exactly the mockup's states
 * (mockups/update.html):
 *
 *   start        "NextBSD <installed>", and after a check that found
 *                nothing "No updates available.", after an update
 *                "Updated successfully."; Check for Updates
 *   checking     an indeterminate bar; Stop
 *   checkfail    the repository couldn't be reached; Try Again
 *   available    "NextBSD <new>" and its download size; Download
 *   downloading  one bar with the size and the time left; Cancel
 *   dlfail       the download stopped; Cancel, Retry
 *   ready        ready to install; Install Now..., which asks for an
 *                administrator (NBAuthorizationPanel)
 *   installing   one bar and one status line
 *   installfail  it couldn't be installed; Try Again...
 *   restart      Later, Restart Now; after Later, "Restart to finish
 *                updating" with Restart...; and if the helper can't
 *                restart (an update replaced it), "Restart your
 *                computer to finish updating" and how
 *
 * The work is SettingsHelper's (nextbsd-userland src/SettingsHelper,
 * sh_update.c): Update never runs pkg itself. Check, download and
 * install start a job there and return; while one runs Update asks for
 * its status twice a second. Update checks only when asked, and has no
 * Preferences.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorization.h"

typedef enum
{
  UPPhaseStart,
  UPPhaseUnavailable,		/* no helper to ask */
  UPPhaseChecking,
  UPPhaseCheckFailed,
  UPPhaseAvailable,
  UPPhaseDownloading,
  UPPhaseDownloadFailed,
  UPPhaseReady,
  UPPhaseInstalling,
  UPPhaseInstallFailed,
  UPPhaseRestart
} UPPhase;

@interface UPController : NSObject
{
  NSWindow *window;
  NSView *content;
  NBAuthorization *checkAuth;	/* org.nextbsd.settings.update.check */
  NBAuthorization *installAuth;	/* org.nextbsd.settings.update */
  NSTimer *poll;

  UPPhase phase;
  int helperStatus;		/* why the helper is unavailable */
  NSString *installed;		/* NextBSD's version */
  NSString *previous;		/* the version before this install */
  NSString *available;		/* the update's version */
  long long size;		/* bytes to download */
  long long done, total;	/* the job's progress */
  NSString *line;		/* the install's status line */
  BOOL changed;			/* a failed install changed packages */
  BOOL noUpdates;		/* a check found nothing */
  BOOL justUpdated;		/* restarted after an update */
  BOOL deferred;		/* Later was clicked */
  BOOL restartByHand;		/* the helper couldn't restart */

  /* The download's rate, smoothed. */
  NSTimeInterval rateAt;
  long long rateDone;
  double rate;			/* bytes a second */

  /* What the progress views show, updated without a new layout. */
  NSProgressIndicator *bar;
  NSTextField *progressText;
  NSTextField *progressRight;
}

@end
