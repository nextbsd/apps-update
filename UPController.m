/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "UPController.h"
#import "UPViews.h"
#import "NBAuthorizationPanel.h"
#import "NBSettingsHelper.h"

#include <sys/param.h>
#include <sys/mount.h>
#include <math.h>
#include <string.h>

static NSString *const UPCheckRight = @"org.nextbsd.settings.update.check";
static NSString *const UPInstallRight = @"org.nextbsd.settings.update";

/* The mockup's measures: a 520-point window, 22 points in, the icon 64
 * points with 18 to the text. */
static const CGFloat UPWindowWidth = 520;
static const CGFloat UPMarginX = 22;
static const CGFloat UPMarginTop = 20;
static const CGFloat UPMarginBottom = 22;
static const CGFloat UPTextX = 22 + 64 + 18;
static const NSTimeInterval UPPollInterval = 0.5;

/* "561.2 MB", "1.07 GB": decimal, as the mockup. */
static NSString *
UPSize (long long bytes)
{
  double mb = bytes / 1e6;

  if (mb >= 1000)
    return [NSString stringWithFormat:@"%.2f GB", mb / 1000];
  return [NSString stringWithFormat:@"%.1f MB", mb];
}

static NSString *
UPRemaining (double seconds)
{
  long minutes;

  if (!isfinite (seconds) || seconds <= 0)
    return @"Calculating time remaining…";
  if (seconds < 10)
    return @"a few seconds remaining";
  if (seconds < 60)
    return [NSString stringWithFormat:@"about %d seconds remaining",
                     (int) ceil (seconds / 5) * 5];
  minutes = lround (seconds / 60);
  return [NSString stringWithFormat:@"about %ld minute%@ remaining", minutes,
                   minutes > 1 ? @"s" : @""];
}

/* The installed NextBSD, as sw_vers says it: SystemVersion.plist's
 * ProductVersion and build, "27.0.0.178". */
static NSString *
UPSystemVersion (void)
{
  NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
                       @"/System/Library/CoreServices/SystemVersion.plist"];
  NSString *version = [d objectForKey:@"ProductVersion"];
  NSString *build = [d objectForKey:@"ProductBuildVersion"];

  if ([version length] == 0)
    return @"";
  if ([build length] == 0)
    return version;
  return [NSString stringWithFormat:@"%@.%@", version, build];
}

/* Is / a ZFS boot environment (<pool>/ROOT/<name>)? Then updates go into
 * new boot environments. */
static BOOL
UPBootEnvironments (void)
{
  struct statfs sfs;

  return statfs ("/", &sfs) == 0 && strcmp (sfs.f_fstypename, "zfs") == 0
    && strstr (sfs.f_mntfromname, "/ROOT/") != NULL;
}

#define UPBootEnvUpdateConf \
  @"/Local/Library/Preferences/org.nextbsd.bootenv-update.conf"

/* How many versions an update keeps: bootenv-update's keep=, else 3. */
static int
UPReadKeep (void)
{
  NSString *text = [NSString stringWithContentsOfFile:UPBootEnvUpdateConf];
  NSEnumerator *e = [[text componentsSeparatedByString:@"\n"]
                      objectEnumerator];
  NSString *l;
  int n = 3;

  while ((l = [e nextObject]) != nil)
    {
      l = [l stringByTrimmingCharactersInSet:
               [NSCharacterSet whitespaceCharacterSet]];
      if ([l hasPrefix:@"keep"] && [l rangeOfString:@"="].location
          != NSNotFound)
        n = [[[l componentsSeparatedByString:@"="] lastObject] intValue];
    }
  return n < 2 ? 2 : n;
}

/* A name an update gave (27.0.0-192, 27.0.0-192-2), as against one a
 * person chose (bectl create test). */
static BOOL
UPBuildNamed (NSString *name)
{
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];

  return [name length] > 0
    && [digits characterIsMember:[name characterAtIndex:0]]
    && [name rangeOfString:@"-"].location != NSNotFound;
}

/* "NextBSD 27.0.0-192" for one an update or the installer named; the
 * name itself for one a person named. */
static NSString *
UPVersionTitle (NSString *name)
{
  if (UPBuildNamed (name))
    return [@"NextBSD " stringByAppendingString:name];
  if ([name hasPrefix:@"NextBSD-"])
    return [@"NextBSD " stringByAppendingString:[name substringFromIndex:8]];
  if ([name isEqualToString:@"default"])
    return @"NextBSD";
  return name;
}

static NSInteger
UPCompareVersions (id a, id b, void *ctx)
{
  NSString *na = [a objectForKey:@"name"], *nb = [b objectForKey:@"name"];
  BOOL ba = UPBuildNamed (na), bb = UPBuildNamed (nb);

  if (ba != bb)
    return ba ? NSOrderedAscending : NSOrderedDescending;
  /* Newest first. */
  return [nb compare:na options:NSNumericSearch];
}

/* The boot environments, from bectl list -H (no privilege needed):
 * name, running, next, space; newest build first, then the others. */
