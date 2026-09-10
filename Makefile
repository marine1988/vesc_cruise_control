VESC_TOOL ?= $(if $(wildcard ./vesc_tool),./vesc_tool,vesc_tool)

PKG = vesc_cruise_control.vescpkg

all: $(PKG)

$(PKG): pkgdesc.qml ui.qml cruise_control.lisp README.md version
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'vesc:maxim 120' --testPkgDesc 'vesc:pronto'

clean:
	rm -f $(PKG)

.PHONY: all clean
