package Uc::IrcGateway::Twitter;

use 5.010;
use common::sense;
use warnings qw(utf8);
use Encode qw(decode find_encoding);
use Any::Moose; # qw(::Util::TypeConstraints);
use Net::Twitter::Lite;
use AnyEvent::Twitter::Stream;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent::IRC::Util qw/parse_irc_msg mk_msg/;
use Sys::Hostname;
use Data::Dumper;
use Config::Pit;
use HTML::Entities qw(decode_entities);
use Uc::IrcGateway::Util::TypableMap;
use Smart::Comments;

use Readonly;
Readonly my $CHARSET => 'utf8';

our $VERSION = '0.0.3';
our $CRLF = "\015\012";
my  $encode = find_encoding($CHARSET);

BEGIN {
    no strict 'refs';
    while (my ($code, $name) = each %AnyEvent::IRC::Util::RFC_NUMCODE_MAP) {
        *{"${name}"} = sub () { $code };
    }
};


extends 'Object::Event';
has 'host' => ( is  => 'ro', isa => 'Str', required => 1, default => '127.0.0.1' );
has 'port' => ( is  => 'ro', isa => 'Int', required => 1, default => 16668 );
has 'servername' => ( is  => 'rw', isa => 'Str', required => 1, default => sub { hostname() } );
has 'welcome'    => ( is  => 'rw', isa => 'Str', default => 'welcome to the utig server' );
has 'conf_app'   => ( is  => 'rw', isa => 'HashRef', required => 1, default => sub { pit_get('utig.pl'); } );
has 'ctime' => ( is  => 'rw', isa => 'Str' );

__PACKAGE__->meta->make_immutable;
no Any::Moose;