static NSArray *
UPReadVersions (void)
{
  NSTask *task = AUTORELEASE ([[NSTask alloc] init]);
  NSPipe *pipe = [NSPipe pipe];
  NSMutableArray *list = [NSMutableArray array];
  NSString *out;
  NSEnumerator *e;
  NSString *l;

  [task setLaunchPath:@"/sbin/bectl"];
  [task setArguments:[NSArray arrayWithObjects:@"list", @"-H", nil]];
  [task setStandardOutput:pipe];
  /* NSTask starts it in Update's own directory, which may be one the
   * user can't enter. */
  [task setCurrentDirectoryPath:@"/"];
  NS_DURING
    [task launch];
  NS_HANDLER
    return list;
  NS_ENDHANDLER
  out = AUTORELEASE ([[NSString alloc]
                       initWithData:[[pipe fileHandleForReading]
                                      readDataToEndOfFile]
                           encoding:NSUTF8StringEncoding]);
  [task waitUntilExit];
  e = [[out componentsSeparatedByString:@"\n"] objectEnumerator];
  while ((l = [e nextObject]) != nil)
    {
      NSArray *f = [l componentsSeparatedByString:@"\t"];
      NSString *active;

      if ([f count] < 4 || [[f objectAtIndex:0] length] == 0)
        continue;
      active = [f objectAtIndex:1];
      [list addObject:
              [NSDictionary dictionaryWithObjectsAndKeys:
                              [f objectAtIndex:0], @"name",
                            [NSNumber numberWithBool:
                                        [active rangeOfString:@"N"].location
                                        != NSNotFound], @"running",
                            [NSNumber numberWithBool:
                                        [active rangeOfString:@"R"].location
                                        != NSNotFound], @"next",
                            [f objectAtIndex:3], @"space", nil]];
    }
  return [list sortedArrayUsingFunction:UPCompareVersions context:NULL];
}

@interface UPController (Private)
- (NSString *)updateName:(BOOL)capital;
- (void)buildMenu;
- (void)setPhase:(UPPhase)p;
- (void)layout;
- (CGFloat)addHeadTitle:(NSString *)title sub:(NSString *)sub
                  badge:(UPBadge)badge;
- (CGFloat)addChipAt:(CGFloat)y;
- (CGFloat)addBarAt:(CGFloat)y indeterminate:(BOOL)indeterminate;
- (CGFloat)addButtons:(NSArray *)buttons at:(CGFloat)y;
- (CGFloat)addCallout:(UPCalloutKind)kind text:(NSString *)text
               detail:(NSString *)detail bold:(BOOL)bold at:(CGFloat)y;
- (NSButton *)button:(NSString *)title action:(SEL)action
             primary:(BOOL)primary;
- (void)updateProgress;
- (void)startPolling;
- (void)stopPolling;
- (void)poll:(NSTimer *)t;
- (BOOL)readStatus:(NSDictionary **)status;
- (void)follow:(NSDictionary *)status;
- (void)jobEnded:(NSDictionary *)status;
- (void)refused:(int)status;
- (void)checkForUpdates:(id)sender;
- (void)stopCheck:(id)sender;
- (void)download:(id)sender;
- (void)cancelDownload:(id)sender;
- (void)install:(id)sender;
- (void)later:(id)sender;
- (void)restartNow:(id)sender;
- (void)confirmRestart:(id)sender;
- (void)restartSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code
               contextInfo:(void *)info;
- (void)showVersions:(id)sender;
- (void)hideVersions:(id)sender;
- (CGFloat)addVersionsAt:(CGFloat)y;
- (void)restartInto:(id)sender;
- (void)removeVersion:(id)sender;
- (void)keepChanged:(id)sender;
- (void)versionSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code
               contextInfo:(void *)info;
- (NSString *)runningVersionTitle;
- (void)startPendingVersion;
- (void)removePendingVersion;
@end

@implementation UPController

- (void)dealloc
{
  [poll invalidate];
  RELEASE (poll);
  RELEASE (window);
  RELEASE (checkAuth);
  RELEASE (installAuth);
  RELEASE (installed);
  RELEASE (previous);
  RELEASE (available);
  RELEASE (line);
  RELEASE (versions);
  RELEASE (pendingVersion);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Update.png"];
  NSDictionary *status;
  int restart;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  ASSIGN (installed, UPSystemVersion ());
  bootenvs = UPBootEnvironments ();
  checkAuth = RETAIN ([NBAuthorization authorizationWithRight:UPCheckRight]);
  installAuth = RETAIN ([NBAuthorization
                          authorizationWithRight:UPInstallRight]);

  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 300, UPWindowWidth, 160)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Update"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Update"];

  /* Where things stand: a job may be running (Update was quit and
   * opened again), or an installed update may wait for a restart. */
  phase = UPPhaseStart;
  if ([self readStatus:&status])
    {
      restart = [[status objectForKey:NBUpdateRestart] intValue];
      if (restart == NBUpdateRestartPending)
        {
          ASSIGN (available,
                  [status objectForKey:NBUpdateRestartVersion]);
          deferred = YES;
          phase = UPPhaseRestart;
        }
      else if (restart == NBUpdateRestartDone)
        justUpdated = YES;
      if ([[status objectForKey:NBUpdateState] intValue]
          == NBUpdateStateRunning)
        [self follow:status];
    }
  else
    phase = UPPhaseUnavailable;
  [self layout];
  [window makeKeyAndOrderFront:self];
  if (phase == UPPhaseChecking || phase == UPPhaseDownloading
      || phase == UPPhaseInstalling)
    [self startPolling];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

/* Quitting stops a check or a download; pkg keeps what it fetched. An
 * install goes on in the helper, and Update shows it when opened
 * again. */
- (void)applicationWillTerminate:(NSNotification *)note
{
  if (phase == UPPhaseChecking || phase == UPPhaseDownloading)
    (void)[NBSettingsHelper cancelUpdateWithAuthorization:checkAuth];
}

/* The app menu's Check for Updates: only from the start or a failed
 * check; otherwise the window shows what's going on. */
- (BOOL)validateMenuItem:(id<NSMenuItem>)item
{
  if ([item action] == @selector (checkForUpdates:))
    return !showingVersions && (phase == UPPhaseStart
      || phase == UPPhaseCheckFailed || phase == UPPhaseUnavailable);
  if ([item action] == @selector (showVersions:))
    return bootenvs && !showingVersions && phase != UPPhaseInstalling;
  return YES;
}

