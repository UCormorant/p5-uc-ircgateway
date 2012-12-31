#!/usr/local/bin/perl

use 5.010;
use common::sense;
use warnings qw(utf8);

use Readonly;
Readonly my $CHARSET => ($^O eq 'MSWin32' ? 'cp932' : 'utf8');
binmode STDIN  => ":encoding($CHARSET)";
binmode STDOUT => ":encoding($CHARSET)";

use opts;

local $| = 1;

opts my $host  => { isa => 'Str',  default => '127.0.0.1' },
     my $port  => { isa => 'Int',  default => '16668' },
     my $debug => { isa => 'Bool', default => 0 },
     my $help  => { isa => 'Bool', default => 0 };

warn <<"_HELP_" and exit if $help;
Usage: $0 --host=127.0.0.1 --port=16668 --debug
_HELP_

my $cv = AnyEvent->condvar;
my $ircd = Uc::TwitterIrcGateway->new(
    host => $host,
    port => $port,
    servername => 'utig.pl',
    welcome => 'Welcome to the utig server',
    time_zone => 'Asia/Tokyo',
    debug => $debug,

    consumer_key    => '99tP2pSCdf7y0LkEKsMR5w',
    consumer_secret => 'iJiKJCAGnwolMDLgGaRyStHQvS5RBVCMGMZlAwk',
);

$ircd->run();
$cv->recv();

