install: 
	echo "Please use the main Makefile for installing NLS."

newinstall: makedir 
	@for po in *.po; do \
		echo "Installing po file...$(DESTDIR)$(PODIR)/$$po"; \
		cp $$po $(DESTDIR)$(PODIR); \
	done

makedir:
	@if [ ! -d $(DESTDIR)$(PODIR)/wwsympa ]; then \
		echo "Creating required directory $(DESTDIR)$(PODIR)"; \
		mkdir -p $(DESTDIR)$(PODIR); \
	fi
