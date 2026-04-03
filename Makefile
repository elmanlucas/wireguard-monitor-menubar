PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

.PHONY: build install uninstall clean

build:
	swiftc -O -o wireguard-monitor-menubar Sources/main.swift -framework AppKit

install: build
	install -d $(BINDIR)
	install -m 755 wireguard-monitor-menubar $(BINDIR)/wireguard-monitor-menubar

uninstall:
	rm -f $(BINDIR)/wireguard-monitor-menubar

clean:
	rm -f wireguard-monitor-menubar
