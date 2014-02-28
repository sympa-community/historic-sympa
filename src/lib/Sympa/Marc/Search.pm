# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$

package Sympa::Marc::Search;

use strict;

use English qw(-no_match_vars);
use File::Find;
use HTML::Entities qw(decode_entities encode_entities);
use Encode qw(decode_utf8 encode_utf8 is_utf8);

use Sympa::Marc;

our @ISA     = qw(Sympa::Marc);
our $VERSION = "4.3";
our ($AUTOLOAD, @MSGFILES);

##------------------------------------------------------------------------##
## Constructor

my %fields = (
    age          => 0,
    archive_name => undef,
    base_href    => undef,
    body         => undef,
    body_count   => 0,
    case         => 0,
    clean_words  => undef,
    date         => undef,
    date_count   => 0,
    directories  => undef,
    error        => undef,
    file_count   => 0,
    from         => undef,
    from_count   => 0,
    function1    => undef,
    function2    => undef,
    how          => undef,
    id           => undef,
    id_count     => 0,
    key_word     => undef,
    limit        => 25,
    match        => 0,
    previous     => undef,
    res          => undef,
    searched     => 0,
    search_base  => undef,
    subj         => undef,
    subj_count   => 0,
    words        => undef,
);

sub new {
    my $class = shift;
    my $self  = Sympa::Marc->new(\%fields);
    bless $self, $class;
    return $self;
}

##------------------------------------------------------------------------##
## These accessor methods keep a running count of matches in each area
## PUBLIC METHOD

sub body_count {
    my $self = shift;
    my $count = shift || 0;
    return $self->{body_count} += $count;
}

sub id_count {
    my $self = shift;
    my $count = shift || 0;
    return $self->{id_count} += $count;
}

sub date_count {
    my $self = shift;
    my $count = shift || 0;
    return $self->{date_count} += $count;
}

sub from_count {
    my $self = shift;
    my $count = shift || 0;
    return $self->{from_count} += $count;
}

sub subj_count {
    my $self = shift;
    my $count = shift || 0;
    return $self->{subj_count} += $count;
}

sub key_word {
    my $self = shift;

    if (scalar @_) {
        my $key_word = shift;
        if (defined $key_word) {
            $key_word = decode_utf8($key_word) unless is_utf8($key_word);
            $self->{'key_word'} = $key_word;
        } else {
            $self->{'key_word'} = undef;
        }
    }
    return $self->{'key_word'};
}

##------------------------------------------------------------------------##
## Handle Actual Search
## PRIVATE METHOD

sub _find_match {
    my ($self, $file, $subj, $from, $date, $id, $body_ref) = @_;
    my $body_string = '';
    my $match       = 0;
    my $res         = undef;

    # Check for a match in subject
    if (($self->subj) && ($_ = $subj) && (&{$self->{function2}})) {
        $subj =~ s,($self->{key_word}),\001$1\002,g;    # Bold any matches
        $self->subj_count(1);                           # Keeping count
        $match = 1;    # We'll be printing this one
    }

    # Check for a match in from
    if (($self->from) && ($_ = $from) && (&{$self->{function2}})) {
        $from =~ s,($self->{key_word}),\001$1\002,g;
        $self->from_count(1);
        $match = 1;
    }

    # Check for a match in date
    if (($self->date) && ($_ = $date) && (&{$self->{function2}})) {
        $date =~ s,($self->{key_word}),\001$1\002,g;
        $self->date_count(1);
        $match = 1;
    }

    # Check for a match in id
    if (($self->id) && ($_ = $id) && (&{$self->{function2}})) {
        $id =~ s,($self->{key_word}),\001$1\002,g;
        $self->id_count(1);
        $match = 1;
    }

    # Is this a full?
    if (defined($body_ref)) {
        my @body = @$body_ref;

        # use routine generated by body_match_all
        if (defined($self->function1)) {
            my @words = @{$self->words};
            my $i;
        BODY: for $i (0 .. $#body) {
                my %matches = ();
                my $hit     = '';
                $_ = $body[$i];
                my @linematches = &{$self->{function1}};
                foreach $hit (@linematches) {

                    # key=searchterm; value=line
                    $matches{$hit} = $i;
                }

                # all keys = all terms?
                if (keys %matches == @words) {

                    # Add to the running total
                    $self->body_count(1);
                    my $line;
                    $match = 1;
                    foreach $hit (
                        sort { $matches{$a} <=> $matches{$b} }
                        keys %matches
                        ) {

                        # no duplicates please
                        next if ($matches{$hit} + 1 == $line);

                        # arrays start from 0
                        $line = $matches{$hit} + 1;
                        $body_string .= "line $line: $body[$matches{$hit}]";
                    }
                    $body_string =~ s,($self->{key_word}),\001$1\002,g;
                    last BODY;
                }
            }
        }

        # otherwise use routine supplied by match_any or match_this
        else {
            my $i;
        BODY: for $i (0 .. $#body) {
                if (($_ = $body[$i]) && (&{$self->{function2}})) {
                    ($body_string =
                            $body[($i - 1)] . $body[$i] . $body[($i + 1)]) =~
                        s,($self->{key_word}),\001$1\002,g;
                    $self->body_count(1);
                    $match = 1;
                    last BODY;
                }
            }
        }
    }
    if ($match == 1) {
        $file =~ s,$self->{'search_base'},$self->{'base_href'},;
        $res->{'file'}        = $file;
        $res->{'body_string'} = $body_string;
        $res->{'id'}          = $id;
        $res->{'date'}        = $date;
        $res->{'from'}        = $from;
        $res->{'subj'}        = $subj;
        $res->{'rich'}        = {};

        foreach my $k (qw(body_string id date from subj)) {
            my @rich = ();
            foreach my $s (split /(\n|\001.*?\002)/, $res->{$k}) {
                next unless length $s;
                if ($s =~ /\n/) {
                    push @rich, {'text' => '', 'format' => 'br'};
                } elsif ($s =~ /\001(.*)\002/) {
                    push @rich, {'text' => encode_utf8($1), 'format' => 'b'};
                } else {
                    push @rich, {'text' => encode_utf8($s), 'format' => ''};
                }
            }
            $res->{'rich'}->{$k} = \@rich;
            $res->{$k} = encode_entities($res->{$k}, '<>&"');
            $res->{$k} =~ s,\001,<B>,g;
            $res->{$k} =~ s,\002,</B>,g;
            $res->{$k} =~ s,\n,<BR/>,g;
            $res->{$k} = encode_utf8($res->{$k});
        }
        push @{$self->{'res'}}, $res;
    }

    return $match;    # 1 if match succeeds; 0 otherwise
}