@end

@implementation UPController (Private)

/* "NextBSD 27.0.0.181", or without a version when the repository's
 * meta-package didn't say: "The NextBSD update". */
- (NSString *)updateName:(BOOL)capital
{
  if ([available length] > 0)
    return [@"NextBSD " stringByAppendingString:available];
  return capital ? @"The NextBSD update" : @"the NextBSD update";
}

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Update"]);

  [menu addItemWithTitle:@"About Update"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  [[menu addItemWithTitle:@"Check for Updates"
                   action:@selector (checkForUpdates:)
            keyEquivalent:@""] setTarget:self];
  [[menu addItemWithTitle:@"Installed Versions…"
                   action:@selector (showVersions:)
            keyEquivalent:@""] setTarget:self];
  [menu addItemWithTitle:@"Close" action:@selector (performClose:)
           keyEquivalent:@"w"];
  [menu addItemWithTitle:@"Hide" action:@selector (hide:) keyEquivalent:@"h"];
  [menu addItemWithTitle:@"Quit" action:@selector (terminate:)
           keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];
}

/* ---- the window ---- */

- (void)setPhase:(UPPhase)p
{
  if (p != UPPhaseStart)
    noUpdates = NO;
  if (p != UPPhaseStart && p != UPPhaseUnavailable)
    justUpdated = NO;
  phase = p;
  [self layout];
}

/* Build the window's contents for the phase, top down, and size the
 * window to them, keeping its top where it is. */
