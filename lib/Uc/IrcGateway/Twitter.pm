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

$Data::Dumper::Indent = 0;

use Readonly;
Readonly my $CHARSET => 'utf8';

our $VERSION = $Uc::IrcGateway::VERSION;
our $CRLF = "\015\012";
our %IRC_COMMAND_EVENT = %Uc::IrcGateway::IRC_COMMAND_EVENT;
my  $encode = find_encoding($CHARSET);

extends 'Uc::IrcGateway';
has '+port' => ( default => 16668 );
has '+gatewayname' => ( default => 'twitterircgateway' );
has 'conf_app' => ( is  => 'rw', isa => 'HashRef', required => 1 );

sub BUILDARGS {
    my ($class, %args) = @_;
    $args{conf_app} = {
        consumer_key => $args{consumer_key},
        consumer_secret => $args{consumer_secret},
    };
    return \%args;
}

sub BUILD {
    no strict 'refs';
    my $self = shift;
    for my $cmd (qw/user join part privmsg favorite unfavorite delete reply pin quit/) {
        $IRC_COMMAND_EVENT{$cmd} = \&{"_event_$cmd"};
    }
    $self->reg_cb( %IRC_COMMAND_EVENT,
        on_eof => sub {
            my ($self, $handle) = @_;
            undef $handle;
        },
        on_error => sub {
            my ($self, $handle, $message) = @_;
#            warn $_[2];
        },
    );
}

override '_event_user' => sub {
    my ($self, $msg, $handle) = super();
    return unless $self;

    my %opt = _opt_parser($handle->self->realname);
    $handle->options(\%opt);
    $handle->options->{account} ||= $handle->self->nick;

    my $conf = $self->servername.'.'.$handle->options->{account};
    $handle->{conf_user} = pit_get( $conf );
    $handle->{lookup} = delete $handle->{conf_user}{lookup} || {};
    $handle->channels( delete $handle->{conf_user}{channels} || {} );

    $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user});
};

override '_event_join' => sub {
    my ($self, $msg, $handle) = super();
    return unless $self;

    for my $chan (split /,/, $msg->{params}[0]) {
        if ($chan eq '#twitter' && $self->check_channel_name( $handle, $chan, joined => 1 )) {
            $self->streamer(
                handle          => $handle,
                consumer_key    => $self->conf_app->{consumer_key},
                consumer_secret => $self->conf_app->{consumer_secret},
                token           => $handle->{conf_user}{token},
                token_secret    => $handle->{conf_user}{token_secret},
            );
        }
    }
};

override '_event_part' => sub {
    my ($self, $msg, $handle) = super();
    return unless $self;

    my ($chans, $text) = @{$msg->{params}};

    for my $chan (split /,/, $chans) {
        delete $handle->{streamer} if $chan eq '#twitter';
    }
};

override '_event_privmsg' => sub {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($chan, $text) = @{$msg->{params}};
    return () unless $self->check_channel_name( $handle, $chan, enable => 1 );

    if ($text =~ /^\s+(\w+)(?:\s+(.*))?/) {
        my ($cmd, $arg) = ($1, $2);
        if ($cmd =~ /^re(?:ply)?$/) {
            my ($tid, $text) = split /\s+/, $arg, 2;
            $self->handle_msg(parse_irc_msg("REPLY $tid :$text"), $handle); return ();
        }
        if ($cmd =~ /^f(?:av(?:ou?rites?)?)?$/)   { $self->handle_msg(parse_irc_msg("FAVORITE $arg"),   $handle); return (); }
        if ($cmd =~ /^unf(?:av(?:ou?rites?)?)?$/) { $self->handle_msg(parse_irc_msg("UNFAVORITE $arg"), $handle); return (); }
        if ($cmd =~ /^o+ps!*$|^del(?:ete)?$/)     { $self->handle_msg(parse_irc_msg("DELETE $arg"),     $handle); return (); }
#        if ($cmd =~ /^rt$|^retweet$/)            { $self->handle_msg(parse_irc_msg("RETWEET $arg"), $handle);  return (); }
#        if ($cmd =~ /^me(?:ntion)?$/)            { $self->handle_msg(parse_irc_msg("MENTION $arg"), $handle);  return (); }
    }

    my $nt = $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user});
    my $w; $w = AnyEvent->timer( after => 0.5, cb => sub {
        eval { $nt->update($encode->decode($text)); };
        if ($@) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', '#twitter', qq|send error: "$text": $@| ); }
        undef $w;
    } );
};

