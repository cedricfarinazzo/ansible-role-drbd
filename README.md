# 💽 Ansible Role: drbd

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **The [DRBD 9](https://linbit.com/drbd/) kernel module built by DKMS from LINBIT's public repositories, with `drbd-utils`, loaded now and at every boot.**

Most distribution kernels ship the DRBD 8.4 module only, while LINSTOR, DRBD Reactor and DRBD 9 resources need DRBD 9. This role adds LINBIT's APT source with a key it checks against a pinned fingerprint first, installs the headers of your kernel flavor, `drbd-dkms` and `drbd-utils`, and makes sure DKMS built DRBD for your kernels. Kernel updates rebuild the module through DKMS, so nothing is held.

## 🚀 Quick Start

The role is installed from this repository (it is not on Ansible Galaxy):

```yaml
# requirements.yml
roles:
  - name: cedricfarinazzo.drbd
    src: https://github.com/cedricfarinazzo/ansible-role-drbd.git
    scm: git
    version: 2.0.0
```

```bash
ansible-galaxy role install -r requirements.yml
```

```yaml
- hosts: storage
  become: true
  roles:
    - role: cedricfarinazzo.drbd
```

The role will:
- ✅ Download LINBIT's key, check it holds exactly one key with the pinned fingerprint, and only then write it to `/etc/apt/keyrings/linbit.gpg` and the source `/etc/apt/sources.list.d/linbit.sources` that names it with `Signed-By` (the key is trusted for that source only; LINBIT's `linbit-keyring` package is never installed)
- ✅ Install the headers metapackage of the running kernel's flavor (`linux-headers-amd64`, `linux-headers-generic`, ...), then `drbd-dkms` and `drbd-utils`, by name; nothing is held
- ✅ Check DKMS shows DRBD installed for the running kernel and the newest kernel, build it where it is not; a failed build prints the end of DKMS's `make.log`. Optionally without LINBIT's spatch-as-a-service, for offline or firewalled hosts
- ✅ Load DRBD 9 now (an older DRBD module, not in use, is unloaded first) and at boot (`/etc/modules-load.d/drbd.conf`), with your module parameters; `modprobe drbd` refuses a module that is not a DKMS build, so a kernel DKMS missed never loads its in-tree DRBD 8.4
- ✅ Turn off LINBIT's usage reporting (`usage-count no;`) unless you want it
- ✅ Optionally wire DRBD's graceful shutdown units from boot, ordered after the services using DRBD, or mask them for a cluster manager that stops DRBD itself

Resource configuration (`/etc/drbd.d/*.res`) is left to you or to a storage manager on top; see the [DRBD 9 User Guide](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/).

## 📋 Requirements

| Component | Requirement |
|-----------|-------------|
| **Operating System** | Debian, Ubuntu (see below), systemd |
| **Ansible** | ansible-core 2.15+ (CI tests the version pinned in `requirements-dev.txt`) |
| **Collections** | `community.general` (`requirements.yml`) |
| **Privileges** | Root or sudo access on the target hosts |
| **Network** | The hosts reach LINBIT's repository (or your mirror) over HTTPS; a DKMS build may reach `spaas.drbd.io` (see `drbd_dkms_spaas`) |

### Supported Distributions

Each is tested in CI with Molecule: a DKMS build of DRBD 9 against the distribution's headers, a rerun for idempotence, then `drbd_state: absent`.

