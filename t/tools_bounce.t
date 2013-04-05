#!/usr/bin/perl
# -*- indent-tabs-mode: t; -*-
# vim:ft=perl:noet:sw=8:textwidth=78
# $Id$

use strict;

use FindBin qw($Bin);
use lib "$Bin/../src/lib";

use Test::More;

use Sympa::Message;
use Sympa::Tools::Bounce;

my %tests_rfc1891 = (
	'error1.eml' => {
		'jpackage@zarb.org' => '5.7.1'
	},
	'error2.eml' => {
		'aris@samizdat.net' => '5.1.1'
	},
	'error3.eml' => {
		'tclapes@attglobal.net' => '5.0.0'
	},
	'error4.eml' => {
		'quanet@tin.it' => '5.1.1'
	},
	'error5.eml' => {
		'support@planetmirror.com' => '5.0.0'
	},
	'error6.eml' => undef,
	'error7.eml' => undef,
	'error8.eml' => {
		'chuck@cvip.uofl.edu' => '5.0.0'
	},
	'error9.eml' => {
		'emmanuel.delaborde@citycampus.com' => '4.4.2'
	},
	'error10.eml' => {
		'aiolia@maciste.it' => '4.4.1'
	},
	'error11.eml' => {
		'kenduest@mdk.linux.org.tw' => '4.7.1'
	},
	'error12.eml' => {
		'wojtula95@op.pl' => '4.7.1'
	},
	'error13.eml' => {
		'mlhydeau@austarnet.com.au' => '4.4.1'
	},
	'error14.eml' => {
		'ftpmaster@t-online.fr' => '4.4.1'
	},
	'error15.eml' => {
		'fuwafuwa@jessicara.co.uk' => '4.4.3'
	},
	'error16.eml' => {
		'jpackage@zarb.org' => '5.1.1'
	},
	'error-500-500.01.eml' => {
		'ensghyvx@o2.pl' =>  '5.0.0'
	},
	'error-500-504.01.eml' => {
		'puzvryh1_n@o2.pl' => '5.0.0'
	},
	'error-500-510.01.eml' => {
		'whyvna.pbephren@vtr.net' => '5.0.0'
	},
	'error-500-510.02.eml' => {
		'yhvfirtn@zonainter.org' => '5.0.0'
	},
	'error-500-511.01.eml' => {
		'3nuhqcvp@thda.org' => '5.0.0'
	},
	'error-500-511.02.eml' => {
		'fhccbeg@planetmirror.com' => '5.0.0'
	},
	'error-500-550.01.eml' => {
		'vq3.fnk@hotmail.com' => '5.0.0'
	},
	'error-500-550.02.eml' => {
		'nqzva@bigsearcher.com' => '5.0.0'
	},
	'error-500-550.03.eml' => {
		'nwnlsvwv@ozemail.com.au' =>  '5.0.0'
	},
	'error-500-550.04.eml' => {
		'gbzlgbat@freesurf.fr' => '5.0.0'
	},
	'error-500-550.05.eml' => {
		'yraabav@btinternet.com' => '5.0.0'
	},
	'error-500-550.06.eml' => {
		'senaxyva.furccrefba@mediclinic.co.za' => '5.0.0'
	},
	'error-500-550.07.eml' => {
		'cbgb@inbox.ru' => '5.0.0'
	},
	'error-500-550.08.eml' => {
		'ouqa@ukr.net' => '5.0.0'
	},
	'error-500-550.09.eml' => {
		'yrvssba_m@126.com' => '5.0.0'
	},
	'error-500-550.10.eml' => {
		'nsznpunqb@dcemail.com' => '5.0.0'
	},
	'error-500-550.11.eml' => {
		'ypnfgvyyb@gya.com.pe' => '5.0.0'
	},
	'error-500-550.12.eml' => {
		'zbba@lunarhub.com' => '5.0.0'
	},
	'error-500-550.13.eml' => {
		'vveb.hhfvgnyb@samk.fi' => '5.0.0'
	},
	'error-500-550.14.eml' => {
		'lbevpx_@openoffice.org' => '5.0.0'
	},
	'error-500-550.15.eml' => {
		'zntrvn@kosmoit.com' => '5.0.0'
	},
	'error-500-550.16.eml' => {
		'trabzrtn@earthlink.net' => '5.0.0'
	},
	'error-500-550.17.eml' => {
		'znk@antidepressound.ru' => '5.0.0'
	},
	'error-500-550.18.eml' => {
		'fcbpx@evansville.net' => '5.0.0'
	},
	'error-511-550.01.eml' => {
		'nyrcu@mandriva.org' => '5.1.1'
	},
	'error-511-550.02.eml' => {
		'rhtrav@mandriva.com' => '5.1.1'
	},
	'error-511-550.03.eml' => {
		'nevf@samizdat.net' => '5.1.1'
	},
	'error-511-550.04.eml' => {
		'fnnivx@tiscalinet.it' => '5.1.1'
	},
	'error-511-550.05.eml' => {
		'wrsgloynpx@gmail.com' => '5.1.1'
	},
	'error-511-550.06.eml' => {
		'pynhqr.qhgervyyl@imag.fr' => '5.1.1'
	},
	'error-511-550.07.eml' => {
		'pypf@freeway.net' => '5.1.1'
	},
	'error-511-550.08.eml' => {
		'dhnarg@tin.it' => '5.1.1'
	},
	'error-511-550.09.eml' => {
		'x9nb@charter.net' => '5.1.1'
	},
	'error-511-550.10.eml' => {
		'iznk2122@zahav.net.il' => '5.1.1'
	},
	'error-511-550.11.eml' => {
		'qrylna@trirand.com' => '5.1.1'
	},
	'error-511-550.12.eml' => {
		'porinaf@telusplanet.net' => '5.1.1'
	},
	'error-511-550.13.eml' => {
		'guvreel-obo@orange.fr' => '5.1.1'
	},
	'error-511-550.14.eml' => {
		'vasb@scideralle.org' => '5.1.1'
	},
	'error-511-550.15.eml' => {
		'jurljneq@clear.net' => '5.1.1'
	},
	'error-511-550.16.eml' => {
		'zvxnyn@zarb.org' => '5.1.1'
	},
	'error-511-550.17.eml' => {
		'ebova.znefbyyvre@etudiant.univ-rennes1.fr' => '5.1.1'
	},
	'error-511-550.18.eml' => {
		'fvambqn1@otenet.gr' => '5.1.1'
	},
	'error-511-550.19.eml' => {
		'abarireab@operamail.com' =>  '5.1.1'
	},
	'error-511-550.20.eml' => {
		'vna@centralfrontenac.com' => '5.1.1'
	},
	'error-521-550.01.eml' => {
		'o.purinyvre@libertysurf.fr' => '5.2.1'
	},
	'error-521-550.02.eml' => {
		'wcevaqvi@redhat.com' => '5.2.1'
	},
	'error-521-550.03.eml' => {
		'qnivq.juvgzber@virgin.net' => '5.2.1'
	},
	'error-522.01.eml' => {
		'nyrfk1@centrum.cz' => '5.2.2'
	},
	'error-544.01.eml' => {
		'zvpuvxb.xnqbe@zeusmail.org' => '5.4.4'
	},
	'error-571-554.01.eml' => {
		'bjra.flatr@desy.de' => '5.7.1'
	},
	'error-571-554.02.eml' => {
		'rzraqbmn@cricyt.edu.ar' => '5.7.1'
	},
);

