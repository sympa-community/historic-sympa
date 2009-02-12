# Makefile - This Makefile builds and installs Sympa sources
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

SUBDIRS = etc

CDEFS = -DCONFIG=\"$(CONFIG)\"

sbin_SRC = sympa.pl alias_manager.pl task_manager.pl sympa_wizard.pl

bin_SRC	= queue bouncequeue familyqueue

modulesdir = $(pkgdatadir)/lib
modules_DATA = admin.pm Archive.pm Commands.pm Conf.pm CAS.pm Config_XML.pm \
	       Family.pm Language.pm List.pm Log.pm mail.pm Ldap.pm Upgrade.pm \
	       Lock.pm Version.pm Fetch.pm Message.pm Task.pm Datasource.pm \
	       SQLSource.pm LDAPSource.pm Scenario.pm PlainDigest.pm \
	       tools.pl tt2.pl parser.pl report.pm time_utils.pl

libexec_SRC = aliaswrapper virtualwrapper

all:	queue bouncequeue familyqueue aliaswrapper virtualwrapper

clean:
	@if [ -f ./queue ]; then \
		rm queue ; \
	fi	
	@if [ -f ./bouncequeue ]; then \
		rm bouncequeue ; \
	fi
	@if [ -f ./familyqueue ]; then \
		rm familyqueue ; \
	fi
	@if [ -f ./aliaswrapper ]; then \
		rm aliaswrapper ; \
	fi
	@if [ -f ./virtualwrapper ]; then \
		rm virtualwrapper ; \
	fi

install-exec-local: installqueue installwrapper
install-data-hook: installlib installsbin

installqueue:
	@echo "Installing Queue binary..."
	install -d -m 755 $(DESTDIR)$(BINDIR)
	install -m 4755 queue $(DESTDIR)$(BINDIR)
	-chown $(USER) $(DESTDIR)$(BINDIR)/queue
	-chgrp $(GROUP) $(DESTDIR)$(BINDIR)/queue
	@echo "Installing BounceQueue binary..."
	install -m 4755 bouncequeue $(DESTDIR)$(BINDIR)
	-chown $(USER) $(DESTDIR)$(BINDIR)/bouncequeue
	-chgrp $(GROUP) $(DESTDIR)$(BINDIR)/bouncequeue
	@echo "Installing FamilyQueue binary..."
	install -m 4755 familyqueue $(DESTDIR)$(BINDIR)
	-chown $(USER) $(DESTDIR)$(BINDIR)/familyqueue
	-chgrp $(GROUP) $(DESTDIR)$(BINDIR)/familyqueue

installwrapper:
	@echo "Installing AliasWrapper binary..."
	install -d -m 755 $(DESTDIR)$(LIBEXECDIR)
	install -m 4750 aliaswrapper $(DESTDIR)$(LIBEXECDIR)
	-chown root $(DESTDIR)$(LIBEXECDIR)/aliaswrapper
	-chgrp $(GROUP) $(DESTDIR)$(LIBEXECDIR)/aliaswrapper
	@echo "Installing VirtualWrapper binary..."
	install -m 4750 virtualwrapper $(DESTDIR)$(LIBEXECDIR)
	-chown root $(DESTDIR)$(LIBEXECDIR)/virtualwrapper
	-chgrp $(GROUP) $(DESTDIR)$(LIBEXECDIR)/virtualwrapper

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
		-e 's|--BINDIR--|$(BINDIR)|' \
		-e 's|--SBINDIR--|$(SBINDIR)|' \
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(datadir)/sympa/lib/, $(modules_DATA))

installsbin:
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
		-e 's|--LIBDIR--|$(datadir)/sympa/lib|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(datadir)/sympa/etc|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(addprefix $(DESTDIR)$(SBINDIR)/, $(sbin_SRC))

queue: queue.c Makefile ../Makefile
	$(CC) $(CFLAGS) $(CDEFS) -o queue queue.c

bouncequeue: bouncequeue.c Makefile ../Makefile
	$(CC) $(CFLAGS) $(CDEFS) -o bouncequeue bouncequeue.c

familyqueue: familyqueue.c Makefile ../Makefile
	$(CC) $(CFLAGS) $(CDEFS) -o familyqueue familyqueue.c

aliaswrapper: aliaswrapper.c Makefile ../Makefile
	$(CC) $(CFLAGS) $(CDEFS) -DNEWALIASES=\"${NEWALIASES}\" \
		-DNEWALIASES_ARG=\"${NEWALIASES_ARG}\" -o aliaswrapper aliaswrapper.c

virtualwrapper: virtualwrapper.c Makefile ../Makefile
	$(CC) $(CFLAGS) $(CDEFS) -DPOSTMAP=\"${POSTMAP}\" \
		-DPOSTMAP_ARG=\"${POSTMAP_ARG}\" -o virtualwrapper virtualwrapper.c

## Dépendances
queue:		queue.c Makefile

bouncequeue:	bouncequeue.c Makefile

familyqueue:	familyqueue.c Makefile