| Distribution | Versions | LINBIT source |
|--------------|----------|---------------|
| **Debian** | 12, 13 | [`packages.linbit.com/public`](https://packages.linbit.com/public/), suites `proxmox-8` (12) and `proxmox-9` (13), component `drbd-9` |
| **Ubuntu** | 24.04, 26.04 | LINBIT's Launchpad PPA [`linbit/linbit-drbd9-stack`](https://launchpad.net/~linbit/+archive/ubuntu/linbit-drbd9-stack) |

#### Platform notes

- **Debian:** LINBIT's only public suites with `drbd-dkms` are its Proxmox VE suites, built for the Debian release under each Proxmox VE release; the `bookworm` and `trixie` suites hold userland tools only. The Proxmox suites also hold LINSTOR and other LINBIT packages: the source is trusted for them too.
- **Secure Boot:** DKMS signs the module with its own key (`/var/lib/dkms/mok.key`); a host with Secure Boot on loads it only once that key is enrolled as a MOK. The role does not enroll it.
- **Enterprise Linux:** not supported, LINBIT publishes no public RPM repository. ELRepo's `kmod-drbd9x` packages are an option outside this role.
- **Containers:** a container cannot load a kernel module; set `drbd_module_load: false` there (the Molecule scenario does).
- **Ubuntu PPA versions:** LINBIT's PPA can carry release candidates (drbd-utils `9.36.0~rc.1` at the time of writing). Pin a release with `drbd_apt_pins` (e.g. `drbd-utils: "9.35.*"`) if you do not want them.
- **drbd-utils upgrades across 9.35:** 9.34 and older ship `drbd-graceful-shutdown.service`, whose `ExecStop` is `drbdsetup down all`; their `prerm` stops it, so the upgrade to 9.35+ takes every resource on the host down. Upgrade with the resources down (or on a node you can drain), then run the role again: it removes the wants link left to the vanished unit and wires `drbd-graceful-down.service` and `drbd-graceful-disconnect.service`.
- **Ubuntu HWE kernels:** set `drbd_kernel_headers_package` to the HWE metapackage (`linux-headers-generic-hwe-24.04`), auto picks `linux-headers-generic`.

## ⚙️ Configuration

Every input is checked before anything changes: a wrong type or value fails the play.

### State and source

```yaml
# present: packages, DKMS build and module; absent: remove what the role added
drbd_state: present

# linbit: add LINBIT's source and key; distribution: install from the sources already configured
drbd_install_method: linbit

# LINBIT source; empty = the default for the distribution and release (table above)
drbd_apt_repo_url: ""        # ends in /
drbd_apt_suite: ""
drbd_apt_components: []
drbd_apt_key_url: ""         # https only
drbd_apt_key_fingerprint: "" # 40 hex digits, spaces and case ignored
# The key file inside a downloaded .deb (never installed); empty = the download is the key (armored or binary)
drbd_apt_key_deb_member: ""
drbd_apt_keyring: /etc/apt/keyrings/linbit.gpg
```

The default sources are HTTPS. A source URL you set may be `http://` (a mirror without TLS): APT still checks every package against the pinned key. The key URL must be HTTPS.

Another source already naming the same repository (a `linbit.list` from LINBIT's own instructions, Proxmox VE's) fails the role before it writes anything: APT rejects one repository under two `Signed-By` keys. Remove that source, or use `drbd_install_method: distribution`.

Defaults: Debian downloads `https://packages.linbit.com/public/linbit-keyring.deb`, extracts `./etc/apt/trusted.gpg.d/linbit-keyring.gpg` and checks fingerprint `4E53 8554 6726 D13C B649 872C FC05 A31D B826 FE48`; Ubuntu fetches the PPA key `CC1B 5A79 3C04 BB39 05AD 8377 3489 3610 CEAA 9512` from `keyserver.ubuntu.com`. Pin the fingerprint in your inventory to keep a role update from moving it.

A key whose fingerprint differs, or a download with more than one key or any secret key, fails the role before the source or the keyring is written, and the download is removed.

### Packages and DKMS

```yaml
drbd_packages:
  - drbd-dkms
  - drbd-utils
drbd_packages_extra: []      # e.g. [drbd-reactor]
# APT pins, package -> version glob, in /etc/apt/preferences.d/drbd.pref (priority 1001); {} = none
drbd_apt_pins: {}            # e.g. {drbd-utils: "9.35.*"}

# Headers metapackage DKMS builds against: auto = the running kernel's flavor
# (6.12.116+deb13-amd64 -> linux-headers-amd64, 6.8.0-45-generic -> linux-headers-generic); "" = none
drbd_kernel_headers_package: auto

# Kernels DKMS builds for: auto = the running kernel and the newest kernel, each when its headers are present;
# or a list of kernel releases
drbd_dkms_kernels: auto

# false: build without LINBIT's spatch-as-a-service
drbd_dkms_spaas: true
# Install coccinelle, the local spatch
drbd_dkms_local_spatch: false

# Lines of make.log printed when a build fails
drbd_dkms_log_lines: 40
```

DRBD's build adapts its sources to each kernel with a compat patch. It takes the patch from the cache the package ships, else from a local `spatch` (coccinelle), else from LINBIT's spatch-as-a-service: the build POSTs the kernel's generated `compat.h` to `https://spaas.drbd.io` and applies the patch it returns, as root, unsigned. That is drbd-dkms's own default (`SPAAS=true` in its Makefile). `drbd_dkms_spaas: false` writes `/etc/dkms/drbd.conf` (`MAKE[0]+=" SPAAS=false"`), read by every DKMS build of DRBD, the role's and the kernel hooks' alike, before `drbd-dkms` is installed. A kernel with no cached patch then needs `drbd_dkms_local_spatch: true` (installs `coccinelle`), or the build fails with DRBD's own message. Use it for offline or firewalled hosts, or when no build may send data out or apply a patch from the network.

When `drbd_module_load` is true and `drbd_dkms_kernels` is auto, the role fails before any build if the running kernel has no headers: DKMS could not build DRBD 9 for it.

A kernel release auto cannot read (no `<version>-<flavor>` form) fails, asking for `drbd_kernel_headers_package`. When DKMS stops before `make` (no headers for a listed kernel), the role prints DKMS's own output instead of `make.log`.

### Module and settings

```yaml
drbd_module_load: true          # load DRBD 9 now
drbd_module_load_at_boot: true  # /etc/modules-load.d/drbd.conf
drbd_module_options: {}         # e.g. {minor_count: 64}, in /etc/modprobe.d/drbd.conf; booleans as 1/0
drbd_module_dkms_only: true     # modprobe drbd loads a DKMS build (updates/) only
drbd_usage_count: false         # usage-count in /etc/drbd.d/global_common.conf; drbd-utils ships yes
drbd_mask_graceful_shutdown: null                   # true mask, false unmask, null leave alone
drbd_graceful_shutdown: null                        # true wire the graceful units from boot, false unwire, null leave alone
drbd_graceful_shutdown_wanted_by: multi-user.target # the target that wants them
drbd_graceful_shutdown_before: []                   # units every graceful unit waits for at shutdown
```

`/etc/modprobe.d/drbd.conf` starts with the line `# Managed by the Ansible role cedricfarinazzo.drbd`. The role removes it only with that line: a file of yours, without it, is never removed (it is replaced if you ask for options or the DKMS-only rule). With `drbd_module_dkms_only: true` it holds an `install drbd` rule: `modprobe drbd` loads the module only when `modinfo` finds it under `updates/` (where DKMS installs it), else it fails with `refusing the in-tree module`. A kernel DKMS did not build for (its headers missing at its install) then has no DRBD at all rather than DRBD 8.4 under DRBD 9 tools; `dkms status drbd` shows which kernels have a build.

The role never reloads a loaded DRBD 9: when the loaded version differs from the DKMS build, or the options changed, it prints that a reload (resources down, `modprobe -r drbd; modprobe drbd`) or a reboot applies them.

drbd-utils' udev rule starts its graceful units only once a DRBD device appears, whatever brought the resource up (`drbd@.service`, LINSTOR's satellite, a script). Their `ExecStop` acts on every DRBD resource in the kernel: `drbd-graceful-shutdown.service` (drbd-utils 9.28 to 9.34) and `drbd-graceful-down.service` (9.35+) run `drbdsetup down all`, `drbd-graceful-disconnect.service` (9.35+) disconnects every peer; they read no config file, so LINSTOR's resources go down too. `drbd_graceful_shutdown: true` makes `drbd_graceful_shutdown_wanted_by` want each graceful unit the package ships (a link in its `.wants/`: they have no `[Install]` section) and starts them now, so every shutdown takes the resources down cleanly. `drbd_graceful_shutdown_before` (e.g. the service that stops your VMs, a mount on a DRBD device) goes into a `Before=` drop-in on each of them: at shutdown none disconnects nor takes down a resource before those have stopped. `false` removes the links (in `drbd_graceful_shutdown_wanted_by` only: after changing the target, remove the old link yourself) and the drop-in. A wants link whose unit is gone (after a drbd-utils upgrade across 9.35) is removed on every run.

