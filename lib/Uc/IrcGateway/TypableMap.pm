package Uc::IrcGateway::TypableMap;

use 5.014;
use warnings;
use utf8;
use Carp qw(croak);
use List::Util qw(shuffle);
use overload '""' => \&tid, '=' => \&tid;
use Any::Moose;

our @TYPABLE_MAP = ();
my @consonant_voiceless         = qw/k s t n h m y r w/;
my @consonant_sonant            = qw/g z d b p/;
my @consonant_contracted        = qw/ky sh ty ny hy my ry/;
my @consonant_contracted_sonant = qw/gy zy dy by py/;
my @consonant = (@consonant_voiceless, @consonant_contracted, @consonant_sonant, @consonant_contracted_sonant);

has 'index' => ( is => 'rw', isa => 'Int', default => 0 );
has 'scale' => ( is => 'ro', isa => 'Int', default => 2 );
has [qw/fixed shuffled/] => ( is => 'ro', isa => 'Bool', default => 0 );
has 'max_size'  => ( is => 'rw', isa => 'Int', lazy_build => 1, trigger => sub {
    my ($self, $value) = @_;
    my $max_size = scalar @{$self->indices};
    if ($value > $max_size) { $self->max_size($max_size); }
    else { CORE::splice @{$self->indices}, $value; }
} );

has 'items'   => ( is => 'ro', isa => 'HashRef', default => sub { return {} }, init_arg => undef );
has 'indices' => ( is => 'ro', isa => 'ArrayRef[Str]', lazy_build => 1, init_arg => undef );
has 'chars'   => ( is => 'ro', isa => 'ArrayRef[Str]', default => sub {
    return \@TYPABLE_MAP if scalar @TYPABLE_MAP;
    local $_;
    for my $consonant ('', @consonant) {
        my @vowel;
        given ($consonant) {
            when ([@consonant_contracted, @consonant_contracted_sonant]) { @vowel = qw/a u o/;     }
            default                                                      { @vowel = qw/a i u e o/; }
        }
        push @TYPABLE_MAP, "$consonant$_" for @vowel;
    }
    return \@TYPABLE_MAP;
} );

__PACKAGE__->meta->make_immutable;
no Any::Moose;

sub _build_indices {
    my $self = CORE::shift;
    my @indices; my $a = $self->chars;

    my $fill_tmap; $fill_tmap = sub {
        my ($prefix, $level) = @_;
        for my $str (@{$self->chars}) {
            if ($level) { $fill_tmap->("$prefix$str", $level-1); }
            else { CORE::push @indices, "$prefix$str"; }
        }
    };
    for my $level (0 .. $self->scale-1) {
        next if $self->fixed && $level != $self->scale-1;
        $fill_tmap->('', $level);
    }

    @indices = shuffle @indices if $self->shuffled;

    return \@indices;
}

sub _build_max_size {
    return scalar @{+CORE::shift->indices};
}


# methods:

sub get {
    my $self = CORE::shift;
    return wantarray ? @{$self->items}{@_} : ${$self->items}{+CORE::shift};
}
sub set {
    my $self = CORE::shift;
    my %set  = @_;
    while (my($k, $v) = each %set) {
        $self->items->{$k} = $v;
    }
    return values %set;
}
sub tid {
    my ($self, $index) = @_;
    $index = 0 if !$index || $index !~ /^[+-]?\d+$/;
    $a = $self->index;
    $b = $self->indices->[$self->index+$index];
    return $self->indices->[$self->index+$index];
}
sub index2tid { ${$_[0]->indices}[$_[1]]; }
sub tid2index {
    my ($self, $tid) = @_;
    my $i = 0;
    for my $index (@{$self->indices}) {
        last if $index eq $tid; $i++;
    }
    return $i;
}
sub roll_index {
    my ($self, $reverse) = @_;
    if ($reverse) { CORE::unshift @{$self->indices}, CORE::pop   @{$self->indices}; }
    else          { CORE::push    @{$self->indices}, CORE::shift @{$self->indices}; }
}
sub pop {
    my $self = CORE::shift;
    my $item = $self->delete($self->tid);
    $self->index($self->index-1) if defined $item;
    return $item;
}
sub shift {
    my $self = CORE::shift;
    my $item = $self->delete($self->indices->[0]);
    $self->roll_index if defined $item;
    return $item;
}
sub push {
    my ($self, @items) = @_;
    my %set;
    for my $item (@items) {
        $set{$self->tid} = $item;
        if ($self->index < $self->max_size - 1) {
            $self->index($self->index+1);
        }
        else {
            $self->roll_index;
        }
    }
    $self->set(%set);
}
sub unshift {
    my ($self, @items) = @_;
    my %set;
    for my $item (@items) {
        $set{$self->tid} = $item;
        if ($self->index < $self->max_size - 1) {
            $self->index($self->index+1);
        }
        else {
            $self->roll_index(1);
        }
    }
    $self->set(%set);
}
sub splice {
    # TODO: ひどい…いつか直す

    my ($self, $offset, $length, @items) = @_;
    my $endset = $offset + $length - 1;

    croak "illegal offset was set" if $offset < 0 || $offset > $self->max_size - 1;
    croak "illegal length was set" if $endset < 0 || $endset > $self->max_size - 1;

    my @tids = @{$self->indices}[$offset .. $endset];
    my @delete_items = $self->get(@tids);
    my $diff = scalar @items - scalar @delete_items;
    if ($diff > 0) {
        for my $i (0 .. $diff) {
            if ($self->index < $self->max_size - 1) {
                $self->index($self->index+1);
                my ($tid) = CORE::splice @{$self->indices}, $self->index, 1;
                CORE::splice @{$self->indices}, $offset+$i, 0, $tid;
                CORE::push @tids, $tid;
            }
            elsif ($offset <= 0) {
                $self->roll_index(1);
                my ($tid) = CORE::shift @{$self->indices};
                CORE::splice @{$self->indices}, $i+$offset, 0, $tid;
                CORE::push @tids, $tid;
            }
            else {
                $self->roll_index;
                my ($tid) = CORE::pop @{$self->indices};
                CORE::splice @{$self->indices}, $i+$offset--, 0, $tid;
                CORE::push @tids, $tid;
            }
        }
    }
    @delete_items = $self->get(@tids);
    my %set = map { ($tids[$_] => $items[$_]) } 0 .. $#tids;
    $self->set(%set);

    return @delete_items;
}
sub exists { CORE::exists $_[0]->items->{$_[1]}; }
sub delete { CORE::delete @{+CORE::shift->items}{@_}; }
sub size   { scalar values %{+CORE::shift->items} }


