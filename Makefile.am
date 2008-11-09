 # Makefile.am - Top-level Makefile.am for Sympa
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

#SUBDIRS = src doc wwsympa nls

PERL_VERSION	=	`$(PERL) -e ' print $$]'`

main_SRC	=	AUTHORS COPYING ChangeLog INSTALL KNOWNBUGS NEWS README

all:	warning checkperl sources wrapper soap_wrapper man locale

warning:
	@echo "######################## W A R N I N G ######################"; \
	echo "## If it is the first time you install Sympa on this server :"; \
	echo "##        It may take a while...."; \
	echo "## The reason is that Sympa requires many Perl modules that"; \
	echo "## are not distributed with the standard Perl distribution."; \
	echo "## We'll try to install these modules automatically..."; \
	echo "## If some modules cannot be installed automatically, (probably" ; \
	echo "## because of the 'make test'), try downloading them from the"; \
	echo "## CPAN website (http://search.cpan.org) and install them manually."; \
	echo "#############################################################"; \
	echo -n "Please hit <Enter> to proceed"; \
	if [ "$(DESTDIR)" = "" ]; then read rep; fi

checkperl:
	@if [ $(PERL_VERSION) = '5.006' ]; then \
	echo "##################################"; \
	echo "## You are using Perl version $(PERL_VERSION) :"; \
	echo "## You need to patch your syslog.pm "; \
	echo "## See http://bugs.perl.org/perlbug.cgi?req=bidmids&bidmids=20000712.003"; \
	echo "##"; \
	echo "## If your Perl version is 5.6.0 AND if your system is Solaris :"; \
	echo "## See also http://bugs.perl.org/perlbug.cgi?req=bidmids&bidmids=20000522.003"; \
	echo "#############################################################################"; \
	if [ "$(DESTDIR)" = "" ]; then read rep; fi \
	fi
	@if [ ! -f $(SUIDPERL) ]; then \
		echo "#################################################################################"; \
		echo "## wwsympa.fcgi that provides Sympa's web interface needs to run as user $(USER)"; \
		echo "## There are many options to do so : "; \
		echo "##  1/ Installing 'suidperl' to run wwsympa.fcgi with SetUID. This is the default method,"; \
		echo "##     but it might be insecure."; \
		echo "##  2/ Use 'sudo' to run wwsympa.fcgi as user $(USER). Your Apache configuration should use wwsympa_sudo_wrapper.pl"; \
		echo "##     You should edit your /etc/sudoers file (with visudo command) as follows :"; \
		echo "##     apache ALL = ($(USER))  NOPASSWD: $(CGIDIR)/wwsympa.fcgi"; \
		echo "##  3/ Use Apache's suExec mode."; \
		echo "## For (2) and (3) you should run Sympa's 'configure' with the '--enable-secure' option"; \
		echo "#######################################################################################"; \
		echo -n "Please hit <Enter> to continue"; \
		if [ "$(DESTDIR)" = "" ]; then read rep; fi \
	fi
	@if [ ! -f $(MSGFMT) ]; then \
		echo "##################################"; \
		echo "## You don't have msgfmt installed. It is required to build message catalogues"; \
		echo "## msgfmt is provided with a 'gettext' package on most systems..."; \
		echo "#####################################################"; \
		if [ "$(DESTDIR)" = "" ]; then read rep; fi \
	fi


sources: src/Makefile src/queue.c src/bouncequeue.c src/aliaswrapper.c
	@(cd src && echo "making in src..." && $(MAKE));

wrapper: src/Makefile src/queue.c src/bouncequeue.c src/aliaswrapper.c
	@(cd wwsympa && echo "making in wwsympa..." && $(MAKE));

soap_wrapper: src/Makefile src/queue.c src/bouncequeue.c src/aliaswrapper.c
	@(cd soap && echo "making in soap..." && $(MAKE));

documentation: doc/sympa.tex.tpl doc/Makefile 
	@(cd doc && echo "making in doc..." && $(MAKE));

man: doc/man8/Makefile
	@(cd doc/man8 && echo "making in doc/man8..." && $(MAKE));

install: importantchanges installdir installsrc installwws installwebtt2 installmailtt2 installlocale installman installscript installsample installdoc installsoap nextstep

nextstep: 
	@echo ""
	@echo "#########################################################"
	@echo "# If you install Sympa for the first time on this server"
	@echo "# you should check the INSTALL file."
	@echo "#"
	@echo "# If you are upgrading, you now need to run"
	@echo "#    $(SBINDIR)/sympa.pl --upgrade"
	@echo "#######################################################"

importantchanges:
	@( 	PERL=$(PERL); export PERL; \
		UMASK=0600; export UMASK; \
		DESTDIR=$(DESTDIR); export DESTDIR; \
		BINDIR=$(SBINDIR); export BINDIR; \
		SBINDIR=$(SBINDIR); export SBINDIR; \
		LIBDIR=$(LIBDIR); export LIBDIR; \
		ETCDIR=$(ETCDIR); export ETCDIR;\
		USER=$(USER); export USER;\
		GROUP=$(GROUP); export GROUP;\
		SYMPA_VERSION=$(PACKAGE_VERSION); export SYMPA_VERSION; \
		$(PERL) ./important_changes.pl \
	) ;

locale:
	@(cd po && echo "making in po..." && $(MAKE))

installlocale:
	@(cd po && echo "making install in po..." && \
		$(MAKE) install) || exit 1;

