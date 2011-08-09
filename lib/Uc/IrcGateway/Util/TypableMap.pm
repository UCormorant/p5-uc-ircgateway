package Uc::IrcGateway::Util::TypableMap;

use common::sense;
use warnings qw(utf8);
use Carp qw(croak);
use List::Util qw(shuffle);
use overload
    '++' => \&increment,
    '--' => \&decrement,
    '""' => \&current,
    '='  => \&current,
;
use Smart::Comments;

our @TYPABLE_MAP;
my @consonant_voiceless         = qw/k s t n h m y r w/;
my @consonant_sonant            = qw/g z d b p/;
my @consonant_contracted        = qw/ky sh ty ny hy py my ry/;
my @consonant_contracted_sonant = qw/gy zy dy by py/;
my @consonant = (@consonant_voiceless, @consonant_contracted, @consonant_sonant, @consonant_contracted_sonant);
for my $consonant ('', @consonant) {
    my @vowel;
    given ($consonant) {
        when ([@consonant_contracted, @consonant_contracted_sonant]) { @vowel = qw/a u o/;     }
        default                                                      { @vowel = qw/a i u e o/; }
    }
    push @TYPABLE_MAP, "$consonant$_" for @vowel;
}

sub new {
    my $class  = shift;
    my $self   = bless {}, __PACKAGE__;
    my %config = @_;

    $self->{index} = 0;
    $self->{tid}   = {};
    $self->{scale} = delete $config{scale} || 2;
    $self->{chars} = delete $config{chars} || \@TYPABLE_MAP;
    $self->{fixed} = delete $config{fixed} || 0;
    $self->{current} = delete $config{init_index} || 0;
    $self->{shuffled_tmap}  = delete $config{shuffled_tmap} || 0;
    $self->{auto_increment} = delete $config{auto_increment} || 0;
    $self->{auto_decrement} = delete $config{auto_decrement} || 0;

    my @tmap;
    my $fill_tmap; $fill_tmap = sub {
        my ($tmap, $chars, $prefix, $level) = @_;
        for my $tid (@$chars) {
            if ($level) { $fill_tmap->($tmap, $chars, "$prefix$tid", $level-1); }
            else { push @$tmap, "$prefix$tid"; }
        }
    };
    for my $level (0 .. $self->{scale}-1) {
        next if $self->{fixed} && $level != $self->{scale}-1;
        $fill_tmap->(\@tmap, $self->{chars}, '', $level);
    }
    $self->{chars} = \@tmap;

    if ($self->{shuffled_tmap}) {
        @{$self->{chars}} = shuffle @{$self->{chars}};
    }
    if ($self->{auto_increment} && $self->{auto_decrement}) {
        croak "should not set 'auto_incriment' and 'auto_decriment' together";
    }

    return $self;
}

sub get       { $_[0]->{tid}{$_[1]} }
sub index     { $_[0]->{index} }
sub max_size  { scalar @{$_[0]->{chars}} }
sub increment { $_[0]->{_c} =  1; $_[0]->current }
sub decrement { $_[0]->{_c} = -1; $_[0]->current }
sub current   {
    my ($self, $tid) = shift;
    $self->{index} += delete $self->{_c} if exists $self->{_c};
    $tid = $self->burn;
    $self->{index}++ if  $self->{auto_increment} && !$self->{auto_decrement};
    $self->{index}-- if !$self->{auto_increment} &&  $self->{auto_decrement};
    $self->burn if $self->{auto_increment} || $self->{auto_decrement};
    return $tid || undef;
}
sub burn {
    my ($self, $tid) = shift;
    $self->{current} = $self->index % $self->max_size;
    $tid = $self->{chars}[$self->{current}];
    $self->{tid}{$tid} = $self->index;
    return $tid;
}


1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway::Util::TypableMap - [Generate TypableMap Object for Uc::IrcGateway]


=head1 SYNOPSIS

    use Uc::IrcGateway::Util::TypableMap;

    my @TIMELINE;
    my $tmap = Uc::IrcGateway::Util::TypableMap->new(auto_increment => 1);
    push @TIMELINE, "you suck! [$tmap]"; # you suck! [a]
    push @TIMELINE, "you suck too! [$tmap]"; # you suck too! [i]
    push @TIMELINE, "there is awesome internet! [$tmap]"; # there is awesome internet! [u]

    some_code($TIMELINE[$tmap->get('u')]); # some_code("there is awesome internet! [u]");


=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE 

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
Uc::IrcGateway::Util::TypableMap requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-uc-ircgateway-util-typablemap@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

U=Cormorant  C<< <u@chimata.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011, U=Cormorant C<< <u@chimata.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
