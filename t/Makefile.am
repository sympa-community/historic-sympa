TESTS = compile_modules.t \
	compile_executables.t \
	critic.t \
	var.t \
	pod-syntax.t \
	pod-coverage.t \
	pod-spelling.t \
	space.t \
	datasource_mysql.t \
	datasource_oracle.t \
	datasource_postgresql.t \
	datasource_sqlite.t \
	datasource_sybase.t \
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
