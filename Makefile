DESTDIR ?= /
prefix ?= $(DESTDIR)
bindir=/usr/bin
datadir ?= /usr/share
sysconfdir ?= /etc
systemd_unitdir ?= /lib/systemd
docexamplesdir ?= /usr/share/doc/mender-client/examples

GO ?= go
GOFMT ?= gofmt
V ?=
PKGS = $(shell go list ./... | grep -v vendor)
PKGFILES = $(shell find . \( -path ./vendor -o -path ./Godeps \) -prune \
		-o -type f -name '*.go' -print)
PKGFILES_notest = $(shell echo $(PKGFILES) | tr ' ' '\n' | grep -v '\(client/test\|_test.go\)' )
GOCYCLO ?= 15

CGO_ENABLED=1
export CGO_ENABLED

# Get rid of useless warning in lmdb
CGO_CFLAGS ?= -Wno-implicit-fallthrough -Wno-stringop-overflow
export CGO_CFLAGS

TOOLS = \
	github.com/fzipp/gocyclo/... \
	gitlab.com/opennota/check/cmd/varcheck \
	github.com/mendersoftware/deadcode \
	github.com/mendersoftware/gobinarycoverage \
	github.com/jstemmer/go-junit-report

VERSION = $(shell git describe --tags --dirty --exact-match 2>/dev/null || git rev-parse --short HEAD)

GO_LDFLAGS = \
	-ldflags "-X github.com/mendersoftware/mender/conf.Version=$(VERSION)"

ifeq ($(V),1)
BUILDV = -v
endif

TAGS =
ifeq ($(LOCAL),1)
TAGS += local
endif

ifneq ($(TAGS),)
BUILDTAGS = -tags '$(TAGS)'
endif

IDENTITY_SCRIPTS = \
	support/mender-device-identity

INVENTORY_SCRIPTS = \
	support/mender-inventory-bootloader-integration \
	support/mender-inventory-hostinfo \
	support/mender-inventory-network \
	support/mender-inventory-os \
	support/mender-inventory-provides \
	support/mender-inventory-rootfs-type \
	support/mender-inventory-update-modules

INVENTORY_NETWORK_SCRIPTS = \
	support/mender-inventory-geo

MODULES = \
	support/modules/deb \
	support/modules/docker \
	support/modules/directory \
	support/modules/single-file \
	support/modules/rpm \
	support/modules/script

MODULES_ARTIFACT_GENERATORS = \
	support/modules-artifact-gen/docker-artifact-gen \
	support/modules-artifact-gen/directory-artifact-gen \
	support/modules-artifact-gen/single-file-artifact-gen

DBUS_POLICY_FILES = \
	support/dbus/io.mender.AuthenticationManager.conf \
	support/dbus/io.mender.UpdateManager.conf

build: mender

mender: $(PKGFILES)
	$(GO) build $(GO_LDFLAGS) $(BUILDV) $(BUILDTAGS)

install: install-bin \
	install-conf \
	install-dbus \
	install-examples \
	install-identity-scripts \
	install-inventory-scripts \
	install-modules \
	install-systemd

install-bin: mender
	install -m 755 -d $(prefix)$(bindir)
	install -m 755 mender $(prefix)$(bindir)/

install-conf:
	install -m 755 -d $(prefix)$(sysconfdir)/mender
	echo "artifact_name=unknown" > $(prefix)$(sysconfdir)/mender/artifact_info

install-datadir:
	install -m 755 -d $(prefix)$(datadir)/mender

uninstall: uninstall-bin \
	uninstall-conf

uninstall-bin:
	rm -f $(prefix)$(bindir)/mender
	-rmdir -p $(prefix)$(bindir)

uninstall-conf:
	rm -f $(prefix)$(sysconfdir)/mender/artifact_info
	-rmdir -p $(prefix)$(sysconfdir)/mender

clean:
	$(GO) clean
	rm -f coverage.txt

get-tools:
	set -e ; for t in $(TOOLS); do \
		echo "-- go getting $$t"; \
		GO111MODULE=off go get -u $$t; \
	done

check: test extracheck

test:
	$(GO) test $(BUILDV) $(PKGS)

extracheck: gofmt govet godeadcode govarcheck gocyclo
	echo "All extra-checks passed!"

gofmt:
	echo "-- checking if code is gofmt'ed"
	if [ -n "$$($(GOFMT) -d $(PKGFILES))" ]; then \
		"$$($(GOFMT) -d $(PKGFILES))" \
		echo "-- gofmt check failed"; \
		/bin/false; \
	fi

govet:
	echo "-- checking with govet"
	$(GO) vet -composites=false -unsafeptr=false ./...

godeadcode:
	echo "-- checking for dead code"
	deadcode -ignore version.go:Version

govarcheck:
	echo "-- checking with varcheck"
	varcheck ./...

gocyclo:
	echo "-- checking cyclometric complexity > $(GOCYCLO)"
	gocyclo -over $(GOCYCLO) $(PKGFILES_notest)

cover: coverage
	$(GO) tool cover -func=coverage.txt

htmlcover: coverage
	$(GO) tool cover -html=coverage.txt

coverage:
	rm -f coverage.txt
	$(GO) test -v -coverprofile=coverage-tmp.txt -coverpkg=./... ./... > .tmp.go-test.txt ; echo $$? > .tmp.return-code.txt
	cat .tmp.go-test.txt
	go-junit-report < .tmp.go-test.txt > report.xml
	rm -f .tmp.go-test.txt
	if [ -f coverage-missing-subtests.txt ]; then \
		echo 'mode: set' > coverage.txt; \
		cat coverage-tmp.txt coverage-missing-subtests.txt | grep -v 'mode: set' >> coverage.txt; \
	else \
		mv coverage-tmp.txt coverage.txt; \
	fi
	rm -f coverage-tmp.txt coverage-missing-subtests.txt
	failing_tests=$$(grep -Po '(?<=failures=")\d+' report.xml | awk '{s+=$$1} END {print s}'); \
	echo FAILING TESTS: $$failing_tests
	return_code=$$(cat .tmp.return-code.txt); \
	rm -f .tmp.return-code.txt; \
	exit $$return_code

.PHONY: build
.PHONY: clean
.PHONY: get-tools
.PHONY: test
.PHONY: check
.PHONY: cover
.PHONY: htmlcover
.PHONY: coverage
.PHONY: install
.PHONY: install-bin
.PHONY: install-conf
.PHONY: install-datadir
.PHONY: uninstall
.PHONY: uninstall-bin
.PHONY: uninstall-conf