BEGIN {

package Uc::TwitterIrcGateway;

use 5.010;
use common::sense;
use warnings qw(utf8);

use lib qw(../../lib);
use Any::Moose;
use Uc::IrcGateway;
use Uc::IrcGateway::TypableMap;
use Uc::Twitter::Schema;
use Net::Twitter::Lite;
use AnyEvent::Twitter;
use AnyEvent::Twitter::Stream;
use HTML::Entities qw(decode_entities);
use DateTime::Format::DateParse;
use Config::Pit qw(pit_get pit_set);
use Scalar::Util qw(refaddr);
use Clone qw(clone);
use Path::Class;
use YAML ();
use Data::Dumper;

$Data::Dumper::Terse = 1;
$ENV{DBIC_DT_SEARCH_OK} = 1;

push @Uc::IrcGateway::IRC_COMMAND_LIST, qw(
    pin
);

our $CRLF    = $Uc::IrcGateway::CRLF;
our $MAXBYTE = $Uc::IrcGateway::MAXBYTE;

my %action_command = (
    mention      => qr{^me(?:ntion)?$},
    reply        => qr{^re(?:ply)?$},
    favorite     => qr{^f(?:av(?:ou?rites?)?)?$},
    unfavorite   => qr{^unf(?:av(?:ou?rites?)?)?$},
    retweet      => qr{^r(?:etwee)?t$},
    quotetweet   => qr{^(?:q[wt]|quote(?:tweet)?)$},
    delete       => qr{^(?:o+p+s+!*|del(?:ete)?)$},
    list         => qr{^li(?:st)?$},
    information  => qr{^in(?:fo(?:rmation)?)?$},
    conversation => qr{^co(?:nversation)?$},
    ratelimit    => qr{^(?:rate(?:limit)?|limit)$},
    ngword       => qr{^ng(?:word)?$},
);
my @action_command_info = (qq|action commands:|
,  qq|/me mention (or me): fetch mentions|
,  qq|/me reply (or re) <tid> <text>: reply to a <tid> tweet|
,  qq|/me favorite (or f, fav) +<tid>: add <tid> tweets to favorites|
,  qq|/me unfavorite (or unf, unfav) +<tid>: remove <tid> tweets from favorites|
,  qq|/me retweet (or rt) +<tid>: retweet <tid> tweets|
,  qq|/me quotetweet (or qt, qw) <tid> <text>: quotetweet a <tid> tweet, like "<text> QT \@tid_user: tid_tweet"|
,  qq|/me delete (or del, oops) *<tid>: delete your <tid> tweets. if unset <tid>, delete your last tweet|
,  qq|/me list (or li) <screen_name>: list <screen_name>'s recent 20 tweets|
,  qq|/me information (or in, info) +<tid>: show <tid> tweets information. e.g. retweet_count, has conversation, created_at|
,  qq|/me conversation (or co) <tid>: show <tid> tweets conversation|
,  qq|/me ratelimit (or rate, limit): show remaining api hit counts|
,  qq|/me ngword (or ng) <text>: set/delete a NG word. if unset <text>, show all NG words|
);
my %api_method = (
    post => qr {
        ^statuses
            /(?:update(?:_with_media)?|destroy|retweet)
        |
        ^(?:
            direct_messages
            | friendship
            | favorites
            | lists
            | lists/members
            | lists/subscribers
            | saved_searchs
            | blocks
         )
            /(?:new|update|create|destroy)
        |
        ^account
            /(?:update|settings|end_session)
        |
        ^notifications
            /(?:follow|leave)
        |
        ^geo/place
        |
        ^report_spam
        |
        ^oauth
            /(?:access_token|request_token)
    }x,
);


extends 'Uc::IrcGateway';
has '+port' => ( default => 16668 );
has '+gatewayname' => ( default => 'twitterircgateway' );
has 'stream_channel' => ( is => 'rw', isa => 'ValidChanName', default => '#twitter' );
has 'activity_channel' => ( is => 'rw', isa => 'ValidChanName', default => '#activity' );
has 'conf_app' => ( is  => 'rw', isa => 'HashRef', required => 1 );

__PACKAGE__->meta->make_immutable;

sub BUILDARGS {
    my ($class, %args) = @_;
    $args{conf_app} = {
        consumer_key => $args{consumer_key},
        consumer_secret => $args{consumer_secret},
    };
    return \%args;
}

sub BUILD {
    my $self = shift;
    my $logger = Uc::IrcGateway::Logger->new(
        gateway => $self,
        log_debug => $self->debug,
        logging => sub {
            my ($self, $queue, %args) = @_;

            if (ref $queue) {
                push @{$self->{queue}}, $queue if ref $queue->{tweet} && ref $queue->{user};
                return;
            }

            eval { $self->{schema}->txn_do( sub {
                while (my $q = shift @{$self->{queue}}) {
                    $self->{schema}->resultset('Status')->find_or_create_from_tweet(
                        $q->{tweet},
                        { user_id => $q->{user}->login, ignore_remark_disabling => 1 }
                    );
                }
            } ); };

            if ($@ && exists $args{handle}) {
                $self->debug($@, handle => $args{handle});
                delete $self->gateway->handles->{refaddr $args{handle}};
#                if ($@ =~ /Rollback failed/) {
#                    undef $handle;
#                }
            }
        },
#        debugging => sub {},
        remark => sub {
            my ($self, $handle, $attr) = @_;

            my $id  = delete $attr->{id}  if exists $attr->{id};
            my $tid = delete $attr->{tid} if exists $attr->{tid};
            $id = $handle->{tmap}->get($tid) if $tid;

            my $columns = { id => $id, user_id => $handle->self->login };
            for my $col (qw/favorited retweeted/) {
                $columns->{$col} = delete $attr->{$col} if exists $attr->{$col};
            }

            $self->{schema}->resultset('Remark')->update_or_create_with_retweet( $columns );
        },
    );
    my $mysql = pit_get('mysql', require => {
        user => '',
        pass => '',
    });
    $logger->{schema} = Uc::Twitter::Schema->connect('dbi:mysql:twitter', $mysql->{user}, $mysql->{pass}, {
        mysql_enable_utf8 => 1,
        on_connect_do     => ['set names utf8mb4'],
    });
    $logger->{trigger} = AE::timer 10, 10, sub { $logger->log; };

    $self->logger($logger);
}


# event function ( irc command ) #

override '_event_irc_nick' => sub {
    my ($self, $handle, $msg) = super();
    return () unless $self && $handle;

    $self->twitter_configure($handle) if $msg->{registered};

    @_;
};

override '_event_irc_user' => sub {
    my ($self, $handle, $msg) = super();
    return () unless $self && $handle;

   $self->twitter_configure($handle) if $msg->{registered};

    @_;
};

override '_event_irc_join' => sub {
    my ($self, $handle, $msg) = super();
    return () unless $self && $handle;

    my $tmap = $handle->{tmap};
    my $stream_channel   = $handle->options->{stream};
    my $activity_channel = $handle->options->{activity};

    for my $chan (@{$msg->{success}}) {
        if ($chan eq $stream_channel) {
            $self->streamer(
                handle          => $handle,
                consumer_key    => $handle->{conf_app}{consumer_key},
                consumer_secret => $handle->{conf_app}{consumer_secret},
                token           => $handle->{conf_user}{token},
                token_secret    => $handle->{conf_user}{token_secret},
            );

            $self->api($handle, 'users/show', params => { user_id => $handle->self->login }, cb => sub {
                my ($header, $res, $reason) = @_;
                if ($res) {
                    my $user = $res;
                    my $status = delete $user->{status};
                    $status->{user} = $user;

                    $self->process_tweet($handle, tweet => $status);
                }
                else {
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $stream_channel, qq|topic fetching error: $reason| );
                }
            });
        }
        elsif ($chan eq $activity_channel) {
            $self->get_mentions($handle);
        }
    }

    @_;
};

override '_event_irc_part' => sub {
    my ($self, $handle, $msg) = super();
    return () unless $self && $handle;
    return () unless scalar @{$msg->{success}};

    for my $chan (@{$msg->{success}}) {
        delete $handle->{streamer} if $chan eq $handle->options->{stream};
    }

    @_;
};

