# Define supported distributions
SUPPORTED_DISTROS := debian12 debian13 ubuntu2404 ubuntu2604
DEFAULT_DISTRO := debian13

.PHONY: molecule-test molecule-test-all molecule-test-failure molecule-test-graceful lint help check-prereqs test

help:
	@echo "Available targets:"
	@echo "  molecule-test              - Run molecule tests with default distro ($(DEFAULT_DISTRO))"
	@echo "  test                       - Alias for molecule-test"
	@echo "  molecule-test-all          - Run molecule tests against all supported distributions, in parallel"
	@echo "  molecule-test-<distro>     - Run molecule tests against specific distribution"
	@echo "  molecule-test-failure      - Run the failure scenario (wrong key, missing headers, broken build) on $(DEFAULT_DISTRO)"
	@echo "  molecule-test-graceful     - Run the graceful scenario (drbd-utils 9.34 to 9.35 units) on debian12"
	@echo "  lint                       - Run ansible-lint"
	@echo "  help                       - Show this help message"
	@echo ""
	@echo "Supported distributions:"
	@for distro in $(SUPPORTED_DISTROS); do \
		echo "  - $$distro"; \
	done
	@echo ""
	@echo "Examples:"
	@echo "  make test                             # Test with $(DEFAULT_DISTRO)"
	@echo "  make molecule-test                    # Test with $(DEFAULT_DISTRO)"
	@echo "  make molecule-test-ubuntu2404         # Test with Ubuntu 24.04"
	@echo "  make molecule-test-all                # Test all distributions"

molecule-test: check-prereqs
	@echo "Running molecule tests with default distribution: $(DEFAULT_DISTRO)"
	./run-tests.sh $(DEFAULT_DISTRO)

# Convenience alias
test: molecule-test

molecule-test-all: check-prereqs
	@echo "Running molecule tests against all supported distributions, in parallel..."
	./run-tests.sh $(SUPPORTED_DISTROS)

molecule-test-failure: check-prereqs
	./run-tests.sh -s failure $(DEFAULT_DISTRO)

molecule-test-graceful: check-prereqs
	./run-tests.sh -s graceful debian12

# Individual distribution targets
molecule-test-%: check-prereqs
	./run-tests.sh $*

lint:
	ansible-lint

# A target that allows to check for prerequisites
check-prereqs:
	@echo "Checking prerequisites..."
	@command -v ansible >/dev/null 2>&1 || { echo "Ansible is not installed"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "Docker is not installed"; exit 1; }
	@echo "All prerequisites are installed"
