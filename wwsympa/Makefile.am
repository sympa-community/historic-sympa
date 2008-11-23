# Makefile - This Makefile does the web interface of Sympa installation
# RCS Identication ; $Revision$ ; $Date$ 
#
# Sympa - SYsteme de Multi-Postage Automatique
# Copyright (c) 1997, 1998, 1999, 2000, 2001 Comite Reseau des Universites
# Copyright (c) 1997,1998, 1999 Institut Pasteur & Christophe Wolfhugel
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

sbin_SUBST	=	bounced.pl archived.pl

cgi_SUBST	=	wwsympa.fcgi wwsympa_sudo_wrapper.pl

cgi_SRC		=	wwsympa-wrapper.fcgi

lib_SUBST	=	wwslib.pm cookielib.pm bounce-lib.pl Marc.pm Auth.pm SharedDocument.pm SympaSession.pm

SRC		=	mime.types 

WWSYMPA = $(CGIDIR)/wwsympa.fcgi

all:	wwsympa-wrapper.fcgi

clean: 
	rm -rf $(DESTDIR)$(SBINDIR)
	@if [ -f ./wwsympa-wrapper.fcgi ]; then \
		rm -f wwsympa-wrapper.fcgi ; \
	fi


install-exec-local: makedir $(sbin_SUBST) $(cgi_SUBST) $(cgi_SRC) $(lib_SUBST) substcgi substsbin installicons installsrc installwrapper installmod installmodules

installmod:
	@for i in $(sbin_SUBST) ; do \
	chown $(USER) $(DESTDIR)$(SBINDIR)/$$i || /bin/true; \
	chgrp $(GROUP) $(DESTDIR)$(SBINDIR)/$$i || /bin/true; \
	done
	@for i in $(cgi_SUBST) ; do \
	chown $(USER) $(DESTDIR)$(CGIDIR)/$$i || /bin/true; \
	chgrp $(GROUP) $(DESTDIR)$(CGIDIR)/$$i || /bin/true; \
	done
	@for i in $(cgi_SRC) ; do \
	chown $(USER) $(DESTDIR)$(CGIDIR)/$$i || /bin/true; \
	chgrp $(GROUP) $(DESTDIR)$(CGIDIR)/$$i || /bin/true; \
	done
	echo "Setting SetUID bit on wwsympa-wrapper.fcgi..."; \
	chmod u+s $(DESTDIR)$(CGIDIR)/wwsympa-wrapper.fcgi;\
	chmod g+s $(DESTDIR)$(CGIDIR)/wwsympa-wrapper.fcgi;

makedir:
	@if [ ! -d $(DESTDIR)$(SBINDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(SBINDIR)"; \
		mkdir -p $(DESTDIR)$(SBINDIR); \
	fi
	@if [ ! -d $(DESTDIR)$(CGIDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(CGIDIR)"; \
		mkdir -p $(DESTDIR)$(CGIDIR); \
	fi

installsrc:
	install -d -m 755 $(DESTDIR)$(DATADIR)
	install -m 644 mime.types $(DESTDIR)$(DATADIR)

installmodules:
	install -d -m 755 $(DESTDIR)$(LIBDIR)
	install -m 644 $(lib_SUBST) $(DESTDIR)$(LIBDIR)
	sed -i \
		-e 's|--USER--|$(USER)|' \
		-e 's|--GROUP--|$(GROUP)|' \
		-e 's|--SYMPA_VERSION--|$(PKG_VERSION)|' \
		-e 's|--SENDMAIL_ALIASES--|$(SENDMAIL_ALIASES)|' \
		-e 's|--VIRTUAL_ALIASES--|$(VIRTUAL_ALIASES)|' \
		-e 's|--CONFIG--|$(CONFIG)|' \
		-e 's|--WWSCONFIG--|$(WWSCONFIG)|' \
		-e 's|--prefix--|$(prefix)|' \
		-e 's|--PIDDIR--|$(PIDDIR)|' \
		-e 's|--INSTALLDIR--|$(INSTALLDIR)|' \
		-e 's|--SCRIPTDIR--|$(SCRIPTDIR)|' \
		-e 's|--BINDIR--|$(BINDIR)|' \
		-e 's|--SBINDIR--|$(SBINDIR)|' \
		-e 's|--LIBDIR--|$(LIBDIR)|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(DATADIR)|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(DESTDIR)$(LIBDIR)/*.pm $(DESTDIR)$(LIBDIR)/*.pl

	install -d -m 755 $(DESTDIR)$(LIBDIR)/Marc
	install -m 644 Marc/Search.pm $(DESTDIR)$(LIBDIR)/Marc

installicons:
	install -d -m 755 $(DESTDIR)$(prefix)/static_content
	install -d -m 755 $(DESTDIR)$(prefix)/static_content/icons
	install -m 644 icons/*.png $(DESTDIR)$(prefix)/static_content/icons

installwrapper:
	@echo "Installing wwsympa-wrapper binary..."
	cp wwsympa-wrapper.fcgi $(DESTDIR)$(CGIDIR)/

substsbin:
	@echo "Doing multiple substitutions while installing binaries..."
	@( \
		PERL=$(PERL); export PERL; \
		UMASK=0755; export UMASK; \
		INSTALLDIR=$(SBINDIR); export INSTALLDIR; \
		SBINDIR=$(SBINDIR); export SBINDIR; \
		CGIDIR=$(CGIDIR); export CGIDIR; \
		USER=$(USER); export USER; \
		GROUP=$(GROUP); export GROUP; \
		PIDDIR=$(PIDDIR); export PIDDIR;\
		LIBDIR=$(LIBDIR); export LIBDIR; \
		DESTDIR=$(DESTDIR); export DESDIR; \
		ETCBINDIR=$(DATADIR); export ETCBINDIR; \
		MAILERPROGDIR=$(BINDIR); export MAILERPROGDIR; \
		WWSCONFIG=$(WWSCONFIG); export WWSCONFIG; \
		CONFIG=$(CONFIG); export CONFIG; \
		$(PERL) ../subst.pl $(sbin_SUBST) \
	)

substcgi:
	@echo "Doing multiple substitutions while installing CGIs..."
	@( \
		PERL=$(PERL); export PERL; \
		UMASK=0755; export UMASK; \
		INSTALLDIR=$(CGIDIR); export INSTALLDIR; \
		USER=$(USER); export USER; \
		SUDO=$(SUDO); export SUDO; \
		SBINDIR=$(SBINDIR); export SBINDIR; \
		CGIDIR=$(CGIDIR); export CGIDIR; \
		PIDDIR=$(PIDDIR); export PIDDIR;\
		LIBDIR=$(LIBDIR); export LIBDIR; \
		DESTDIR=$(DESTDIR); export DESDIR; \
		ETCBINDIR=$(DATADIR); export ETCBINDIR; \
		MAILERPROGDIR=$(BINDIR); export MAILERPROGDIR; \
		WWSCONFIG=$(WWSCONFIG); export WWSCONFIG; \
		CONFIG=$(CONFIG); export CONFIG; \
		PERLOPT="-U"; export PERLOPT; \
		$(PERL) ../subst.pl $(cgi_SUBST) \
	)

wwsympa-wrapper.fcgi: wwsympa-wrapper.fcgi.c Makefile ../Makefile
	$(CC) $(CFLAGS) -DWWSYMPA=\"$(WWSYMPA)\" -o wwsympa-wrapper.fcgi wwsympa-wrapper.fcgi.c