override '_event_irc_privmsg' => sub {
    my ($self, $handle, $msg) = @_;
    return () unless $self->check_ngword($handle, $msg->{params}[1]);

    ($self, $handle, $msg) = super();
    return () unless $self && $handle;

    my ($msgtarget, $text, $plain_text, $ctcp) = @{$msg->{params}};
    my @target_list = @{$msg->{success}};

    my $ctcp_text = '';
    if ($text =~ /^\s/) {
        $plain_text =~ s/^\s+//;
        my $action = ['ACTION', $plain_text];
        push @$ctcp, $action;
        $self->handle_ctcp_msg( $handle, join(' ', @$action), target => $_ ) for @target_list;
        $plain_text = '';
    }
    $text = $plain_text;

    if ($text && scalar @target_list && $self->twitter_agent($handle)) {
        for my $target (@target_list) {
            $self->api($handle, 'statuses/update', params => { status => $text }, cb => sub {
                my ($header, $res, $reason) = @_;
                if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|send error: "$text": $reason| ); }
            } );
        }
    }

    @_;
};

override '_event_irc_quit' => sub {
    my ($self, $handle, $msg) = @_;
    my $conf = $self->servername.'.'.$handle->options->{account};

    for my $chan ($handle->channel_list) {
        $handle->get_channels($chan)->part_users($handle->get_channels($chan)->login_list) if not $chan eq $handle->options->{stream};
        $handle->del_channels($chan) if !$handle->get_channels($chan)->user_count;
    }
    pit_set( $conf, data => {
        %{$handle->{conf_user}},
    } );
    my $config_file = file($handle->{conf_app}{config_dir}, $handle->options->{account}.".yaml");
    my $fh = $config_file->openw;
    if ($fh) {
        $fh->print(YAML::Dump({
            users    => $handle->users,
            channels => $handle->channels,
            ngword   => $handle->{ngword},
        }), "\n");
    }

    super();
};

sub _event_irc_pin {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my $pin = $msg->{params}[0];
    my $nt = $self->twitter_agent($handle, $pin);
    return () unless $nt;

    my $conf = $self->servername.'.'.$handle->options->{account};
    pit_set( $conf, data => {
        %{$handle->{conf_user}},
    } ) if $nt->{config_updated};
}


# event function ( ctcp command ) #

