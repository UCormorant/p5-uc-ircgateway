package Uc::IrcGateway::Twitter;

use 5.010;
use common::sense;
use warnings qw(utf8);
use Encode qw(decode find_encoding);
use Any::Moose; # qw(::Util::TypeConstraints);
use Uc::IrcGateway;
use Net::Twitter::Lite;
use AnyEvent::Twitter::Stream;
use HTML::Entities qw(decode_entities);
use Config::Pit;

use Data::Dumper;
use Smart::Comments;

use Readonly;
Readonly my $CHARSET => 'utf8';

extends 'Uc::IrcGateway';
has '+port' => ( default => 16668 );
has '+gatewayname' => ( default => 'twitterircgateway' );
has 'conf_app' => ( is  => 'rw', isa => 'HashRef', required => 1, default => sub { pit_get('utig.pl'); } );

__PACKAGE__->meta->make_immutable;
no Any::Moose;

our $VERSION = $Uc::IrcGateway::VERSION;
our $CRLF = "\015\012";
my  $encode = find_encoding($CHARSET);

sub BUILD {
    my $self = shift;
    $self->reg_cb(
        nick => \&nick,
        user => \&user,
        join => \&join,
        part => \&part,
        topic => \&topic,
        privmsg => \&privmsg,
        notice => \&notice,
        pin => \&pin,
        list => \&list,
        who => \&who,
        quit => \&quit,
        on_eof => sub {
            my ($self, $handle) = @_;
            undef $handle;
        },
    );
}

sub nick {
    my ($self, $msg, $handle) = @_;
    my $nick = shift @{$msg->{params}};

    unless ($nick) {
        $self->need_more_params($handle, 'NICK');
    }

    $handle->{conf_user} = pit_get("utig.pl.$nick") if $nick;
}

sub user {
    my ($self, $msg, $handle) = @_;
    my ($nick, $host, $server, $realname) = @{$msg->{params}};
    $handle->self(Uc::IrcGateway::Util::User->new(
        nick => $nick, login => $nick, realname => $realname,
        host => $host, addr => '*', server => $server,
    ));

    $self->send_msg( $handle, RPL_WELCOME, $self->welcome );
    $self->send_msg( $handle, RPL_YOURHOST, "Your host is @{[ $self->servername ]} [@{[ $self->servername ]}/@{[ $self->port ]}]. @{[ ref $self ]}/$VERSION" );
    $self->send_msg( $handle, RPL_CREATED, "This server was created ".$self->ctime);
    $self->send_msg( $handle, RPL_MYINFO, "@{[ $self->servername ]} @{[ ref $self ]}-$VERSION" );
    if (-e $self->motd) {
        $self->send_msg( $handle, ERR_NOMOTD, "MOTD File is found" );
    }
    else {
        $self->send_msg( $handle, ERR_NOMOTD, "MOTD File is missing" );
    }

    $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user});
}

sub join {
    my ($self, $msg, $handle) = @_;
    my $chans = shift @{$msg->{params}};
    my $nick = $handle->self->nick;

    unless ($chans) {
        $self->need_more_params($handle, 'JOIN');
    }

    for my $chan (split /,/, $chans) {
        my $raw;
        $handle->set_channels($chan => Uc::IrcGateway::Util::Channel->new) if !$handle->has_channel($chan);
        $handle->get_channels($chan)->set_users( $handle->{conf_user}{user_id} => $handle->self );

        # sever reply
        $self->send_msg( $handle, RPL_TOPIC, $chan, $handle->get_channels($chan)->topic || '' );
        $self->send_msg( $handle, RPL_NAMREPLY, $chan, "duke" ); # TODO
        $raw = mk_msg($self->servername, 'MODE', $chan, '+o', $nick) . $CRLF;
        ### $raw
        $handle->push_write($raw);

        # send join message
        my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
        $raw = mk_msg($comment, 'JOIN', $chan) . $CRLF;
        ### $raw
        $handle->push_write($raw);

        if ($chan eq '#twitter') {
            $self->streamer(
                handle          => $handle,
                consumer_key    => $self->conf_app->{consumer_key},
                consumer_secret => $self->conf_app->{consumer_secret},
                token           => $handle->{conf_user}{token},
                token_secret    => $handle->{conf_user}{token_secret},
            );
        }
    }
}