sub BUILD {
    my $self = shift;
    $self->reg_cb(
        nick => sub {
            my ($self, $msg, $handle) = @_;
            my $nick = shift @{$msg->{params}};

            unless ($nick) {
                $self->need_more_params($handle, 'NICK');
            }

            ### $nick
            $handle->{conf_user} = pit_get("utig.pl.$nick") if $nick;

            twitter_agent($handle, $self->conf_app, $handle->{conf_user});
            $handle->{channels}->{'#twitter'} = {};
            $self->streamer(
                handle          => $handle,
                consumer_key    => $self->conf_app->{consumer_key},
                consumer_secret => $self->conf_app->{consumer_secret},
                token           => $handle->{conf_user}{token},
                token_secret    => $handle->{conf_user}{token_secret},
            );
        },
        user => sub {
            my ($self, $msg, $handle) = @_;
            my ($nick, $host, $server, $realname) = @{$msg->{params}};
            $handle->{nick}     = $nick;
            $handle->{host}     = $host;
            $handle->{server}   = $server;
            $handle->{realname} = $realname;

            $handle->{channels}->{'#twitter'} = { $handle->{conf_user}{user_id} => $handle->{nick} };
            $self->send_msg( $handle, RPL_WELCOME, $self->{welcome} );
            $self->send_msg( $handle, RPL_YOURHOST, "Your host is @{[ $self->servername ]} [@{[ $self->servername ]}/@{[ $self->port ]}]. @{[ ref $self ]}/$VERSION" ); # 002
            $self->send_msg( $handle, RPL_CREATED, "This server was created $self->{ctime}");
            $self->send_msg( $handle, RPL_MYINFO, "@{[ $self->servername ]} @{[ ref $self ]}-$VERSION" ); # 004
            $self->send_msg( $handle, ERR_NOMOTD, "MOTD File is missing" );

            $self->handle_msg(parse_irc_msg('JOIN #twitter'), $handle);
        },
        join => sub {
            my ($self, $msg, $handle) = @_;
            my $chans = shift @{$msg->{params}};
            my $nick = $handle->{nick};

            unless ($chans) {
                $self->need_more_params($handle, 'JOIN');
            }

            for my $chan (split /,/, $chans) {
                my $raw;
                $handle->{channels}->{$chan}->{$handle->{conf_user}{user_id}} = $nick;

                # sever reply
                $self->send_msg( $handle, RPL_TOPIC, $chan,  $handle->{topics}->{$chan} || '' );
                $self->send_msg( $handle, RPL_NAMREPLY, $chan, "duke" ); # TODO
                $raw = mk_msg($self->servername, 'MODE', $chan, '+o', $nick) . $CRLF;
                ### $raw
                $handle->push_write($raw);

                # send join message
                my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
                $raw = mk_msg($comment, 'JOIN', $chan) . $CRLF;
                ### $raw
                $handle->push_write($raw);
            }
        },
        part => sub {
            my ($self, $msg, $handle) = @_;
            my ($chans, $text) = @{$msg->{params}};
            my $nick = $handle->{nick};

            unless ($chans) {
                $self->need_more_params($handle, 'JOIN');
            }

            for my $chan (split /,/, $chans) {
                delete $handle->{channels}->{$chan}->{$handle->{conf_user}{user_id}};

                # send part message
                my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
                my $raw = mk_msg($comment, 'PART', $chan, $text) . $CRLF;
                ### $raw
                $handle->push_write($raw);
            }
        },
        topic => sub {
            my ($self, $msg, $handle) = @_;
            my ($chan, $topic) = @{$msg->{params}};
            my $nick = $handle->{nick};

            unless ($chan) {
                $self->need_more_params($handle, 'TOPIC');
            }

            if ($topic) {
                $handle->{topics}->{$chan} = $topic;
                $self->send_msg($handle, RPL_TOPIC, $chan, $topic);
            }
            else {
                $self->send_msg($handle, RPL_NOTOPIC, $chan, 'No topic is set');
            }
        },
        privmsg => sub {
            my ($self, $msg, $handle) = @_;
            my ($chan, $text) = @{$msg->{params}};
            my $nick = $handle->{nick};

            unless ($chan) {
                $self->need_more_params($handle, 'PRIVMSG');
            }
            eval { twitter_agent($handle)->update($encode->decode($text)); };
            if ($@) {
                my $comment = sprintf("%s!%s@%s", 'twitterircgateway', 'twitterircgateway', $self->servername);
                my $raw = mk_msg($comment, 'NOTICE', '#twitter', qq|send error: "$text": $@| ) . $CRLF;
                $handle->push_write($raw);
            }
        },
        notice => sub {
            my ($self, $msg, $handle) = @_;
            my ($chan, $text) = @{$msg->{params}};
            my $nick = $handle->{nick};
            unless ($chan) {
                $self->need_more_params($handle, 'NOTICE');
            }
            # no reply any message
        },
        list => sub {
            my ($self, $msg, $handle) = @_;
            my $chans = shift @{$msg->{params}};
            my $nick = $handle->{nick};
            $self->list($handle, $chans);
        },
        who => sub {
            my ($self, $msg, $handle) = @_;
            my $chans = shift @{$msg->{params}};
            my $nick = $handle->{nick};
            unless ($chans) {
                $self->need_more_params($handle, 'WHO');
            }
            while (my ($k, $v) = each %{$handle->{channels}{$chans}}) {
                $self->send_msg( $handle, RPL_WHOREPLY, $chans, $v, $k, $k, $v, "H :1", $k);
            }
            $self->send_msg( $handle, RPL_ENDOFWHO, 'END of /WHO List');
        },
        quit => sub {
            my ($self, $msg, $handle) = @_;
            undef $handle->{streamer};
            undef $handle;
        },
        on_eof => sub {
            my ($self, $handle) = @_;
            undef $handle;
        },
    );
}

sub run {
    my $self = shift;
    $self->ctime(scalar(localtime));
    tcp_server $self->host, $self->port, sub {
        my ($fh, $host, $port) = @_;
        my $handle = AnyEvent::Handle->new(fh => $fh,
            on_error => sub {
                my $handle = shift;
                $self->event('on_error', $handle);
            },
            on_eof => sub {
                my $handle = shift;
                $self->event('on_eof', $handle);
            },
        );
        $handle->on_read(sub { $handle->push_read(line => sub {
            my ($handle, $line, $eol) = @_;
            ### $line
            my $msg = parse_irc_msg($line);
            ### $msg
            $self->handle_msg($msg, $handle);
        }) });
    }, sub {
        my ($fh, $host, $port) = @_;
        say "bound to $host:$port";
        say $self->welcome();
    };
}

sub handle_msg {
    my ($self, $msg, $handle) = @_;
    my $event = lc($msg->{command});
       $event =~ s/^(\d+)$/irc_$1/g;
    $self->event($event, $msg, $handle);
}

sub _server_comment {
    my ($self, $nick) = @_;
    return sprintf '%s!~%s@%s', $nick, $nick, $self->servername;
}

