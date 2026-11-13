# Tsuki AUR Packages

This directory contains the two Arch User Repository (AUR) packages for Tsuki:

- `tsuki-git/` — Builds from the latest `main` branch commit on GitHub.
- `tsuki-bin/` — Installs the prebuilt `.pkg.tar.zst` package from the latest GitHub Release.

## First-Time AUR Setup

Ensure your SSH key is added to your [AUR account](https://aur.archlinux.org/account/) and configured in `~/.ssh/config`:

```sshconfig
Host aur.archlinux.org
  IdentityFile ~/.ssh/aur
  User aur
```

Clone each AUR repository (creating it if it doesn't exist yet):

```bash
git clone ssh://aur@aur.archlinux.org/tsuki-git.git
git clone ssh://aur@aur.archlinux.org/tsuki-bin.git
```

## Publishing `tsuki-git`

`tsuki-git` dynamically resolves `pkgver` from git history at build time, so you normally only need to push it once (or when dependencies/build flags change):

```bash
cp packaging/aur/tsuki-git/{PKGBUILD,.SRCINFO,tsuki.install} /path/to/aur-tsuki-git/
cd /path/to/aur-tsuki-git
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO tsuki.install
git commit -m "Initial import: tsuki-git"
git push -u origin master
```

## Updating `tsuki-bin` on a New GitHub Release

After pushing a `v*` tag to GitHub and waiting for the Release workflow to finish:

Option A — Sync automatically from the latest GitHub release:
```bash
./packaging/aur/update-bin.sh
cp packaging/aur/tsuki-bin/{PKGBUILD,.SRCINFO,tsuki.install} /path/to/aur-tsuki-bin/
cd /path/to/aur-tsuki-bin
git add PKGBUILD .SRCINFO tsuki.install
git commit -m "Update to $(grep '^pkgver=' PKGBUILD | cut -d= -f2)"
git push origin master
```

Option B — Download the ready-made `aur-tsuki-bin` workflow artifact from the GitHub Actions Release run and copy `PKGBUILD`, `.SRCINFO`, and `tsuki.install` into `/path/to/aur-tsuki-bin/`.

