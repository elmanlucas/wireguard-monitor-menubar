PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

.PHONY: build install uninstall clean

build:
	swiftc -O -o wireguard-monitor Sources/main.swift -framework AppKit

install: build
	install -d $(BINDIR)
	install -m 755 wireguard-monitor $(BINDIR)/wireguard-monitor

uninstall:
	rm -f $(BINDIR)/wireguard-monitor

clean:
	rm -f wireguard-monitor
