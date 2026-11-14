# CLAUDE.md — ansible-role-drbd

Orientation for Claude Code sessions in this repository. `AGENTS.md` is a symlink to this file.

## Purpose

Public Ansible role `cedricfarinazzo.drbd` (installed from git; not on Ansible Galaxy): the DRBD 9 kernel module built by DKMS from LINBIT's public repositories, `drbd-utils`, the module loaded now and at boot. Generic by design: no reference to any downstream project, host, user or network in code, defaults, docs or commit messages.

## Layout

- `defaults/main.yml` — every user-facing variable (`drbd_*`), with its generic default.
- `vars/main.yml` — LINBIT's source per distribution and release (`drbd_linbit_sources`), the values resolved from the user's inputs (`drbd_repo_*`, `drbd_key_*`), file paths, the role's marker line, the graceful unit names, the module options line, the kernel-flavor regex, the DKMS targets read from the host.
- `tasks/main.yml` — `validate.yml` (every input asserted before any change), then for `present`: `repo.yml` (method `linbit`: fail on another source of the same repository, download the key, check one key with the pinned fingerprint, then the keyring and the deb822 source; a mismatch removes the download and fails), `install.yml` (headers metapackage, the running kernel's headers when it loads, the DKMS `SPAAS=false` override, coccinelle, the APT pins, then the packages, by name), `dkms.yml` (reads the DKMS version and status; `dkms install` per target kernel not installed; `rescue` prints the `make.log` tail, or dkms's output when there is none), `module.yml` (modprobe.d with the marker, options and the DKMS-only `install` rule, modules-load.d, load DRBD 9, report a stale loaded module, `usage-count`), `graceful.yml` (tri-state masks and wants links, dangling links removed, the `Before=` drop-in on every graceful unit), `tls.yml` with `drbd_tls` (ktls-utils and openssl; the certificate, key and CA checked: files, PEM, chain, expiry, key match, key owner and mode; the marked tlshd config with the files' hashes, the `-c` drop-in, `tls` at boot, tlshd enabled, restarted on a config change, checked up), `tls_off.yml` without (marked TLS files removed); `tls_kernel.yml` before any change with `drbd_tls` (the kernel config holds every `drbd_tls_kernel_options` entry); for `absent`: `absent.yml` (no live resource, no reverse dependency, then purge, `drbd_tls_packages` too when the role's tlshd config is there; source and keyring under `linbit` only; marked files only).
- `handlers/main.yml` — APT list refresh after `absent` removes the source.
- `meta/main.yml` — Galaxy metadata; `platforms` lists exactly what CI tests.
- `molecule/default/` — one container per distribution: check mode on a fresh container, converge, verify (source, keyring, no other LINBIT trust, no hold, `dkms status`, `modinfo` from `updates/dkms`, files, `SPAAS=false` build, the modprobe rule, graceful units wanted, active and ordered), idempotence, `side_effect/` (masks, null leaves alone, rewired with a dangling link dropped, absent refused on a live resource and a reverse dependency, absent under `distribution`, then nothing left).
- `molecule/failure/` — Debian 13: a download holding a secret key, a wrong fingerprint (no source, no keyring), the headers removed (stops on DKMS), a broken kernel Makefile (`make.log` tail); `converge/` records each failure, `verify/` checks it.
- `molecule/graceful/` — Debian 12 only (LINBIT's proxmox-8 suite holds drbd-utils 9.34.x and 9.35): pinned to 9.34 by `drbd_apt_pins`, the `drbd-graceful-shutdown` unit wanted, active and ordered; `side_effect/` upgrades to 9.35 outside the role (dangling wants link), reruns the role, checks the cleanup and the down and disconnect units, then absent.
- `molecule/tls/` — Debian 12 and 13, three peers, a throwaway CA (`files/make-pki.sh`), ktls-utils pinned to LINBIT's 1.5.x: check mode, config, drop-in, tlshd up on it, a GnuTLS handshake between every ordered pair of peers (`files/handshake.yml`, `molecule_pair`), idempotence; `side_effect/` no restart without a change, a re-issued certificate restarts tlshd, another CA refused, `drbd_tls: false`, absent.
- `molecule/tls-failure/` — Debian 13: each bad kernel config, certificate, key or CA (`converge/case.yml` per case, a sibling intermediate included) stops the role on its own check before tlshd's config.
- `tests/validate.test.sh` — good and bad inputs against `tasks/validate.yml` on localhost, with Debian or Ubuntu facts set by the play.
- `run-tests.sh` / `Makefile` — local Molecule entry points: `run-tests.sh [-s SCENARIO] <distro>`; several distros or `all` run in parallel, one log each in `.molecule-logs/` (git-ignored).
- `requirements.yml` — collections the role needs at runtime (consumer-facing ranges).
- `requirements-dev.txt` — controller tooling, exact pins.
- `package.json`, `bun.lock`, `.releaserc.json` — semantic-release tooling only.
- `.github/workflows/` — `ci.yml` (lint, Galaxy description length, shellcheck, input tests, Molecule matrix, failure, graceful, tls and tls-failure scenarios), `pr-title.yml` (Conventional Commit title check), `release.yml` (semantic-release after `ci.yml` passes on `main`).
- `renovate.json` — dependency updates.

## Conventions

- **Conventional Commits** (`conventionalcommits` preset, so a `!` after the type is breaking). `feat:` → minor, `fix:` / `perf:` → patch, `!` or a `BREAKING CHANGE:` footer → major; `docs:` / `ci:` / `chore:` / `test:` / `refactor:` / `build:` release nothing. A squash merge lands the **PR title** (`pr-title.yml` checks it).
- **Breaking = a consumer must act.** Dropping a platform, renaming or removing a variable, changing a default source, suite or key fingerprint, or a default that changes which kernels are built or whether the module loads.
- **Tags are bare semver** (`1.2.3`, no `v`, `tagFormat` in `.releaserc.json`). Release notes live in GitHub Releases; no `CHANGELOG.md`, no release commit.
- **No ruleset or branch protection on `main`:** a ruleset blocks semantic-release. Changes still go through a PR with green CI, by discipline.
- **Variables:** every user-facing variable starts with `drbd_`, is defined in `defaults/main.yml`, asserted in `tasks/validate.yml` (with a case in `tests/validate.test.sh`) and documented in `README.md` in the same PR. Internal values start with `drbd_` too (ansible-lint `var-naming[no-role-prefix]`).
- **A key is trusted only after its fingerprint check:** no task before the check writes the source or the keyring; the check refuses a download holding more than one key, so the keyring (the download, dearmored if armored) holds the pinned key only. Never `gpg --import` on the host: a fresh GnuPG home needs a gpg-agent, which fails on Ubuntu. A key fingerprint in `vars/` is re-read from LINBIT over HTTPS before it changes.
- **Nothing held:** packages are installed by name; kernel updates rebuild the module through DKMS. APT pins only when `drbd_apt_pins` asks.
- **Remove only what the role marked:** a file the role may delete starts with `drbd_marker`; a `null` graceful setting touches nothing.
- **Examples never copy a real deployment:** README and Molecule values use `example.com` names and made-up hosts.
- **Every input is asserted before any change.**
- **GitHub Actions pinned by full commit SHA**, tag in a trailing comment.
- **Exact pins for tooling** (`requirements-dev.txt`, `package.json`, `molecule/*/collections.yml`); ranges only in `requirements.yml`. `renovate.json` is identical in the sibling roles: change them together.
- **License:** MIT.

## Supported platforms

`meta/main.yml` `platforms`, the CI matrix, the `README.md` table, `run-tests.sh --help` and the `Makefile` list the same set. End-of-life releases are dropped (a `feat!:` change).

### Adding a platform — checklist

1. Check a `geerlingguy/docker-<distro>-ansible:latest` image exists.
2. Find a LINBIT source that ships `drbd-dkms` and `drbd-utils` for it (public repository suite or PPA); add it to `drbd_linbit_sources` in `vars/main.yml`, its key fingerprint re-read over HTTPS.
3. Check its headers metapackage matches the kernel-flavor mapping in `vars/main.yml`.
4. Add it to the CI matrix, `meta/main.yml`, `README.md`, `run-tests.sh` usage and the `Makefile`.
5. `./run-tests.sh <distro>` green locally: the DKMS build must pass against its headers.

## How releases work

1. A PR is squash-merged into `main` with a Conventional Commit title.
2. When `ci.yml` passes on the push to `main`, `release.yml` (`workflow_run`) runs `bunx semantic-release`: tag, GitHub Release with notes, comments on the released PRs.
3. The role is not on Ansible Galaxy: users install a tag from git (`README.md` Quick Start); nothing in CI pushes to Galaxy.

## Commands

- Lint: `source .venv/bin/activate && yamllint . && ansible-lint && shellcheck run-tests.sh tests/*.sh molecule/tls/files/*.sh`
- Input tests: `tests/validate.test.sh`
- Molecule: `./run-tests.sh debian13`, `./run-tests.sh -s failure debian13`, `./run-tests.sh -s graceful`, `./run-tests.sh -s tls debian13`, `./run-tests.sh -s tls-failure debian13`, all distros in parallel: `./run-tests.sh all`

## Gotchas

- A container shares the host's kernel: it cannot load the module, and its `uname -r` is the CI host's. The scenarios name the distribution's headers metapackage and set `drbd_module_load: false`; auto then builds for the newest kernel with headers.
- `drbd-dkms`'s postinst already builds for every kernel with headers: the DKMS task usually finds it installed and changes nothing.
- DKMS stops before `make` when a kernel has no headers: there is no `make.log` then, so the role prints dkms's output.
- drbd-utils 9.35 replaced `drbd-graceful-shutdown.service` with `drbd-graceful-down.service` and `drbd-graceful-disconnect.service`; none has an `[Install]` section, so masking is a `/dev/null` link and wanting is a link in the target's `.wants/`. Only the udev rule (`SYSTEMD_WANTS` on `drbd*` block devices) pulls them in otherwise.
- A non-empty list in a `when` fails on ansible-core's strict conditionals: test `| length > 0`.
- A shell check in a Molecule verify ends each line in `|| fail`: a shell task's status is its last command's only.
- A Jinja string literal unescapes backslashes again: the kernel regex uses `[.]` and `[+]`, and the flavor is read with `regex_findall`, never a `\4` back-reference.
- Check mode on a fresh host: no cache dir, no key, no LINBIT source. The key tasks are skipped then and the package install has `ignore_errors` in check mode; Molecule's `check` step proves it.
- drbd-dkms's Makefile defaults `SPAAS=true` (compat patch from spaas.drbd.io when no cached patch nor local spatch fits). DKMS sources `/etc/dkms/drbd.conf` after the package's `dkms.conf`: `MAKE[0]+=" SPAAS=false"` reaches every build, kernel hooks included.
- dkms before 3.1 (Debian 12, Ubuntu 24.04) writes no `# command:` line in `make.log`: verify reads `MAKE` as dkms does (its `dkms.conf`, then `/etc/dkms/drbd.conf`).
- `grep -q` at the end of a pipe under `pipefail` can fail the pipe (the writer gets SIGPIPE): capture long output first.
- Without a cached compat patch for the kernel (Debian 13 today), `SPAAS=false` fails the build unless `spatch` is installed: the scenario sets `drbd_dkms_local_spatch` and points `spaas.drbd.io` at `0.0.0.0`.
- A `'` in a comment inside an `ansible.builtin.shell` block fails the syntax check (unbalanced quotes): no apostrophes there.
- tlshd reads its config once, at start, and ktls-utils 1.0 reads `/etc/tlshd.conf` while 1.1+ reads `/etc/tlshd/config`. The role loads its own file with `tlshd -c` from a drop-in, and puts the files' hashes in it so a new certificate restarts tlshd.
- A container cannot prove a DRBD connection over TLS: the kernel, `tls` and the handshake upcall are the CI host's. The `tls` scenario proves tlshd's config and start, plus a GnuTLS handshake with the same files; the README lists what only the target host shows.
- tlshd's server asks for a client certificate (`GNUTLS_CERT_REQUEST`) and accepts a client that sends none (ktls-utils 1.5.0 `server.c`); `gnutls-serv --require-client-cert` in `files/handshake.yml` is stricter than tlshd. Never claim the role gives mutual authentication on its own.
- ktls-utils' postinst starts tlshd on the package config: "tlshd not running" is no proof the role stopped before it. The failure cases check the role's config and drop-in instead.
- `get_url` with `force: false` still fetches a URL that sends no `Last-Modified` (keyserver.ubuntu.com) and rewrites it when its bytes vary: the key download runs only when the cache file is missing.

## Self Improvement Loop

Keep `CLAUDE.md` and `README.md` accurate, in the same PR as the change. Update when:

- **A variable is added, renamed or removed:** `defaults/main.yml`, `tasks/validate.yml`, `tests/validate.test.sh` and the `README.md` blocks.
- **A platform is added or dropped:** the checklist above.
- **A file or task file is added, removed or changes role:** Layout above.
- **A tool or Action is added:** pinned in its own file; never copy versions into prose.
- **A trap costs a debugging round:** one Gotchas line: the symptom, the cause, the fix.
- **A convention is established:** Conventions above.

New fact replaces the old clause; never append a changelog. Prefer small targeted edits over rewrites.