override '_event_ctcp_action' => sub {
    my ($self, $handle, $msg) = @_;
    my ($command, $params) = split(' ', $msg->{params}[0], 2);
    my @params = $params ? split(' ', $params) : ();
    my $target = $msg->{target};
    @{$msg}{qw/command params/} = ($command, \@params);

    given ($command) {
        when (/$action_command{mention}/) {
            my %opt;
            $opt{target}   = $target;
            $opt{since_id} = $handle->{last_mention_id} if exists $handle->{last_mention_id};
            $self->get_mentions($handle, %opt);
        }
        when (/$action_command{reply}/) {
            break unless check_params($self, $handle, $msg);

            my ($tid, $text) = split(' ', $params, 2); $text ||= '';
            break unless $self->check_ngword($handle, $text);

            $self->logger->log();
            my $tweet_id = $handle->{tmap}->get($tid);
            my $tweet = $self->logger->{schema}->resultset('Status')->search( { 'me.id' => $tweet_id }, { prefetch => 'user' } )->first;
            if (!$tweet) {
                $text = "reply error: no such tid";
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
            }
            else {
                $self->api($handle, 'statuses/update', params => {
                    status => '@'.$tweet->user->screen_name.' '.$text, in_reply_to_status_id => $tweet->id,
                }, cb => sub {
                    my ($header, $res, $reason) = @_;
                    if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target,  qq|reply error: "$text": $reason| ); }
                } );
            }
        }
        when (/$action_command{favorite}/) {
            break unless check_params($self, $handle, $msg);

            for my $tid (@params) {
                $self->tid_event($handle, 'favorites/create', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->logger->remark( $handle, { tid => $tid, favorited => 1 } ) if $res;
                });
            }
        }
        when (/$action_command{unfavorite}/) {
            break unless check_params($self, $handle, $msg);

            for my $tid (@params) {
                $self->tid_event($handle, 'favorites/destroy', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->logger->remark( $handle, { tid => $tid, favorited => 0 } ) if $res;
                });
            }
        }
        when (/$action_command{retweet}/) {
            break unless check_params($self, $handle, $msg);

            for my $tid (@params) {
                $self->tid_event($handle, 'statuses/retweet', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->logger->remark( $handle, { tid => $tid, retweeted => 1 } ) if $res;
                });
            }
        }
        when (/$action_command{quotetweet}/) {
            break unless check_params($self, $handle, $msg);

            my ($tid, $comment) = split(' ', $params, 2);
            break unless $self->check_ngword($handle, $comment);

            $self->logger->log();
            my $tweet_id = $handle->{tmap}->get($tid);
            my $tweet = $self->logger->{schema}->resultset('Status')->search( { 'me.id' => $tweet_id }, { prefetch => 'user' } )->first;
            my $text;
            if (!$tweet) {
                $text = "quotetweet error: no such tid";
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
            }
            else {
                my $notice = $tweet->text;

                $comment = $comment ? $comment.' ' : '';
                $text    = $comment.'QT @'.$tweet->user->screen_name.': '.$notice;
                while (length $text > 140 && $notice =~ /....$/) {
                    $notice =~ s/....$/.../;
                    $text   = $comment.'QT @'.$tweet->user->screen_name.': '.$notice;
                }

                $self->api($handle, 'statuses/update', params => {
                    status => $text, in_reply_to_status_id => $tweet->id,
                }, cb => sub {
                    my ($header, $res, $reason) = @_;
                    if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|quotetweet error: "$text": $reason| ); }
                } );
            }
        }
        when (/$action_command{delete}/) {
            my @tids = @params;
               @tids = $handle->get_channels($handle->options->{stream})->topic =~ /\[(.+?)\]$/ if not scalar @tids;

            break if not scalar @tids;
            for my $tid (@tids) {
                $self->tid_event($handle, 'statuses/destroy', $tid, target => $target);
            }
        }
        when (/$action_command{list}/) {
            break unless check_params($self, $handle, $msg);

            $self->api($handle, 'statuses/user_timeline', params => { screen_name => $params[0] }, cb => sub {
                my ($header, $res, $reason) = @_;
                if ($res) {
                    my $tweets = $res;
                    for my $tweet (reverse @$tweets) {
                        $self->process_tweet($handle, tweet => $tweet, target => $target, notice => 1);
                    }
                }
                else { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|list action error: $reason| ); }
            });
        }
        when (/$action_command{information}/) {
            break unless check_params($self, $handle, $msg);

            for my $tid (@params) {
                my $text;
                my $tweet_id = $handle->{tmap}->get($tid);
                if (!$tweet_id) {
                    $text = "information error: no such tid";
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
                }
                else {
                    $self->api($handle, "statuses/show/$tweet_id", cb => sub {
                        my ($header, $res, $reason) = @_;
                        if ($res) {
                            my $tweet = $res;
                            $text  = "information: $tweet->{user}{screen_name}: retweet count $tweet->{retweet_count}: source $tweet->{source}";
                            $text .= ": conversation" if $tweet->{in_reply_to_status_id};
                            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text ($tweet->{created_at}) [$tid]" );
                        }
                        else { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|information action error: $reason| ); }
                    });
                }
            }
        }
        when (/$action_command{conversation}/) {
            break unless check_params($self, $handle, $msg);

            $self->logger->log();
            my $tid = $params[0];
            my $tweet_id = $handle->{tmap}->get($tid);
            my @statuses;
            my $limit = 10;
            my $cb; $cb = sub {
                my ($header, $res, $reason) = @_;
                my $conversation = 0;

                if ($res) {
                    $conversation = 1 if $res->{in_reply_to_status_id};
                    push @statuses, $res;
                }
                else {
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|conversation error: $reason| );
                }

                if (--$limit > 0 && $conversation) {
                    $self->api($handle, 'statuses/show/'.$res->{in_reply_to_status_id}, cb => $cb);
                }
                else {
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target,
                        "conversation: there are more conversation before" ) if $limit <= 0;
                    for my $status (reverse @statuses) {
                        $self->process_tweet($handle, tweet =>  $status, target => $target, notice => 1);
                    }
                }
            };

            if (!$tweet_id) {
                my $text;
                $text = "conversation error: no such tid";
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
            }
            else {
                $self->api($handle, 'statuses/show/'.$tweet_id, cb => $cb);
            }
        }
        when (/$action_command{ratelimit}/) {
            $self->api($handle, 'account/rate_limit_status', params => { screen_name => $params[0] }, cb => sub {
                my ($header, $res, $reason) = @_;
                my $text;
                if (!$res) {
                    $text = "ratelimit error: $reason";
                }
                else {
                    my $limit = $res;
                    $text  = "ratelimit: remaining hits $limit->{remaining_hits}/$limit->{hourly_limit}";
                    $text .= ": reset time $limit->{reset_time}" if $limit->{remaining_hits} <= 0;
                }
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $text);
            });
        }
        when (/$action_command{ngword}/) {
            my $text = "ngword:";
            my $ngword = lc $params;
            if ($params) {
                if (exists $handle->{ngword}{$ngword}) {
                    delete $handle->{ngword}{$ngword};
                    $text .= qq| -"$ngword"|;
                }
                else {
                    $handle->{ngword}{$ngword} = 1;
                    $text .= qq| +"$ngword"|;
                }
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $text );
            }
            else {
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|ngword: "$_"| )
                    for sort { length $a <=> length $b } keys %{$handle->{ngword}};
            }
        }
        default {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $_) for @action_command_info;
        }
    }

    @_;
};


# IrcGateway::Twitter subroutines #

sub validate_text {
    my $text = shift || return '';

    replace_crlf(decode_entities($text));
}

sub validate_user {
    my $user = shift;
    @{$user}{qw/original_name original_url/} = @{$user}{qw/name url/};
    $user->{name} = validate_text($user->{name});
    $user->{url}  = validate_text($user->{url});
    $user->{url}  ||= "https://twitter.com/$user->{screen_name}";

    $user->{_validated} = 1;
}

sub validate_tweet {
    my $tweet = shift;
    @{$tweet}{qw/original_text original_source/} = @{$tweet}{qw/text source/};
    $tweet->{text}   = validate_text($tweet->{text});
    $tweet->{source} = validate_text($tweet->{source});

    validate_user($tweet->{user}) if $tweet->{user} && !$tweet->{user}{_validated};

    $tweet->{_validated} = 1;
}

