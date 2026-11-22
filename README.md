# Update

Update keeps NextBSD itself up to date. NextBSD works like an appliance: the
system is updated as a whole, from NextBSD's own packages, with nothing to
choose package by package. Update is part of NextBSD and installed by pkg.

It's at the design stage, planned in
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

## Mockup

[`mockups/update.html`](mockups/update.html) is an interactive simulator of
Update in the NextBSD theme. Download it and open it in a browser to run an
upgrade end to end: check, download, authenticate, install and restart. The
Simulator controls panel (bottom left) starts from any state, forces a
failure at any step, and speeds time up. Versions, sizes and timings are
sample data, and authentication is simulated (any password works).

## License

BSD 2-Clause. See [LICENSE](LICENSE).
