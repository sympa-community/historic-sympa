# Makefile - This Makefile does the web templates installation
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

default: none

install: makedir installtemplates installmod

installmod:
	-chown $(USER) $(DESTDIR)$(DATADIR)/web_tt2/*
	-chgrp $(GROUP) $(DESTDIR)$(DATADIR)/web_tt2/*
	chmod 755 $(DESTDIR)$(DATADIR)/web_tt2

makedir:
	@if [ ! -d $(DESTDIR)$(DATADIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)"; \
		mkdir -p $(DESTDIR)$(DATADIR); \
	fi
	@if [ ! -d $(DESTDIR)$(DATADIR)/web_tt2 ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/web_tt2"; \
		mkdir $(DESTDIR)$(DATADIR)/web_tt2; \
	fi

installtemplates:
	@echo
	@echo "Installing web templates..."
		@( \
		PERL=$(PERL); export PERL; \
		UMASK=0644; export UMASK; \
		INSTALLDIR=$(DATADIR)/web_tt2; export INSTALLDIR; \
		SBINDIR=$(SBINDIR); export SBINDIR; \
		CGIDIR=$(CGIDIR); export CGIDIR; \
		LIBDIR=$(LIBDIR); export LIBDIR; \
		DESTDIR=$(DESTDIR); export DESTDIR; \
		ETCBINDIR=$(DATADIR); export ETCBINDIR; \
		$(PERL) ../subst.pl *.tt2; \
		); \
	$(PERL) ../set_symlinks.pl web_tt2 $(DESTDIR)$(DATADIR)/web_tt2
	find $(DESTDIR)$(DATADIR) -type d -exec chmod 755 {} \;
	find $(DESTDIR)$(DATADIR) -type f -exec chmod 644 {} \;