sub new_user {
    my $user = shift;
    validate_user($user) if !$user->{_validated};

    Uc::IrcGateway::User->new(
        registered => 1,
        nick => $user->{screen_name}, login => $user->{id}, realname => $user->{name},
        host => 'twitter.com', addr => '127.0.0.1', server => $user->{url},
    );
}

sub datetime2simple {
    my ($created_at, $time_zone) = @_;
    my %opt = ();
    $opt{time_zone} = $time_zone if $time_zone;

    my $dt_now        = DateTime->now(%opt);
    my $dt_created_at = DateTime::Format::DateParse->parse_datetime($created_at);
    $dt_created_at->set_time_zone( $time_zone ) if $time_zone;

    my $date_delta = $dt_now - $dt_created_at;
    my $time = '';
       $time = $dt_created_at->hms            if $date_delta->minutes;
       $time = $dt_created_at->ymd . " $time" if $dt_created_at->day != $dt_now->day;

    $time;
}


# IrcGateway::Twitter method #

sub api {
    my ($self, $handle, $api, %opt) = @_;
    my $nt = $self->twitter_agent($handle);
    my $cb = delete $opt{cb} || delete $opt{callback};
    my %request;

    return unless $nt && $cb;

    $request{$api =~ /^http/ ? 'url' : 'api'} = $api;
    $request{params} = delete $opt{params} if exists $opt{params};
    $request{method} = $opt{method}                ? delete $opt{method}
                     : $api =~ /$api_method{post}/ ? 'POST'
                                                   : 'GET';

    $nt->request( %request, $cb );
}

sub get_mentions {
    my ($self, $handle, %opt, %params) = @_;
    my $activity_channel = $handle->options->{activity};
    my $target = exists $opt{target} ? delete $opt{target} : $activity_channel;

    $params{count}       = $handle->options->{mention_count};
    $params{include_rts} = $handle->options->{include_rts};

    $params{max_id}   = delete $opt{max_id}   if exists $opt{max_id};
    $params{since_id} = delete $opt{since_id} if exists $opt{since_id};
    $self->api($handle, 'statuses/mentions', params => \%params, cb => sub {
        my ($header, $res, $reason) = @_;
        if ($res) {
            my $mentions = $res;

            if (scalar @$mentions) {
                for my $mention (reverse @$mentions) {
                    $self->process_tweet($handle, tweet => $mention, target => $activity_channel);
                }
            }
            else {
                $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|mention: no new mentions yet| );
            }
        }
        else {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|mention fetching error: $reason| );
        }
    });
}

sub tid_event {
    my ($self, $handle, $api, $tid, %opt) = @_;
    $self->logger->log();
    my $target = delete $opt{target} || $handle->self->nick;
    my $tweet_id = $handle->{tmap}->get($tid);
    my $tweet = $self->logger->{schema}->resultset('Status')->search( { 'me.id' => $tweet_id }, { prefetch => 'user' } )->first;
    my $text = '';
    my @event = split('/', $api);
    my $event = $event[1] =~ /(create)|(destroy)/ ? ($2 ? 'un' : '') . $event[0]
                                                  : $event[1];
    my $cb = $opt{overload} && exists $opt{cb}       ? delete $opt{cb}
           : $opt{overload} && exists $opt{callback} ? delete $opt{callback} : sub {
        my ($header, $res, $reason) = @_;
        if (!$res) { $text = "$event error: $reason"; }
        else {
            $event =~ s/[es]+$//;
            $text = validate_text("${event}ed: ".$tweet->user->screen_name.": ".$tweet->text);
        }
        $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );

        my $sub = exists $opt{cb}       ? delete $opt{cb}
                : exists $opt{callback} ? delete $opt{callback} : undef;
        $sub->(@_) if defined $sub;
    };

    if (!$tweet) {
        $text = "$event error: no such tid";
        $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
    }
    else {
        $api .= "/$tweet_id";
        $self->api($handle, $api, cb => $cb);
    }
}

sub lookup_users {
    my ($self, $handle, @reals) = @_;
    my $stream_channel_name = $handle->options->{stream};
    return () unless $handle->has_channel($stream_channel_name);

    $handle->get_channels($stream_channel_name)->get_nicks(@reals);
}