- (void)layout
{
  NSRect frame;
  CGFloat y = 0, height;
  NSString *have = installed != nil ? installed : @"";

  content = AUTORELEASE ([[NSView alloc]
                           initWithFrame:NSMakeRect (0, 0, UPWindowWidth,
                                                     400)]);
  bar = nil;
  progressText = nil;
  progressRight = nil;

  /* Installed Versions covers the update's own phase, which waits
   * underneath until Done. */
  if (showingVersions)
    {
      y = [self addHeadTitle:@"Installed Versions"
                         sub:@"Go back to an earlier version of NextBSD. "
                             @"Your accounts, files and settings are the "
                             @"same in all of them."
                       badge:UPBadgeNone];
      y = [self addVersionsAt:y];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Done"
                                   action:@selector (hideVersions:)
                                  primary:YES]]
                        at:y];
    }
  else switch (phase)
    {
    case UPPhaseStart:
      /* Update says nothing about being current until it has checked. */
      y = [self addHeadTitle:[@"NextBSD " stringByAppendingString:have]
                         sub:justUpdated ? @"Updated successfully."
                             : noUpdates ? @"No updates available." : nil
                       badge:justUpdated ? UPBadgeOK : UPBadgeNone];
      y = [self addButtons:
                  bootenvs
                  ? [NSArray arrayWithObjects:
                               [self button:@"Check for Updates"
                                     action:@selector (checkForUpdates:)
                                    primary:YES],
                               [self button:@"Installed Versions…"
                                     action:@selector (showVersions:)
                                    primary:NO], nil]
                  : [NSArray arrayWithObject:
                               [self button:@"Check for Updates"
                                     action:@selector (checkForUpdates:)
                                    primary:YES]]
                        at:y];
      break;

    case UPPhaseUnavailable:
      y = [self addHeadTitle:@"NextBSD"
                         sub:[NBAuthorization messageForStatus:helperStatus]
                       badge:UPBadgeWarning];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Try Again"
                                   action:@selector (checkForUpdates:)
                                  primary:YES]]
                        at:y];
      break;

    case UPPhaseChecking:
      y = [self addHeadTitle:@"Checking for updates…"
                         sub:@"Asking the NextBSD package repository "
                             @"what’s new."
                       badge:UPBadgeNone];
      y = [self addBarAt:y indeterminate:YES];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Stop"
                                   action:@selector (stopCheck:)
                                  primary:NO]]
                        at:y];
      break;

    case UPPhaseCheckFailed:
      y = [self addHeadTitle:@"Can’t check for updates"
                         sub:@"Update couldn’t reach the NextBSD package "
                             @"repository."
                       badge:UPBadgeWarning];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Try Again"
                                   action:@selector (checkForUpdates:)
                                  primary:YES]]
                        at:y];
      y = [self addCallout:UPCalloutError
                      text:@"Your computer doesn’t seem to be connected to "
                           @"the internet."
                    detail:@"Check your Wi-Fi or Ethernet connection, then "
                           @"try again. Nothing was changed."
                      bold:NO
                        at:y];
      break;

    case UPPhaseAvailable:
      y = [self addHeadTitle:[self updateName:YES]
                         sub:[NSString stringWithFormat:
                                @"An update for NextBSD is available. You "
                                @"have NextBSD %@.", have]
                       badge:UPBadgeNone];
      y = [self addChipAt:y];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Download"
                                   action:@selector (download:)
                                  primary:YES]]
                        at:y];
      break;

    case UPPhaseDownloading:
      y = [self addHeadTitle:[self updateName:YES]
                         sub:@"Downloading. You can keep working."
                       badge:UPBadgeNone];
      y = [self addBarAt:y indeterminate:NO];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Cancel"
                                   action:@selector (cancelDownload:)
                                  primary:NO]]
                        at:y];
      break;

    case UPPhaseDownloadFailed:
      y = [self addHeadTitle:@"The download stopped"
                         sub:[NSString stringWithFormat:
                                @"%@ · %@ of %@ downloaded",
                                [self updateName:YES],
                                UPSize (done), UPSize (total)]
                       badge:UPBadgeWarning];
      y = [self addBarAt:y indeterminate:NO];
      [progressText removeFromSuperview];
      [progressRight removeFromSuperview];
      progressText = progressRight = nil;
      y = [self addButtons:
                  [NSArray arrayWithObjects:
                             [self button:@"Cancel"
                                   action:@selector (cancelDownload:)
                                  primary:NO],
                             [self button:@"Retry"
                                   action:@selector (download:)
                                  primary:YES], nil]
                        at:y];
      y = [self addCallout:UPCalloutError
                      text:@"The connection to the package repository was "
                           @"lost."
                    detail:@"What was downloaded is kept, so Retry "
                           @"continues where it stopped. Nothing was "
                           @"installed."
                      bold:NO
                        at:y];
      break;

    case UPPhaseReady:
      y = [self addHeadTitle:[NSString stringWithFormat:
                                         @"%@ is ready to install",
                                         [self updateName:YES]]
                         sub:@"Installing takes a few minutes. Your "
                             @"computer needs to restart when it’s done."
                       badge:UPBadgeNone];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Install Now…"
                                   action:@selector (install:)
                                  primary:YES]]
                        at:y];
      break;

    case UPPhaseInstalling:
      y = [self addHeadTitle:[NSString stringWithFormat:
                                         @"Installing %@…",
                                         [self updateName:NO]]
                         sub:bootenvs
                             ? @"Installing into a new boot environment. "
                               @"You can keep working; nothing changes "
                               @"until you restart."
                             : @"Installing over the running system. Don’t "
                               @"turn off your computer."
                       badge:UPBadgeNone];
      y = [self addBarAt:y indeterminate:NO];
      break;

    case UPPhaseInstallFailed:
      y = [self addHeadTitle:@"The update couldn’t be installed"
                         sub:[self updateName:YES]
                       badge:UPBadgeWarning];
      y = [self addButtons:
                  [NSArray arrayWithObject:
                             [self button:@"Try Again…"
                                   action:@selector (install:)
                                  primary:YES]]
                        at:y];
      if (bootenvs)
        y = [self addCallout:UPCalloutOK
                        text:@"Your system was not changed."
                      detail:[NSString stringWithFormat:
                                @"Update stopped and removed the incomplete "
                                @"copy. You’re still using NextBSD %@, "
                                @"exactly as before.",
                                previous != nil ? previous : have]
                        bold:YES
                          at:y];
      else if (changed)
        y = [self addCallout:UPCalloutError
                        text:@"NextBSD is only partly updated."
                      detail:@"Update stopped while installing packages, "
                             @"and without a backup they can’t be undone. "
                             @"Try again to finish the update. Until then, "
                             @"some apps may not work correctly."
                        bold:YES
                          at:y];
      else
        y = [self addCallout:UPCalloutOK
                        text:@"Your system was not changed."
                      detail:[NSString stringWithFormat:
                                @"Update stopped before installing "
                                @"anything. You’re still using NextBSD %@, "
                                @"exactly as before.",
                                previous != nil ? previous : have]
                        bold:YES
                          at:y];
      break;

    case UPPhaseRestart:
      if (!deferred)
        {
          y = [self addHeadTitle:@"Restart required"
                             sub:[NSString stringWithFormat:
                                    @"%@ is installed. Restart your "
                                    @"computer to start using it.",
                                    [self updateName:YES]]
                           badge:UPBadgeRestart];
          y = [self addButtons:
                      [NSArray arrayWithObjects:
                                 [self button:@"Later"
                                       action:@selector (later:)
                                      primary:NO],
                                 [self button:@"Restart Now"
                                       action:@selector (restartNow:)
                                      primary:YES], nil]
                            at:y];
          if (bootenvs)
            y = [self addCallout:UPCalloutOK
                            text:[NSString stringWithFormat:
                                    @"%@ is installed alongside the system "
                                    @"you’re using, and starts next time.",
                                    [self updateName:YES]]
                          detail:[NSString stringWithFormat:
                                    @"NextBSD %@ stays installed. If "
                                    @"something goes wrong, go back to it "
                                    @"in Installed Versions.",
                                    previous != nil ? previous : have]
                            bold:NO
                              at:y];
          else
            y = [self addCallout:UPCalloutInfo
                            text:@"Save your work in other apps before you "
                                 @"restart."
                          detail:nil
                            bold:NO
                              at:y];
        }
      else if (restartByHand)
        {
          /* Nothing in the session takes a restart request: the login
           * window's Restart button does it. No error: the update is
           * installed. */
          y = [self addHeadTitle:@"Restart to finish updating"
                             sub:@"Restart your computer to finish "
                                 @"updating."
                           badge:UPBadgeRestart];
          y = [self addCallout:UPCalloutInfo
                          text:@"Log out, then click Restart in the login "
                               @"window."
                        detail:nil
                          bold:NO
                            at:y];
        }
      else
        {
          y = [self addHeadTitle:@"Restart to finish updating"
                             sub:[NSString stringWithFormat:
                                    @"%@ is installed. It starts the "
                                    @"next time you restart.",
                                    [self updateName:YES]]
                           badge:UPBadgeRestart];
          y = [self addButtons:
                      [NSArray arrayWithObject:
                                 [self button:@"Restart…"
                                       action:@selector (confirmRestart:)
                                      primary:YES]]
                            at:y];
          y = [self addCallout:UPCalloutInfo
                          text:previous != nil
                               ? [NSString stringWithFormat:
                                    @"You’re still using NextBSD %@ until "
                                    @"you restart.", previous]
                               : @"You’re still using the earlier NextBSD "
                                 @"until you restart."
                        detail:bootenvs
                               ? @"The update waits in a new boot "
                                 @"environment; the system you’re using "
                                 @"hasn’t changed."
                               : @"Some apps may behave oddly until you "
                                 @"restart, because parts of the system were "
                                 @"replaced while running."
                          bold:NO
                            at:y];
        }
      break;
    }

  /* Flip: the views were placed top down. */
  height = y + UPMarginBottom;
  {
    NSEnumerator *e = [[content subviews] objectEnumerator];
    NSView *view;

    while ((view = [e nextObject]) != nil)
      {
        NSRect f = [view frame];
        f.origin.y = height - NSMaxY (f);
        [view setFrame:f];
      }
  }
  [content setFrameSize:NSMakeSize (UPWindowWidth, height)];
  frame = [window frameRectForContentRect:
                    NSMakeRect (0, 0, UPWindowWidth, height)];
  frame.origin.x = NSMinX ([window frame]);
  frame.origin.y = NSMaxY ([window frame]) - NSHeight (frame);
  [window setContentView:content];
  [window setFrame:frame display:YES];
  [self updateProgress];
}

