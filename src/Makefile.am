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

lib_SRC	= admin.pm Archive.pm Commands.pm Conf.pm CAS.pm Config_XML.pm \
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

install-exec-local: makedir subst $(sbin_SRC) $(lib_SRC) installqueue installwrapper installmodules

installqueue:
	@echo "Installing Queue binary..."
	install -m 4755 queue $(DESTDIR)$(BINDIR)
	-chown $(USER).$(GROUP) $(DESTDIR)$(BINDIR)/queue
	@echo "Installing BounceQueue binary..."
	install -m 4755 bouncequeue $(DESTDIR)$(BINDIR)
	-chown $(USER).$(GROUP) $(DESTDIR)$(BINDIR)/bouncequeue
	@echo "Installing FamilyQueue binary..."
	install -m 4755 familyqueue $(DESTDIR)$(BINDIR)
	-chown $(USER).$(GROUP) $(DESTDIR)$(BINDIR)/familyqueue

installwrapper:
	@echo "Installing AliasWrapper binary..."
	install -m 4750 aliaswrapper $(DESTDIR)$(LIBEXECDIR)
	-chown root.$(GROUP) $(DESTDIR)$(LIBEXECDIR)/aliaswrapper
	@echo "Installing VirtualWrapper binary..."
	install -m 4750 virtualwrapper $(DESTDIR)$(LIBEXECDIR)
	-chown root.$(GROUP) $(DESTDIR)$(LIBEXECDIR)/virtualwrapper

installmodules:
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
		-e 's|--SBINDIR--|$(SBINDIR)|' \
		-e 's|--LIBDIR--|$(LIBDIR)|' \
		-e 's|--LOCALEDIR--|$(LOCALEDIR)|' \
		-e 's|--DATADIR--|$(DATADIR)|' \
		-e 's|--ETCDIR--|$(ETCDIR)|' \
		-e 's|--EXPLDIR--|$(EXPLDIR)|' \
		-e 's|--SPOOLDIR--|$(SPOOLDIR)|' \
		$(DESTDIR)$(LIBDIR)/*.pm $(DESTDIR)$(LIBDIR)/*.pl 

makedir:
	@if [ ! -d $(DESTDIR)$(BINDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(BINDIR)"; \
		mkdir -p $(DESTDIR)$(BINDIR); \
	fi
	@if [ ! -d $(DESTDIR)$(LIBEXECDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(LIBEXECDIR)"; \
		mkdir -p $(DESTDIR)$(LIBEXECDIR); \
	fi
	@if [ ! -d $(DESTDIR)$(BINDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(BINDIR)"; \
		mkdir -p $(DESTDIR)$(BINDIR); \
	fi
	@if [ ! -d $(DESTDIR)$(SBINDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(SBINDIR)"; \
		mkdir -p $(DESTDIR)$(SBINDIR); \
	fi
	@if [ ! -d $(DESTDIR)$(LIBDIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(LIBDIR)"; \
		mkdir -p $(DESTDIR)$(LIBDIR); \
	fi

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

subst:
	@echo "Doing multiple substitutions while installing binaries..."
	@( \
		PERL=$(PERL); export PERL;\
		UMASK=0755; export UMASK;\
		USER=$(USER); export USER;\
		GROUP=$(GROUP); export GROUP;\
		prefix=$(prefix); export prefix;\
		DESTDIR=$(DESTDIR); export DESTDIR;\
		PIDDIR=$(PIDDIR); export PIDDIR;\
		INSTALLDIR=$(SBINDIR); export INSTALLDIR;\
		SBINDIR=$(SBINDIR); export SBINDIR;\
		LIBDIR=$(LIBDIR); export LIBDIR;\
		LOCALEDIR=$(LOCALEDIR); export LOCALEDIR;\
		DATADIR=$(DATADIR); export DATADIR;\
		ETCDIR=$(ETCDIR); export ETCDIR;\
		EXPLDIR=$(EXPLDIR); export EXPLDIR;\
		CONFIG=$(CONFIG); export CONFIG;\
		WWSCONFIG=$(WWSCONFIG); export WWSCONFIG;\
		SYMPA_VERSION=$(PACKAGE_VERSION); export SYMPA_VERSION;\
		SENDMAIL_ALIASES=$(SENDMAIL_ALIASES); export SENDMAIL_ALIASES;\
		VIRTUAL_ALIASES=$(VIRTUAL_ALIASES); export VIRTUAL_ALIASES;\
		SPOOLDIR=$(SPOOLDIR); export SPOOLDIR;\
		$(PERL) ../subst.pl $(sbin_SRC) \
	)

## Dépendances
queue:		queue.c Makefile

bouncequeue:	bouncequeue.c Makefile

familyqueue:	familyqueue.c Makefile
