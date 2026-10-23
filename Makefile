PREFIX ?= $(HOME)/.local
ODIN ?= odin

pasians: $(wildcard *.odin game/*.odin) extras/theme-set-hook
	$(ODIN) build . -out:pasians -o:speed

test:
	$(ODIN) test game -o:speed

install: pasians
	install -Dm755 pasians $(PREFIX)/bin/pasians
	install -Dm644 extras/pasians.desktop $(PREFIX)/share/applications/pasians.desktop
	install -Dm644 extras/pasians.svg $(PREFIX)/share/icons/hicolor/scalable/apps/pasians.svg
	@if [ -d $(HOME)/.config/omarchy ]; then $(PREFIX)/bin/pasians --install-hook; fi
	@if [ -d $(HOME)/.config/hypr ]; then \
	  install -Dm644 extras/hypr.lua $(HOME)/.config/hypr/pasians.lua; \
	  echo 'Add require("hypr.pasians") to ~/.config/hypr/hyprland.lua for the floating window rule.'; \
	fi

uninstall:
	rm -f $(PREFIX)/bin/pasians $(PREFIX)/share/applications/pasians.desktop \
	  $(PREFIX)/share/icons/hicolor/scalable/apps/pasians.svg \
	  $(HOME)/.config/omarchy/hooks/theme-set.d/pasians

clean:
	rm -f pasians

.PHONY: test install uninstall clean
