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

sbin_SCRIPTS = bounced.pl archived.pl
cgi_SCRIPTS  = wwsympa.fcgi wwsympa_sudo_wrapper.pl
cgi_PROGRAMS = wwsympa-wrapper.fcgi
wwsympa_wrapper_fcgi_SOURCES = wwsympa-wrapper.fcgi.c
wwsympa_wrapper_fcgi_CPPFLAGS = -DWWSYMPA=\"$(cgidir)/wwsympa.fcgi\"

modulesdir = $(pkgdatadir)/lib
nobase_modules_DATA = wwslib.pm cookielib.pm bounce-lib.pl Marc.pm Auth.pm \
		      SharedDocument.pm SympaSession.pm Marc/Search.pm

data_SRC	= mime.types 

install-data-hook: installperlcgi installdata installlib installsbin \
		    installicons

installdata:
	install -d -m 755 $(DESTDIR)$(datadir)/sympa/etc
	install -m 644 $(data_SRC) $(DESTDIR)$(datadir)/sympa/etc

installlib:
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
		-e 's|--SCRIPTDIR--|$(SCRIPTDIR)|' \
		-e 's|--BINDIR--|$(libexecdir)|' \
		-e 's|--SBINDIR--|$(sbindir)|' \
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(datadir)/sympa/lib/, $(nobase_modules_DATA))

installicons:
	install -d -m 755 $(DESTDIR)$(prefix)/static_content
	install -d -m 755 $(DESTDIR)$(prefix)/static_content/icons
	install -m 644 icons/*.png $(DESTDIR)$(prefix)/static_content/icons

install-exec-hook:
	chmod 6755 $(DESTDIR)$(cgidir)/wwsympa-wrapper.fcgi
	-chown $(USER) $(DESTDIR)$(cgidir)/wwsympa-wrapper.fcgi
	-chgrp $(GROUP) $(DESTDIR)$(cgidir)/wwsympa-wrapper.fcgi

installsbin:
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
		-e 's|--BINDIR--|$(libexecdir)|' \
		-e 's|--SBINDIR--|$(sbindir)|' \
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(sbindir)/, $(sbin_SCRIPTS))

installperlcgi:
	sed -i \
		-e 's|--PERLOPT--|-U|' \
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
		-e 's|--BINDIR--|$(libexecdir)|' \
		-e 's|--SBINDIR--|$(sbindir)|' \
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(cgidir)/, $(cgi_SCRIPTS))
