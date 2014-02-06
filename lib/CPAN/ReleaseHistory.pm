package CPAN::ReleaseHistory;

use 5.006;
use Moo;
use File::HomeDir;
use File::Spec::Functions 'catfile';
use HTTP::Date qw(time2str);
use HTTP::Tiny;
use CPAN::DistnameInfo;
use Carp;
use File::Temp qw/ tempfile /;
use PerlIO::gzip;
use autodie qw(open);

use CPAN::ReleaseHistory::Release;

my $DISTNAME = 'CPAN-ReleaseHistory';
my $BASENAME = 'release-history.txt';

has 'url' =>
    (
     is      => 'ro',
     default => sub { return 'http://gitpan.integra.net/backpan-index.gz' },
    );

has 'path' =>
    (
     is      => 'rw',
    );

sub release_iterator
{
    my $self = shift;

    require CPAN::ReleaseHistory::ReleaseIterator;
    return CPAN::ReleaseHistory::ReleaseIterator->new( history => $self );
}

sub BUILD
{
    my $self = shift;

    # If constructor didn't specify a local file, then mirror the file from CPAN
    if (not $self->path) {
        $self->path( catfile(File::HomeDir->my_dist_data( $DISTNAME, { create => 1 } ), $BASENAME) );
        $self->_cache_file_if_needed();
    }
}

sub _cache_file_if_needed
{
    my $self    = shift;
    my $options = {};
    my $ua      = HTTP::Tiny->new();

    if (-f $self->path) {
        $options->{'If-Modified-Since'} = time2str( (stat($self->path))[9]);
    }
    my $response = $ua->get($self->url, $options);

    return if $response->{status} == 304; # Not Modified

    if ($response->{status} == 200) {
        my ($fh, $filename) = tempfile();
        print $fh $response->{content};
        close($fh);
        $self->_transform_and_cache($filename);
        return;
    }

    croak("request for backpan-index failed: $response->{status} $response->{reason}");
}

sub _transform_and_cache
{
    my ($self, $filename) = @_;
    my ($in_fh, $out_fh);
    local $_;
    my @lines;
    my ($distinfo, $distname);

    open($in_fh,  '<:gzip', $filename);
    open($out_fh, '>',      $self->path);

    LINE:
    while (<$in_fh>) {
        next LINE unless m!^authors/id/!;
        next LINE if /\.(readme|meta) /;
        next LINE if m!/CHECKSUMS !;
        next LINE unless /^\S+\s+\S+\s+\S+/;

        chomp;
        s!^authors/id/!!;

        my ($path, $time, $size) = split(/\s+/, $_);
        $distinfo = CPAN::DistnameInfo->new($path);
        $distname = defined($distinfo) && defined($distinfo->dist)
                    ? $distinfo->dist
                    : '';

        push(@lines, [$distname, $path, $time, $size]);

    }
    close($in_fh);
    unlink($filename);

    foreach my $line (sort by_dist_then_date @lines) {
        printf $out_fh "%s %d %d\n", $line->[1], $line->[2], $line->[3];
    }

    close($out_fh);
}

sub by_dist_then_date
{
    return $a->[0] ne $b->[0]
           ? $a->[0] cmp $b->[0]
           : $a->[2] <=> $b->[2];
}

1;

=head1 NAME

CPAN::ReleaseHistory - information about all files ever released to CPAN

=head1 SYNOPSIS

  use CPAN::ReleaseHistory 0.02;

  my $history  = CPAN::ReleaseHistory->new();
  my $iterator = $history->release_iterator();

  while (my $release = $iterator->next_release) {
    print 'path = ', $release->path,           "\n";
    print 'dist = ', $release->distinfo->dist, "\n";
    print 'time = ', $release->timestamp,      "\n";
    print 'size = ', $release->size,           "\n";
  }
  
=head1 DESCRIPTION

B<NOTE>: this is very much an alpha release. Any and all feedback appreciated.

The internal caching format changed in 0.02, so you should make sure you have
at least 0.02, using the C<use> line shown in the SYNOPSIS.

This module provides an iterator that can be used to look at every file
that has ever been released to CPAN, regardless of whether it is still on CPAN.

The C<$release> returned by the C<next_release()> method on the iterator
is an instance of L<CPAN::ReleaseHistory::Release>. It has four methods:

=over 4

=item path

the relative path of the release. For example C<N/NE/NEILB/again-0.05.tar.gz>.

=item distinfo

an instance of L<CPAN::DistnameInfo>, which is constructed lazily.
Ie it is only created if you ask for it.

=item timestamp

An integer epoch-based timestamp.

=item size

The number of bytes in the file.

=back

=head1 METHODS

At the moment there is only one method, to create a release iterator.
Other methods will be added as required / requested.

=head2 release_iterator()

See the SYNOPSIS.

=head1 NOTES

At the moment this module will use up a lot of memory: it grabs the remote BackPAN index,
extracts the data it needs into memory, sorts it, then writes it to the local cache.
If this is a problem then I'll look at another way of doing it. If it's a problem for you,
then you should look at L<BackPAN::Index>.

=head1 SEE ALSO

L<BackPAN::Index> - creates an SQLite database of the BackPAN index,
and provides an interface for querying it.

=head1 REPOSITORY

L<https://github.com/neilbowers/CPAN-ReleaseHistory>

=head1 AUTHOR

Neil Bowers E<lt>neilb@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Neil Bowers <neilb@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