/* The icon and the title with its line under it; returns the bottom. */
- (CGFloat)addHeadTitle:(NSString *)title sub:(NSString *)sub
                  badge:(UPBadge)badge
{
  CGFloat width = UPWindowWidth - UPTextX - UPMarginX, y;
  UPIconView *icon = AUTORELEASE ([[UPIconView alloc]
                                    initWithFrame:NSMakeRect (UPMarginX,
                                                              UPMarginTop,
                                                              68, 68)]);
  NSTextField *label;

  [icon setBadge:badge];
  [content addSubview:icon];
  label = UPLabel (title, [NSFont boldSystemFontOfSize:18], width);
  [label setFrameOrigin:NSMakePoint (UPTextX, UPMarginTop + 4)];
  [content addSubview:label];
  y = NSMaxY ([label frame]) + 2;
  if ([sub length] > 0)
    {
      label = UPLabel (sub, [NSFont systemFontOfSize:13], width);
      [label setTextColor:UPSecondaryColor ()];
      [label setFrameOrigin:NSMakePoint (UPTextX, y)];
      [content addSubview:label];
      y = NSMaxY ([label frame]);
    }
  return MAX (y, UPMarginTop + 64);
}

/* "Download 561.2 MB", the mockup's chip. */
- (CGFloat)addChipAt:(CGFloat)y
{
  NSTextField *chip = UPLabel ([@"Download " stringByAppendingString:
                                               UPSize (size)],
                               [NSFont systemFontOfSize:11], 300);
  NSRect f;

  [chip setDrawsBackground:YES];
  [chip setBackgroundColor:[NSColor controlBackgroundColor]];
  [chip setBordered:YES];
  [chip sizeToFit];
  f = [chip frame];
  f.origin = NSMakePoint (UPTextX, y + 10);
  f.size.width += 8;
  [chip setFrame:f];
  [content addSubview:chip];
  return NSMaxY (f);
}

/* The progress bar, and under it the line of text and the figure at the
 * right. */
- (CGFloat)addBarAt:(CGFloat)y indeterminate:(BOOL)indeterminate
{
  CGFloat width = UPWindowWidth - UPTextX - UPMarginX;

  bar = AUTORELEASE ([[NSProgressIndicator alloc]
                       initWithFrame:NSMakeRect (UPTextX, y + 14, width,
                                                 14)]);
  [bar setIndeterminate:indeterminate];
  [bar setMinValue:0];
  [bar setMaxValue:1];
  [content addSubview:bar];
  y = NSMaxY ([bar frame]);
  if (indeterminate)
    {
      [bar startAnimation:self];
      return y;
    }
  progressText = UPLabel (@" ", [NSFont systemFontOfSize:11], width - 110);
  [progressText setTextColor:UPSecondaryColor ()];
  [progressText setFrameOrigin:NSMakePoint (UPTextX, y + 6)];
  [content addSubview:progressText];
  progressRight = UPLabel (@" ", [NSFont systemFontOfSize:11], 100);
  [progressRight setTextColor:UPSecondaryColor ()];
  [progressRight setAlignment:NSRightTextAlignment];
  [progressRight setFrameOrigin:NSMakePoint (UPWindowWidth - UPMarginX - 100,
                                             y + 6)];
  [content addSubview:progressRight];
  return NSMaxY ([progressText frame]);
}

/* Buttons in a row under the text, left to right. */
- (CGFloat)addButtons:(NSArray *)buttons at:(CGFloat)y
{
  NSEnumerator *e = [buttons objectEnumerator];
  NSButton *b;
  CGFloat x = UPTextX;

  while ((b = [e nextObject]) != nil)
    {
      [b setFrameOrigin:NSMakePoint (x, y + 14)];
      [content addSubview:b];
      x = NSMaxX ([b frame]) + 12;
    }
  return y + 14 + 24;
}

- (CGFloat)addCallout:(UPCalloutKind)kind text:(NSString *)text
               detail:(NSString *)detail bold:(BOOL)bold at:(CGFloat)y
{
  UPCalloutView *callout = [UPCalloutView
                             calloutWithKind:kind
                                        text:text
                                      detail:detail
                                        bold:bold
                                       width:UPWindowWidth - 2 * UPMarginX];

  [callout setFrameOrigin:NSMakePoint (UPMarginX, y + 16)];
  [content addSubview:callout];
  return NSMaxY ([callout frame]);
}

- (NSButton *)button:(NSString *)title action:(SEL)action
             primary:(BOOL)primary
{
  NSButton *b = AUTORELEASE ([[NSButton alloc]
                               initWithFrame:NSMakeRect (0, 0, 100, 24)]);
  NSRect f;

  [b setTitle:title];
  [b setTarget:self];
  [b setAction:action];
  [b sizeToFit];
  f = [b frame];
  f.size.width = MAX (NSWidth (f) + 24, 90);
  f.size.height = 24;
  [b setFrame:f];
  if (primary)
    {
      [b setKeyEquivalent:@"\r"];
      [window setDefaultButtonCell:[b cell]];
    }
  return b;
}

