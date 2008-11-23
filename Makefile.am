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

SUBDIRS = src wwsympa soap web_tt2 mail_tt2 doc po

install-data-hook: installdir installconfig nextstep importantchanges

installdir:
	@echo "Creating required directories"
	@for dir in $(EXPLDIR); do \
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
                ETCBINDIR=$(DATADIR); export ETCBINDIR; \
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
			chown $(USER) $(DESTDIR)$(prefix)/$$dir || /bin/true; \
			chgrp $(GROUP) $(DESTDIR)$(prefix)/$$dir || /bin/true; \
		fi \
	done \
	fi

installconfig:
	@echo "Installing basic configuration ..."
	-$(DESTDIR)$(BINDIR)/sympa_wizard.pl \
		--create sympa.conf --target $(DESTDIR)$(ETCDIR)/sympa.conf
	-$(DESTDIR)$(BINDIR)/sympa_wizard.pl \
		--create wwsympa.conf --target $(DESTDIR)$(ETCDIR)/wwsympa.conf

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
