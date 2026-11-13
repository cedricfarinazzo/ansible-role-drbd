# 💽 Ansible Role: drbd

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-cedricfarinazzo.drbd-blue)](https://galaxy.ansible.com/cedricfarinazzo/drbd)

> **The [DRBD 9](https://linbit.com/drbd/) kernel module built by DKMS from LINBIT's public repositories, with `drbd-utils`, loaded now and at every boot.**

Most distribution kernels ship the DRBD 8.4 module only, while LINSTOR, DRBD Reactor and DRBD 9 resources need DRBD 9. This role adds LINBIT's APT source with a key it checks against a pinned fingerprint first, installs the headers of your kernel flavor, `drbd-dkms` and `drbd-utils`, and makes sure DKMS built DRBD for your kernels. Kernel updates rebuild the module through DKMS, so nothing is held.

## 🚀 Quick Start

```yaml
- hosts: storage
  become: true
  roles:
    - role: cedricfarinazzo.drbd
```

The role will:
- ✅ Download LINBIT's key, check it holds exactly one key with the pinned fingerprint, and only then write it to `/etc/apt/keyrings/linbit.gpg` and the source `/etc/apt/sources.list.d/linbit.sources` that names it with `Signed-By` (the key is trusted for that source only; LINBIT's `linbit-keyring` package is never installed)
- ✅ Install the headers metapackage of the running kernel's flavor (`linux-headers-amd64`, `linux-headers-generic`, ...), then `drbd-dkms` and `drbd-utils`, by name; nothing is held
- ✅ Check DKMS shows DRBD installed for the running kernel and the newest kernel, build it where it is not; a failed build prints the end of DKMS's `make.log`
- ✅ Load DRBD 9 now (an older DRBD module, not in use, is unloaded first) and at boot (`/etc/modules-load.d/drbd.conf`), with your module parameters
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
| **Network** | The hosts reach LINBIT's repository (or your mirror) over HTTP(S) |

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

Defaults: Debian downloads `https://packages.linbit.com/public/linbit-keyring.deb`, extracts `./etc/apt/trusted.gpg.d/linbit-keyring.gpg` and checks fingerprint `4E53 8554 6726 D13C B649 872C FC05 A31D B826 FE48`; Ubuntu fetches the PPA key `CC1B 5A79 3C04 BB39 05AD 8377 3489 3610 CEAA 9512` from `keyserver.ubuntu.com`. Pin the fingerprint in your inventory to keep a role update from moving it.

A key whose fingerprint differs, or a download with more than one key, fails the role before the source or the keyring is written, and the download is removed.

### Packages and DKMS

```yaml
drbd_packages:
  - drbd-dkms
  - drbd-utils
drbd_packages_extra: []      # e.g. [drbd-reactor]

# Headers metapackage DKMS builds against: auto = the running kernel's flavor
# (6.12.116+deb13-amd64 -> linux-headers-amd64, 6.8.0-45-generic -> linux-headers-generic); "" = none
drbd_kernel_headers_package: auto

# Kernels DKMS builds for: auto = the running kernel and the newest kernel, each when its headers are present;
# or a list of kernel releases
drbd_dkms_kernels: auto

# Lines of make.log printed when a build fails
drbd_dkms_log_lines: 40
```

A kernel release auto cannot read (no `<version>-<flavor>` form) fails, asking for `drbd_kernel_headers_package`. When DKMS stops before `make` (no headers for a listed kernel), the role prints DKMS's own output instead of `make.log`.

### Module and settings

```yaml
drbd_module_load: true          # load DRBD 9 now
drbd_module_load_at_boot: true  # /etc/modules-load.d/drbd.conf
drbd_module_options: {}         # e.g. {minor_count: 64}, in /etc/modprobe.d/drbd.conf
drbd_usage_count: false         # usage-count in /etc/drbd.d/global_common.conf; drbd-utils ships yes
drbd_mask_graceful_shutdown: false
drbd_graceful_shutdown: false                       # wire the graceful units from boot
drbd_graceful_shutdown_wanted_by: multi-user.target # the target that wants them
drbd_graceful_shutdown_before: []                   # units the graceful down waits for at shutdown
```

drbd-utils' udev rule starts its graceful units (`ExecStop` runs `drbdadm down all`) only once a DRBD device appears, whatever brought the resource up (`drbd@.service`, LINSTOR's satellite, a script). `drbd_graceful_shutdown: true` makes `drbd_graceful_shutdown_wanted_by` want each graceful unit the package ships (a link in its `.wants/`: they have no `[Install]` section) and starts them now, so every shutdown takes the resources down cleanly. `drbd_graceful_shutdown_before` (e.g. the service that stops your VMs, a mount on a DRBD device) goes into a `Before=` drop-in on the down unit: at shutdown it runs once those have stopped. `drbdadm down all` reads `/etc/drbd.conf`, so resources a tool writes elsewhere must be included from `/etc/drbd.d/` (LINSTOR's satellite package does this). `false` removes the links and the drop-in.

`drbd_mask_graceful_shutdown: true` masks `drbd-graceful-shutdown.service` (drbd-utils 9.28 to 9.34) or `drbd-graceful-down.service` and `drbd-graceful-disconnect.service` (9.35+), e.g. under Pacemaker, which stops DRBD itself; it excludes `drbd_graceful_shutdown`. `false` removes only masks (links to `/dev/null`), never a unit file of yours.

A loaded DRBD 8.4 module still in use (resources up) is never unloaded: the role fails and asks you to stop the resources first.

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

### A cluster under Pacemaker, more DRBD devices

```yaml
drbd_mask_graceful_shutdown: true
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
```

## ↩️ Rollback

`drbd_state: absent` purges the DRBD packages (their DKMS builds go with them) and removes the source, the keyring, the key cache, the module files, and the masks, wants links and drop-ins the role made. The headers stay (other DKMS modules may need them); a loaded module stays until the next reboot.

## 🧪 Testing

Molecule runs in Docker containers, which share the CI host's kernel: the scenarios build DRBD for the headers the distribution ships and never load it. `default` runs the role in check mode on a fresh container, converges, checks the exact source, the keyring's single key and fingerprint, that no other source names LINBIT, no LINBIT key sits in `trusted.gpg.d`, `linbit-keyring` is not installed and nothing is held, then `dkms status`, `modinfo` (9.x, from `updates/dkms`) and the files; the graceful units wanted, active and ordered; it reruns for idempotence, masks the graceful units (no longer wanted), then runs `drbd_state: absent` and checks everything is gone. `failure` (Debian 13) runs the role with a wrong fingerprint (it must stop before the source is written), with the headers removed (it must stop on DKMS and show its output), and with a broken kernel Makefile (it must show the end of `make.log`). `tests/validate.test.sh` feeds good and bad inputs to the role's checks.

```bash
# One distribution
./run-tests.sh debian13

# Every supported distribution, in parallel (logs in .molecule-logs/)
make molecule-test-all

# The failure paths
./run-tests.sh -s failure debian13

# Lint and input tests
source .venv/bin/activate && yamllint . && ansible-lint && shellcheck run-tests.sh tests/*.sh && tests/validate.test.sh
```

## 🚢 Releases

Once CI passes on `main`, [semantic-release](https://github.com/semantic-release/semantic-release) cuts the version from [Conventional Commits](https://www.conventionalcommits.org/): `fix:` releases a patch, `feat:` a minor, a `!` or `BREAKING CHANGE:` footer a major. A squash merge lands the pull request title (checked in CI). Each release gets a bare semver tag (`1.2.3`) and GitHub release notes; Ansible Galaxy imports the new tag from the repository. [Renovate](https://docs.renovatebot.com/) keeps the tooling and the pinned GitHub Actions up to date.

## 📦 Dependencies

- ✅ **Ansible Core Modules** (built-in)
- ✅ **OS packages** `gpg`, `ca-certificates`, the headers metapackage, `drbd-dkms` (pulls `dkms` and a compiler), `drbd-utils`
- ✅ **Collection** `community.general` (`modprobe`), from `requirements.yml`

## 👥 Authors & Contributors

**Cédric Farinazzo** ([@cedricfarinazzo](https://github.com/cedricfarinazzo)) - *Author and Maintainer*