/* The bar and its line, from done and total. */
- (void)updateProgress
{
  double fraction = total > 0 ? (double) done / total : 0;

  if (bar == nil || [bar isIndeterminate])
    return;
  [bar setDoubleValue:MIN (fraction, 1.0)];
  if (phase == UPPhaseDownloading)
    {
      [progressText setStringValue:
                      [NSString stringWithFormat:@"%@ of %@ · %@",
                                UPSize (done), UPSize (total),
                                UPRemaining (rate > 0 ? (total - done) / rate
                                                      : 0)]];
      [progressRight setStringValue:
                       rate > 0 ? [NSString stringWithFormat:@"%.1f MB/s",
                                            rate / 1e6]
                                : @""];
    }
  else if (phase == UPPhaseInstalling)
    {
      [progressText setStringValue:line != nil ? line : @""];
      [progressRight setStringValue:
                       [NSString stringWithFormat:@"%d%%",
                                 (int) floor (fraction * 100)]];
    }
}

/* ---- following the helper's job ---- */

- (void)startPolling
{
  if (poll != nil)
    return;
  rateAt = 0;
  rate = 0;
  ASSIGN (poll, [NSTimer scheduledTimerWithTimeInterval:UPPollInterval
                                                 target:self
                                               selector:@selector (poll:)
                                               userInfo:nil
                                                repeats:YES]);
}

- (void)stopPolling
{
  [poll invalidate];
  DESTROY (poll);
}

- (BOOL)readStatus:(NSDictionary **)status
{
  int rc = [NBSettingsHelper updateStatus:status authorization:checkAuth];

  if (rc != NBAuthorizationOK)
    {
      helperStatus = rc;
      return NO;
    }
  return YES;
}

- (void)poll:(NSTimer *)t
{
  NSDictionary *status;

  if (![self readStatus:&status])
    {
      [self stopPolling];
      [self setPhase:UPPhaseUnavailable];
      return;
    }
  if ([[status objectForKey:NBUpdateState] intValue] == NBUpdateStateRunning)
    [self follow:status];
  else
    {
      [self stopPolling];
      [self jobEnded:status];
    }
}

/* A running job: its phase and progress. */
- (void)follow:(NSDictionary *)status
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  NSString *v = [status objectForKey:NBUpdateAvailableVersion];
  UPPhase p;

  switch ([[status objectForKey:NBUpdateJob] intValue])
    {
    case NBUpdateJobCheck:
      p = UPPhaseChecking;
      break;
    case NBUpdateJobDownload:
      p = UPPhaseDownloading;
      break;
    default:
      p = UPPhaseInstalling;
      break;
    }
  if ([v length] > 0)
    ASSIGN (available, v);
  done = [[status objectForKey:NBUpdateDone] longLongValue];
  total = [[status objectForKey:NBUpdateTotal] longLongValue];
  ASSIGN (line, [status objectForKey:NBUpdateLine]);

  /* The rate over the last few seconds. */
  if (p == UPPhaseDownloading)
    {
      if (rateAt > 0 && now > rateAt && done >= rateDone)
        {
          double r = (done - rateDone) / (now - rateAt);
          rate = rate > 0 ? rate * 0.8 + r * 0.2 : r;
        }
      rateAt = now;
      rateDone = done;
    }
  if (p != phase)
    [self setPhase:p];
  else
    [self updateProgress];
}

- (void)jobEnded:(NSDictionary *)status
{
  int job = [[status objectForKey:NBUpdateJob] intValue];
  int state = [[status objectForKey:NBUpdateState] intValue];
  NSString *v = [status objectForKey:NBUpdateAvailableVersion];

  done = [[status objectForKey:NBUpdateDone] longLongValue];
  total = [[status objectForKey:NBUpdateTotal] longLongValue];
  size = [[status objectForKey:NBUpdateSize] longLongValue];
  /* A check names the update afresh, or leaves it without a version. */
  if (job == NBUpdateJobCheck || [v length] > 0)
    ASSIGN (available, v);

  switch (job)
    {
    case NBUpdateJobCheck:
      if (state == NBUpdateStateDone
          && ![[status objectForKey:NBUpdatePending] boolValue])
        {
          noUpdates = YES;
          justUpdated = NO;
          [self setPhase:UPPhaseStart];
        }
      else if (state == NBUpdateStateDone)
        /* Nothing left to download (it's all in pkg's cache already):
         * straight to ready. */
        [self setPhase:size > 0 ? UPPhaseAvailable : UPPhaseReady];
      else if (state == NBUpdateStateCancelled)
        [self setPhase:UPPhaseStart];
      else
        [self setPhase:UPPhaseCheckFailed];
      break;
    case NBUpdateJobDownload:
      if (state == NBUpdateStateDone)
        [self setPhase:UPPhaseReady];
      else if (state == NBUpdateStateCancelled)
        [self setPhase:UPPhaseAvailable];
      else
        [self setPhase:UPPhaseDownloadFailed];
      break;
    case NBUpdateJobInstall:
      changed = [[status objectForKey:NBUpdateChanged] boolValue];
      if (state == NBUpdateStateDone)
        {
          ASSIGN (installed, UPSystemVersion ());
          deferred = NO;
          [self setPhase:UPPhaseRestart];
        }
      else
        [self setPhase:UPPhaseInstallFailed];
      break;
    default:
      [self setPhase:UPPhaseStart];
      break;
    }
}

/* The helper said no to starting something. */
- (void)refused:(int)status
{
  if (status == NBAuthorizationUnavailable)
    {
      helperStatus = status;
      [self setPhase:UPPhaseUnavailable];
      return;
    }
  NSRunAlertPanel (@"Update", @"%@", @"OK", nil, nil,
                   [NBAuthorization messageForStatus:status]);
}

