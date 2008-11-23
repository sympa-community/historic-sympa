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

cgi_SUBST	=	sympa_soap_server.fcgi 

cgi_SRC		= 	sympa_soap_server-wrapper.fcgi

script_SUBST	=	sympa_soap_client.pl

lib_SRC	= sympasoap.pm SympaTransport.pm

data_SRC = sympa.wsdl

all:	sympa_soap_server-wrapper.fcgi

clean: 
	@if [ -f ./sympa_soap_server-wrapper.fcgi ]; then \
		rm -f sympa_soap_server-wrapper.fcgi ; \
	fi

install-exec-local: makedir $(cgi_SUBST) $(lib_SUBST) substcgi installmodules substscript installdata installwrapper installmod

installmod:
	@for i in $(SRC) ; do \
	chown $(USER) $(DESTDIR)$(DATADIR)/$$i || /bin/true; \
	chgrp $(GROUP) $(DESTDIR)$(DATADIR)/$$i || /bin/true; \
	done
	@for i in $(script_SUBST) ; do \
	chown $(USER) $(DESTDIR)$(SCRIPTDIR)/$$i || /bin/true; \
	chgrp $(GROUP) $(DESTDIR)$(SCRIPTDIR)/$$i || /bin/true; \
	chmod a+x $(DESTDIR)$(SCRIPTDIR)/$$i; \
	done
	@for i in $(cgi_SUBST) ; do \
	chown $(USER) $(DESTDIR)$(CGIDIR)/$$i || /bin/true; \
	chgrp $(GROUP) $(DESTDIR)$(CGIDIR)/$$i || /bin/true; \
	done

makedir:
	@if [ ! -d $(DESTDIR)$(CGIDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(CGIDIR)"; \
		mkdir -p $(DESTDIR)$(CGIDIR); \
	fi
	@if [ ! -d $(DESTDIR)$(SCRIPTDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(SCRIPTDIR)"; \
		mkdir -p $(DESTDIR)$(SCRIPTDIR); \
	fi

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
		$(DESTDIR)$(LIBDIR)/*.pm

installwrapper:
	@echo "Installing sympa_soap_server-wrapper binary..."
	install -m 6755 sympa_soap_server-wrapper.fcgi $(DESTDIR)$(CGIDIR)
	-chown $(USER) $(DESTDIR)$(CGIDIR)/sympa_soap_server-wrapper.fcgi
	-chgrp $(GROUP) $(DESTDIR)$(CGIDIR)/sympa_soap_server-wrapper.fcgi

substscript:
	@echo "Doing multiple substitutions while installing scripts..."
	@( \
		PERL=$(PERL); export PERL; \
		UMASK=0644; export UMASK; \
		INSTALLDIR=$(SCRIPTDIR); export INSTALLDIR; \
		SBINDIR=$(SBINDIR); export SBINDIR; \
		CGIDIR=$(CGIDIR); export CGIDIR; \
		PIDDIR=$(PIDDIR); export PIDDIR;\
		LIBDIR=$(LIBDIR); export LIBDIR; \
		DESTDIR=$(DESTDIR); export DESDIR; \
		MAILERPROGDIR=$(BINDIR); export MAILERPROGDIR; \
		ICONSDIR=$(ICONSDIR); export ICONSDIR; \
		WWSCONFIG=$(WWSCONFIG); export WWSCONFIG; \
		CONFIG=$(CONFIG); export CONFIG; \
		$(PERL) ../subst.pl $(script_SUBST) \
	)

substcgi:
	@echo "Doing multiple substitutions while installing CGIs..."
	@( \
		PERL=$(PERL); export PERL; \
		UMASK=0755; export UMASK; \
		INSTALLDIR=$(CGIDIR); export INSTALLDIR; \
		SBINDIR=$(SBINDIR); export SBINDIR; \
		CGIDIR=$(CGIDIR); export CGIDIR; \
		PIDDIR=$(PIDDIR); export PIDDIR;\
		LIBDIR=$(LIBDIR); export LIBDIR; \
		DESTDIR=$(DESTDIR); export DESDIR; \
		MAILERPROGDIR=$(BINDIR); export MAILERPROGDIR; \
		ICONSDIR=$(ICONSDIR); export ICONSDIR; \
		WWSCONFIG=$(WWSCONFIG); export WWSCONFIG; \
		CONFIG=$(CONFIG); export CONFIG; \
		$(PERL) ../subst.pl $(cgi_SUBST) \
	)

sympa_soap_server-wrapper.fcgi: sympa_soap_server-wrapper.fcgi.c Makefile
	$(CC) $(CFLAGS) -DSYMPASOAP=\"$(CGIDIR)/sympa_soap_server.fcgi\" -o sympa_soap_server-wrapper.fcgi sympa_soap_server-wrapper.fcgi.c
