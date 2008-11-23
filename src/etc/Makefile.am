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

SUBDIRS = script sample

install-data-local: makedir installscenari installtask_models installetc installlisttemplates installfamilies installgeneral_task_models

makedir:
	@if [ ! -d $(DESTDIR)$(DATADIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/etc"; \
		mkdir -p $(DESTDIR)$(DATADIR); \
	fi
	@if [ ! -d $(DESTDIR)$(DATADIR)/scenari ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/scenari"; \
		mkdir $(DESTDIR)$(DATADIR)/scenari; \
	fi
	@if [ ! -d $(DESTDIR)$(DATADIR)/create_list_templates ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/create_list_templates"; \
		mkdir $(DESTDIR)$(DATADIR)/create_list_templates; \
	fi
	@if [ ! -d $(DESTDIR)$(DATADIR)/families ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/families"; \
		mkdir $(DESTDIR)$(DATADIR)/families; \
	fi
	@if [ ! -d $(DESTDIR)$(DATADIR)/list_task_models ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/list_task_models"; \
		mkdir $(DESTDIR)$(DATADIR)/list_task_models; \
	fi
	@if [ ! -d $(DESTDIR)$(DATADIR)/global_task_models ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/global_task_models"; \
		mkdir $(DESTDIR)$(DATADIR)/global_task_models; \
	fi

installtask_models:
	@echo "Installing default task models ..."
	cp -pR list_task_models/* $(DESTDIR)$(DATADIR)/list_task_models

installgeneral_task_models:
	@echo "Installing general task models ..."
	cp -pR global_task_models/* $(DESTDIR)$(DATADIR)/global_task_models

installetc:
	@echo "Installing default configuration ..."
	cp \
		topics.conf nrcpt_by_domain.conf \
		ldap_alias_manager.conf edit_list.conf \
		create_list.conf crawlers_detection.conf auth.conf \
		ca-bundle.crt $(DESTDIR)$(DATADIR)/
	@( \
		UMASK=0664; export UMASK;\
		INSTALLDIR=$(DATADIR); export INSTALLDIR;\
		DESTDIR=$(DESTDIR); export DESTDIR;\
		DARK_COLOR=$(DARK_COLOR); export DARK_COLOR;\
		LIGHT_COLOR=$(LIGHT_COLOR); export LIGHT_COLOR;\
		BG_COLOR=$(BG_COLOR); export BG_COLOR;\
		TEXT_COLOR=$(TEXT_COLOR); export TEXT_COLOR;\
		ERROR_COLOR=$(ERROR_COLOR); export ERROR_COLOR;\
		SHADED_COLOR=$(SHADED_COLOR); export SHADED_COLOR;\
		$(PERL) ../../subst.pl mhonarc-ressources.tt2 README \
	)
	@( \
		UMASK=0664; export UMASK;\
		INSTALLDIR=$(DATADIR); export INSTALLDIR;\
		MAILERPROGDIR=$(BINDIR); export MAILERPROGDIR;\
		$(PERL) ../../subst.pl list_aliases.tt2 \
	)

installlisttemplates:
	@echo "Installing default list templates ..."
	cp -pR create_list_templates/* $(DESTDIR)$(DATADIR)/create_list_templates

installfamilies:
	@echo "Installing default list families ..."
	cp -pR families/* $(DESTDIR)$(DATADIR)/families

installscenari:
	@echo "Installing default scenari..."
	cp scenari/*.* $(DESTDIR)$(DATADIR)/scenari
	$(PERL) ../../set_symlinks.pl scenari $(DESTDIR)$(DATADIR)/scenari
