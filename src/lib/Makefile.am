nobase_modules_DATA = Sympa/Admin.pm \
		      Sympa/Archive.pm \
		      Sympa/Auth.pm \
		      Sympa/Bulk.pm \
		      Sympa/Challenge.pm \
		      Sympa/Commands.pm \
		      Sympa/Configuration.pm \
		      Sympa/Configuration/XML.pm \
		      Sympa/Configuration/Definition.pm \
		      Sympa/Constants.pm \
		      Sympa/DatabaseDescription.pm \
		      Sympa/Datasource.pm \
		      Sympa/Datasource/LDAP.pm \
		      Sympa/Datasource/SQL.pm \
		      Sympa/Datasource/SQL/Default.pm \
		      Sympa/Datasource/SQL/Informix.pm \
		      Sympa/Datasource/SQL/MySQL.pm \
		      Sympa/Datasource/SQL/Oracle.pm \
		      Sympa/Datasource/SQL/PostgreSQL.pm \
		      Sympa/Datasource/SQL/SQLite.pm \
		      Sympa/Datasource/SQL/Sybase.pm \
		      Sympa/Family.pm \
		      Sympa/Fetch.pm \
		      Sympa/HTML/FormatText.pm \
		      Sympa/Language.pm \
		      Sympa/LDAP.pm \
		      Sympa/List.pm \
		      Sympa/Lock.pm \
		      Sympa/Log.pm \
		      Sympa/Mail.pm \
		      Sympa/Message.pm \
		      Sympa/OAuth/Consumer.pm \
		      Sympa/OAuth/Provider.pm \
		      Sympa/PlainDigest.pm \
		      Sympa/Report.pm \
		      Sympa/Robot.pm \
		      Sympa/Scenario.pm \
		      Sympa/SDM.pm \
		      Sympa/Session.pm \
		      Sympa/SharedDocument.pm \
		      Sympa/SOAP.pm \
		      Sympa/Spool.pm \
		      Sympa/Task.pm \
		      Sympa/Template.pm \
		      Sympa/Template/Compat.pm \
		      Sympa/Tools.pm \
		      Sympa/Tools/Bounce.pm \
		      Sympa/Tools/Cookie.pm \
		      Sympa/Tools/Daemon.pm \
		      Sympa/Tools/Data.pm \
		      Sympa/Tools/DKIM.pm \
		      Sympa/Tools/File.pm \
		      Sympa/Tools/SMIME.pm \
		      Sympa/Tools/Time.pm \
		      Sympa/Tracking.pm \
		      Sympa/Transport.pm \
		      Sympa/Upgrade.pm \
		      Sympa/VOOT/Consumer.pm \
		      Sympa/VOOT/Provider.pm \
		      Sympa/WebAgent.pm \
		      Sympa/WWSympa.pm

EXTRA_DIST = Sympa/Constants.pm.in $(nobase_modules_DATA)
CLEANFILES = Sympa/Constants.pm

Sympa/Constants.pm: Sympa/Constants.pm.in Makefile
	[ -d Sympa ] || mkdir Sympa
	rm -f $@
	$(AM_V_GEN)$(SED) \
		-e 's|--VERSION--|$(VERSION)|' \
		-e 's|--USER--|$(USER)|' \
		-e 's|--GROUP--|$(GROUP)|' \
		-e 's|--CONFIG--|$(CONFIG)|' \
		-e 's|--WWSCONFIG--|$(WWSCONFIG)|' \
		-e 's|--SENDMAIL_ALIASES--|$(SENDMAIL_ALIASES)|' \
		-e 's|--piddir--|$(piddir)|' \
		-e 's|--expldir--|$(expldir)|' \
		-e 's|--spooldir--|$(spooldir)|' \
		-e 's|--sysconfdir--|$(sysconfdir)|' \
		-e 's|--localedir--|$(localedir)|' \
		-e 's|--libexecdir--|$(libexecdir)|' \
		-e 's|--sbindir--|$(sbindir)|' \
		-e 's|--scriptdir--|$(scriptdir)|' \
		-e 's|--modulesdir--|$(modulesdir)|' \
		-e 's|--defaultdir--|$(defaultdir)|' \
		-e 's|--staticdir--|$(staticdir)|' \
		-e 's|--arcdir--|$(arcdir)|' \
		-e 's|--bouncedir--|$(bouncedir)|' \
		< $(srcdir)/$@.in > $@
