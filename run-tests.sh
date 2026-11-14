#!/usr/bin/env bash
# Runs the Molecule scenario on one or more distributions; several run in parallel, one log each.
set -uo pipefail

SUPPORTED="debian12 debian13 ubuntu2404 ubuntu2604"
SCENARIO=default

show_usage() {
    echo "Usage: $0 [-s SCENARIO] [DISTRO...] | all"
    echo
    echo "Run a Molecule scenario of the drbd role (default: the default scenario on debian13)."
    echo "Scenarios: default (LINBIT source, DKMS build, idempotence, then state absent),"
    echo "failure (a wrong key fingerprint, missing kernel headers, a broken kernel Makefile: the role must stop),"
    echo "graceful (Debian 12 only: drbd-utils pinned to 9.34, then upgraded across the 9.35 unit split)."
    echo "Several distributions, or 'all', run in parallel; each writes .molecule-logs/<scenario>-<distro>.log."
    echo
    echo "Supported: ${SUPPORTED// /, }"
    echo
    echo "Examples:"
    echo "  $0                       # Debian 13"
    echo "  $0 ubuntu2404            # Ubuntu 24.04"
    echo "  $0 all                   # every supported distribution, in parallel"
    echo "  $0 -s failure debian13   # the failure paths"
    echo "  $0 -s graceful           # the 9.34 to 9.35 graceful units (Debian 12)"
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then show_usage; exit 0; fi
if [[ ${1:-} == -s || ${1:-} == --scenario ]]; then SCENARIO=${2:?scenario name}; shift 2; fi
if [[ ! -d molecule/$SCENARIO ]]; then echo "Unknown scenario: $SCENARIO"; show_usage; exit 1; fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
VENV_PATH=.venv

distros=("$@")
# graceful needs LINBIT's proxmox-8 suite, the only public one with drbd-utils 9.34 and 9.35 side by side
if [[ $SCENARIO == graceful ]]; then SUPPORTED=debian12; fi
default_distro=debian13
if [[ $SCENARIO == graceful ]]; then default_distro=debian12; fi
if [[ ${#distros[@]} -eq 0 ]]; then distros=("$default_distro"); fi
if [[ ${distros[*]} == all ]]; then read -ra distros <<< "$SUPPORTED"; fi
for d in "${distros[@]}"; do
    if [[ " $SUPPORTED " != *" $d "* ]]; then echo -e "${RED}Unsupported distribution: $d${NC}"; show_usage; exit 1; fi
done

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Docker is required for molecule tests.${NC}"
    exit 1
fi
if ! docker info &> /dev/null; then
    echo -e "${RED}Docker is not running. Please start Docker daemon.${NC}"
    exit 1
fi

# Once, before any run: the runs share .venv and the collections
if [ ! -d "${VENV_PATH}" ]; then python3 -m venv "${VENV_PATH}"; fi
if ! "${VENV_PATH}/bin/pip" install --quiet -r requirements-dev.txt; then
    echo -e "${RED}Failed to install the tooling from requirements-dev.txt.${NC}"
    exit 1
fi
if ! "${VENV_PATH}/bin/ansible-galaxy" collection install -r requirements.yml; then
    echo -e "${RED}Failed to install Ansible collections.${NC}"
    exit 1
fi
# shellcheck source=/dev/null
source "${VENV_PATH}/bin/activate"
export MOLECULE_NO_LOG=false MOLECULE_ROLE_NAME_CHECK=0

# One distribution: containers, network and Molecule state are suffixed with it, so runs never collide
run_one() {
    local d=$1
    docker pull --quiet "geerlingguy/docker-${d}-ansible:latest" > /dev/null || return 1
    MOLECULE_DISTRO=$d MOLECULE_EPHEMERAL_DIRECTORY="${HOME}/.cache/molecule/ansible-role-drbd/${SCENARIO}-${d}" \
        molecule test -s "$SCENARIO"
}

if [[ ${#distros[@]} -eq 1 ]]; then
    echo -e "${YELLOW}Running the ${SCENARIO} scenario on ${distros[0]}...${NC}"
    if run_one "${distros[0]}"; then echo -e "${GREEN}Tests completed successfully!${NC}"; exit 0; fi
    echo -e "${RED}Tests failed.${NC}"
    exit 1
fi

mkdir -p .molecule-logs
declare -A pids
for d in "${distros[@]}"; do
    echo -e "${YELLOW}Starting ${SCENARIO} on ${d} (.molecule-logs/${SCENARIO}-${d}.log)${NC}"
    run_one "$d" > ".molecule-logs/${SCENARIO}-${d}.log" 2>&1 &
    pids[$d]=$!
done
failed=()
for d in "${distros[@]}"; do
    if wait "${pids[$d]}"; then echo -e "${GREEN}${d}: passed${NC}"; else echo -e "${RED}${d}: failed (.molecule-logs/${SCENARIO}-${d}.log)${NC}"; failed+=("$d"); fi
done
if [[ ${#failed[@]} -gt 0 ]]; then echo -e "${RED}Failed: ${failed[*]}${NC}"; exit 1; fi
echo -e "${GREEN}All distributions passed.${NC}"
