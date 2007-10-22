#!/usr/bin/perl

eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell
# $File: //member/autrijus/Locale-Maketext-Lexicon/bin/xgettext.pl $ $Author$
# $Revision$ $Change: 5999 $ $DateTime: 2003/05/20 07:50:59 $
## [O. Salaun] 12/08/02 : Also look for gettext() in perl code
##                        No more escape '\' chars
##                        Extract gettext_id entries from List.pm
##                        Extract title.gettext entries from scenarios

use strict;
use Getopt::Std;
use Pod::Usage;
use constant NUL  => 0;
use constant BEG  => 1;
use constant PAR  => 2;
use constant QUO1 => 3;
use constant QUO2 => 4;
use constant QUO3 => 5;
use constant BEGM => 6;
use constant PARM => 7;
use constant QUOM1 => 8;
use constant QUOM2 => 9;
use constant COMM => 10;

=head1 NAME

xgettext.pl - Extract gettext strings from source

=head1 SYNOPSIS

B<xgettext.pl> [ B<-u> ] [ B<-g> ] [ B<-o> I<outputfile> ] [ I<inputfile>... ]

=head1 OPTIONS

[ B<-u> ] Disables conversion from B<Maketext> format to B<Gettext>
format -- i.e. it leaves all brackets alone.  This is useful if you are
also using the B<Gettext> syntax in your program.

[ B<-g> ] Enables GNU gettext interoperability by printing C<#,
maketext-format> before each entry that has C<%> variables.

[ B<-o> I<outputfile> ] PO file name to be written or incrementally
updated C<-> means writing to F<STDOUT>.  If not specified,
F<messages.po> is used.

[ I<inputfile>... ] is the files to extract messages from.

=head1 DESCRIPTION

This program extracts translatable strings from given input files, or
STDIN if none are given.

Currently the following formats of input files are supported:

=over 4

=item Perl source files

Valid localization function names are: C<translate>, C<maketext>,
C<loc>, C<x>, C<_> and C<__>.

=item HTML::Mason

The text inside C<E<lt>&|/lE<gt>I<...>E<lt>/&E<gt>> or
C<E<lt>&|/locE<gt>I<...>E<lt>/&E<gt>> will be extracted.

=item Template Toolkit

Texts inside C<[%|l%]...[%END%]>, C<[%|loc%]...[%END%]> or C<[%|locdt%]...[%END%]>
are extracted.

=item Text::Template

Sentences of texts between C<STARTxxx> and C<ENDxxx> are
extracted.

=cut

my (%file, %type_of_entries, %Lexicon, %opts);
my ($PO, $out);

# options as above. Values in %opts
getopts('hugo:', \%opts)
    or pod2usage( -verbose => 1, -exitval => 1 );
$opts{h} and pod2usage( -verbose => 2, -exitval => 0 );

$PO = $opts{o} || "messages.po";

@ARGV = ('-') unless @ARGV;

## Ordering files to present the most interresting strings to translate first.
my %files_to_parse;
foreach my $file_to_parse (@ARGV) {
    $files_to_parse{$file_to_parse} = 1;
}
my %favoured_files;
my @ordered_files;
my @planned_ordered_files = ("web_tt2/home.tt2","web_tt2/login.tt2","web_tt2/main.tt2","web_tt2/title.tt2","web_tt2/menu.tt2","web_tt2/login_menu.tt2",
			     "web_tt2/your_lists.tt2","web_tt2/footer.tt2","web_tt2/list_menu.tt2","web_tt2/list_panel.tt2","web_tt2/admin.tt2","web_tt2/list_admin_menu.tt2");
foreach my $file (@planned_ordered_files) {
    if ($files_to_parse{$file}) {
	@ordered_files = (@ordered_files,$file);
    }
}
my @ordered_directories = ("web_tt2","mail_tt2","src/etc/scenari","src/etc");

foreach my $file (@ordered_files) {
    $favoured_files{$file} = 1;
}
## Sorting by directories
foreach my $dir (@ordered_directories) {
    foreach my $file (@ARGV) {
	unless ($favoured_files{$file}) {
	    if ($file =~ /^$dir/g) {
		@ordered_files = (@ordered_files,$file);
		$favoured_files{$file} = 1;
	    }
	}
    }
}
    
