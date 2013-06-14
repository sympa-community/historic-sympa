TESTS = compile_modules.t \
	compile_executables.t \
	critic.t \
	var.t \
	pod-syntax.t \
	pod-coverage.t \
	pod-spelling.t \
	space.t \
	datasource/mysql.t \
	datasource/mysql_live.t \
	datasource/oracle.t \
	datasource/postgresql.t \
	datasource/postgresql_live.t \
	datasource/sqlite.t \
	datasource/sqlite_live.t \
	datasource/sybase.t \
	tools_data.t \
	tools_file.t \
	tools_password.t  \
	tools_time.t \
	tools_bounce.t \
	tools_smime.t \
	message.t \
	upgrade.t \
	lock.t

TEST_LOG_DRIVER = env AM_TAP_AWK='$(AWK)' $(SHELL) \
                       $(top_srcdir)/tap-driver.sh

EXTRA_DIST = $(TESTS)
