modules_DATA = admin.pm Archive.pm Bulk.pm Commands.pm confdef.pm Conf.pm \
	       CAS.pm Config_XML.pm Family.pm Language.pm List.pm Log.pm \
	       mail.pm Ldap.pm Upgrade.pm Lock.pm Version.pm Fetch.pm \
	       Message.pm Task.pm Datasource.pm SQLSource.pm LDAPSource.pm \
	       Scenario.pm PlainDigest.pm report.pm \
	       tools.pm tt2.pm time_utils.pm

nobase_modules_DATA = Sympa/Constants.pm

EXTRA_DIST = Sympa/Constants.pm.in
CLEANFILES = Sympa/Constants.pm

Sympa/Constants.pm: Sympa/Constants.pm.in Makefile
	rm -f $@
	sed \
		-e 's|--PERL--|$(PERL)|' \
		-e 's|--USER--|$(USER)|' \
		-e 's|--GROUP--|$(GROUP)|' \
		-e 's|--VERSION--|$(VERSION)|' \
		-e 's|--SENDMAIL_ALIASES--|$(SENDMAIL_ALIASES)|' \
		-e 's|--CONFIG--|$(CONFIG)|' \
		-e 's|--WWSCONFIG--|$(WWSCONFIG)|' \
		-e 's|--prefix--|$(prefix)|' \
		-e 's|--piddir--|$(piddir)|' \
		-e 's|--libexecdir--|$(libexecdir)|' \
		-e 's|--sbindir--|$(sbindir)|' \
		-e 's|--localedir--|$(localedir)|' \
		-e 's|--pkgdatadir--|$(pkgdatadir)|' \
		-e 's|--sysconfdir--|$(sysconfdir)|' \
		-e 's|--expldir--|$(expldir)|' \
		-e 's|--spooldir--|$(spooldir)|' \
		< $< > $@