sub list {
    my ($self, $handle, $chans) = @_;
    my $nick = $handle->{nick};
    my $comment = $self->_server_comment($nick);
    my $send = sub {
        my $msg = mk_msg($comment, @_) . $CRLF;
        $handle->push_write($msg);
    };
    my $send_rpl_list = sub {
        my $chan = shift;
        $send->(RPL_LIST, $nick, $chan, scalar values %{$handle->{channels}{$chan}}, (":$handle->{topics}{$chan}" || ''));
    };
    $send->(RPL_LISTSTART, $nick, 'Channel', ':Users', 'Name');
    $chans = join ',', sort keys %{$handle->{channels}} if !$chans;
    for my $chan (split /,/, $chans) {
        $send_rpl_list->($chan);
    }
    $send->(RPL_LISTEND, '$nick', 'END of /List');
}

sub send_msg {
    my ($self, $handle, $cmd, @args) = @_;
    my $msg = mk_msg($self->host, $cmd, $handle->{nick}, @args) . $CRLF;
    ### $msg
    $handle->push_write($msg);
}

sub need_more_params {
    my ($self, $handle, $cmd) = @_;
    $self->send_msg($handle, ERR_NEEDMOREPARAMS, $cmd, 'Not enough parameters');
}

sub twitter_agent {
    my ($handle, $conf_app, $conf_user) = @_;
    return $handle->{nt} if ref $handle->{nt} eq 'Net::Twitter::Lite';

    my $nt = Net::Twitter::Lite->new(%$conf_app);
    $nt->access_token($conf_user->{token});
    $nt->access_token_secret($conf_user->{token_secret});

    my ($pin, @userdata);
    while (!$nt->authorized()) {
        say 'please open the following url and allow this app, then enter PIN code.';
        say $nt->get_authorization_url();
        print 'PIN: '; chomp($pin = <STDIN>);

        @{$conf_user}{qw/token token_secret user_id screen_name/} = $nt->request_access_token(verifier => $pin);
        $nt->{config_updated} = 1;
    }

    return $handle->{nt} = $nt;
}

sub streamer {
    my ($self, %config) = @_;
    my $handle = delete $config{handle};
    my $tmap = tie my(@TIMELINE), 'Uc::IrcGateway::Util::TypableMap', shuffled => 1;
    return $handle->{streamer} if exists $handle->{streamer};
    $handle->{streamer} = AnyEvent::Twitter::Stream->new(
        method  => 'userstream',
        timeout => 45,
        %config,

        on_connect => sub {
            my $comment = sprintf("%s!%s@%s", 'twitterircgateway', 'twitterircgateway', $self->servername);
            my $raw = mk_msg($comment, 'NOTICE', '#twitter', 'streamer start to read.' ) . $CRLF;
            $handle->push_write($raw);
        },
        on_tweet => sub {
            my $tweet = shift;
            my $nick = $tweet->{user}{screen_name};
            return unless $nick and $tweet->{text};

            (my $text = $encode->encode(decode_entities($tweet->{text}))) =~ s/[\r\n]+/ /g;
            if (exists $handle->{channels}{'#twitter'} and exists $tweet->{user}{id}) {
                if (not exists $handle->{channels}{'#twitter'}{$tweet->{user}{id}}) {
                    my $raw = mk_msg($nick, 'JOIN', '#twitter') . $CRLF;
                    ### $raw
                    $handle->push_write($raw);
                    $handle->{channels}{'#twitter'}{$tweet->{user}{id}} = $nick;
                }
                elsif ($handle->{channels}{'#twitter'}{$tweet->{user}{id}} ne $nick) {
                    my $raw = mk_msg($handle->{channels}{'#twitter'}{$tweet->{user}{id}}, 'NICK', $nick) . $CRLF;
                    ### $raw
                    $handle->push_write($raw);
                    $handle->{channels}{'#twitter'}{$tweet->{user}{id}} = $nick;
                }
                if ($nick eq $handle->{nick}) {
                    $handle->{topics}->{'#twittter'} = "$text [$tmap]";
                    $self->send_msg($handle, RPL_TOPIC, '#twitter', "$text [$tmap]");
                }
                my $comment = sprintf("%s!%s@%s", $nick, $nick, $self->servername);
                my $raw = mk_msg($comment, 'PRIVMSG', '#twitter', "$text [$tmap]" ) . $CRLF;
                # $raw
                $handle->push_write($raw);
                push @TIMELINE, $tweet if defined $tweet;
            }
        },
        on_error => sub {
            warn "error: $_[0]";
            #        undef $streamer;
        },
        on_eof => sub {
            my $comment = sprintf("%s!%s@%s", 'twitterircgateway', 'twitterircgateway', $self->servername);
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
