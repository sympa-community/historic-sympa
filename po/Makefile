

MOFILES = cs.mo de.mo en_US.mo es.mo et.mo fi.mo fr.mo hu.mo it.mo nl.mo pl.mo pt.mo ro.mo zh_CN.mo zh_TW.mo

MSGMERGE = msgmerge
MSGFMT   = msgfmt
XGETTEXT = xgettext

## Available catalogues (languages)
.SUFFIXES: .po .mo

.mo:   .po

.po.mo:
	$(MSGFMT) -o $@ $<

all: $(MOFILES)

pot: sympa.pot

sympa.pot: 
	cd .. ;\
	$(XGETTEXT) -o po/sympa.pot wwsympa/tt2/*.tt2 src/etc/tt2/*.tt2 src/etc/mhonarc-ressources

install: makedir 
	@for po in *.po; do \
		echo "Installing po file...$(DESTDIR)$(PODIR)/$$po"; \
		cp $$po $(DESTDIR)$(PODIR); \
	done

makedir:
	@if [ ! -d $(DESTDIR)$(PODIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(PODIR)"; \
		mkdir -p $(DESTDIR)$(PODIR); \
	fi