# for tie

use Tie::Array;

sub TIEARRAY  { CORE::shift->new(@_); }
sub STORE     { $_[0]->set(${$_[0]->indices}[$_[1]] => $_[2]); }
sub FETCH     { $_[0]->get($_[0]->tid($_[1]-$_[0]->index)); }
sub FETCHSIZE { $_[0]->size; }
sub EXISTS    { $_[0]->exists($_[1]); }
sub DELETE    { $_[0]->delete($_[1]); }
sub PUSH      { CORE::shift->push(@_); }
sub POP       { $_[0]->pop; }
sub SHIFT     { $_[0]->shift; }
sub UNSHIFT   { CORE::shift->unshift(@_); }
sub SPLICE    {
    my ($self, $offset, $length, @item) = @_;
    $self->splice($offset, $length, @item);
}


1; # Magic true value required at end of module
__END__

=encoding utf8

=head1 NAME

Uc::IrcGateway::TypableMap - Generate TypableMap Object for Uc::IrcGateway


=head1 SYNOPSIS

    use Uc::IrcGateway::TypableMap;

    my $tmap = Uc::IrcGateway::TypableMap->new(scale => 1);
    $tmap->push("you suck! [$tmap]"); # you suck! [a]
    $tmap->push("you suck too! [$tmap]"); # you suck too! [i]
    $tmap->push("there is awesome internet! [$tmap]"); # there is awesome internet! [u]

    print $tmap->get('u'); # there is awesome internet! [u];

    # or

    my @TIMELINE;
    my $tmap = tie \@TIMELINE, 'Uc::IrcGateway::TypableMap', fixed => 1, shuffled => 1;
    push @TIMELINE, "you suck! [$tmap]"; # you suck! [ka]
    push @TIMELINE, "you suck too! [$tmap]"; # you suck too! [nu]
    push @TIMELINE, "there is awesome internet! [$tmap]"; # there is awesome internet! [pia]

    print $TIMELINE[2]; # there is awesome internet! [pia];
    print $TIMELINE[$tmap->tid2index('pia')]; # there is awesome internet! [pia];


=head1 DESCRIPTION


=head1 INTERFACE

methods:
    ITEM     = pop()
    ITEMS    = push( ITEM [, ITEM, ...] )
    ITEM     = shift()
    ITEMS    = unshift( ITEM [, ITEM, ...] )
    ITEMS    = get( TID [, TID, TID, ...] )
    ITEMS    = set( TID => ITEM [, TID => ITEM] )
    BOOL     = exists( TID )
    ITEMS    = delete( TID [, TID, TID, ...] )
    NUMBER   = size( [ MAXSIZE ] ) # get or set array size
    ITEMS    = splice( OFFSET, LENGTH [, ITEM [, ITEM, ITEM, ...]] ) # return DELETE_ITEMS
    NUMBER   = index() # current index number
    TID      = tid()   # current tid
    NUMBER   = tid2index( TID ) # index number of tid
    TID      = index2tid( NUMBER ) # tid of index number

properties:
    items   -> { TID => ITEM, ... } # hash as item storage
    indices -> [ TID, TID, ... ]    # list of tid
    chars   -> [ CHAR, CHAR, ... ]  # chars list for tid
    index   -> NUMBER               # number of current index

options:
    scale    -> NUMBER   # number of digits of tid
    fixed    -> BOOL     # use fixed digit number for tid
    chars    -> ARRAYREF # chars list for tmap
    shuffled -> BOOL     # randomize tmap index


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
L<https://github.com/UCormorant/p5-uc-ircgateway/issues>


=head1 SEE ALSO

=over

=item L<Uc::IrcGateway>

=back


=head1 AUTHOR

U=Cormorant  C<< <u@chimata.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011-2013, U=Cormorant C<< <u@chimata.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
