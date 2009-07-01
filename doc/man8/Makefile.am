man8_MANS = archived.8 bounced.8 alias_manager.8 sympa.8 

EXTRA_DIST = archived.pod.in bounced.pod.in alias_manager.pod.in sympa.pod

CLEANFILES = $(man8_MANS) archived.pod bounced.pod alias_manager.pod

.pod.8:
	rm -f $@
	pod2man --section=8 --center="sympa $(VERSION)" --lax --release="$(VERSION)" $< $@

archived.pod bounced.pod alias_manager.pod: Makefile
	rm -f $@
	sed \
		-e 's|--piddir--|$(piddir)|' \
		-e 's|--libexecdir--|$(libexecdir)|' \
		-e 's|--sysconfdir--|$(sysconfdir)|' \
		-e 's|--defaultdir--|$(defaultdir)|' \
		-e 's|--expldir--|$(expldir)|' \
		-e 's|--spooldir--|$(spooldir)|' \
		-e 's|--docdir--|$(docdir)|' \
		< $(srcdir)/$@.in > $@

archived.pod: $(srcdir)/archived.pod.in
bounced.pod: $(srcdir)/bounced.pod.in
alias_manager.pod: $(srcdir)/alias_manager.pod.in
