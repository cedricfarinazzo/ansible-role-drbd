#!/usr/bin/env bash
# The role's input checks: each bad input fails before anything changes, the good ones pass.
# Runs tasks/validate.yml on localhost; needs ansible-playbook on PATH, no host.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/roles"
ln -s "$REPO" "$WORK/roles/drbd"
# Facts of a Debian 13 host, so the default LINBIT source resolves whatever runs the test
cat > "$WORK/play.yml" <<'PLAY'
- name: Validate drbd inputs
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Facts of a Debian 13 host
      ansible.builtin.set_fact:
        ansible_facts:
          distribution: "{{ molecule_distribution | default('Debian') }}"
          distribution_release: "{{ molecule_release | default('trixie') }}"
          kernel: 6.12.116+deb13-amd64

    - name: Validate
      ansible.builtin.include_role:
        name: drbd
        tasks_from: validate.yml
PLAY
fails=0
run() { ANSIBLE_ROLES_PATH=$WORK/roles ansible-playbook -i localhost, -c local -e "$1" "$WORK/play.yml" > "$WORK/out" 2>&1; }
good() { if run "$2"; then echo "ok   accepted: $1"; else echo "FAIL rejected a good input: $1" >&2; tail -5 "$WORK/out" >&2; fails=$((fails + 1)); fi; }
# Rejected by an assert, never by a templating crash: that would pass for the wrong reason.
bad() {
  if run "$2"; then echo "FAIL accepted: $1" >&2; fails=$((fails + 1))
  elif grep -qE '"assertion"|Action failed: ' "$WORK/out"; then echo "ok   rejected: $1"
  else echo "FAIL failed without an assertion: $1" >&2; grep -m3 -E 'ERROR|fatal' "$WORK/out" >&2; fails=$((fails + 1)); fi
}

good "defaults on Debian 13" '{}'
good "defaults on Debian 12" '{"molecule_release": "bookworm"}'
good "defaults on Ubuntu 24.04" '{"molecule_distribution": "Ubuntu", "molecule_release": "noble"}'
good "a fingerprint with spaces, lower case" '{"drbd_apt_key_fingerprint": "4e53 8554 6726 d13c b649 872c fc05 a31d b826 fe48"}'
good "a custom source and key" '{"drbd_apt_repo_url": "https://mirror.example/linbit/", "drbd_apt_suite": "proxmox-9", "drbd_apt_components": ["drbd-9"], "drbd_apt_key_url": "https://mirror.example/linbit.asc", "drbd_apt_key_fingerprint": "4E5385546726D13CB649872CFC05A31DB826FE48"}'
good "distribution packages on an unknown release" '{"drbd_install_method": "distribution", "molecule_release": "forky"}'
good "state absent on an unknown distribution" '{"drbd_state": "absent", "molecule_distribution": "Fedora"}'
good "every option set" '{"drbd_packages_extra": ["drbd-reactor"], "drbd_kernel_headers_package": "linux-headers-cloud-amd64", "drbd_dkms_kernels": ["6.12.116+deb13-amd64", "6.12.120+deb13-amd64"], "drbd_module_load": false, "drbd_module_load_at_boot": false, "drbd_module_options": {"minor_count": 64, "usermode_helper": "disabled"}, "drbd_usage_count": true, "drbd_mask_graceful_shutdown": true, "drbd_dkms_log_lines": 100}'
good "graceful shutdown, ordered" '{"drbd_graceful_shutdown": true, "drbd_graceful_shutdown_wanted_by": "drbd-cluster.target", "drbd_graceful_shutdown_before": ["example-guests.service", "srv-data.mount"]}'
good "no headers package" '{"drbd_kernel_headers_package": ""}'
bad "an unknown state" '{"drbd_state": "latest"}'
bad "an unknown install method" '{"drbd_install_method": "source"}'
bad "a relative keyring" '{"drbd_apt_keyring": "linbit.gpg"}'
bad "no packages" '{"drbd_packages": []}'
bad "packages as a string" '{"drbd_packages": "drbd-dkms"}'
bad "a package name with a space" '{"drbd_packages_extra": ["drbd reactor"]}'
bad "a headers package with a space" '{"drbd_kernel_headers_package": "linux headers"}'
bad "kernels as a string" '{"drbd_dkms_kernels": "6.12.116+deb13-amd64"}'
bad "a kernel with a slash" '{"drbd_dkms_kernels": ["../6.12"]}'
bad "module load as a string" '{"drbd_module_load": "yes"}'
bad "boot load as a string" '{"drbd_module_load_at_boot": "yes"}'
bad "module options as a list" '{"drbd_module_options": ["minor_count=64"]}'
bad "an upper-case module option" '{"drbd_module_options": {"MINOR": 1}}'
bad "a module option value with a space" '{"drbd_module_options": {"minor_count": "6 4"}}'
bad "usage count as a string" '{"drbd_usage_count": "no"}'
bad "mask as a string" '{"drbd_mask_graceful_shutdown": "true"}'
bad "graceful shutdown as a string" '{"drbd_graceful_shutdown": "yes"}'
bad "graceful shutdown and mask together" '{"drbd_graceful_shutdown": true, "drbd_mask_graceful_shutdown": true}'
bad "wanted by a service" '{"drbd_graceful_shutdown_wanted_by": "sshd.service"}'
bad "before as a string" '{"drbd_graceful_shutdown_before": "example-guests.service"}'
bad "before a unit with a space" '{"drbd_graceful_shutdown_before": ["example guests.service"]}'
bad "zero log lines" '{"drbd_dkms_log_lines": 0}'
bad "log lines not a number" '{"drbd_dkms_log_lines": "all"}'
bad "no LINBIT source for the release" '{"molecule_release": "forky"}'
bad "no LINBIT source for the distribution" '{"molecule_distribution": "Fedora", "molecule_release": "43"}'
bad "a short fingerprint" '{"drbd_apt_key_fingerprint": "FC05A31DB826FE48"}'
bad "a fingerprint that is not hex" '{"drbd_apt_key_fingerprint": "4E5385546726D13CB649872CFC05A31DB826FE4Z"}'
bad "a key over plain http" '{"drbd_apt_key_url": "http://packages.example/linbit.asc"}'
bad "a source URL without its final slash" '{"drbd_apt_repo_url": "http://packages.example/public"}'
bad "a suite with a space" '{"drbd_apt_suite": "proxmox 9"}'
bad "components as a string" '{"drbd_apt_components": "drbd-9"}'
bad "a deb member with a space" '{"drbd_apt_key_url": "https://mirror.example/k.deb", "drbd_apt_key_deb_member": "./etc/a b.gpg"}'

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"