sub check_ngword {
    my ($self, $handle, $msgtext) = @_;
    if ($msgtext =~ /^\s/) {
        $msgtext =~ s/^\s+/\001/; $msgtext .= "\001";
    }
    my ($plain_text, $ctcp) = decode_ctcp($msgtext);
    for my $word (keys $handle->{ngword}) {
        if ($plain_text =~ /$word/i) {
            my $text = qq|ngword: "$word" is a substring of "$plain_text"|;
            while (length $text.$CRLF > $MAXBYTE && $text =~ /...."$/) {
                $text =~ s/...."$/..."/;
            }
            $self->send_msg( $handle, ERR_NOTEXTTOSEND, $text );
            return 0;
        }
    }
    return 1;
}
sub process_tweet {
    my ($self, $handle, %opt) = @_;

    my $target = delete $opt{target};
    my $tweet  = delete $opt{tweet};
    my $notice = delete $opt{notice};
    my $user   = $tweet->{user};
    return unless $user;

    my $real = $user->{id};
    my $nick = $user->{screen_name};
    return unless $nick and $tweet->{text};

    my $raw_tweet = clone $tweet;
    $self->logger->log( { tweet => $raw_tweet, user => $handle->self } );

    validate_tweet($tweet);

    my $text = $tweet->{text};
    my $stream_channel_name   = $handle->options->{stream};
    my $activity_channel_name = $handle->options->{activity};
    my $target_channel_name   = $target ? $target : $stream_channel_name;
    return unless $self->check_channel($handle, $target_channel_name, joined => 1, silent => 1);

    my $tmap = $handle->{tmap};
    my $tid_color  = $handle->options->{tid_color}  || '';
    my $time_color = $handle->options->{time_color} || '';
    my $oldnick = $self->lookup_users($handle, $real) || '';
    my $target_joined   = $self->check_channel($handle, $target_channel_name,   joined => 1, silent => 1);
    my $stream_joined   = $self->check_channel($handle, $stream_channel_name,   joined => 1, silent => 1);
    my $activity_joined = $self->check_channel($handle, $activity_channel_name, joined => 1, silent => 1);
    my $target_channel   = $handle->get_channels($target_channel_name);
    my $stream_channel   = $handle->get_channels($stream_channel_name);
    my $activity_channel = $handle->get_channels($activity_channel_name);

    if (!$oldnick || !$handle->has_user($real)) {
        $oldnick = '';
        $user = new_user($user);
        $handle->set_users($user);
        $stream_channel->join_users($real => $nick);
        $self->send_cmd( $handle, $user, 'JOIN', $stream_channel_name ) if $stream_joined;
    }
    else {
        $user = $handle->get_users($real);
    }

    if (!$target_channel->has_user($real)) {
        $target_channel->join_users($real => $nick);
        $self->send_cmd( $handle, $user, 'JOIN', $target_channel_name ) if $target_joined;
    }

    if ($oldnick && $oldnick ne $nick) {
        $user->nick($nick);
        for my $chan ($handle->who_is_channels($real)) {
            $handle->get_channels($chan)->users->{$real} = $nick;
        }
        $self->send_cmd( $handle, $user, 'NICK', $nick );
    }

    # check time delay
    my $time = datetime2simple($tweet->{created_at}, $self->time_zone);
       $time = " ($time)" if $time;

    # list action
    if ($notice) {
        $self->send_cmd( $handle, $user, 'NOTICE', $target_channel_name, "$text [$tmap]$time" );
    }

    # mention
    elsif ($target_channel_name eq $activity_channel_name) {
        $tweet->{_is_mention} = 1;
        $self->send_cmd( $handle, $user, 'PRIVMSG', $target_channel_name,
            $text." ".decorate_text("[$tmap]", $tid_color).decorate_text($time, $time_color) );
    }

    # not stream
    elsif ($target_channel_name ne $stream_channel_name) {
        $self->send_cmd( $handle, $user, 'PRIVMSG', $target_channel_name,
            $text." ".decorate_text("[$tmap]", $tid_color).decorate_text($time, $time_color) );
    }

    # myself
    elsif ($nick eq $handle->self->nick) {
        $stream_channel->topic("$text [$tmap]");
        $self->send_cmd( $handle, $user, 'TOPIC',  $stream_channel_name,   "$text [$tmap]$time" );
        $self->send_cmd( $handle, $user, 'NOTICE', $activity_channel_name, "$text [$tmap]$time" );
    }

    # stream
    else {
        my @include_users;
        my @include_channels;

        push @include_users, $tweet->{in_reply_to_user_id} if defined $tweet->{in_reply_to_user_id};
        push @include_users, map { $_->{id} } @{$tweet->{user_mentions}} if exists $tweet->{user_mentions};
        my @user_mentions = $text =~ /\@(\w+)/g;
        if (scalar @user_mentions) {
            for my $u ($handle->get_users_by_nicks(@user_mentions)) {
                push @include_users, $u->login if defined $u;
            }
        }
        my %uniq;
        @include_users = grep { defined && !$uniq{$_}++ } @include_users;

        for my $chan ($handle->channel_list) {
            if ($self->check_channel($handle, $chan, joined => 1, silent => 1)) {
                for my $u (@include_users) {
                    my $is_mention_to_me = $u == $handle->self->login;
                    my $is_activity      = $chan eq $activity_channel_name;
                    my $in_channel       = $handle->get_channels($chan)->has_user($u);
                    if ($is_mention_to_me) {
#                        $tweet->{_is_mention} = 1;
                        if ($is_activity && !$activity_channel->has_user($user->login)) {
                            $activity_channel->join_users($user->login => $user->nick);
                            $self->send_cmd( $handle, $user, 'JOIN', $activity_channel_name );
                        }
                    }
                    push @include_channels, $chan
                        if $is_mention_to_me && $is_activity || !$is_mention_to_me && !$is_activity && $in_channel;
                }
            }
        }
        push @include_channels, grep { $_ ne $activity_channel_name } $handle->who_is_channels($real);

        %uniq = ();
        @include_channels = grep { defined && !$uniq{$_}++ } @include_channels;
        for my $chan (@include_channels) {
            $self->send_cmd( $handle, $user, 'PRIVMSG', $chan,
                $text." ".decorate_text("[$tmap]", $tid_color).decorate_text($time, $time_color) );
        }
    }

    $handle->{last_mention_id} = $tweet->{id} if $tweet->{_is_mention};

    $user->last_modified(time);
    push @{$handle->{timeline}}, $tweet->{id};
}