updatelocale:
	@(cd po && echo "making update-po in po..." && \
		$(MAKE) update-po) || exit 1;

installsrc:
	@(cd src && echo "making install in src..." && \
		$(MAKE) install) || exit 1;

installdoc:
	@(cd doc && echo "making install in doc..." && \
		$(MAKE) install) || exit 1;

installwws:
	@(cd wwsympa && echo "making install in wwsympa..." && \
		$(MAKE) install) || exit 1;

installwebtt2:
	@(cd web_tt2 && echo "making install in web_tt2..." && \
		$(MAKE) install) || exit 1;

installmailtt2:
	@(cd mail_tt2 && echo "making install in mail_tt2..." && \
		$(MAKE) install) || exit 1;

installsoap:
	@(cd soap && echo "making install in soap..." && \
		$(MAKE) install) || exit 1;

installsample:
	@(cd src/etc/sample && echo "making install in src/etc/sample..." && \
		$(MAKE) install) || exit 1;

installman:
	@(cd doc/man8 && echo "making install in doc/man8..." && \
		$(MAKE) install) || exit 1;

installscript:
	@(cd src/etc/script && echo "making install in src/etc/script..." && \
		$(MAKE) install) || exit 1;

installdir:
	@echo "Creating required directories"
	@for dir in $(prefix) $(EXPLDIR) $(CONFDIR) $(SAMPLEDIR) $(ETCDIR) $(BINDIR) $(LOCALEDIR) $(DOCDIR) $(ETCBINDIR) $(prefix)/static_content $(prefix)/static_content/icons ; do \
		if [ ! -d $(DESTDIR)$$dir ] ; then \
			echo "Creating $(DESTDIR)$$dir"; \
			mkdir -p $(DESTDIR)$$dir; \
			chown $(USER) $(DESTDIR)$$dir || /bin/true; \
			chgrp $(GROUP) $(DESTDIR)$$dir || /bin/true; \
			chmod 755 $(DESTDIR)$$dir; \
		fi \
	done
	@if [ ! -f $(DESTDIR)$(CONFDIR)/sympa.conf ] ; then \
	echo "First installation : installing conf directories..."; \
	for dir in create_list_templates mail_tt2 web_tt2 scenari \
	task_models general_task_models; do \
		if [ ! -d $(DESTDIR)$(ETCDIR)/$$dir ] ; then \
			echo "Creating $(DESTDIR)$(ETCDIR)/$$dir"; \
			mkdir -p $(DESTDIR)$(ETCDIR)/$$dir; \
			chown $(USER) $(DESTDIR)$(ETCDIR)/$$dir || /bin/true; \
			chgrp $(GROUP) $(DESTDIR)$(ETCDIR)/$$dir || /bin/true; \
		fi \
	done; \
	( \
		PERL=$(PERL); export PERL; \
		UMASK=0600; export UMASK; \
		INSTALLDIR=$(ETCDIR); export INSTALLDIR; \
		USER=$(USER); export USER;\
		GROUP=$(GROUP); export GROUP;\
		INSTALLNAME='README'; export INSTALLNAME; \
                ETCDIR=$(ETCDIR); export ETCDIR; \
                ETCBINDIR=$(ETCBINDIR); export ETCBINDIR; \
		$(PERL) ./subst.pl src/etc/README_etc \
	) \
	fi
	@if [ ! -f $(DESTDIR)$(CONFDIR)/sympa.conf ] ; then \
	echo "First installation : installing spool directories..."; \
	for dir in $(SPOOLDIR) $(SPOOLDIR)/msg $(SPOOLDIR)/digest $(SPOOLDIR)/moderation \
	$(SPOOLDIR)/expire $(SPOOLDIR)/auth $(SPOOLDIR)/outgoing $(SPOOLDIR)/tmp \
	$(SPOOLDIR)/task ; do \
		if [ ! -d $(DESTDIR)$$dir ] ; then \
			echo "Creating $(DESTDIR)$$dir"; \
			mkdir -p $(DESTDIR)$$dir; \
			chown $(USER) $(DESTDIR)$$dir || /bin/true; \
			chgrp $(GROUP) $(DESTDIR)$$dir || /bin/true; \
			chmod 770 $(DESTDIR)$$dir; \
		fi \
	done \
	fi
	@if [ ! -f $(DESTDIR)$(CONFDIR)/sympa.conf ] ; then \
	echo "First installation : creating archives and bounce directories..."; \
	for dir in bounce arc ; do \
		if [ ! -d $(DESTDIR)$(prefix)/$$dir ] ; then \
			echo "Creating $(DESTDIR)$(prefix)/$$dir"; \
			mkdir -p $(DESTDIR)$(prefix)/$$dir; \
			-chown $(USER) $(DESTDIR)$(prefix)/$$dir; \
			-chgrp $(GROUP) $(DESTDIR)$(prefix)/$$dir; \
		fi \
	done \
	fi

ChangeLog:
	$(CVS2CL)

tag:	ChangeLog
	@if [ ! $(NEW_VERSION) ]; then \
	echo "Current version is $(VERSION)"; \
	echo "You need to define NEW_VERSION"; \
	else echo $(NEW_VERSION) > .version; cvs ci -m 'preparing $(NEW_VERSION)' .version ChangeLog; cvs tag -F `echo sympa-$(NEW_VERSION)|sed 's/\./_/g'`; \
	fi
