# $Id: TiVo.pm 32 2006-08-03 01:40:11Z boumenot $
# Author: Christopher Boumenot <boumenot@gmail.com>
######################################################################
#
# Copyright 2006 by Christopher Boumenot.  This program is free 
# software; you can redistribute it and/or modify it under the same
# terms as Perl itself.
#
######################################################################

package Net::TiVo;

use strict;
use warnings;

our $VERSION = '0.03';

use LWP::UserAgent;
use HTTP::Request;
use XML::Simple;
use Data::Dumper;
use Log::Log4perl qw(:easy get_logger);
use Net::TiVo::Folder;
use Net::TiVo::Show;

use constant TIVO_URL => '/TiVoConnect?Command=QueryContainer&Container=%2FNowPlaying';

sub new { 
    my $class = shift;
    my $self = {username => 'tivo',
                realm    => 'TiVo DVR',
                @_};

    $self->{host}     || die "%Error: no host was defined!\n";
    $self->{mac}      || die "%Error: no mac was defined!\n";
    $self->{username} || die "%Error: no username was defined!\n";

    $self->{ua}  = LWP::UserAgent->new() or
        die "%Error: failed to create a LWP::UserAgent!";

    $self->{ua}->credentials($self->{host}.':443',
                             $self->{realm}, 
                             $self->{username} => $self->{mac});

    $self->{url} = 'https://'.$self->{host}.TIVO_URL;

    bless $self, $class;
    return $self;
}


sub folders {
    my $self = shift;

    my $resp = $self->_fetch($self->{url});

    if ($resp->is_success()) {
        my @folders;
        $self->_parse_content($resp->content(), \@folders);

        if (scalar(@folders) == 0) {
            return undef;
        } 
        return (wantarray) ? @folders : \@folders;
    } 
    print "%Error: $resp->status_line()!\n";
    return undef;
}


sub _fetch {
    my ($self, $url) = @_;
    my $resp;

    INFO("fetching $url");

    if (exists $self->{cache}) {
        $resp = $self->{cache}->get($url, $resp);
        if (defined $resp) {
            INFO("cache hit");
            return $resp;
        }
        INFO("cache miss");
    } 

    $resp = $self->{ua}->request(HTTP::Request->new(GET => $url));
    die "%Error: fetch failed, " . $resp->status_line() . "!\n" unless $resp->is_success();

    if (exists $self->{cache}) {
        $self->{cache}->set($url, $resp);
    }

    return $resp;
}

sub _parse_content {
    my ($self, $cont, $folder_aref) = @_;

    DEBUG(sub { "Received [" . $cont . "]"});

    my $xmlref = XMLin($cont, ForceArray => ['Item']);
    die "%Error: cannot parse the TiVO XML!\n" unless defined $xmlref->{Item};
    
    DEBUG(sub { Dumper($xmlref) });

    # TiVo only allows you to create one folder to hold shows, but the
    # top most folder, Now Playing, as to be accounted for too.  If we
    # haven't created any folders yet, then this is the Now Playing
    # folder, and needs to be treated specially.
    push @$folder_aref, Net::TiVo::Folder->new(xmlref => $xmlref);
    INFO("added the folder " . $folder_aref->[-1]->name());

    for my $i (@{$xmlref->{Item}}) {
        my $ct = $i->{Links}->{Content}->{ContentType};


        if ($ct eq 'x-tivo-container/folder') {
            my $resp = $self->_fetch($i->{Links}->{Content}->{Url});
            $self->_parse_content($resp->content(), $folder_aref);
        } else {
            INFO("skipping the content for $ct");
        }
    }
}


1;
__END__

=head1 NAME

Net::TiVo - Perl interface to TiVo.

=head1 SYNOPSIS

  use Net::TiVo;
	
  my $tivo = Net::TiVo->new(host => '192.168.1.25', mac => 'MEDIA_ACCESS_KEY');

  for ($tivo->folders()) {
      print $_->as_string(), "\n";
  }	

=head1 ABSTRACT

C<Net::TiVo> provides an object-oriented interface to TiVo's XML/HTTPS
interface.  This makes it possible to enumerate the folders and shows,
and dump their meta-data.

=head1 DESCRIPTION

C<Net::TiVo> has a very simple interface, and currently only supports
the enumeration of folder and shows using the XML/HTTPS interface.  The
main purpose of this module was to provide access to the TiVo
programmatically to automate the process of downloading shows from a
TiVo.

=head2 METHODS

=over 4

=item folders()

Returns an array or reference to an array containing a list of
Net::TiVo::Folder objects.

=back

=head1 SEE ALSO

Net::TiVo::Folder, Net::TiVo::Show

=head1 AUTHOR

Christopher Boumenot, E<lt>boumenot@gmail.comE<gt>

=cut
