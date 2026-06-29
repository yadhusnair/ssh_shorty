.PHONY: release tag

VERSION := $(shell cat VERSION)

# Create a git tag and push it — triggers the GitHub Actions release workflow
release:
	@echo "Releasing v$(VERSION)..."
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@git push origin "v$(VERSION)"
	@echo "Tag pushed — GitHub Actions will build the release and update Homebrew."
	@echo "Watch: https://github.com/yadhusnair/ssh_shorty/actions"