sub join_channels {
    my ($self, $handle, $retry) = @_;
    return () unless $self && $handle;
    $retry ||= 5 + 1;

    $self->api($handle, 'lists/all', cb => sub {
        my ($header, $res, $reason) = @_;

        if (!$res && --$retry) {
            my $time = 10;
            my $text = "list fetching error (you will retry after $time sec): $reason";
            $self->send_msg( $handle, 'NOTICE', $text);
            my $w; $w = AnyEvent->timer( after => $time, cb => sub {
                $self->join_channels($handle, $retry);
                undef $w;
            } );
        }
        else {
            my $stream_channel   = $handle->options->{stream};
            my $activity_channel = $handle->options->{activity};

            $handle->set_channels(
                $activity_channel => Uc::IrcGateway::Channel->new(name => $activity_channel),
            ) if !$handle->has_channel($activity_channel);
            $handle->get_channels($activity_channel)->topic('@mentions and more');
            $self->handle_irc_msg( $handle, "JOIN $stream_channel,$activity_channel" );

            my $lists = $res;
            for my $list (@$lists) {
                next if $list->{user}{id} ne $handle->self->login;

                my $text = validate_text($list->{description});
                my $chan = '#'.$list->{slug};
                my @users;
                my $page = -1;

                my $cb; $cb = sub {
                    my ($header, $res, $reason) = @_;

                    if ($res) {
                        push @users, @{$res->{users}};
                        $page = $res->{next_cursor};
                    }

                    if ($res && $page) {
                        $self->api($handle, 'lists/members', params => {
                            list_id => $list->{id}, cursor => $page,
                        }, cb => $cb);
                    }
                    else {
                        my $lookup = $handle->get_channels($stream_channel);
                        $handle->set_channels($chan => Uc::IrcGateway::Channel->new(name => $chan)) if !$handle->has_channel($chan);
                        for my $u (@users) {
                            next if $u->{id} eq $handle->self->login;
                            my $user = new_user($u);
                            $handle->set_users($user);
                            $handle->get_channels($chan)->join_users($user->login => $user->nick);
                        }

                        $handle->get_channels($chan)->topic($text);
                        $self->handle_irc_msg($handle, "JOIN $chan");
                    }
                };

                $self->api($handle, 'lists/members', params => {
                    list_id => $list->{id}, cursor => $page,
                }, cb => $cb);
            }
        }
    });
}

sub twitter_configure {
    my ($self, $handle) = @_;

    my %opt = opt_parser($handle->self->realname);
    $handle->options(\%opt);
    $handle->options->{account} ||= $handle->self->nick;
    $handle->options->{mention_count} ||= 20;
    $handle->options->{include_rts} ||= 0;
    $handle->options->{shuffle_tid} ||= 0;
    if (!$handle->options->{stream} ||
        not $self->check_channel($handle, $handle->options->{stream})) {
            $handle->options->{stream} = $self->stream_channel;
    }
    if (!$handle->options->{activity} ||
        not $self->check_channel($handle, $handle->options->{activity})) {
            $handle->options->{activity} = $self->activity_channel;
    }
    if ($handle->options->{consumer}) {
        @{$handle->{conf_app}}{qw/consumer_key consumer_secret/} = split /:/, $handle->options->{consumer};
    }
    else {
        $handle->{conf_app} = $self->conf_app;
    }

    my $path = file($0);
    my ($dir, $file) = ($path->dir, $path =~ /(\w+(?:\.\w+)*)$/);
    my $appdir = ".$file";
    for my $home (qw/HOME USERPROFILE/) {
        if (exists $ENV{$home} and -e $ENV{$home}) {
            $dir = $ENV{$home}; last;
        }
    }
    $appdir = dir($dir, $appdir);
    $appdir->mkpath if not -e $appdir;

    $handle->{conf_app}{config_dir} = $appdir->stringify;

    my $conf = $self->servername.'.'.$handle->options->{account};
    my $config_file = file($handle->{conf_app}{config_dir}, $handle->options->{account}.".yaml");
    my $fh = $config_file->open('<:utf8');
    my $app_data = {};
    if ($fh) {
        local $/;
        $app_data = YAML::Load($fh->getline);
    }
    $handle->{conf_user} = pit_get( $conf );
    $handle->{tmap} = tie @{$handle->{timeline}}, 'Uc::IrcGateway::TypableMap', shuffled => $handle->options->{shuffle_tid};
    $handle->{ngword} = delete $app_data->{ngword} || {};
    $handle->users( delete $app_data->{users} || {} );
    $handle->channels( delete $app_data->{channels} || {} );
    my %nicks = map { ($_->nick, $_->login) } values %{$handle->users};
    $handle->nicks( \%nicks );

    $handle->self->nick($handle->{conf_user}{screen_name}) if exists $handle->{conf_user}{screen_name};
    $handle->self->login($handle->{conf_user}{user_id})    if exists $handle->{conf_user}{user_id};

    $self->twitter_agent($handle);
}