/* ---- the buttons ---- */

- (void)checkForUpdates:(id)sender
{
  int rc = [NBSettingsHelper checkForUpdateWithAuthorization:checkAuth];

  if (rc != NBAuthorizationOK && rc != NBAuthorizationBusy)
    {
      [self refused:rc];
      return;
    }
  [self setPhase:UPPhaseChecking];
  [self startPolling];
}

- (void)stopCheck:(id)sender
{
  (void)[NBSettingsHelper cancelUpdateWithAuthorization:checkAuth];
}

- (void)download:(id)sender
{
  int rc = [NBSettingsHelper downloadUpdateWithAuthorization:checkAuth];

  if (rc != NBAuthorizationOK)
    {
      [self refused:rc];
      return;
    }
  done = 0;
  total = size;
  [self setPhase:UPPhaseDownloading];
  [self startPolling];
}

/* Cancel: while downloading, stop it (the helper then says cancelled);
 * after it stopped, back to the update. */
- (void)cancelDownload:(id)sender
{
  if (phase == UPPhaseDownloadFailed)
    {
      [self setPhase:UPPhaseAvailable];
      return;
    }
  (void)[NBSettingsHelper cancelUpdateWithAuthorization:checkAuth];
}

- (void)install:(id)sender
{
  NSString *reason = [@"install " stringByAppendingString:
                                    [self updateName:NO]];
  int rc;

  if (![NBAuthorizationPanel obtainAuthorization:installAuth
                                          reason:reason
                                       forWindow:window])
    return;
  rc = [NBSettingsHelper installUpdateWithAuthorization:installAuth];
  if (rc != NBAuthorizationOK)
    {
      [self refused:rc];
      return;
    }
  ASSIGN (previous, installed);
  done = 0;
  total = 0;
  DESTROY (line);
  [self setPhase:UPPhaseInstalling];
  [self startPolling];
}

- (void)later:(id)sender
{
  deferred = YES;
  [self setPhase:UPPhaseRestart];
}

- (void)restartNow:(id)sender
{
  [self confirmRestart:sender];
}

- (void)confirmRestart:(id)sender
{
  NSBeginAlertSheet (@"Restart now?", @"Restart", @"Cancel", nil, window,
                     self,
                     @selector (restartSheetDidEnd:returnCode:contextInfo:),
                     NULL, NULL,
                     @"Open apps will quit. Make sure your work is saved.");
}

- (void)restartSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code
               contextInfo:(void *)info
{
  int rc;

  if (code != NSAlertDefaultReturn)
    return;
  rc = [NBSettingsHelper restartForUpdateWithAuthorization:checkAuth];
  if (rc != NBAuthorizationOK)
    {
      /* The helper that answers may not be the one that installed the
       * update (the update replaced it, and it has no restart or no
       * rule): say how to restart, not why it failed. */
      restartByHand = YES;
      deferred = YES;
      [self setPhase:UPPhaseRestart];
    }
}

/* ---- Installed Versions ---- */

- (void)showVersions:(id)sender
{
  if (!bootenvs)
    return;
  ASSIGN (versions, UPReadVersions ());
  keep = UPReadKeep ();
  showingVersions = YES;
  [self layout];
}

- (void)hideVersions:(id)sender
{
  showingVersions = NO;
  [self layout];
}

/* One row a version: its name and what it is, its size, and Restart
 * Into... and Remove... where they apply; then how many to keep. */
- (CGFloat)addVersionsAt:(CGFloat)y
{
  CGFloat right = UPWindowWidth - UPMarginX;
  NSUInteger i, count = [versions count];
  NSTextField *label;
  NSPopUpButton *popup;
  NSArray *choices = [NSArray arrayWithObjects:@"2", @"3", @"5", @"10", nil];
  NSString *k = [NSString stringWithFormat:@"%d", keep];

  y += 12;
  if (count == 0)
    {
      label = UPLabel (@"Update couldn’t list the installed versions.",
                       [NSFont systemFontOfSize:13], 400);
      [label setFrameOrigin:NSMakePoint (UPTextX, y)];
      [content addSubview:label];
      y = NSMaxY ([label frame]);
    }
  for (i = 0; i < count; i++)
    {
      NSDictionary *v = [versions objectAtIndex:i];
      NSString *name = [v objectForKey:@"name"];
      BOOL running = [[v objectForKey:@"running"] boolValue];
      BOOL next = [[v objectForKey:@"next"] boolValue];
      NSString *tag = running ? @"Running" : next ? @"Starts next" : nil;
      CGFloat bottom, x = right;
      NSButton *b;

      label = UPLabel (UPVersionTitle (name), [NSFont boldSystemFontOfSize:13],
                       160);
      [label setFrameOrigin:NSMakePoint (UPMarginX, y)];
      [content addSubview:label];
      bottom = NSMaxY ([label frame]);
      if (tag != nil)
        {
          label = UPLabel (tag, [NSFont systemFontOfSize:11], 160);
          [label setTextColor:UPSecondaryColor ()];
          [label setFrameOrigin:NSMakePoint (UPMarginX, bottom)];
          [content addSubview:label];
          bottom = NSMaxY ([label frame]);
        }
      label = UPLabel ([v objectForKey:@"space"], [NSFont systemFontOfSize:11],
                       56);
      [label setAlignment:NSRightTextAlignment];
      [label setTextColor:UPSecondaryColor ()];
      [label setFrameOrigin:NSMakePoint (UPMarginX + 160, y + 2)];
      [content addSubview:label];
      if (!running && !next)
        {
          b = [self button:@"Remove…" action:@selector (removeVersion:)
                   primary:NO];
          [b setTag:(NSInteger) i];
          x -= NSWidth ([b frame]);
          [b setFrameOrigin:NSMakePoint (x, y)];
          [content addSubview:b];
          x -= 8;
        }
      if (!running)
        {
          b = [self button:@"Restart Into…" action:@selector (restartInto:)
                   primary:NO];
          [b setTag:(NSInteger) i];
          x -= NSWidth ([b frame]);
          [b setFrameOrigin:NSMakePoint (x, y)];
          [content addSubview:b];
        }
      y = MAX (bottom, y + 24) + 10;
    }

  y += 6;
  label = UPLabel (@"Keep the", [NSFont systemFontOfSize:13], 80);
  [label sizeToFit];
  [label setFrameOrigin:NSMakePoint (UPMarginX, y + 3)];
  [content addSubview:label];
  popup = AUTORELEASE ([[NSPopUpButton alloc]
                         initWithFrame:NSMakeRect (NSMaxX ([label frame]) + 6,
                                                   y, 60, 24)
                             pullsDown:NO]);
  [popup addItemsWithTitles:choices];
  if (![choices containsObject:k])
    [popup addItemWithTitle:k];
  [popup selectItemWithTitle:k];
  [popup setTarget:self];
  [popup setAction:@selector (keepChanged:)];
  [content addSubview:popup];
  label = UPLabel (@"most recent versions. Older ones are removed after "
                   @"an update.", [NSFont systemFontOfSize:13],
                   right - NSMaxX ([popup frame]) - 8);
  [label setFrameOrigin:NSMakePoint (NSMaxX ([popup frame]) + 8, y + 3)];
  [content addSubview:label];
  return MAX (NSMaxY ([label frame]), y + 24);
}

