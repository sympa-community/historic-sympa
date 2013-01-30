TESTS = 00compile_modules.t \
	01compile_executables.t \
	02critic.t \
	03var.t \
	04pod.t \
	05pod-coverage.t \
	06spelling.t \
	07space.t \
	datasource_mysql.t \
	datasource_oracle.t \
	datasource_postgresql.t \
	datasource_sqlite.t \
	datasource_sybase.t \
	tools_data.t \
	tools_file.t \
	tools_password.t  \
	tools_time.t \
	message.t \
	upgrade.t \
	lock.t

TEST_LOG_DRIVER = env AM_TAP_AWK='$(AWK)' $(SHELL) \
                       $(top_srcdir)/tap-driver.sh

EXTRA_DIST = $(TESTS)