sub twitter_agent {
    my ($self, $handle, $pin) = @_;
    return $handle->{nt} if ref $handle->{nt} eq 'AnyEvent::Twitter' && $handle->{nt}{authorized};

    my ($conf_app, $conf_user) = @{$handle}{qw/conf_app conf_user/};
    if (ref $handle->{nt} ne 'Net::Twitter::Lite') {
        $handle->{nt} = Net::Twitter::Lite->new(%$conf_app, legacy_lists_api => 1);
    }

    my $nt = $handle->{nt};
    $nt->access_token($conf_user->{token});
    $nt->access_token_secret($conf_user->{token_secret});

    if ($pin) {
        eval {
            @{$conf_user}{qw/token token_secret user_id screen_name/} = $nt->request_access_token(verifier => $pin);
            $nt->{config_updated} = 1;
        };
        if ($@) {
            $self->send_msg( $handle, ERR_YOUREBANNEDCREEP, "twitter authorization error: $@" );
        }
    }
    if ($nt->{authorized} = eval { $nt->account_totals; }) {
        my ($authorized, $config_updated) = @{$nt}{qw/authorized config_updated/};
        $handle->{nt} = AnyEvent::Twitter->new(
            consumer_key    => $handle->{conf_app}{consumer_key},
            consumer_secret => $handle->{conf_app}{consumer_secret},
            token           => $handle->{conf_user}{token},
            token_secret    => $handle->{conf_user}{token_secret},
        );
        $handle->{nt}{authorized}     = $authorized;
        $handle->{nt}{config_updated} = $config_updated;

        my $user = $handle->self;
        $user->login($conf_user->{user_id});
        $user->host('twitter.com');

        my @channels = $handle->who_is_channels($handle->self->login);
        if (scalar @channels) {
            for my $channel ($handle->get_channels(@channels)) {
                $channel->part_users($handle->self->login);
            }
        }

        $self->join_channels($handle);

        return $handle->{nt};
    }
    else {
        $nt->{rate_limit_status} = eval { $nt->rate_limit_status; };
        if ($nt->{rate_limit_status} && $nt->{rate_limit_status}{remaining_hits} <= 0) {
            $self->send_msg($handle, 'NOTICE', "the remaining api request count is $nt->{rate_limit_status}{remaining_hits}.");
            $self->send_msg($handle, 'NOTICE', "twitter api calls are permitted $nt->{rate_limit_status}{hourly_limit} requests per hour.");
            $self->send_msg($handle, 'NOTICE', "the rate limit reset time is $nt->{rate_limit_status}{reset_time}.");
        }
        else {
            $self->send_msg($handle, 'NOTICE', 'please open the following url and allow this app, then enter /PIN {code}.');
            $self->send_msg($handle, 'NOTICE', $nt->get_authorization_url);
        }
    }

    return ();
}

sub streamer {
    my ($self, %config) = @_;
    my $handle = delete $config{handle};
    return $handle->{streamer} if exists $handle->{streamer};

    my $tmap = $handle->{tmap};
    $handle->{streamer} = AnyEvent::Twitter::Stream->new(
        method  => 'userstream',
        timeout => 45,
        %config,

        on_connect => sub {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $handle->options->{stream}, 'streamer start to read.' );
        },
        on_eof => sub {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $handle->options->{stream}, 'streamer stop to read.' );
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
                my $user = new_user($source);
                my $activity_channel_name = $handle->options->{activity};
                my $activity_channel = $handle->get_channels($activity_channel_name);
                if (!$activity_channel->has_user($user->login)) {
                    $activity_channel->join_users($user->login => $user->nick);
                    $self->send_cmd( $handle, $user, 'JOIN', $activity_channel_name );
                }

                my $text = '';
                if ($tweet->{text}) {
                    my $time = datetime2simple($tweet->{created_at}, $self->time_zone);
                    $text  = validate_text("$tweet->{text} {id:$tweet->{id}}");
                    $text .= " ($time)" if $time;
                }
                my $notice = "$happen ".$handle->self->nick.($text ? ": $text" : "");
                $self->send_cmd( $handle, $user, 'NOTICE', $handle->options->{activity}, $notice );
            }
        },
        on_tweet => sub {
            my $tweet = shift;
            $self->process_tweet($handle, tweet => $tweet);
        },
    );
}

no Any::Moose;


}

1;
