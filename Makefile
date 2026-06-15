.PHONY: build test verify-arch clean help

help:
	@echo "ReLay Build Commands"
	@echo "  make build          - Build ReLay (with architecture check)"
	@echo "  make test           - Run tests (with architecture check)"
	@echo "  make verify-arch    - Verify architecture only"
	@echo "  make clean          - Clean build artifacts"

verify-arch:
	@bash Sources/ReLayCore/Scripts/verify_architecture.sh

build: verify-arch
	swift build

test: verify-arch
	swift test

clean:
	rm -rf .build
