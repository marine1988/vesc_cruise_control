VESC_TOOL ?= $(if $(wildcard ./vesc_tool),./vesc_tool,vesc_tool)

VERSION := $(shell cat version)
PKG = vesc_cruise_control_v$(VERSION).vescpkg
TMP = vesc_cruise_control.vescpkg

all: $(PKG)

$(PKG): pkgdesc.qml ui.qml cruise_control.lisp README.md version
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'vesc:maxim 120' --testPkgDesc 'vesc:pronto'
	mv $(TMP) $(PKG)

clean:
	rm -f $(TMP) vesc_cruise_control_v*.vescpkg

.PHONY: all clean