sub part {
    my ($self, $msg, $handle) = @_;
    my ($chans, $text) = @{$msg->{params}};
    my $nick = $handle->self->nick;

    unless ($chans) {
        $self->need_more_params($handle, 'JOIN');
    }

    for my $chan (split /,/, $chans) {
        $handle->get_channels($chan)->del_users($handle->{conf_user}{user_id});

        # send part message
        my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
        my $raw = mk_msg($comment, 'PART', $chan, $text) . $CRLF;
        ### $raw
        $handle->push_write($raw);

        if ($chan eq '#twitter') {
            delete $handle->{streamer};
        }
    }
}

sub topic {
    my ($self, $msg, $handle) = @_;
    my ($chan, $topic) = @{$msg->{params}};
    my $nick = $handle->self->nick;

    unless ($chan) {
        $self->need_more_params($handle, 'TOPIC');
    }

    if ($topic) {
        $handle->get_channels($chan)->topic( $topic );
        $self->send_msg($handle, RPL_TOPIC, $chan, $topic);
    }
    else {
        $self->send_msg($handle, RPL_NOTOPIC, $chan, 'No topic is set');
    }
}

sub privmsg {
    my ($self, $msg, $handle) = @_;
    my ($chan, $text) = @{$msg->{params}};
    my $nick = $handle->self->nick;

    unless ($chan) {
        $self->need_more_params($handle, 'PRIVMSG');
    }
    eval { $self->twitter_agent($handle)->update($encode->decode($text)); };
    if ($@) {
        my $comment = sprintf("%s!%s@%s", $self->gatewayname, $self->gatewayname, $self->servername);
        my $raw = mk_msg($comment, 'NOTICE', '#twitter', qq|send error: "$text": $@| ) . $CRLF;
        ### $raw
        $handle->push_write($raw);
    }
}

sub notice {
    my ($self, $msg, $handle) = @_;
    my ($chan, $text) = @{$msg->{params}};
    my $nick = $handle->self->nick;
    unless ($chan) {
        $self->need_more_params($handle, 'NOTICE');
    }
    # no reply any message
}

sub pin {
    my ($self, $msg, $handle) = @_;
    my $pin = shift @{$msg->{params}};
    $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user}, $pin);
}

sub list {
    my ($self, $msg, $handle) = @_;
    my $chans = shift @{$msg->{params}};
    my $nick = $handle->self->nick;
    $self->list($handle, $chans);
}

sub who {
    my ($self, $msg, $handle) = @_;
    my $chans = shift @{$msg->{params}};
    my $nick = $handle->self->nick;
    unless ($chans) {
        $self->need_more_params($handle, 'WHO');
    }
    while (my ($k, $v) = each %{$handle->get_channels($chans)->users}) {
        $self->send_msg( $handle, RPL_WHOREPLY, $chans, $v->login, $v->host, $v->server, $v->nick, "H :1", $v->realname);
    }
    $self->send_msg( $handle, RPL_ENDOFWHO, 'END of /WHO List');
}

sub quit {
    my ($self, $msg, $handle) = @_;
    undef $handle->{streamer};
    undef $handle;
}

sub twitter_agent {
    my ($self, $handle, $conf_app, $conf_user, $pin) = @_;
    return $handle->{nt} if defined $handle->{nt} && $handle->{nt}{authorized};

    if (ref $handle->{nt} ne 'Net::Twitter::Lite' || ref $conf_app) {
        $handle->{nt} = Net::Twitter::Lite->new(%$conf_app);
    }

    my $nt = $handle->{nt};
    $nt->access_token($conf_user->{token});
    $nt->access_token_secret($conf_user->{token_secret});

    if ($pin) {
        @{$conf_user}{qw/token token_secret user_id screen_name/} = $nt->request_access_token(verifier => $pin);
        $nt->{config_updated} = 1;
    }
    if ($nt->{authorized} = $nt->authorized()) {
        $self->handle_msg(parse_irc_msg('JOIN #twitter'), $handle);
    }
    else {
        $self->send_cmt($handle, 'NOTICE', 'please open the following url and allow this app, then enter /PIN {code}.');
        $self->send_cmt($handle, 'NOTICE', $nt->get_authorization_url());
    }
}

