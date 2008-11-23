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

sbin_SRC = bounced.pl archived.pl

cgi_SRC	= wwsympa-wrapper.fcgi wwsympa.fcgi wwsympa_sudo_wrapper.pl

lib_SRC	= wwslib.pm cookielib.pm bounce-lib.pl Marc.pm Auth.pm \
	  SharedDocument.pm SympaSession.pm

data_SRC = mime.types 

all:	wwsympa-wrapper.fcgi

clean: 
	@if [ -f ./wwsympa-wrapper.fcgi ]; then \
		rm -f wwsympa-wrapper.fcgi ; \
	fi


install-exec-local: $(cgi_SUBST) $(cgi_SRC) installcgi installicons installdata installwrapper installmodules installdaemons

installmod:
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

installdata:
	install -d -m 755 $(DESTDIR)$(DATADIR)
	install -m 644 $(data_SRC) $(DESTDIR)$(DATADIR)

installmodules:
	install -d -m 755 $(DESTDIR)$(LIBDIR)
	install -m 644 $(lib_SRC) $(DESTDIR)$(LIBDIR)
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
	install -m 6755 wwsympa-wrapper.fcgi $(DESTDIR)$(CGIDIR)

installdaemons:
	install -d -m 755 $(DESTDIR)$(SBINDIR)
	install -m 755 $(sbin_SRC) $(DESTDIR)$(SBINDIR)
	sed -i \
		-e 's|--PERL--|$(PERL)|' \
		-e 's|--USER--|$(USER)|' \
		-e 's|--GROUP--|$(GROUP)|' \
		-e 's|--SYMPA_VERSION--|$(PKG_VERSION)|' \
		-e 's|--SENDMAIL_ALIASES--|$(SENDMAIL_ALIASES)|' \
		-e 's|--VIRTUAL_ALIASES--|$(VIRTUAL_ALIASES)|' \
		-e 's|--CONFIG--|$(CONFIG)|' \
		-e 's|--WWSCONFIG--|$(WWSCONFIG)|' \
		-e 's|--prefix--|$(prefix)|' \
		-e 's|--PIDDIR--|$(PIDDIR)|' \
		-e 's|--SCRIPTDIR--|$(SCRIPTDIR)|' \
		-e 's|--BINDIR--|$(BINDIR)|' \
		-e 's|--SBINDIR--|$(SBINDIR)|' \
		-e 's|--LIBDIR--|$(LIBDIR)|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(DATADIR)|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(DESTDIR)$(SBINDIR)/*.pl 

installcgi:
	install -d -m 755 $(DESTDIR)$(CGIDIR)
	install -m 755 wwsympa.fcgi $(DESTDIR)$(CGIDIR)
	install -m 755 wwsympa_sudo_wrapper.pl $(DESTDIR)$(CGIDIR)
	sed -i \
		-e 's|--PERL--|$(PERL)|' \
		-e 's|--USER--|$(USER)|' \
		-e 's|--GROUP--|$(GROUP)|' \
		-e 's|--SYMPA_VERSION--|$(PKG_VERSION)|' \
		-e 's|--SENDMAIL_ALIASES--|$(SENDMAIL_ALIASES)|' \
		-e 's|--VIRTUAL_ALIASES--|$(VIRTUAL_ALIASES)|' \
		-e 's|--CONFIG--|$(CONFIG)|' \
		-e 's|--WWSCONFIG--|$(WWSCONFIG)|' \
		-e 's|--prefix--|$(prefix)|' \
		-e 's|--PIDDIR--|$(PIDDIR)|' \
		-e 's|--SCRIPTDIR--|$(SCRIPTDIR)|' \
		-e 's|--BINDIR--|$(BINDIR)|' \
		-e 's|--SBINDIR--|$(SBINDIR)|' \
		-e 's|--LIBDIR--|$(LIBDIR)|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(DATADIR)|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(DESTDIR)$(CGIDIR)/wwsympa.fcgi \
		$(DESTDIR)$(CGIDIR)/wwsympa_sudo_wrapper.pl

wwsympa-wrapper.fcgi: wwsympa-wrapper.fcgi.c Makefile ../Makefile
	$(CC) $(CFLAGS) -DWWSYMPA=\"$(CGIDIR)/wwsympa.fcgi\" -o wwsympa-wrapper.fcgi wwsympa-wrapper.fcgi.c