`drbd_mask_graceful_shutdown: true` masks the graceful units, e.g. under Pacemaker, which stops DRBD itself; it excludes `drbd_graceful_shutdown: true`. A mask does not stop a unit already active: its `ExecStop` still runs at this boot's shutdown; reboot, or stop it yourself (which runs it now). `false` removes only masks (links to `/dev/null`), never a unit file of yours. `null`, the default of both, changes neither: masks and links you made by hand stay.

A loaded DRBD 8.4 module still in use (resources up) is never unloaded: the role fails and asks you to stop the resources first (`drbdsetup down all`).

### Kernel TLS for replication

```yaml
drbd_tls: false                  # true: ktls-utils, tlshd on the files below, the tls module
drbd_tls_packages:               # from the configured sources; pin with drbd_apt_pins
  - ktls-utils
drbd_tls_certificate: ""         # PEM certificate, signed by the CA file, for client and server use
drbd_tls_private_key: ""         # its unencrypted PEM key, owned by root, mode 0600 or 0640
drbd_tls_truststore: ""          # PEM CA the peers' certificates must chain to
drbd_tls_cert_min_days: 0        # stop when the certificate expires within this many days
drbd_tls_config_file: /etc/tlshd-drbd.conf  # tlshd's config, loaded by tlshd -c (a drop-in)
drbd_tls_loglevel: 0             # tlshd [debug] loglevel
drbd_tls_kernel_check: true      # stop before any change if the kernel lacks an option below
drbd_tls_kernel_config: auto     # auto: /boot/config-<running kernel>, then /proc/config.gz
drbd_tls_kernel_options:
  - CONFIG_TLS
  - CONFIG_NET_HANDSHAKE
```

