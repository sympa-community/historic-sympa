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

## For preparing samples
HOST		=	`$(PERL) -MSys::Hostname -e "printf '%s', Sys::Hostname::hostname();"`
COOKIE		=	`$(PERL) -e " print int(rand ( time ))  "`
PERL_VERSION	=	`$(PERL) -e ' print $$]'`

## Both queue and bouncequeue are lunched by sendmail. If sendmail
## is configured to used smrsh (check the mailer prog definition), thoses
## files needs to be installed in /etc/smrsh.  
MAILERPROGDIR	=	@BINDIR@

## Directory for installing WWSympa
WWSBINDIR	=	$(BINDIR)

ETCBINDIR	=	@DATADIR@

## Web interface colors are now defined in sympa.conf

## Settings used in src/etc/scripts/sympa
PIDPRE		=	pidof -x
PIDPOST		=	

SSLCERTDIR =	$(EXPLDIR)/X509-user-certs

CFLAGS	=	-g

CONFIG		=	$(CONFDIR)/sympa.conf
WWSCONFIG	=	$(CONFDIR)/wwsympa.conf

main_SRC	=	AUTHORS COPYING ChangeLog INSTALL KNOWNBUGS NEWS README

LOG_SOCKET_TYPE	=	unix

all:	warning checkperl checkcpan sources wrapper soap_wrapper man locale

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
	@echo "Making src"
	@(cd src && echo "making in src..." && \
	$(MAKE) \
	WWSBINDIR='${WWSBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	ETCBINDIR='${ETCBINDIR}'\
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	PIDPRE='${PIDPRE}' \
	PIDPOST='${PIDPOST}' \
	);

wrapper: src/Makefile src/queue.c src/bouncequeue.c src/aliaswrapper.c
	@echo "Making wwsympa"
	@(cd wwsympa && echo "making in wwsympa..." && \
	$(MAKE) WWSYMPA='${CGIDIR}/wwsympa.fcgi');

soap_wrapper: src/Makefile src/queue.c src/bouncequeue.c src/aliaswrapper.c
	@echo "Making sympa_soap"
	@(cd soap && echo "making in soap..." && \
	$(MAKE) SYMPASOAP='${CGIDIR}/sympa_soap_server.fcgi');

documentation: doc/sympa.tex.tpl doc/Makefile 
	@echo "Making documentation"
	@(cd doc && echo "making in doc/..." && \
	$(MAKE) \
	WWSBINDIR='${WWSBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	ETCBINDIR='${ETCBINDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	);

man: doc/man8/Makefile
	@echo "Making man"
	@(cd doc/man8 && echo "making in doc/man8/..." && \
	$(MAKE));

checkcpan: 
	@echo "Checking needed CPAN modules ..."
	$(PERL) ./check_perl_modules.pl

clean:
	find . \( -name ".#*" -o -name "*~" -o -name ".*~" -o -name "#*#" \) -exec  rm -f {} \;
	@for i in src wwsympa src/etc/sample;\
	do \
	(cd $$i && echo "making clean in $$i..." && \
	$(MAKE) PERL='${PERL}' clean) || exit 1; \
	done;

install: importantchanges installdir installsrc installwws installwebtt2 installmailtt2 installlocale installman installscript installsample installconfig installdoc installsoap nextstep

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
	@(cd po && echo "making in po/...." && \
	$(MAKE) \
	ETCBINDIR='${ETCBINDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	) || exit 1;

installlocale:
	@(cd po && echo "making install in po/...." && \
	$(MAKE) \
	ETCBINDIR='${ETCBINDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	install) || exit 1;

updatelocale:
	@(cd po && echo "make update-po in po/...." && \
	$(MAKE) \
	ETCBINDIR='${ETCBINDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	update-po) || exit 1;

installsrc:
	@(cd src && echo "making in src..." && \
	$(MAKE) \
	WWSBINDIR='${WWSBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	ETCBINDIR='${ETCBINDIR}' \
	HOST='${HOST}' \
	COOKIE='${COOKIE}' \
	LOG_SOCKET_TYPE='${LOG_SOCKET_TYPE}' \
	SSLCERTDIR='${SSLCERTDIR}' \
	PODIR='${prefix}/po' \
	newinstall) || exit 1;

installdoc:
	@(cd doc && echo "make install in doc..." && \
	$(MAKE) \
	ETCBINDIR='${ETCBINDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	install) || exit 1;

installwws:
	@(cd wwsympa && echo "making in wwsympa..." && \
	$(MAKE) \
	SUDO='${SUDO}' \
	enable_secure='${enable_secure}' \
	WWSBINDIR='${WWSBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	ETCBINDIR='${ETCBINDIR}' \
	newinstall) || exit 1;

installwebtt2:
	@(cd web_tt2 && echo "making in web_tt2..." && \
	$(MAKE) \
	WWSBINDIR='${WWSBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	ETCBINDIR='${ETCBINDIR}' \
	newinstall) || exit 1;

installmailtt2:
	@(cd mail_tt2 && echo "making in mail_tt2..." && \
	$(MAKE) \
	WWSBINDIR='${WWSBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	ETCBINDIR='${ETCBINDIR}' \
	newinstall) || exit 1;

installsoap:
	@(cd soap && echo "making in soap/..." && \
	$(MAKE) \
	WWSBINDIR='${WWSBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	ETCBINDIR='${ETCBINDIR}' \
	newinstall) || exit 1;

installsample:
	@(cd src/etc/sample && echo "making in src/etc/sample..." && \
	$(MAKE) LOG_SOCKET_TYPE='${LOG_SOCKET_TYPE}' \
	WWSBINDIR='${WWSBINDIR}' \
	HOST='${HOST}' \
	CONFIG='${CONFIG}' \
	WWSCONFIG='${WWSCONFIG}' \
	ETCBINDIR='${ETCBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' \
	COOKIE='${COOKIE}' \
	SSLCERTDIR='${SSLCERTDIR}' \
	install) || exit 1;

installman:
	@(cd doc/man8 && \
	$(MAKE) PERL='${PERL}' DIR='${DIR}' DESTDIR='${DESTDIR}' SYMPA_VERSION='$(PACKAGE_VERSION)' MANDIR='${MANDIR}' \
	USER='${USER}' GROUP='${GROUP}' \
	CONFDIR='${CONFDIR}' SENDMAIL_ALIASES='${SENDMAIL_ALIASES}' VIRTUAL_ALIASES='${VIRTUAL_ALIASES}' UMASK='${UMASK}'  \
	MAILERPROGDIR='${MAILERPROGDIR}' PIDDIR='${PIDDIR}' SPOOLDIR='${SPOOLDIR}' PIDDIR='${PIDDIR}' ETCBINDIR='${ETCBINDIR}' \
	newinstall) || exit 1;

installscript:
	@(cd src/etc/script && echo "making in src/etc/script..." && \
	$(MAKE) SH='${SH}' CC='${CC}' CFLAGS='${CFLAGS}' PERL='${PERL}' \
	DIR='${DIR}' DESTDIR='${DESTDIR}' SCRIPTDIR='${SCRIPTDIR}' \
	BINDIR='${BINDIR}' SBINDIR='${SBINDIR}' LIBDIR='${LIBDIR}' \
	WWSBINDIR='${WWSBINDIR}' HOST='${HOST}' \
	CONFIG='${CONFIG}' WWSCONFIG='${WWSCONFIG}' ETCBINDIR='${ETCBINDIR}' \
	MAILERPROGDIR='${MAILERPROGDIR}' PIDDIR='${PIDDIR}' \
	COOKIE='${COOKIE}' INITDIR='${INITDIR}' \
	PIDPRE='${PIDPRE}' PIDPOST='${PIDPOST}' LOCKDIR='${LOCKDIR}' \
	OPENSSL='@OPENSSL@' USER='${USER}' GROUP='${GROUP}' install) || exit 1;


installdir:
	@echo "Creating required directories"
	@for dir in $(prefix) $(EXPLDIR) $(CONFDIR) $(SAMPLEDIR) $(ETCDIR) $(BINDIR) $(LOCALEDIR) $(DOCDIR) $(prefix)/static_content $(prefix)/static_content/icons ; do \
		if [ ! -d $(DESTDIR)$$dir ] ; then \
			echo "Creating $(DESTDIR)$$dir"; \
			mkdir -p $(DESTDIR)$$dir; \
			chown $(USER) $(DESTDIR)$$dir; \
			chgrp $(GROUP) $(DESTDIR)$$dir; \
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
			chown $(USER) $(DESTDIR)$(ETCDIR)/$$dir; \
			chgrp $(GROUP) $(DESTDIR)$(ETCDIR)/$$dir; \
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
			chown $(USER) $(DESTDIR)$$dir; \
			chgrp $(GROUP) $(DESTDIR)$$dir; \
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
			chown $(USER) $(DESTDIR)$(prefix)/$$dir; \
			chgrp $(GROUP) $(DESTDIR)$(prefix)/$$dir; \
		fi \
	done \
	fi


installconfig:
	mkdir -p $(DESTDIR)$(CONFDIR)
	@INITCONF='0'
	@for cfile in sympa.conf wwsympa.conf ; do \
	if [ ! -f $(DESTDIR)$(CONFDIR)/$$cfile ] ; then \
	echo "Installing sample config file $$cfile..."; \
	DESTDIR=$(DESTDIR); export DESTDIR; \
	$(PERL) -I $(DESTDIR)$(LIBDIR) $(DESTDIR)$(SBINDIR)/sympa_wizard.pl -c $$cfile; \
	chown $(USER) $(DESTDIR)$(CONFDIR)/$$cfile; \
	chgrp $(GROUP) $(DESTDIR)$(CONFDIR)/$$cfile; \
	if [ "$(DESTDIR)" = "" ]; then \
	INITCONF='1'; \
	fi \
	fi \
	done; \
	if [ "$$INITCONF" ] ; then \
	echo "###############################################"; \
	echo "It seems to be your first installation of Sympa"; \
	echo "The following wizard will help you create your $(CONFDIR)/sympa.conf and $(CONFDIR)/wwsympa.conf :"; \
	DESTDIR=$(DESTDIR); export DESTDIR; \
	$(PERL) -I $(DESTDIR)$(LIBDIR) $(DESTDIR)$(SBINDIR)/sympa_wizard.pl; \
	fi

ChangeLog:
	$(CVS2CL)

tag:	ChangeLog
	@if [ ! $(NEW_VERSION) ]; then \
	echo "Current version is $(VERSION)"; \
	echo "You need to define NEW_VERSION"; \
	else echo $(NEW_VERSION) > .version; cvs ci -m 'preparing $(NEW_VERSION)' .version ChangeLog; cvs tag -F `echo sympa-$(NEW_VERSION)|sed 's/\./_/g'`; \
	fi
