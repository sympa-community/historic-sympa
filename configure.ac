# configure.in - Top-level configure.in for Sympa
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

AC_PREREQ(2.59)
AC_INIT(sympa, 6.0a.8, sympa-authors@cru.fr)
AM_INIT_AUTOMAKE

AC_PREFIX_DEFAULT(/home/sympa)

## Directories setup
## for main config files

## location of main config files
CONFDIR='${prefix}/etc'
AC_ARG_WITH(
    confdir,
    AS_HELP_STRING(
	[--with-confdir=DIR],
	[Sympa main configuration files in DIR (default ${prefix}/etc)]
    ),
    [CONFDIR="$withval"]
)
AC_SUBST(CONFDIR)

## location of CGIs
CGIDIR='${prefix}/bin'
AC_ARG_WITH(
    cgidir,
    AS_HELP_STRING(
	[--with-cgidir=DIR],
	[CGIs in DIR (default ${prefix}/bin)]
    ),
    [CGIDIR="$withval"]
)
AC_SUBST(CGIDIR)

## location of user executables
BINDIR='${prefix}/bin'
AC_ARG_WITH(
    bindir,
    AS_HELP_STRING(
	[--with-bindir=DIR],
	[user executables in DIR (default ${prefix}/bin). queue and bouncequeue programs will be installed in this directory. If sendmail is configured to use smrsh (check the mailer prog definition in your sendmail.cf), this should point to /etc/smrsh. This is probably the case if you are using Linux]
    ),
    [BINDIR="$withval"]
)
AC_SUBST(BINDIR)

## location of system admin executables
SBINDIR='${prefix}/bin'
AC_ARG_WITH(
    sbindir,
    AS_HELP_STRING(
	[--with-sbindir=DIR],
	[system admin executables in DIR (default ${prefix}/bin)]
    ),
    [SBINDIR="$withval"]
)
AC_SUBST(SBINDIR)

## location of program executables
LIBEXECDIR='${prefix}/bin'
AC_ARG_WITH(
    libexecdir,
    AS_HELP_STRING(
	[--with-libexecdir=DIR],
	[program executables in DIR (default ${prefix}/bin)]
    ),
    [LIBEXECDIR="$withval"]
)
AC_SUBST(LIBEXECDIR)

## location of Perl modules
LIBDIR='${prefix}/bin'
AC_ARG_WITH(
    libdir,
    AS_HELP_STRING(
	[--with-libdir=DIR]
	[Perl modules in DIR (default ${prefix}/bin)]
    ),
    [LIBDIR="$withval"]
)
AC_SUBST(LIBDIR)

## location of default *read-only* data files
DATADIR='${prefix}/bin/etc'
AC_ARG_WITH(
    datadir,
    AS_HELP_STRING(
	[--with-datadir=DIR]
	[default *read-only* data files in DIR (default ${prefix}/bin/etc)]
    ),
    [DATADIR="$withval"]
)
AC_SUBST(DATADIR)

## location of modifiable data files
EXPLDIR='${prefix}/expl'
AC_ARG_WITH(
    expldir,
    AS_HELP_STRING(
	[--with-expldir=DIR],
	[modifiable data files in DIR (default ${prefix}/expl)]
    ),
    [EXPLDIR="$withval"]
)
AC_SUBST(EXPLDIR)

## location of documentation
AC_ARG_WITH(
    mandir,
    AS_HELP_STRING(
	[--with-mandir=DIR],
	[obsolete option, use --mandir instead]
    ),
    [
     AC_MSG_WARN([obsolete --with-mandir option used])
     mandir="$withval"
     ]
)

## SYS V init scripts directory
INITDIR='${prefix}/etc/rc.d/init.d'
AC_ARG_WITH(
    initdir,
    AS_HELP_STRING(
	[--with-initdir=DIR],
	[install System V init script in DIR  (default /etc/rc.d/init.d)]
    ),
    [INITDIR="$withval"]
)
AC_SUBST(INITDIR)

## Lock directory
LOCKDIR=/var/lock/subsys
AC_ARG_WITH(
    lockdir,
    AS_HELP_STRING(
	[--with-lockdir=DIR],
	[create lock files in DIR  (default /var/lock/subsys)]
    ),
    [LOCKDIR="$withval"]
)
AC_SUBST(LOCKDIR)

## directory for storing .pid files
PIDDIR='${prefix}'
AC_ARG_WITH(
    piddir,
    AS_HELP_STRING(
	[--with-piddir=DIR],
	[create .pid files in DIR (default ${prefix})]
    ),
    [PIDDIR="$withval"]
)
AC_SUBST(PIDDIR)

## directory for Config directories populated by the user
ETCDIR='${prefix}/etc'
AC_ARG_WITH(
    etcdir,
    AS_HELP_STRING(
	[--with-etcdir=DIR],
	[Config directories populated by the user are in DIR (default ${prefix}/etc)]
    ),
    [ETCDIR="$withval"]
)
AC_SUBST(ETCDIR)

## directory for language files
LOCALEDIR='${prefix}/locale'
AC_ARG_WITH(
    localedir,
    AS_HELP_STRING(
	[--with-localedir=DIR],
	[create language files in DIR  (default ${prefix}/locale)]
    ),
    [LOCALEDIR="$withval"]
)
AC_SUBST(LOCALEDIR)

## directory for Documentation files
AC_ARG_WITH(
    docdir,
    AS_HELP_STRING(
	[--with-docdir=DIR],
	[obsolete option, use --docdir instead]
    ),
    [
	AC_MSG_WARN([obsolete --with-docdir option used])
	docdir="$withval"
    ]
)