sub _event_reply {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my ($tid, $text) = @{$msg->{params}};
    my $tweet = $handle->{tmap}->get($tid);
    my $nt = $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user});
    my $w; $w = AnyEvent->timer( after => 0.5, cb => sub {
        eval { $nt->update({ status => $encode->decode($text), in_reply_to_status_id => $tweet->{id} }); };
        if ($@) { $self->send_cmd($handle, $self->daemon, 'NOTICE', '#twitter', "reply error: $@"); }
        undef $w;
    } );
}

sub _event_favorite {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my $nt = $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user});
    for my $tweet ($handle->{tmap}->get(@{$msg->{params}})) {
        my $w; $w = AnyEvent->timer( after => 0.5, cb => sub {
            eval { $nt->create_favorite($tweet->{id}); };
            if ($@) { $self->send_cmd($handle, $self->daemon, 'NOTICE', '#twitter', "favorite error: $@"); }
            else    {
                (my $text = $encode->encode(decode_entities($tweet->{text}))) =~ s/[\r\n]+/ /g;
                $self->send_cmd($handle, $self->daemon, 'NOTICE', '#twitter', "faved: $tweet->{user}{screen_name}: $text");
            }
            undef $w;
        } );
    }
}

sub _event_unfavorite {
    my ($self, $msg, $handle) = _check_params(@_);
    return unless $self;

    my $nt = $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user});
    for my $tweet ($handle->{tmap}->get(@{$msg->{params}})) {
        my $w; $w = AnyEvent->timer( after => 0.5, cb => sub {
            eval { $nt->destroy_favorite($tweet->{id}); };
            if ($@) { $self->send_cmd($handle, $self->daemon, 'NOTICE', '#twitter', "unfavorite error: $@"); }
            else    {
                (my $text = $encode->encode(decode_entities($tweet->{text}))) =~ s/[\r\n]+/ /g;
                $self->send_cmd($handle, $self->daemon, 'NOTICE', '#twitter', "unfaved: $tweet->{user}{screen_name}: $text");
            }
            undef $w;
        } );
    }
}

sub _event_delete {
    my ($self, $msg, $handle) = @_;

    my $nt = $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user});
    my @tids = @{$msg->{params}} || $handle->get_channels('#twitter')->topic =~ /\[(.+?)\]$/;
    for my $tweet ($handle->{tmap}->get(@tids)) {
        my $w; $w = AnyEvent->timer( after => 0.5, cb => sub {
            eval { $nt->destroy_status($tweet->{id}); };
            if ($@) { $self->send_cmd($handle, $self->daemon, 'NOTICE', '#twitter', "delete error: $@"); }
            else    {
                (my $text = $encode->encode(decode_entities($tweet->{text}))) =~ s/[\r\n]+/ /g;
                $self->send_cmd($handle, $self->daemon, 'NOTICE', '#twitter', "delete: $tweet->{user}{screen_name}: $text");
            }
            undef $w;
        } );
    }
}

sub _event_pin {
    my ($self, $msg, $handle) = _check_params(@_);
    my $pin = $msg->{params}[0];

    $self->twitter_agent($handle, $self->conf_app, $handle->{conf_user}, $pin);
    my $conf = $self->servername.'.'.$handle->options->{account};
    pit_set( $conf, data => {
        %{$handle->{conf_user}},
        lookup   => $handle->{lookup},
        channels => $handle->channels,
    } ) if $handle->{nt}{config_updated};
};

sub _event_quit {
    my ($self, $msg, $handle) = @_;
    my $conf = $self->servername.'.'.$handle->options->{account};
    pit_set( $conf, data => {
        %{$handle->{conf_user}},
        lookup   => $handle->{lookup},
        channels => $handle->channels,
    } );
    undef $handle;
};

sub _opt_parser { my %opt; $opt{$1} = $2 while $_[0] =~ /(?:(\w+)=(\S+))/g; %opt }

