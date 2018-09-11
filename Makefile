# This Makefile was copied (with modification) from:
# https://raw.githubusercontent.com/genuinetools/bane/master/Makefile
# ...which was authored by https://github.com/jessfraz


### CONFIG


# Setup name variables for the package/tool
NAME := ghlatest
PKG := github.com/airplanefood/$(NAME)
TARGETS := $(shell for osarch in \
               darwin-amd64 \
               freebsd-386 freebsd-amd64 \
               linux-386 linux-amd64 linux-arm linux-arm64 \
               windows-amd64; \
             do echo "builds/$(NAME)-$$osarch"; done)

# Set any default go build tags
GO := go
BUILDTAGS :=

# Populate version variables
# Add to compile time flags
VERSION := $(shell cat VERSION.txt)
GITCOMMIT := $(shell git rev-parse --short HEAD)
GITUNTRACKEDCHANGES := $(shell git status --porcelain --untracked-files=no)
ifneq ($(GITUNTRACKEDCHANGES),)
	GITCOMMIT := $(GITCOMMIT)-dirty
endif
CTIMEVAR=-X main.GITCOMMIT=$(GITCOMMIT) -X main.VERSION=$(VERSION)
GO_LDFLAGS=-ldflags "-w $(CTIMEVAR)"
GO_LDFLAGS_STATIC=-ldflags "-w $(CTIMEVAR) -extldflags -static"
BUILDDIR := builds


### PRODUCTIVE TARGETS


.PHONY: build
build: $(NAME) ## Builds a dynamic executable or package (default target)


.PHONY: static
static: ## Builds a static executable
	@echo "+ $@"
	CGO_ENABLED=0 \
	$(GO) build \
	  -tags "$(BUILDTAGS) static_build" \
	  ${GO_LDFLAGS_STATIC} \
	  -o $(NAME) \
	  .


.PHONY: all
all: clean build fmt lint test staticcheck vet install ## Runs a clean, build, fmt, lint, test, staticcheck, vet and install


.PHONY: release
release: $(TARGETS) ## Build cross-compiled binaries for target architectures


AUTHORS: $(wildcard *.go) $(wildcard */*.go) VERSION.txt ## Generate the AUTHORS file from the git log
	@echo "+ $@"
	@printf '%s\n' \
	  '# This file lists everyone with commits to this repository (sorted alphabetically).' \
	  '# It is automatically updated with the `make AUTHORS` command.' \
	  "$$(git log --format='%aN <%aE>' | LC_ALL=C.UTF-8 sort -uf)" \
	  | tee $@


### DYNAMIC PRODUCTIVE TARGETS


# matches yourprogram
$(NAME): $(wildcard *.go) $(wildcard */*.go) VERSION.txt
	@echo "+ $@"
	$(GO) build \
	  -tags "$(BUILDTAGS)" \
	  ${GO_LDFLAGS} \
	  -o $(NAME) \
	  .


# matches targets like "builds/yourprogram-linux-amd64"
$(BUILDDIR)/% $(BUILDDIR)/%.md5 $(BUILDDIR)/%.sha256 : $(wildcard *.go) $(wildcard */*.go) VERSION.txt
	GOOS=$$(printf '%s' "$@" | cut -f 2 -d '-') \
	GOARCH=$$(printf '%s' "$@" | cut -f 3 -d '-') \
	CGO_ENABLED=0 \
	$(GO) build \
	  -a \
	  -tags "$(BUILDTAGS) static_build netgo" \
	  -installsuffix netgo \
	  ${GO_LDFLAGS_STATIC} \
	  -o "$@" \
	  .
	@md5sum "$@" | tee "$@.md5"
	@sha256sum "$@" | tee "$@.sha256"
	@printf '\n\n'


### VALIDATION TARGETS


.PHONY: fmt
fmt: ## Verifies all files have been `gofmt`ed
	@echo "+ $@"
	@gofmt -s -l . 2>&1 \
	  | grep -Ev '(.pb.go:|vendor)' \
	  | tee /dev/stderr \
	  | [ "$$(wc -c)" = "0" ]


.PHONY: lint
lint: ## Verifies `golint` passes
	@echo "+ $@"
	@golint ./... 2>&1 \
	  | grep -Ev '(.pb.go:|vendor)' \
	  | tee /dev/stderr \
	  | [ "$$(wc -c)" = "0" ]


.PHONY: test
test: ## Runs the go tests
	@echo "+ $@"
	@$(GO) test -v -tags "$(BUILDTAGS) cgo" $(shell $(GO) list ./... | grep -v vendor)


.PHONY: vet
vet: ## Verifies `go vet` passes
	@echo "+ $@"
	@$(GO) vet $(shell $(GO) list ./... | grep -v vendor) \
	  | grep -Ev '(.pb.go:|vendor)' \
	  | tee /dev/stderr \
	  | [ "$$(wc -c)" = "0" ]


.PHONY: staticcheck
staticcheck: ## Verifies `staticcheck` passes
	@echo "+ $@"
	@staticcheck $(shell $(GO) list ./... | grep -v vendor) \
	  | grep -Ev '(.pb.go:|vendor)' \
	  | tee /dev/stderr \
	  | [ "$$(wc -c)" = "0" ]


.PHONY: cover
cover: ## Runs go test with coverage
	@echo "" > coverage.txt
	@for d in $(shell $(GO) list ./... | grep -v vendor); do \
	  $(GO) test -race -coverprofile=profile.out -covermode=atomic "$$d"; \
	  [ -f profile.out ] || continue; \
	  cat profile.out >> coverage.txt; \
	  rm profile.out; \
	done;


### UTILITY TARGETS


.PHONY: install
install: ## Installs the executable or package
	@echo "+ $@"
	$(GO) install -a -tags "$(BUILDTAGS)" ${GO_LDFLAGS} .


.PHONY: version-bump-major
version-bump-major: ## Increment the major version number in VERSION.txt, e.g. v1.2.3 -> v2.2.3
	@echo "+ $@"
	@NEW=$$(awk -F '.' '{ print "v" substr($$1,2)+1 "." $$2 "." $$3 }' VERSION.txt) \
	  ; printf '%s\n' "$$NEW" | tee VERSION.txt


.PHONY: version-bump-minor
version-bump-minor: ## Increment the minor version number in VERSION.txt, e.g. v1.2.3 -> v1.3.3
	@echo "+ $@"
	@NEW=$$(awk -F '.' '{ print $$1 "." $$2+1 "." $$3 }' VERSION.txt) \
	  ; printf '%s\n' "$$NEW" | tee VERSION.txt


.PHONY: version-bump-patch
version-bump-patch: ## Increment the patch version number in VERSION.txt, e.g. v1.2.3 -> v1.2.4
	@echo "+ $@"
	@NEW=$$(awk -F '.' '{ print $$1 "." $$2 "." $$3+1 }' VERSION.txt) \
	  ; printf '%s\n' "$$NEW" | tee VERSION.txt


.PHONY: tag
tag: ## Create a new git tag to prepare to build a release
	@echo "+ $@"
	git tag -sa $(VERSION) -m "$(VERSION)"
	@printf '%s\n' \
	  "To push your new tag to GitHub and trigger a travis build, run:" \
	  "git push origin $(VERSION)"


.PHONY: clean
clean: ## Cleanup any build binaries or packages
	@echo "+ $@"
	$(RM) $(NAME)
	$(RM) -r $(BUILDDIR)


.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
