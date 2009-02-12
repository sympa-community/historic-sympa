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

SUBDIRS = script

install-data-local: makedir installscenari installtask_models installetc installlisttemplates installfamilies installgeneral_task_models

makedir:
	@if [ ! -d $(DESTDIR)$(DATADIR) ]; then \
		echo "Creating required directory $(DESTDIR)$(DATADIR)/etc"; \
		install -d -m 755 $(DESTDIR)$(DATADIR); \
	fi

installtask_models:
	@echo "Installing default task models ..."
	install -d -m 755 $(DESTDIR)$(DATADIR)/list_task_models
	install -m 644 list_task_models/* \
		$(DESTDIR)$(DATADIR)/list_task_models

installgeneral_task_models:
	@echo "Installing general task models ..."
	install -d -m 755 $(DESTDIR)$(DATADIR)/global_task_models
	install -m 644 global_task_models/* \
		$(DESTDIR)$(DATADIR)/global_task_models

installetc:
	@echo "Installing default configuration ..."
	install -m 644 \
		topics.conf nrcpt_by_domain.conf \
		ldap_alias_manager.conf edit_list.conf \
		create_list.conf crawlers_detection.conf auth.conf \
		ca-bundle.crt mhonarc-ressources.tt2 list_aliases.tt2 \
		$(DESTDIR)$(DATADIR)
	sed -i -e 's|--MAILERPROGDIR--|$(BINDIR)|' \
		$(DESTDIR)$(DATADIR)/list_aliases.tt2

installlisttemplates:
	@echo "Installing default list templates ..."
	install -d -m 755 $(DESTDIR)$(DATADIR)/create_list_templates
	install -d -m 755 \
		$(DESTDIR)$(DATADIR)/create_list_templates/discussion_list
	install -m 644 create_list_templates/discussion_list/* \
		$(DESTDIR)$(DATADIR)/create_list_templates/discussion_list
	install -d -m 755 \
		$(DESTDIR)$(DATADIR)/create_list_templates/hotline
	install -m 644 create_list_templates/hotline/* \
		$(DESTDIR)$(DATADIR)/create_list_templates/hotline
	install -d -m 755 \
		$(DESTDIR)$(DATADIR)/create_list_templates/html-news-letter
	install -m 644 create_list_templates/html-news-letter/* \
		$(DESTDIR)$(DATADIR)/create_list_templates/html-news-letter
	install -d -m 755 \
		$(DESTDIR)$(DATADIR)/create_list_templates/intranet_list
	install -m 644 create_list_templates/intranet_list/* \
		$(DESTDIR)$(DATADIR)/create_list_templates/intranet_list
	install -d -m 755 \
		$(DESTDIR)$(DATADIR)/create_list_templates/news-letter
	install -m 644 create_list_templates/news-letter/* \
		$(DESTDIR)$(DATADIR)/create_list_templates/news-letter
	install -d -m 755 \
		$(DESTDIR)$(DATADIR)/create_list_templates/private_working_group/
	install -m 644 create_list_templates/private_working_group/* \
		$(DESTDIR)$(DATADIR)/create_list_templates/private_working_group/
	install -d -m 755 \
		$(DESTDIR)$(DATADIR)/create_list_templates/public_web_forum
	install -m 644 create_list_templates/public_web_forum/* \
		$(DESTDIR)$(DATADIR)/create_list_templates/public_web_forum

installfamilies:
	@echo "Installing default list families ..."
	install -d -m 755 $(DESTDIR)$(DATADIR)/families
	install -d -m 755 $(DESTDIR)$(DATADIR)/families/sample-auto
	install -m 644 families/sample-auto/* \
		$(DESTDIR)$(DATADIR)/families/sample-auto

installscenari:
	@echo "Installing default scenari..."
	install -d -m 755 $(DESTDIR)$(DATADIR)/scenari
	install -m 644 scenari/* \
		$(DESTDIR)$(DATADIR)/scenari
	$(PERL) ../../set_symlinks.pl scenari $(DESTDIR)$(DATADIR)/scenari
