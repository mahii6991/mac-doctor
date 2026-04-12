# Mac Doctor — Makefile
# Usage:
#   sudo make install      Install mac-doctor to /usr/local/bin
#   sudo make uninstall    Remove mac-doctor and LaunchAgent
#   make schedule          Install weekly scan LaunchAgent (no sudo needed)
#   make unschedule        Remove LaunchAgent only

PREFIX     ?= /usr/local
BINDIR      = $(PREFIX)/bin
PLIST_NAME  = com.macdoctor.scan.plist
LAUNCHD_DIR = $(HOME)/Library/LaunchAgents
SHARE_DIR   = $(HOME)/.mac-doctor

.PHONY: install uninstall schedule unschedule

install:
	@echo "Installing mac-doctor to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@cp mac-doctor.sh $(BINDIR)/mac-doctor
	@chmod 755 $(BINDIR)/mac-doctor
	@echo ""
	@echo "  Done. Run:  mac-doctor"
	@echo "  Optional:   make schedule   (weekly scan with macOS notifications)"
	@echo ""

uninstall: unschedule
	@echo "Removing mac-doctor..."
	@rm -f $(BINDIR)/mac-doctor
	@rm -f $(SHARE_DIR)/mac-doctor-notify.sh
	@echo "  Done. mac-doctor removed."

schedule:
	@echo "Installing weekly scan LaunchAgent..."
	@mkdir -p $(SHARE_DIR)
	@mkdir -p $(LAUNCHD_DIR)
	@cp packaging/launchd/mac-doctor-notify.sh $(SHARE_DIR)/mac-doctor-notify.sh
	@chmod 755 $(SHARE_DIR)/mac-doctor-notify.sh
	@sed "s|__NOTIFY_SCRIPT__|$(SHARE_DIR)/mac-doctor-notify.sh|g" \
		packaging/launchd/$(PLIST_NAME) > $(LAUNCHD_DIR)/$(PLIST_NAME)
	@launchctl unload $(LAUNCHD_DIR)/$(PLIST_NAME) 2>/dev/null || true
	@launchctl load $(LAUNCHD_DIR)/$(PLIST_NAME)
	@echo ""
	@echo "  Done. Mac Doctor will scan every Sunday at 10:00 AM."
	@echo "  You will get a macOS notification with your health score."
	@echo "  To disable:  make unschedule"
	@echo ""

unschedule:
	@echo "Removing LaunchAgent..."
	@launchctl unload $(LAUNCHD_DIR)/$(PLIST_NAME) 2>/dev/null || true
	@rm -f $(LAUNCHD_DIR)/$(PLIST_NAME)
	@echo "  Done. Weekly scan disabled."