Kernel TLS is tested in CI on Debian 12 and 13, with LINBIT's ktls-utils 1.5.x (their Debian suites carry it). LINBIT's Ubuntu PPA carries no ktls-utils: on Ubuntu the role installs the distribution's own (older) package, untested, and a `1.5.*` pin matches nothing.

DRBD 9.2.6 and later encrypt a connection with the kernel's TLS when its net section says `tls yes;`. The kernel hands the handshake to `tlshd` (from ktls-utils) through its handshake upcall, and once the keys are agreed the data path stays in the kernel. drbd-utils 9.26 or later is needed to parse the option. With `drbd_tls: true` the role:

- checks before any change that the kernel config sets every `drbd_tls_kernel_options` entry to `y` or `m`;
- installs `drbd_tls_packages` and `openssl` (LINBIT's Debian suites ship a newer ktls-utils than Debian; pin it with `drbd_apt_pins: {ktls-utils: "1.5.*"}`);
- refuses to touch tlshd unless the three files exist (a symlink counts as its target), are PEM, the certificate chains to a certificate of the CA file (an intermediate alone is enough, as for tlshd), is valid for `drbd_tls_cert_min_days`, matches the key, and the key is owned by root with mode 0600 or 0640 (0400 and 0440 pass too);
- writes `drbd_tls_config_file` (mode 0600, with the role's first line), which presents the certificate and trusts the CA on both ends of a handshake, `[authenticate.client]` and `[authenticate.server]`;
- adds a drop-in, `/etc/systemd/system/tlshd.service.d/50-drbd-role.conf`, so `tlshd -c` reads that file whichever ktls-utils version runs (1.0 reads `/etc/tlshd.conf`, 1.1 and later `/etc/tlshd/config`); the package's own file is left untouched;
- loads `tls` now (with `drbd_module_load`) and at boot (`/etc/modules-load.d/drbd-tls.conf`);
- enables tlshd and checks it is still running two seconds after its start.

tlshd reads its config and the files once, at start. The config holds the SHA-256 of the certificate, key and CA, so a renewed certificate changes it and the role restarts tlshd. Nothing else restarts it. Peer authentication is tlshd's (ktls-utils 1.5.0, `server.c` and `client.c`): the connecting side requires a server certificate that chains to its truststore and matches the peer name. The listening side asks for a client certificate and verifies one that is offered, but a client that sends none is not refused by tlshd, so keep DRBD's own peer authentication (`cram-hmac-alg` and `shared-secret`) on as well. tlshd serves every kernel TLS user on the host (NFS, NVMe-TCP as well as DRBD), so set the files to suit them all.

The role never sets DRBD's `tls` option itself. With plain DRBD, add it to the resource and apply it:

```
resource r0 {
  net { tls yes; }
  ...
}
```

Run `drbdadm disconnect r0; drbdadm adjust r0` on both nodes: turning TLS on or off is not an online change. With LINSTOR, set `DrbdOptions/Net/tls yes` (`linstor resource-group drbd-options --tls yes <group>`, or per resource definition), then disconnect and adjust each resource the same way. `drbd_tls: false` (the default) removes the role's config, drop-in and module file (only with the role's first line) and restarts a running tlshd on the package's config. ktls-utils stays installed, since another kernel TLS user may need it.

## 🎯 Usage Examples

### Pin the source and key in your inventory

```yaml
drbd_apt_suite: proxmox-9
drbd_apt_components:
  - drbd-9
drbd_apt_key_fingerprint: 4E5385546726D13CB649872CFC05A31DB826FE48
```

### A local mirror of LINBIT's repository

```yaml
drbd_apt_repo_url: https://mirror.example.com/linbit/public/
drbd_apt_key_url: https://mirror.example.com/linbit/linbit-keyring.deb
drbd_apt_key_deb_member: ./etc/apt/trusted.gpg.d/linbit-keyring.gpg
drbd_apt_key_fingerprint: 4E5385546726D13CB649872CFC05A31DB826FE48
```

### Proxmox VE, which already has LINBIT's source

```yaml
drbd_install_method: distribution
drbd_kernel_headers_package: proxmox-default-headers
```

### DRBD resources taken down after the VMs at shutdown

```yaml
drbd_graceful_shutdown: true
drbd_graceful_shutdown_before:
  - example-guests.service
```

### An offline or firewalled host

```yaml
drbd_dkms_spaas: false
drbd_dkms_local_spatch: true
```

### Hold back release candidates from the PPA

```yaml
drbd_apt_pins:
  drbd-utils: "9.35.*"
```

### Replication over kernel TLS, with LINBIT's ktls-utils

```yaml
drbd_tls: true
drbd_tls_certificate: /etc/ssl/drbd/node.example.com.pem
drbd_tls_private_key: /etc/ssl/drbd/node.example.com.key
drbd_tls_truststore: /etc/ssl/drbd/ca.pem
drbd_tls_cert_min_days: 14
drbd_apt_pins:
  ktls-utils: "1.5.*"
```

### A cluster under Pacemaker, more DRBD devices

```yaml
drbd_mask_graceful_shutdown: true
drbd_graceful_shutdown: false
drbd_module_options:
  minor_count: 256
drbd_packages_extra:
  - drbd-reactor
```

## 🔍 Check

```bash
head -1 /proc/drbd                 # version: 9.x
modinfo -F version drbd            # 9.x
modinfo -n drbd                    # /lib/modules/<release>/updates/dkms/drbd.ko*
dkms status drbd                   # drbd/<version>, <kernel>, <arch>: installed
cat /etc/apt/sources.list.d/linbit.sources
# drbd_tls: true
systemctl status tlshd             # active, ExecStart ... -c /etc/tlshd-drbd.conf
journalctl -u tlshd | grep -i handshake   # "Handshake with <peer> (<address>) was successful"
cat /proc/net/tls_stat             # TlsTxSw/TlsRxSw (or TlsTxDevice/TlsRxDevice) rise with traffic
drbdsetup show <resource> | grep tls      # tls yes;
```

## ↩️ Rollback

`drbd_state: absent` first checks that no DRBD resource is up (`/sys/block/drbd*`, `drbdsetup status`) and that purging the DRBD packages would remove nothing else (`apt-get -s purge`: `drbd-reactor`, `linstor-satellite` or another package depending on them must be removed first, or listed in `drbd_packages_extra`); either fails before any change. It then purges the DRBD packages (their DKMS builds go with them), removes the files the role wrote (`/etc/modprobe.d/drbd.conf`, `/etc/dkms/drbd.conf` and the APT pins only with the role's first line; `/etc/modules-load.d/drbd.conf`), under `drbd_install_method: linbit` only the source, the keyring and the key cache, then the graceful units' masks, wants links, drop-ins and empty drop-in directories, and the role's tlshd config, drop-in and `tls` module file. When the role's tlshd config was there, `drbd_tls_packages` are purged with the DRBD packages, under the same purge check. The headers stay (other DKMS modules may need them); a loaded module stays until the next reboot.

## 🧪 Testing

Molecule runs in Docker containers, which share the CI host's kernel: the scenarios build DRBD for the headers the distribution ships and never load it. `default` runs the role in check mode on a fresh container, converges, checks the exact source, the keyring's single key and fingerprint, that no other source names LINBIT, no LINBIT key sits in `trusted.gpg.d`, `linbit-keyring` is not installed and nothing is held, then `dkms status`, `modinfo` (9.x, from `updates/dkms`), the build made with `SPAAS=false` and a local spatch while `spaas.drbd.io` resolves nowhere, the files, the APT pin, `modprobe drbd` refused outside a DKMS build; every graceful unit wanted, active and ordered after the guests; it reruns for idempotence, masks the graceful units (no longer wanted), checks the null defaults leave the masks and an admin's `modprobe.d` file alone, wires the units again and drops a dangling wants link, then runs `drbd_state: absent` with a resource up and with a package depending on drbd-utils (both must stop before the purge), under method `distribution` (the source stays), and finally checks everything is gone. `failure` (Debian 13) runs the role on a key download that also holds a secret key and with a wrong fingerprint (each must stop before the source or the keyring is written), with the headers removed (it must stop on DKMS and show its output), and with a broken kernel Makefile (it must show the end of `make.log`). `graceful` (Debian 12 only) pins `drbd-utils` to 9.34.x from LINBIT's proxmox-8 suite and checks the single `drbd-graceful-shutdown` unit is wanted from boot, active and ordered after the guests; it then upgrades `drbd-utils` to 9.35 behind the role's back (the old unit goes, its wants link dangles), reruns the role pinned to 9.35 and checks the dangling link and stale drop-in are gone and `drbd-graceful-down` and `drbd-graceful-disconnect` are wanted, active and ordered, then absent leaves nothing. `tls` (Debian 12 and 13) runs two peers with certificates from a throwaway CA and ktls-utils pinned to LINBIT's 1.5.x. It runs check mode on fresh containers, converges, and checks the config (paths in both sections, mode 0600, the files' hashes), the drop-in, that tlshd runs with `-c` on it and is enabled, the `tls` module file, and a GnuTLS handshake between the peers (the library tlshd uses), both ends presenting and verifying a certificate, with exactly those files (gnutls-serv requires the client certificate, which tlshd's server does not: see below). It then reruns for idempotence; checks that a rerun does not restart tlshd while a re-issued certificate does (on that peer only); checks that a client certificate from another CA is refused; checks that `drbd_tls: false` removes the role's files and keeps ktls-utils; and finally checks that absent purges ktls-utils. `tls-failure` (Debian 13) runs the role on a kernel config without `CONFIG_NET_HANDSHAKE` and on a missing kernel config (both must stop before any change), then on a missing certificate, one that is not PEM, one expired, one expiring within `drbd_tls_cert_min_days`, one signed by another CA, a truststore of another CA (and, which must pass, a truststore holding only an intermediate CA, and a key that is a symlink; a certificate of a sibling intermediate against that truststore must fail), a key that does not match, a key with mode 0644 and a key not owned by root: each must stop on its own check with its own message, before tlshd's config is written. `tests/validate.test.sh` feeds good and bad inputs to the role's checks.

Containers cannot prove a real DRBD connection over TLS. The kernel, its `tls` module and the handshake upcall belong to the CI host, and no DRBD module loads in a container. That leaves these checks for the target host: the kernel options of the running kernel; `tls` loading; DRBD's handshake upcall reaching tlshd, which then shows `Handshake with ... was successful` in its journal; tlshd's checks of the peer's name against its certificate (the client side passes the name DRBD gives it to GnuTLS, so the certificate needs a matching SAN); the `/proc/net/tls_stat` counters rising; no plaintext on the wire (`tcpdump` while writing a known string); a peer from another CA, or tlshd stopped, keeping the connection down; and the reconnection after a reboot.

```bash
# One distribution
./run-tests.sh debian13

# Every supported distribution, in parallel (logs in .molecule-logs/)
make molecule-test-all

# The failure paths
./run-tests.sh -s failure debian13

# The 9.34 to 9.35 graceful units (Debian 12)
./run-tests.sh -s graceful

# Kernel TLS: tlshd on two peers, then its failure paths
./run-tests.sh -s tls debian13
./run-tests.sh -s tls-failure debian13

# Lint and input tests
source .venv/bin/activate && yamllint . && ansible-lint && shellcheck run-tests.sh tests/*.sh molecule/tls/files/*.sh && tests/validate.test.sh
```

## 🚢 Releases

Once CI passes on `main`, [semantic-release](https://github.com/semantic-release/semantic-release) cuts the version from [Conventional Commits](https://www.conventionalcommits.org/): `fix:` releases a patch, `feat:` a minor, a `!` or `BREAKING CHANGE:` footer a major. A squash merge lands the pull request title (checked in CI). Each release gets a bare semver tag (`1.2.3`) and GitHub release notes; install a tag with `version:` in `requirements.yml` (Quick Start). [Renovate](https://docs.renovatebot.com/) keeps the tooling and the pinned GitHub Actions up to date.

## 📦 Dependencies

- ✅ **Ansible Core Modules** (built-in)
- ✅ **OS packages** `gpg`, `ca-certificates`, the headers metapackage, `drbd-dkms` (pulls `dkms` and a compiler), `drbd-utils`
- ✅ **Collection** `community.general` (`modprobe`), from `requirements.yml`

## 👥 Authors & Contributors

**Cédric Farinazzo** ([@cedricfarinazzo](https://github.com/cedricfarinazzo)) - *Author and Maintainer*
