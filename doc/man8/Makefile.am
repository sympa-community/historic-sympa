man8_MANS = archived.8 bounced.8 alias_manager.8 sympa.8 

EXTRA_DIST = archived.pod bounced.pod alias_manager.pod sympa.pod

CLEANFILES = $(man8_MANS)

.pod.8:
	rm -f $@
	pod2man --section=8 --center="sympa $(PACKAGE_VERSION)" --lax --release="$(PACKAGE_VERSION)" $< $@