## directory for script files
SCRIPTDIR='${prefix}/bin'
AC_ARG_WITH(
    scriptdir,
    AS_HELP_STRING(
	[--with-scriptdir=DIR],
	[create script files in DIR  (default ${prefix}/bin)]
    ),
    [SCRIPTDIR="$withval"]
)
AC_SUBST(SCRIPTDIR)

## directory for sample files
AC_ARG_WITH(
    sampledir,
    AS_HELP_STRING(
	[--with-sampledir=DIR],
	[obsolete option, samples are now installed with documentation]
    ),
    [
	AC_MSG_WARN([obsolete --with-sampledir option used])
    ]
)

## directory for sample files
SPOOLDIR='${prefix}/spool'
AC_ARG_WITH(
    spooldir,
    AS_HELP_STRING(
	[--with-spooldir=DIR],
	[spool directory is DIR  (default ${prefix}/spool)]
    ),
    [SPOOLDIR="$withval"]
)
AC_SUBST(SPOOLDIR)

# SSL certs dir
SSLCERTDIR=$EXPLDIR/X509-user-certs
AC_SUBST(SSLCERTDIR)

CONFIG=$CONFDIR/sympa.conf
AC_SUBST(CONFIG)
WWSCONFIG=$CONFDIR/wwsympa.conf
AC_SUBST(WWSCONFIG)

AC_PROG_CC

AC_ARG_WITH(
    [perl],
    AS_HELP_STRING(
	[--with-perl=FULLPATH],
        [set full path to Perl interpreter]
    ),
    [PERL="$withval"]
)
if test -n "$PERL"; then
    # user-supplied value
    AC_MSG_CHECKING([user-supplied perl interpreter])
    if test -f "$PERL"; then
	:
    else
	AC_MSG_RESULT([non-existing])
	AC_MSG_ERROR([invalid value $PERL for perl interpreter])
    fi
    if test -x "$PERL"; then
	:
    else
	AC_MSG_RESULT([non-executable])
	AC_MSG_ERROR([invalid value $PERL for perl interpreter])
    fi
    AC_MSG_RESULT([$PERL])
else
    # check in PATH
    AC_PATH_PROG(PERL, perl)
    if test -z "$PERL"; then
	AC_MSG_ERROR([perl required])
    fi
fi

AC_PATH_PROG(MSGFMT, msgfmt)
if test -z "$MSGFMT"; then
    AC_MSG_ERROR([msgfmt required])
fi


USER=sympa
AC_ARG_WITH(
    [user],
    AS_HELP_STRING(
	[--with-user=LOGIN],
	[set sympa user name (default sympa)]
    ),
    [USER="$withval"]
)
AC_SUBST(USER)

GROUP=sympa
AC_ARG_WITH(
    [group],
    AS_HELP_STRING(
	[--with-group=LOGIN],
	[set sympa group name (default sympa)]
    ),
    [GROUP="$withval"]
)
AC_SUBST(GROUP)

SENDMAIL_ALIASES=/etc/mail/sympa_aliases
AC_ARG_WITH(
    [sendmail_aliases],
    AS_HELP_STRING(
	[--with-sendmail_aliases=ALIASFILE],
	[set aliases file to be used by Sympa (default /etc/mail/sympa_aliases)]
    ),
    [SENDMAIL_ALIASES="$withval"]
)
AC_SUBST(SENDMAIL_ALIASES)

## The postfix virtual file we use. Better use a seperate one for sympa.
## Of course an extra alias file must be generated with proper permissions
## (owner sympa, write access for sympa, no write access for anyone else)
## and declared in main.cf!
VIRTUAL_ALIASES=/etc/mail/sympa_virtual
AC_ARG_WITH(
    [virtual_aliases],
    AS_HELP_STRING(
	[--with-virtual_aliases=ALIASFILE],
	[ set postfix virtual file to be used by Sympa (default /etc/mail/sympa_virtual)]
    ),
    [VIRTUAL_ALIASES="$withval"]
)
AC_SUBST(VIRTUAL_ALIASES)

NEWALIASES=/usr/bin/newaliases
AC_ARG_WITH(
    [newaliases],
    AS_HELP_STRING(
	[--with-newaliases=FULLPATH],
	[set path to newaliases command (default /usr/bin/newaliases)]
    ),
    [NEWALIASES="$withval"]
)
AC_SUBST(NEWALIASES)

NEWALIASES_ARG=
AC_ARG_WITH(
    [newaliases_arg],
    AS_HELP_STRING(
	[--with-newaliases_arg=ARGS],
	[set arguments to newaliases command (default NONE)]
    ),
    [NEWALIASES_ARG="$withval"]
)
AC_SUBST(NEWALIASES_ARG)

POSTMAP=/usr/sbin/postmap
AC_ARG_WITH(
    [postmap],
    AS_HELP_STRING(
	[--with-postmap=FULLPATH],
	[set path to postfix postmap command (default /usr/sbin/postmap)]
    ),
    [POSTMAP="$withval"]
)
AC_SUBST(POSTMAP)

POSTMAP_ARG=${VIRTUAL_ALIASES}
AC_ARG_WITH(
    [postmap_arg],
    AS_HELP_STRING(
	[--with-postmap_arg=ARGS],
	[set arguments to postfix postmap command (default [same as virtual_aliases])]
    ),
    [POSTMAP_ARG="$withval"]
)
AC_SUBST(POSTMAP_ARG)

AC_CONFIG_FILES([
    Makefile
    src/Makefile
    src/etc/Makefile
    src/etc/sample/Makefile
    src/etc/script/Makefile
    soap/Makefile
    doc/Makefile
    doc/man8/Makefile
    web_tt2/Makefile
    wwsympa/Makefile
    mail_tt2/Makefile
    po/Makefile
])
AC_OUTPUT