## Sorting by files
foreach my $file (@ARGV) {
    unless ( $favoured_files{$file} ) {
	@ordered_files = (@ordered_files,$file);
    }
}

open DUMP, ">/tmp/d1";
foreach (@ARGV) {
    print DUMP;
    print DUMP"\n";
}
close DUMP;

open DUMP, ">/tmp/d2";
foreach (@ordered_files) {
    print DUMP;
    print DUMP"\n";
}
close DUMP;

if (-r $PO) {
    open LEXICON, $PO or die $!;
    while (<LEXICON>) {
	if (1 .. /^$/) { $out .= $_; next }
	last;
    }
    
    1 while chomp $out;
    
    require Locale::Maketext::Lexicon::Gettext;
    %Lexicon = map {
	if ($opts{u}) {
	    s/\\/\\\\/g;
	    s/\"/\\"/g;
	    s/((?<!~)(?:~~)*)\[_(\d+)\]/$1%$2/g;
	    s/((?<!~)(?:~~)*)\[([A-Za-z#*]\w*),([^\]]+)\]/"$1%$2(".escape($3).")"/eg;
	    s/~([\~\[\]])/$1/g;
	}
	$_;
    } %{ Locale::Maketext::Lexicon::Gettext->parse(<LEXICON>) };
    close LEXICON;
    delete $Lexicon{''};
}

open PO, ">$PO" or die "Can't write to $PO:$!\n";
select PO;

undef $/;

foreach my $file (@ordered_files) {
    next if ($file=~/\.po$/i); # Don't parse po files
    my $filename = $file;
    printf STDOUT "Processing $file...\n";	    
    unless (-f $file) {
	print STDERR "Cannot open $file\n";
	next;
    }
    open F, $file or die $!; $_ = <F>; $filename =~ s!^./!!;

    my $line = 1; pos($_) = 0;
    # Text::Template
    if (/^STARTTEXT$/m and /^ENDTEXT$/m) {
	require HTML::Parser;
	require Lingua::EN::Sentence;

	{
	    package MyParser;
	    @MyParser::ISA = 'HTML::Parser';
	    sub text {
		my ($self, $text, $is_cdata) = @_;
		my $sentences = Lingua::EN::Sentence::get_sentences($text) or return;
		$text =~ s/\n/ /g; $text =~ s/^\s+//; $text =~ s/\s+$//;
		&add_expression({'expression' => $text,
				 'filename' => $filename,
				 'line' => $line});
	    }
	}   

	my $p = MyParser->new;
	while (m/\G(.*?)^(?:START|END)[A-Z]+$/smg) {
	    my ($str) = ($1);
	    $line += ( () = ($& =~ /\n/g) ); # cryptocontext!
	    $p->parse($str); $p->eof; 
	}
	$_ = '';
    }

    # HTML::Mason
    $line = 1; pos($_) = 0;
    while (m!\G.*?<&\|/l(?:oc)?(.*?)&>(.*?)</&>!sg) {
	my ($vars, $str) = ($1, $2);
	$line += ( () = ($& =~ /\n/g) ); # cryptocontext!
	$str =~ s/\\\'/\'/g; 
	&add_expression({'expression' => $str,
			 'filename' => $filename,
			 'line' => $line,
			 'vars' => $vars});
    }

    # Template Toolkit
    $line = 1; pos($_) = 0;
    while (m!\G.*?\[%\s*\|(locdt|loc)(.*?)\s*%\](.*?)\[%\-?\s*END\s*\-?%\]!sg) {
	my ($this_tag, $vars, $str) = ($1, $2, $3);
	$line += ( () = ($& =~ /\n/g) ); # cryptocontext!
	$str =~ s/\\\'/\'/g; 
	$vars =~ s/^\s*\(//;
	$vars =~ s/\)\s*$//;
	my $expression = {'expression' => $str,
			  'filename' => $filename,
			  'line' => $line,
			  'vars' => $vars};       
	$expression->{'type'} = 'date' if ($this_tag eq 'locdt');
	&add_expression($expression);
    }
	    
    # Template Toolkit with ($tag$%|loc%$tag$)...($tag$%END%$tag$) in archives
    $line = 1; pos($_) = 0;
    while (m!\G.*?\(\$tag\$%\s*\|(locdt|loc)(.*?)\s*%\$tag\$\)(.*?)\(\$tag\$%\s*END\s*%\$tag\$\)!sg) {
	my ($this_tag, $vars, $str) = ($1, $2, $3);
	$line += ( () = ($& =~ /\n/g) ); # cryptocontext!
	$str =~ s/\\\'/\'/g; 
	$vars =~ s/^\s*\(//;
	$vars =~ s/\)\s*$//;
	my $expression = {'expression' => $str,
			  'filename' => $filename,
			  'line' => $line,
			  'vars' => $vars};       
	$expression->{'type'} = 'date' if ($this_tag eq 'locdt');
	&add_expression($expression);
    }	    

	    # Sympa variables (gettext_id)
	    $line = 1; pos($_) = 0;
	    while (/\G.*?\'gettext_id\'\s*=>\s*\"([^\"]+)\"/sg) {
		my $str = $1;
		$line += ( () = ($& =~ /\n/g) ); # cryptocontext!
		&add_expression({'expression' => $str,
				 'filename' => $filename,
				 'line' => $line});
	    }

	    $line = 1; pos($_) = 0;
	    while (/\G.*?\'gettext_id\'\s*=>\s*\'([^\']+)\'/sg) {
		my $str = $1;
		$line += ( () = ($& =~ /\n/g) ); # cryptocontext!
		&add_expression({'expression' => $str,
				 'filename' => $filename,
				 'line' => $line});
	    }

	    # Sympa scenarios variables (title.gettext)
	    $line = 1; pos($_) = 0;
	    while (/\G.*?title.gettext\s*([^\n]+)/sg) {
		my $str = $1;
		$line += ( () = ($& =~ /\n/g) ); # cryptocontext!
		&add_expression({'expression' => $str,
				 'filename' => $filename,
				 'line' => $line});
	    }

    # Perl source file
	    my ($state,$str,$vars)=(0); my $is_date = 0;
    pos($_) = 0;
    my $orig = 1 + (() = ((my $__ = $_) =~ /\n/g));
  PARSER: {
      $_ = substr($_, pos($_)) if (pos($_));
      my $line = $orig - (() = ((my $__ = $_) =~ /\n/g));
      # maketext or loc or _
      $state == NUL &&
        m/\b(translate|gettext(?:_strftime)?|maketext|__?|loc|x)/gcx && do {
          if ($& eq 'gettext_strftime') {
            $state = BEGM;
	    $is_date = 1;
          } else {
            $state = BEG;
	    $is_date = 0;
          }
          redo;
        };
      ($state == BEG || $state == BEGM) && m/^([\s\t\n]*)/gcx && do { redo; };
      # begin ()
      $state == BEG && m/^([\S\(]) /gcx && do {
	$state = ( ($1 eq '(') ? PAR : NUL) ;
	redo;
      };
      $state == BEGM && m/^([\(])  /gcx && do { $state = PARM; redo };

      # begin or end of string
      $state == PAR  && m/^(\')  /gcx     && do { $state = QUO1; redo; };
      $state == QUO1 && m/^([^\']+)/gcx && do { $str.=$1; redo; };
      $state == QUO1 && m/^\'  /gcx     && do { $state = PAR;  redo; };

      $state == PAR  && m/^\"  /gcx     && do { $state = QUO2; redo; };
      $state == QUO2 && m/^([^\"]+)/gcx && do { $str.=$1; redo; };
      $state == QUO2 && m/^\"  /gcx     && do { $state = PAR;  redo; };

      $state == PAR  && m/^\`  /gcx     && do { $state = QUO3; redo; };
      $state == QUO3 && m/^([^\`]*)/gcx && do { $str.=$1; redo; };
      $state == QUO3 && m/^\`  /gcx     && do { $state = PAR;  redo; };

      $state == BEGM && m/^(\') /gcx     && do { $state = QUOM1; redo; };
      $state == PARM && m/^(\') /gcx     && do { $state = QUOM1; redo; };
      $state == QUOM1 && m/^([^\']+)/gcx && do { $str.=$1; redo; };
      $state == QUOM1 && m/^\'  /gcx     && do { $state = COMM;  redo; };

      $state == BEGM && m/^(\") /gcx     && do { $state = QUOM2; redo; };
      $state == PARM && m/^(\") /gcx     && do { $state = QUOM2; redo; };
      $state == QUOM2 && m/^([^\"]+)/gcx && do { $str.=$1; redo; };
      $state == QUOM2 && m/^\"  /gcx     && do { $state = COMM;  redo; };

      # end ()
      ($state == PAR && m/^[\)]/gcx || $state == COMM && m/^,/gcx)
	&& do {
	  $state = NUL;	
	  $vars =~ s/[\n\r]//g if ($vars);
	  if ($str) {
	      my $expression = {'expression' => $str,
				'filename' => $filename,
				'line' => $line - (() = $str =~ /\n/g),
				'vars' => $vars};
	      $expression->{'type'} = 'date' if ($is_date);

	      &add_expression($expression);
	  }
	  undef $str; undef $vars;
	  redo;
	};

      # a line of vars
      $state == PAR && m/^([^\)]*)/gcx && do { 	$vars.=$1."\n"; redo; };
    }
}

foreach my $str (sort keys %file) {
    my $ostr = $str;
    my $entry = $file{$str};
    my $lexi = $Lexicon{$ostr};

    ## Skip meta information (specific to Sympa)
    next if ($str =~ /^_\w+\_$/);

#    $str =~ s/\\/\\\\/g;
    $str =~ s/\"/\\"/g;
    $lexi =~ s/\\/\\\\/g;
    $lexi =~ s/\"/\\"/g;

    unless ($opts{u}) {
	$str =~ s/((?<!~)(?:~~)*)\[_(\d+)\]/$1%$2/g;
	$str =~ s/((?<!~)(?:~~)*)\[([A-Za-z#*]\w*)([^\]]+)\]/"$1%$2(".escape($3).")"/eg;
	$str =~ s/~([\~\[\]])/$1/g;
	$lexi =~ s/((?<!~)(?:~~)*)\[_(\d+)\]/$1%$2/g;
	$lexi =~ s/((?<!~)(?:~~)*)\[([A-Za-z#*]\w*)([^\]]+)\]/"$1%$2(".escape($3).")"/eg;
	$lexi =~ s/~([\~\[\]])/$1/g;
    }

    $Lexicon{$str} ||= '';
    next if $ostr eq $str;

    $Lexicon{$str} ||= $lexi;
    delete $file{$ostr}; delete $Lexicon{$ostr};
    $file{$str} = $entry;
}
#				     &dump_var(\%file,0,\*STDOUT);
exit unless %Lexicon;

print $out ? "$out\n" : (<< '.');
# SOME DESCRIPTIVE TITLE.
# Copyright (C) YEAR THE PACKAGE'S COPYRIGHT HOLDER
# This file is distributed under the same license as the PACKAGE package.
# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
#
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: PACKAGE VERSION\n"
"POT-Creation-Date: 2002-07-16 17:27+0800\n"
"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\n"
"Language-Team: LANGUAGE <LL@li.org>\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=CHARSET\n"
"Content-Transfer-Encoding: 8bit\n"
.
my @Lexicon;
my %Lexiconbis;

foreach my $o_file (@ordered_files) {
    foreach my $entry (keys %Lexicon) {
	unless ($Lexiconbis{$entry}){
	    my %f = (map { ( "$_->[0]" => 1 ) } @{$file{$entry}});
	    if ($f{$o_file}) {
		@Lexicon = (@Lexicon,$entry);
		$Lexiconbis{$entry} = 1;
	    }
	}
    }
}

foreach my $entry (@Lexicon) {
    my %f = (map { ( "$_->[0]:$_->[1]" => 1 ) } @{$file{$entry}});
    my $f = join(' ', sort keys %f);
    $f = " $f" if length $f;

    my $nospace = $entry;
    $nospace =~ s/ +$//;

    if (!$Lexicon{$entry} and $Lexicon{$nospace}) {
	$Lexicon{$entry} = $Lexicon{$nospace} . (' ' x (length($entry) - length($nospace)));
    }

    my %seen;

    ## Print code/templates references
    print "\n#:$f\n";

    ## Print variables if any
    foreach my $entry ( grep { $_->[2] } @{$file{$entry}} ) {
	my ($file, $line, $var) = @{$entry};
	$var =~ s/^\s*,\s*//; $var =~ s/\s*$//;
	print "#. ($var)\n" unless !length($var) or $seen{$var}++;
    }

    ## If the entry is a date format, add a developper comment to help translators
    if ($type_of_entries{$entry} eq 'date') {
	print "#. This entry is a date/time format\n";
	print "#. Check the strftime manpage for format details : http://docs.freebsd.org/info/gawk/gawk.info.Time_Functions.html\n";
    }

    print "#, maketext-format" if $opts{g} and /%(?:\d|\w+\([^\)]*\))/;
    print "msgid "; output($entry);
    print "msgstr "; output($Lexicon{$entry});
}

open DUMP, ">/tmp/dump2"; &dump_var(\%Lexicon,0,\*DUMP);close DUMP;

## Add expressions to list of expressions to translate
## parameters : expression, filename, line, vars
sub add_expression {
    my $param = shift;

    push @{$file{$param->{'expression'}}}, [ $param->{'filename'}, $param->{'line'}, $param->{'vars'} ];
    $type_of_entries{$param->{'expression'}} = $param->{'type'} if ($param->{'type'});

}

sub output {
    my $str = shift;

    ## Normalize
    $str =~ s/\\n/\n/g;

    if ($str =~ /\n/) {
	print "\"\"\n";

	## Avoid additional \n entries
	my @lines = split(/\n/, $str, -1);
	my @output_lines;

	## Move empty lines to previous line as \n
	my $current_line;
	foreach my $i (0..$#lines) {
	    if ($lines[$i] eq '') {
		if ($#output_lines < 0) {
		    $current_line .= '\n';
		    next;
		}else {
		    $output_lines[$#output_lines] .= '\n';
		    next;
		}
	    }else {
		$current_line .= $lines[$i];
	    }
	    push @output_lines, $current_line;
	    $current_line = '';
	}
	
	## Add \n unless 
	foreach my $i (0..$#output_lines) {
	    if ($i == $#output_lines) {
		## No additional \n
		print "\"$output_lines[$i]\"\n";
	    }else {
		print "\"$output_lines[$i]\\n\"\n";
	    }
	}

	
    }
    else {
	print "\"$str\"\n"
    }
}

sub escape {
    my $text = shift;
    $text =~ s/\b_(\d+)/%$1/;
    return $text;
}

## Dump a variable's content
sub dump_var {
    my ($var, $level, $fd) = @_;

    return undef unless ($fd);

    if (ref($var)) {
	if (ref($var) eq 'ARRAY') {
	    foreach my $index (0..$#{$var}) {
		print $fd "\t"x$level.$index."\n";
		&dump_var($var->[$index], $level+1, $fd);
	    }
	}elsif (ref($var) eq 'HASH' || ref($var) eq 'Scenario' || ref($var) eq 'List') {
	    foreach my $key (sort keys %{$var}) {
		print $fd "\t"x$level.'_'.$key.'_'."\n";
		&dump_var($var->{$key}, $level+1, $fd);
	    }    
	}else {
	    printf $fd "\t"x$level."'%s'"."\n", ref($var);
	}
    }else {
	if (defined $var) {
	    print $fd "\t"x$level."'$var'"."\n";
	}else {
	    print $fd "\t"x$level."UNDEF\n";
	}
    }
}



1;

=head1 ACKNOWLEDGMENTS

Thanks to Jesse Vincent for contributing to an early version of this
utility.

Also to Alain Barbet, who effectively re-wrote the source parser with a
flex-like algorithm.

=head1 SEE ALSO

L<Locale::Maketext>, L<Locale::Maketext::Lexicon::Gettext>

=head1 AUTHORS

Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>

=head1 COPYRIGHT

Copyright 2002, 2003 by Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