/* The running version's name, for the sheets. */
- (NSString *)runningVersionTitle
{
  NSEnumerator *e = [versions objectEnumerator];
  NSDictionary *v;

  while ((v = [e nextObject]) != nil)
    if ([[v objectForKey:@"running"] boolValue])
      return UPVersionTitle ([v objectForKey:@"name"]);
  return @"the version you’re using";
}

- (void)restartInto:(id)sender
{
  NSString *name = [[versions objectAtIndex:[sender tag]] objectForKey:@"name"];
  NSString *title = UPVersionTitle (name);

  ASSIGN (pendingVersion, name);
  NSBeginAlertSheet ([NSString stringWithFormat:@"Restart into %@?", title],
                     @"Restart", @"Cancel", nil, window, self,
                     @selector (versionSheetDidEnd:returnCode:contextInfo:),
                     NULL, (void *) 1,
                     @"Apps and system files go back to %@. Your accounts, "
                     @"files and settings stay as they are. %@ stays "
                     @"installed, and you can come back to it here.",
                     title, [self runningVersionTitle]);
}

- (void)removeVersion:(id)sender
{
  NSDictionary *v = [versions objectAtIndex:[sender tag]];
  NSString *title = UPVersionTitle ([v objectForKey:@"name"]);

  ASSIGN (pendingVersion, [v objectForKey:@"name"]);
  NSBeginAlertSheet ([NSString stringWithFormat:@"Remove %@?", title],
                     @"Remove", @"Cancel", nil, window, self,
                     @selector (versionSheetDidEnd:returnCode:contextInfo:),
                     NULL, (void *) 2,
                     @"This frees %@. Your accounts, files and settings "
                     @"aren’t affected, but you won’t be able to go back to "
                     @"this version.", [v objectForKey:@"space"]);
}

- (void)versionSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code
               contextInfo:(void *)info
{
  if (code != NSAlertDefaultReturn || pendingVersion == nil)
    return;
  /* After the sheet has gone: the authorization panel is a sheet too. */
  [self performSelector:(info == (void *) 1
                         ? @selector (startPendingVersion)
                         : @selector (removePendingVersion))
             withObject:nil
             afterDelay:0];
}

- (void)startPendingVersion
{
  NSString *reason = [@"restart into " stringByAppendingString:
                                         UPVersionTitle (pendingVersion)];
  int rc;

  if (![NBAuthorizationPanel obtainAuthorization:installAuth
                                          reason:reason
                                       forWindow:window])
    return;
  rc = [NBSettingsHelper startVersion:pendingVersion
                        authorization:installAuth];
  if (rc != NBAuthorizationOK)
    [self refused:rc];
  /* Otherwise the computer is restarting. */
}

- (void)removePendingVersion
{
  NSString *reason = [@"remove " stringByAppendingString:
                                   UPVersionTitle (pendingVersion)];
  int rc;

  if (![NBAuthorizationPanel obtainAuthorization:installAuth
                                          reason:reason
                                       forWindow:window])
    return;
  rc = [NBSettingsHelper removeVersion:pendingVersion
                         authorization:installAuth];
  if (rc != NBAuthorizationOK)
    [self refused:rc];
  ASSIGN (versions, UPReadVersions ());
  [self layout];
}

- (void)keepChanged:(id)sender
{
  int n = [[sender titleOfSelectedItem] intValue], rc;

  if (n == keep)
    return;
  if (![NBAuthorizationPanel obtainAuthorization:installAuth
                                          reason:@"change how many versions "
                                                 @"are kept"
                                       forWindow:window])
    {
      [sender selectItemWithTitle:[NSString stringWithFormat:@"%d", keep]];
      return;
    }
  rc = [NBSettingsHelper setKeepVersions:n authorization:installAuth];
  if (rc != NBAuthorizationOK)
    {
      [sender selectItemWithTitle:[NSString stringWithFormat:@"%d", keep]];
      [self refused:rc];
      return;
    }
  keep = n;
}

@end
