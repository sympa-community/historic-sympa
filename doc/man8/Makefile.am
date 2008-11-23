man8_SRC	= archived.8 bounced.8 alias_manager.8 sympa.8 

SUFFIXES:	.8 .pod

.8:	.pod

.pod.8:
	rm -f $@
	pod2man --section=8 --center="sympa $(PACKAGE_VERSION)" --lax --release="$(PACKAGE_VERSION)" $< $@

all:	$(MAN8)

clean:
	rm -f *.8

install-data-local:
	install -d -m 755 $(DESTDIR)$(MANDIR)
	install -d -m 755 $(DESTDIR)$(MANDIR)/man8
	install -m 644 $(man8_SRC) $(DESTDIR)$(MANDIR)/man8