##------------------------------------------------------------------------##
## Build up a list of files to search; read in the relevant portions;
## pass those parts off for checking (and printing if there's a match)
## by the _find_match method
## PUBLIC METHOD

sub search {
    my $self        = shift;
    my $limit       = $self->limit;
    my $previous    = $self->previous || 0;
    my $directories = $self->directories;
    my $body        = $self->body || 0;

    @MSGFILES = '';

    my @directories = split /\0/, $directories;
    foreach my $dir (@directories) {
        my $directory = ($self->search_base . '/' . $dir . '/');
        find(
            {   wanted          => \&_get_file_list,
                untaint         => 1,
                untaint_pattern => qr|^([-@\w./]+)$|
            },
            $directory
        );
    }

    # File::Find returns these in somewhat haphazard order.
    @MSGFILES = sort @MSGFILES;

    # Newest files first!
    @MSGFILES = reverse(@MSGFILES) if $self->age;

    # The *real* number of files
    $self->file_count($#MSGFILES);

    @MSGFILES = splice(@MSGFILES, $previous) if $previous;
    my $file;
    my $i = 1;    # Arrays are numbered from 0
                  # Avoid doing a lot of extra math inside the loop
    $limit += $previous;
    foreach $file (@MSGFILES) {
        my ($subj, $from, $date, $id, $body_ref);
        unless (open FH, '<:encoding(utf8)', $file) {

            #			$self->error("Couldn't open file $file, $ERRNO");
        }

        # Need this loop because newer versions of MHonArc put a version
        # number on the first line of the message.  Just in case Earl
        # decides to change this again, we will loop until the subject
        # comment tag is found.  Thanks to Douglas Gray Stephens for
        # pointing this out, and more importantly, for suggesting a good
        # solution (though ultimately not the one in place here).  That
        # DGS was able to contribute to this modest little program is, I
        # think, a good argument in favor of open source code!
        while (<FH>) {
            ## Next line is appended to the subject
            if (defined $subj) {
                $subj .= $1 if (/\s(.*)( -->|$)/);
                if (/-->$/) {
                    $subj =~ s/ -->$//;
                    last;
                }
            } elsif (/^<!--X-Subject: (.*)( -->|$)/) {
                ## No more need to decode header fields
                # $subj = MIME::Words::decode_mimewords($1);
                $subj = $1;
                last if (/-->/);
            }
        }
        $subj =~ s/ *-->$//;

        ($from = <FH>) =~ s/^<!--X-From-R13: (.*) -->/$1/;

        ## No more need to decode header fields
        #$from = MIME::Words::decode_mimewords($from);

        $from =~ tr/N-Z[@A-Mn-za-m/@A-Z[a-z/;

        ($date = <FH>) =~ s/^<!--X-Date: (.*) -->/$1/;

        ($id = <FH>) =~ s/^<!--X-Message-Id: (.*) -->/$1/;

        if ($body) {
            my $lines = '';
            while (<FH>) {

                # Messages are contained between Body-of-Message tags
                next unless (/^<!--X-Body-of-Message-->/);
                $_ = <FH>;
                while (!eof && ($_ !~ /^<!--X-MsgBody-End-->/)) {
                    $lines .= $_;
                    $_ = <FH>;
                }
                last;
            }

            # Remove HTML comments
            $lines =~ s/<!--[^<>]*?-->//g;

            # Translate newlines
            $lines =~ s{<PRE\b[^>]*>(.*?)</PRE\b[^>]*>}
					   { my $s = $1; $s =~ s,\r\n|\r|\n,<BR/>,g; $s; }egis;
            $lines =~ s/[\r\n]/ /g;
            $lines =~ s/<(BR|DIV|P)\b[^>]*>[ \t]*/\n/gi;

            # Remove other HTML tags
            $lines =~ s,[ \t]*</[^>]*>,,g;
            $lines =~ s/<[^>]*>[ \t]*//g;
            $lines =~ s/[<>]/ /g;

            # Decode entities
            $lines = decode_entities($lines);
            $lines =~ s/[\001\002]/ /g;

            # Split lines
            $body_ref = [split /(?<=\n)/, $lines];
        }
        unless (close FH) {

            #            $self->error("Couldn't close file $file, $ERRNO");
        }

        # Decode entities
        if ($subj) {
            $subj = decode_entities($subj);
            $subj =~ s/[\001\002\r\n]/ /g;
        }
        if ($from) {
            $from = decode_entities($from);
            $from =~ s/[\001\002\r\n]/ /g;
        }
        if ($date) {
            $date = decode_entities($date);
            $date =~ s/[\001\002\r\n]/ /g;
        }
        if ($id) {
            $id = decode_entities($id);
            $id =~ s/[\001\002\r\n]/ /g;
        }

        if ($self->_find_match($file, $subj, $from, $date, $id, $body_ref)) {
            return ($i + $previous)
                if ($self->body_count == $limit
                or $self->subj_count == $limit
                or $self->from_count == $limit
                or $self->date_count == $limit
                or $self->id_count == $limit);
        }
        $i++;
    }

    return $self->file_count + 1;
}

##------------------------------------------------------------------------##
## Function for use with File::Find -- recursive
## PRIVATE METHOD

sub _get_file_list {
    /^msg/ && push @MSGFILES, $File::Find::name;
}

##------------------------------------------------------------------------##
## Eval anonymous pattern match functions based on user search terms

## PUBLIC METHOD
sub match_any {
    my $self = shift;
    my ($tail, $pat);
    if   ($self->case) { $tail = '/i' }
    else               { $tail = '/' }
    my $code = <<EOCODE;
sub {
      use utf8;
EOCODE
    $code .= <<EOCODE if @_ > 5;
      study;
EOCODE
    for $pat (@_) {
        $code .= <<EOCODE;
      return 1 if /$pat$tail;
EOCODE
    }
    $code .= "}\n";
    my $function = eval $code;
    die "bad pattern: $EVAL_ERROR" if $EVAL_ERROR;
    return $function;
}

## PUBLIC METHOD
sub body_match_all {
    my ($self, @ret) = @_;
    my ($len) = ($#ret + 1) / 2;
    my (@pat) = splice(@ret, $len);
    my $tail;
    if   ($self->case) { $tail = '/i' }
    else               { $tail = '/' }
    my $code = <<EOCODE;
sub {
	use utf8;
	my(\@matches);
EOCODE
    $code .= <<EOCODE if @pat > 5;
	study;
EOCODE
    my $i;

    for $i (0 .. $#pat) {
        $code .= <<EOCODE;
	push \@matches, '$ret[$i]' if /$pat[$i]$tail;
EOCODE
    }
    $code .= <<EOCODE;
	return \@matches;
}
EOCODE

    #	print "<PRE>$code</pre>";	# used for debugging
    my $function = eval $code;
    die "bad pattern: $EVAL_ERROR" if $EVAL_ERROR;
    return $function;
}

## PUBLIC METHOD
sub match_all {
    my $self = shift;
    my ($sep, $tail);
    if ($self->case) {
        $sep  = "/i && /";
        $tail = "/i }";
    } else {
        $sep  = "/ && /";
        $tail = "/ }";
    }
    my $code = "sub { use utf8; /" . join("$sep", @_) . $tail;
    my $function = eval $code;
    die "bad pattern: $EVAL_ERROR" if $EVAL_ERROR;
    return $function;
}

## PUBLIC METHOD
sub match_this {
    my $self = shift;
    my $string = join(' ', @_);
    $string = '(?i)' . $string if ($self->case);
    my $code     = "sub { use utf8; /" . $string . "/ }";
    my $function = eval $code;
    die "bad pattern: $EVAL_ERROR" if $EVAL_ERROR;
    return $function;
}

1;