sub twitter_agent {
    my ($self, $handle, $conf_app, $conf_user, $pin) = @_;
    return $handle->{nt} if defined $handle->{nt} && $handle->{nt}{authorized};

    if (ref $handle->{nt} ne 'Net::Twitter::Lite') {
        $handle->{nt} = Net::Twitter::Lite->new(%$conf_app);
    }

    my $nt = $handle->{nt};
    $nt->access_token($conf_user->{token});
    $nt->access_token_secret($conf_user->{token_secret});

    eval {
        if ($pin) {
            @{$conf_user}{qw/token token_secret user_id screen_name/} = $nt->request_access_token(verifier => $pin);
            $nt->{config_updated} = 1;
        }
        if ($nt->{authorized} = $nt->authorized) {
            my $user = $handle->self;
            $user->login($conf_user->{user_id});
            $user->host('twitter.com');
            $self->handle_msg(parse_irc_msg('JOIN #twitter'), $handle);
        }
        else {
            $self->send_msg($handle, 'NOTICE', 'please open the following url and allow this app, then enter /PIN {code}.');
            $self->send_msg($handle, 'NOTICE', $nt->get_authorization_url);
        }
    };
    if ($@) {
        $self->send_msg( $handle, ERR_YOUREBANNEDCREEP, "twitter authorization error: $@" );
    }

    return ();
}

sub streamer {
    my ($self, %config) = @_;
    my $handle = delete $config{handle};
    return $handle->{streamer} if exists $handle->{streamer};

    my $tmap = $handle->{tmap} = tie my(@TIMELINE), 'Uc::IrcGateway::Util::TypableMap', shuffled => 1;
    $handle->{streamer} = AnyEvent::Twitter::Stream->new(
        method  => 'userstream',
        timeout => 45,
        %config,

        on_connect => sub {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', '#twitter', 'streamer start to read.' );
        },
        on_eof => sub {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', '#twitter', 'streamer stop to read.' );
            delete $handle->{streamer};
            $self->streamer(handle => $handle, %config);
        },
        on_error => sub {
            warn "error: $_[0]";
            delete $handle->{streamer};
            $self->streamer(handle => $handle, %config);
        },
        on_event => sub {
            my $event = shift;
            my $happen = $event->{event};
            my $source = $event->{source};
            my $target = $event->{target};
            my $tweet  = $event->{target_object} || {};

            if ($target->{id} == $handle->self->login) {
                $tweet->{text} ||= '';
                (my $text = $encode->encode(decode_entities($tweet->{text}))) =~ s/[\r\n]+/ /g;
                my $notice = "\@$source->{screen_name} $happen \@$target->{screen_name}".($text ? ": $text" : "");
                $self->send_cmd( $handle, $source->{screen_name}, 'NOTICE', '#twitter', $notice );
            }
        },
        on_tweet => sub {
            my $tweet = shift;
            my $real = $tweet->{user}{id};
            my $nick = $tweet->{user}{screen_name};
            return unless $nick and $tweet->{text};

            $tweet->{text}       ||= '';
            $tweet->{user}{name} ||= '';
            $tweet->{user}{url}  ||= '';
            (my $text = $encode->encode(decode_entities($tweet->{text})))       =~ s/[\r\n]+/ /g;
            (my $name = $encode->encode(decode_entities($tweet->{user}{name}))) =~ s/[\r\n]+/ /g;
            (my $url  = $encode->encode(decode_entities($tweet->{user}{url})))  =~ s/[\r\n]+/ /g;
            $url =~ s/\s/+/g; $url ||= "http://twitter.com/$nick";

            if ($handle->has_channel('#twitter') and defined $real) {
                my $oldnick = $handle->{lookup}{$real} || '';
                my $channel = $handle->get_channels('#twitter');

                my $user;
                if (!$oldnick || !$channel->has_user($oldnick)) {
                    $user = Uc::IrcGateway::Util::User->new(
                        nick => $nick, login => $real, realname => $name,
                        host => 'twitter.com', addr => '127.0.0.1', server => $url,
                    );
                    $self->send_cmd( $handle, $user, 'JOIN', '#twitter' );
                    $channel->set_users($nick => $user);
                }
                else {
                    $user = $channel->get_users($oldnick);
                    if ($oldnick ne $nick) {
                        $self->send_cmd( $handle, $user, 'NICK', $nick );
                        $user->nick($nick);
                    }
                }

                if ($nick eq $handle->self->nick) {
                    $channel->topic("$text [$tmap]");
                    $self->send_msg($handle, RPL_TOPIC, '#twitter', "$text [$tmap]");
                }
                else {
                    $self->send_cmd( $handle, $user, 'PRIVMSG', '#twitter', "$text [$tmap]" );
                }

                $user->last_modified(time);
                $handle->{lookup}{$real} = $nick;
                push @TIMELINE, $tweet;
            }
        },
    );
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;


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
