# Update

Update keeps NextBSD itself up to date. NextBSD works like an appliance: the
system is updated as a whole, from NextBSD's own packages, with nothing to
choose package by package. Update is part of NextBSD and installed by pkg.

It's planned in
[nextbsd/nextbsd#661](https://github.com/nextbsd/nextbsd/issues/661) (epic
E45).

## Keep it simple

- **Only when asked.** Update checks when you click Check for Updates. It
  never checks, downloads or installs on its own, and it has no Preferences.
- **One update.** An update is a new NextBSD version, shown with its download
  size. Every update rebuilds and replaces all of NextBSD's packages, so
  there's no package list or release notes.
- **Download, then install.** Download shows progress and can be cancelled.
  Install Now asks for an administrator, through the settings apps'
  privileged helper and authentication panel
  ([nextbsd/nextbsd#628](https://github.com/nextbsd/nextbsd/issues/628)).
- **Restart.** Every update needs a restart: Restart Now or Later. The Dock
  and the menu bar show when an update or a restart is waiting.
- **Apps from Software** are updated in Software, not here.

Not now: keeping the previous system as a backup (it needs ZFS boot
environments), and automatic or scheduled updates.

## How it works

Update never runs pkg itself. The settings apps' privileged helper,
SettingsHelper (nextbsd-userland `src/SettingsHelper`, `sh_update.c`),
does the work in typed operations whose pkg arguments are all its own:

| Operation | What the helper runs | Right |
|-----------|----------------------|-------|
| UpdateCheck | `pkg update`, then `pkg upgrade -n`: is there anything to do, and how much to download | `org.nextbsd.settings.update.check` (allow) |
| UpdateDownload | `pkg upgrade -F`: into pkg's cache, nothing installed | `org.nextbsd.settings.update.check` |
| UpdateInstall | `pkg upgrade`, from the cache | `org.nextbsd.settings.update` (authenticate-admin) |
| UpdateCancel | stops a check or a download | `org.nextbsd.settings.update.check` |
| UpdateRestart | `shutdown -r now`, only while an installed update waits for it | none: the install's approval covers it |
| UpdateStatus | the running job, or the last one | none (the console session) |

No pkg run names a package: there is an update when `pkg upgrade -n` has
something to do, and after the check every run keeps to the catalogue it
read (`-U`). Package names only label the window: the installed NextBSD
is SystemVersion.plist's (as `sw_vers` shows it), and the update's version
is the repository's `NextBSD-desktop`, else `NextBSD-server`, else
`NextBSD-everything` (one list in `sh_update.c`). Without one, the update
is still offered, as "the NextBSD update".

Check, download and install take minutes, so each starts a job in the
helper and returns at once. The job reads pkg's progress from its event
pipe (`-o EVENT_PIPE`), and Update asks for the status twice a second
while one runs. Quitting Update stops a check or a download (pkg keeps
what it fetched); an install goes on, and Update shows it when opened
again. After an install the helper records the boot it happened in, so
Update says a restart is waiting until the next boot, and "Updated
successfully." after it.

An update replaces SettingsHelper and its rules too, so the restart
depends on neither: the administrator who allowed the install allowed
the restart, and the helper that installed the update stays running
until then. If the restart still can't go through the helper (it was
stopped, and the one now installed has no UpdateRestart), Update says
"Restart your computer to finish updating" and points to the login
window's Restart button: neither loginwindow nor Workspace takes a
restart request from a session app.

## Building

Update compiles in the settings apps' shared code, `Frameworks/NBSettings`,
from a checkout of [apps-settings](https://github.com/nextbsd/apps-settings)
beside this one (`gmake NBSETTINGS=/path/to/NBSettings` to use another):

    gmake
    gmake install

## Not yet

- The Dock and menu-bar extras that show a waiting update or restart.
- Packaging: installing Update with NextBSD's packages.

## Mockup

[`mockups/update.html`](mockups/update.html) is an interactive simulator of
Update in the NextBSD theme. Download it and open it in a browser to run an
upgrade end to end: check, download, authenticate, install and restart. The
Simulator controls panel (bottom left) starts from any state, forces a
failure at any step, and speeds time up. Versions, sizes and timings are
sample data, and authentication is simulated (any password works).

## License

BSD 2-Clause. See [LICENSE](LICENSE).
