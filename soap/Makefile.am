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

execcgi_SCRIPTS	 = sympa_soap_server.fcgi
execcgi_PROGRAMS = sympa_soap_server-wrapper.fcgi
sympa_soap_server_wrapper_fcgi_SOURCES = sympa_soap_server-wrapper.fcgi.c
sympa_soap_server_wrapper_fcgi_CPPFLAGS = \
			  -DSYMPASOAP=\"$(execcgidir)/sympa_soap_server.fcgi\"

script_SRC	= sympa_soap_client.pl
lib_SRC		= sympasoap.pm SympaTransport.pm
data_SRC	= sympa.wsdl

install-exec-hook:
	chmod 6755 $(DESTDIR)$(execcgidir)/sympa_soap_server-wrapper.fcgi
	-chown $(USER) $(DESTDIR)$(execcgidir)/sympa_soap_server-wrapper.fcgi
	-chgrp $(GROUP) $(DESTDIR)$(execcgidir)/sympa_soap_server-wrapper.fcgi

install-data-local: installperlcgi installdata installlib installscript

installdata:
	install -d -m 755 $(DESTDIR)$(datadir)/sympa/etc
	install -m 644 $(data_SRC) $(DESTDIR)$(datadir)/sympa/etc

installlib:
	install -d -m 755 $(DESTDIR)$(datadir)/sympa/lib
	install -m 644 $(lib_SRC) $(DESTDIR)$(datadir)/sympa/lib
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
		-e 's|--DIR--|$(datadir)/sympa/bin|' \
		-e 's|--BINDIR--|$(libexecdir)|' \
		-e 's|--SBINDIR--|$(sbindir)|' \
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(datadir)/sympa/lib/, $(lib_SRC))

installscript:
	install -d -m 755 $(DESTDIR)$(datadir)/sympa/bin
	install -m 755 $(script_SRC) $(DESTDIR)$(datadir)/sympa/bin
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
		-e 's|--DIR--|$(datadir)/sympa/bin|' \
		-e 's|--BINDIR--|$(libexecdir)|' \
		-e 's|--SBINDIR--|$(sbindir)|' \
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(datadir)/sympa/bin/, $(script_SRC))

installperlcgi:
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
		-e 's|--DIR--|$(datadir)/sympa/bin|' \
		-e 's|--BINDIR--|$(BINDIR)|' \
		-e 's|--SBINDIR--|$(sbindir)|' \
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(execcgidir)/, $(execcgi_SCRIPTS))