my %tests = (
	'error1.eml' => {
		'fnasser@redhat.com' => '5.7.1'
	},
	'error2.eml' => {
		'aris@samizdat.net' => 'user unknown'
	},
	'error3.eml' => undef,
	'error4.eml' => undef,
	'error5.eml' => undef,
	'error6.eml' => {
		'efthimeros@chemeng.upatras.gr' => '5.1.1'
	},
	'error7.eml' => undef,
	'error8.eml' => undef,
	'error9.eml' => {
		'emmanuel.delaborde@citycampus.com' => 'conversation with citycampus.com[199.59.243.118] timed out while receiving the initial server greeting'
	},
	'error10.eml' => {
		'aiolia@maciste.it' => 'connect to mx2.maciste.it[62.149.198.62]:25: connection timed out'
	},
	'error11.eml' => {
		'kenduest@mdk.linux.org.tw' => '4.7.1',
	},
	'error12.eml' => {
		'wojtula95@op.pl' => '4.7.1',
	},
	'error13.eml' => {
		'mlhydeau@austarnet.com.au' => 'connect to austarnet.com.au[203.22.8.238]:25: connection timed out'
	},
	'error14.eml' => {
		'ftpmaster@t-online.fr' => 'connect to mailx.tcommerce.de[193.158.123.94]:25: connection timed out'
	},
	'error15.eml' => {
		'fuwafuwa@jessicara.co.uk' => 'host or domain name not found. name service error for name=jessicara.co.uk type=mx: host not found, try again'
	},
	'error16.eml' => {
		'nim@zarb.org' => 'unknown user: "nim"',
		'fnasser@zarb.org' => 'unknown user: "fnasser"'
	},
	'error-500-500.01.eml' => {
		'ensghyvx@o2.pl' => 'host mx11.go2.pl[193.17.41.141] said: 500 no such user (in reply to rcpt to command)'
	},
	'error-500-504.01.eml' => {
		'puzvryh1_n@o2.pl' => 'host mx11.go2.pl[193.17.41.141] said: 504 mailbox is disabled (in reply to rcpt to command)'
	},
	'error-500-510.01.eml' => undef,
	'error-500-510.02.eml' => undef,
	'error-500-511.01.eml' => undef,
	'error-500-511.02.eml' => undef,
	'error-500-550.01.eml' => {
		'vq3.fnk@hotmail.com' => 'host mx3.hotmail.com[65.54.188.94] said: 550 requested action not taken: mailbox unavailable (in reply to rcpt to command)'
	},
	'error-500-550.02.eml' => {
		'nqzva@bigsearcher.com' => 'host bigsearcher.com[69.194.230.130] said: 550 no such user here (in reply to rcpt to command)'
	},
	'error-500-550.03.eml' => {
		'nwnlsvwv@ozemail.com.au' => 'host as-av.iinet.net.au[203.0.178.180] said: 550 #5.1.0 address rejected. (in reply to rcpt to command)'
	},
	'error-500-550.04.eml' => {
		'gbzlgbat@freesurf.fr' => 'host mx1.freesurf.fr[80.168.44.23] said: 550 "gbzlgbat@freesurf.fr" is not a known user (in reply to rcpt to command)'
	},
	'error-500-550.05.eml' => {
		'yraabav@btinternet.com' => 'host mx-bt.mail.am0.yahoodns.net[212.82.111.207] said: 554 delivery error: dd this user doesn\'t have a btinternet.com account (yraabav@btinternet.com) [0] - mta1017.bt.mail.ird.yahoo.com (in reply to end of data command)'
	},
	'error-500-550.06.eml' => {
		'senaxyva.furccrefba@mediclinic.co.za' => 'host mail51.mimecast.co.za[41.74.193.51] said: 550 invalid recipient - http://www.mimecast.com/knowledgebase/kbid10473.htm#550 (in reply to rcpt to command)'
	},
	'error-500-550.07.eml' => {
		'cbgb@inbox.ru' => 'host mxs.mail.ru[94.100.176.20] said: 550 message was not accepted -- invalid mailbox. local mailbox cbgb@inbox.ru is unavailable: user not found (in reply to end of data command)'
	},
	'error-500-550.08.eml' => {
		'ouqa@ukr.net' => 'host mxs.ukr.net[195.214.192.100] said: 550 <ouqa@ukr.net> not used (in reply to rcpt to command)'
	},
	'error-500-550.09.eml' => {
		'yrvssba_m@126.com' => 'host 126mx02.mxmail.netease.com[220.181.14.133] said: 550 user not found: yrvssba_m@126.com (in reply to rcpt to command)'
	},
	'error-500-550.10.eml' => {
		'nsznpunqb@dcemail.com' => 'host sitemail.everyone.net[216.200.145.235] said: 550 account inactive (in reply to end of data command)'
	},
	'error-500-550.11.eml' => {
		'ypnfgvyyb@gya.com.pe' => 'host mx01.mep.pandasecurity.com[87.236.241.209] said: 550 relay not permitted (in reply to rcpt to command)'
	},
	'error-500-550.12.eml' => {
		'zbba@lunarhub.com' => 'host smtp.secureserver.net[72.167.238.201] said: 550 #5.1.0 address rejected. (in reply to rcpt to command)'
	},
	'error-500-550.13.eml' => {
		'vveb.hhfvgnyb@samk.fi' => 'host mgw2.samk.fi[193.166.40.62] said: 550 #5.1.0 address rejected. (in reply to rcpt to command)'
	},
	'error-500-550.14.eml' => {
		'lbevpx_@openoffice.org' => 'host mx1.us.apache.org[140.211.11.136] said: 550 apache openoffice no longer relays openoffice.org mail. see http://incubator.apache.org/openofficeorg/mailing-lists.html#legacy-openofficeorg-lists (in reply to rcpt to command)'
	},
	'error-500-550.15.eml' => {
		'zntrvn@kosmoit.com' => 'host kosmoit.com[66.147.244.222] said: 550 no such user here" (in reply to rcpt to command)'
	},
	'error-500-550.16.eml' => {
		'trabzrtn@earthlink.net' => 'host mx4.earthlink.net[209.86.93.229] said: 550 trabzrtn@earthlink.net...user account is unavailable (in reply to rcpt to command)'
	},
	'error-500-550.17.eml' => {
		'znk@antidepressound.ru' => 'host fresnomail.hostforweb.net[216.246.77.209] said: 550 no such user here (in reply to rcpt to command)'
	},
	'error-500-550.18.eml' => {
		'fcbpx@evansville.net' => 'host mx01.windstream.net[162.39.147.49] said: 550 recipient does not exist here (in reply to rcpt to command)'
	},
	'error-511-550.01.eml' => {
		'nyrcu@mandriva.org' => '5.1.1'
	},
	'error-511-550.02.eml' => {
		'rhtrav@mandriva.com' => '5.1.1'
	},
	'error-511-550.03.eml' => {
		'nevf@samizdat.net' => 'user unknown'
	},
	'error-511-550.04.eml' => {
		'fnnivx@tiscalinet.it' => '5.1.1'
	},
	'error-511-550.05.eml' => {
		'wrsgloynpx@gmail.com' => 'host gmail-smtp-in.l.google.com[2a00:1450:400c:c05::1b] said: 550-5.1.1 the email account that you tried to reach does not exist. please try 550-5.1.1 double-checking the recipient\'s email address for typos or 550-5.1.1 unnecessary spaces. learn more at 550 5.1.1 http://support.google.com/mail/bin/answer.py?answer=6596 ku4si4223285wjb.19 - gsmtp (in reply to rcpt to command)'
	},
	'error-511-550.06.eml' => {
		'pynhqr.qhgervyyl@imag.fr' => 'host mx1.imag.fr[2001:660:5301:6::5] said: 550 5.1.1 <pynhqr.qhgervyyl@imag.fr>... user unknown (in reply to rcpt to command)'
	},
	'error-511-550.07.eml' => {
		'pypf@freeway.net' => '5.1.1'
	},
	'error-511-550.08.eml' => undef,
	'error-511-550.09.eml' => {
		'x9nb@charter.net' => '5.1.1'
	},
	'error-511-550.10.eml' => {
		'iznk2122@zahav.net.il' => '5.1.1'
	},
	'error-511-550.11.eml' => {
		'qrylna@trirand.com' => '5.1.1'
	},
	'error-511-550.12.eml' => {
		'porinaf@telusplanet.net' => '5.1.1'
	},
	'error-511-550.13.eml' => {
		'guvreel-obo@orange.fr' => '5.1.1'
	},
	'error-511-550.14.eml' => {
		'vasb@scideralle.org' => 'host spool.mail.gandi.net[2001:4b98:c:521::6] said: 550 5.1.1 <vasb@scideralle.org>: recipient address rejected: user unknown in virtual mailbox table (in reply to rcpt to command)'
	},
	'error-511-550.15.eml' => {
		'jurljneq@clear.net' => 'host aspmx.l.google.com[2a00:1450:400c:c03::1a] said: 550-5.1.1 the email account that you tried to reach does not exist. please try 550-5.1.1 double-checking the recipient\'s email address for typos or 550-5.1.1 unnecessary spaces. learn more at 550 5.1.1 http://support.google.com/mail/bin/answer.py?answer=6596 l6si2662364wiy.60 - gsmtp (in reply to rcpt to command)'
	},
	'error-511-550.16.eml' => {
		'zvxnyn@zarb.org' => '5.1.1'
	},
	'error-511-550.17.eml' => {
		'ebova.znefbyyvre@etudiant.univ-rennes1.fr' => '5.1.1'
	},
	'error-511-550.18.eml' => {
		'fvambqn1@otenet.gr' => '5.1.1'
	},
	'error-511-550.19.eml' => {
		'abarireab@operamail.com' =>  '5.1.1'
	},
	'error-511-550.20.eml' => {
		'vna@centralfrontenac.com' => '5.1.1'
	},
	'error-521-550.01.eml' => {
		'o.purinyvre@libertysurf.fr' => '5.2.1'
	},
	'error-521-550.02.eml' => {
		'wcevaqvi@redhat.com' => '5.2.1'
	},
	'error-521-550.03.eml' => {
		'qnivq.juvgzber@virgin.net' => 'host aspmx.l.google.com[2a00:1450:400c:c03::1b] said: 550 5.2.1 the email account that you tried to reach is disabled. va4si4196384wjc.145 - gsmtp (in reply to rcpt to command)'
	},
	'error-522.01.eml' => undef,
	'error-544.01.eml' => {
		'zvpuvxb.xnqbe@zeusmail.org' => 'host or domain name not found. name service error for name=zeusmail.org type=aaaa: host not found'
	},
	'error-571-554.01.eml' => {
		'bjra.flatr@desy.de' => '5.7.1'
	},
	'error-571-554.02.eml' => {
		'rzraqbmn@cricyt.edu.ar' => '5.7.1'
	},
);

plan tests => (scalar keys %tests_rfc1891) + (scalar keys %tests);

chdir "$Bin/..";

foreach my $test (sort keys %tests_rfc1891) {
	my $message = Sympa::Message->new(
		file       => "t/samples/$test",
		noxsympato => 1
	);
	is_deeply(
		Sympa::Tools::Bounce::parse_rfc1891_notification($message),
		$tests_rfc1891{$test},
		"$test message parsing as RFC1891 compliant notification"
	);
}

foreach my $test (sort keys %tests) {
	my $message = Sympa::Message->new(
		file       => "t/samples/$test",
		noxsympato => 1
	);
	is_deeply(
		Sympa::Tools::Bounce::parse_notification($message),
		$tests{$test},
		"$test message parsing as arbitrary notification"
	);
}