sub streamer {
    my ($self, %config) = @_;
    my $handle = delete $config{handle};
    return $handle->{streamer} if exists $handle->{streamer};

    my $tmap = tie my(@TIMELINE), 'Uc::IrcGateway::Util::TypableMap', shuffled => 1;
    $handle->{streamer} = AnyEvent::Twitter::Stream->new(
        method  => 'userstream',
        timeout => 45,
        %config,

        on_connect => sub {
            my $comment = sprintf("%s!%s@%s", $self->gatewayname, $self->gatewayname, $self->servername);
            my $raw = mk_msg($comment, 'NOTICE', '#twitter', 'streamer start to read.' ) . $CRLF;
            $handle->push_write($raw);
        },
        on_tweet => sub {
            my $tweet = shift;
            my $real = $tweet->{user}{id};
            my $nick = $tweet->{user}{screen_name};
            return unless $nick and $tweet->{text};

            (my $text = $encode->encode(decode_entities($tweet->{text})))       =~ s/[\r\n]+/ /g;
            (my $name = $encode->encode(decode_entities($tweet->{user}{name}))) =~ s/[\r\n]+/ /g;
            (my $url  = $encode->encode(decode_entities($tweet->{user}{url})))  =~ s/[\r\n]+/ /g;
            $url =~ s/\s/+/g; $url ||= "http://twitter.com/$nick";
            if ($handle->has_channel('#twitter') and defined $real) {
                if (not $handle->get_channels('#twitter')->has_user($real)) {
                    my $user = Uc::IrcGateway::Util::User->new(
                        nick => $nick, login => $real, realname => $name,
                        host => 'twitter.com', addr => '127.0.0.1', server => $url,
                    );
                    my $raw = mk_msg($user->to_prefix, 'JOIN', '#twitter') . $CRLF;
                    ### $raw
                    $handle->push_write($raw);
                    $handle->get_channels('#twitter')->set_users($real => $user);
                }
                elsif ((my $oldnick = $handle->get_channels('#twitter')->get_users($real)->nick) ne $nick) {
                    my $raw = mk_msg($oldnick, 'NICK', $nick) . $CRLF;
                    ### $raw
                    $handle->push_write($raw);
                    $handle->get_channels('#twitter')->get_users($real)->nick($nick);
                }
                if ($nick eq $handle->self->nick) {
                    $handle->get_channels('#twitter')->topic("$text [$tmap]");
                    $self->send_msg($handle, RPL_TOPIC, '#twitter', "$text [$tmap]");
                }
                else {
                    my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
                    my $raw = mk_msg($comment, 'PRIVMSG', '#twitter', "$text [$tmap]" ) . $CRLF;
                    # $raw
                    $handle->push_write($raw);
                }
                push @TIMELINE, $tweet if defined $tweet;
            }
        },
        on_error => sub {
            warn "error: $_[0]";
            #        undef $streamer;
        },
        on_eof => sub {
            my $comment = sprintf("%s!%s@%s", $self->gatewayname, $self->gatewayname, $self->servername);
            my $raw = mk_msg($comment, 'NOTICE', '#twitter', 'streamer stop to read.' ) . $CRLF;
            $handle->push_write($raw);
        },
    );
}


1; # Magic true value required at end of module
__END__

=head1 NAME

Uc::IrcGateway::Twitter - [One line description of module's purpose here]


=head1 VERSION

This document describes Uc::IrcGateway::Twitter version 0.0.1


=head1 SYNOPSIS

    use Uc::IrcGateway::Twitter;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
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
  
Uc::IrcGateway::Twitter requires no configuration files or environment variables.


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
C<bug-uc-ircgateway-twitter@rt.cpan.org>, or through the web interface at
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
