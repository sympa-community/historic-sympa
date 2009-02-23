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

SUBDIRS = src wwsympa soap web_tt2 mail_tt2 doc po po-wwsympa

install-data-hook: installdir installconfig nextstep importantchanges

installdir:
	@echo "Creating writable directories"
	@for dir in $(EXPLDIR) $(SPOOLDIR) $(SPOOLDIR)/msg $(SPOOLDIR)/digest \
		$(SPOOLDIR)/moderation $(SPOOLDIR)/expire $(SPOOLDIR)/auth \
		$(SPOOLDIR)/outgoing $(SPOOLDIR)/tmp \ $(SPOOLDIR)/task \
		$(prefix)/bounce $(prefix)/arc; do \
		if [ ! -d $(DESTDIR)$$dir ] ; then \
			echo "Creating $(DESTDIR)$$dir"; \
			install -d -m 755 $(DESTDIR)$$dir; \
			chown $(USER) $(DESTDIR)$$dir || /bin/true; \
			chgrp $(GROUP) $(DESTDIR)$$dir || /bin/true; \
		fi \
	done
	@echo "Creating non-writable directories"
	@for dir in create_list_templates mail_tt2 web_tt2 scenari \
		task_models general_task_models; do \
		if [ ! -d $(DESTDIR)$(sysconfdir)/$$dir ] ; then \
			echo "Creating $(DESTDIR)$(sysconfdir)/$$dir"; \
			install -d -m 755 $(DESTDIR)$(sysconfdir)/$$dir; \
		fi \
	done

installconfig:
	@echo "Installing basic configuration ..."
	-$(DESTDIR)$(sbindir)/sympa_wizard.pl \
		--create sympa.conf --target $(DESTDIR)$(sysconfdir)/sympa.conf
	-$(DESTDIR)$(sbindir)/sympa_wizard.pl \
		--create wwsympa.conf --target $(DESTDIR)$(sysconfdir)/wwsympa.conf

nextstep: 
	@echo ""
	@echo "#########################################################"
	@echo "# If you install Sympa for the first time on this server"
	@echo "# you should check the INSTALL file."
	@echo "#"
	@echo "# If you are upgrading, you now need to run"
	@echo "#    $(sbindir)/sympa.pl --upgrade"
	@echo "#######################################################"

importantchanges:
	@( 	PERL=$(PERL); export PERL; \
		UMASK=0600; export UMASK; \
		DESTDIR=$(DESTDIR); export DESTDIR; \
		BINDIR=$(libexecdir); export BINDIR; \
		SBINDIR=$(sbindir); export SBINDIR; \
		LIBDIR=$(datadir)/sympa/etc; export LIBDIR; \
		ETCDIR=$(sysconfdir); export ETCDIR;\
		USER=$(USER); export USER;\
		GROUP=$(GROUP); export GROUP;\
		SYMPA_VERSION=$(PACKAGE_VERSION); export SYMPA_VERSION; \
		$(PERL) ./important_changes.pl \
	) ;
