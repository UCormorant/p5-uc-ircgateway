package Uc::IrcGateway::Twitter;

use 5.010;
use common::sense;
use warnings qw(utf8);

use Any::Moose;
use Any::Moose qw(::Util::TypeConstraints);
use Uc::IrcGateway;
use Net::Twitter::Lite;
use AnyEvent::Twitter;
use AnyEvent::Twitter::Stream;
use Encode qw(decode find_encoding);
use HTML::Entities qw(decode_entities);
use DateTime::Format::DateParse;
use Config::Pit qw(pit_get pit_set);
use Clone qw(clone);

use Data::Dumper;
#use Smart::Comments;

$Data::Dumper::Indent = 0;

use Readonly;
Readonly my $CHARSET => 'utf8';

our @IRC_COMMAND_LIST_EXTEND = qw(
    user join part privmsg
    quit pin
);
our @CTCP_COMMAND_LIST_EXTEND = qw(
    action
);

my $encode = find_encoding($CHARSET);
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
,  qq|/me delete (or del, oops) *<tid>: delete your <tid> tweets. when unset <tid>, delete your last tweet|
,  qq|/me list (or li) <screen_name>: list <screen_name>'s recent 20 tweets|
,  qq|/me information (or in, info) +<tid>: show <tid> tweets information. e.g. retweet_count, has conversation, created_at|
,  qq|/me conversation (or co) <tid>: show <tid> tweets conversation|
,  qq|/me ratelimit (or rate, limit): show remaining api hit counts|
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
subtype 'ValidChanName' => as 'Str' => where { /^[#&][^\s,]+$/ } => message { "This Str ($_) is not a valid channel name!" };
has '+port' => ( default => 16668 );
has '+gatewayname' => ( default => 'twitterircgateway' );
has 'stream_channel' => ( is => 'rw', isa => 'ValidChanName', default => '#twitter' );
has 'activity_channel' => ( is => 'rw', isa => 'ValidChanName', default => '#activity' );
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
    for my $cmd (@IRC_COMMAND_LIST_EXTEND) {
        $IRC_COMMAND_EVENT{"irc_$cmd"} = \&{"_event_irc_$cmd"};
    }
    for my $cmd (@CTCP_COMMAND_LIST_EXTEND) {
        $CTCP_COMMAND_EVENT{"ctcp_$cmd"} = \&{"_event_ctcp_$cmd"};
    }

    $self->reg_cb(
        %IRC_COMMAND_EVENT, %CTCP_COMMAND_EVENT,

        on_eof => sub {
            my ($self, $handle) = @_;
            undef $handle;
        },
        on_error => sub {
            my ($self, $handle, $message) = @_;
#            warn $_[2];
        },
    );

    eval { require Uc::Twitter::Schema; };
    if ($@) {
        $self->reg_cb(
            do_logging   => sub {},
            do_remarking => sub {},
        );

    }
    else {
        my $mysql = pit_get('mysql', require => {
            user => '',
            pass => '',
        });
        my $log_capture = sub {
            my ($handle, $tweet) = @_;

            if (not ref $handle->{_log_schema} eq 'Uc::Twitter::Schema') {
                $handle->{_log_schema} = Uc::Twitter::Schema->connect('dbi:mysql:twitter', $mysql->{user}, $mysql->{pass}, {
                    mysql_enable_utf8 => 1,
                    on_connect_do     => ['set names utf8', 'set character set utf8'],
                });
            }

            if (ref $tweet) {
                push @{$handle->{_raw_tweet}}, $tweet;
                return;
            }

            eval { $handle->{_log_schema}->txn_do( sub {
                while (@{$handle->{_raw_tweet}}) { ### txn_do [===  ]
                    $handle->{_log_schema}->resultset('Status')->find_or_create_from_tweet(
                        shift @{$handle->{_raw_tweet}},
                        { user_id => $handle->self->login, ignore_remark_disabling => 1 }
                    );
                }
                ### txn_do done
            } ); };
            if ($@) {
                ### logging failed
                if ($@ =~ /Rollback failed/) {
                    ### Rollback failed
                    undef $handle;
                }
            }
        };

        my $logger = sub {
            my ($self, $handle, $tweet) = @_;

            if (not defined $handle->{_log_trigger}) {
                $handle->{_log_trigger} = AE::timer 10, 10, sub { $self->event( do_logging => $handle ); };
            }

            if (not $handle->{_log_capture}) {
                my $code = $handle->on_destroy();
                $code = ref $code eq 'CODE' ? sub { $log_capture->(@_); $code->(@_) } : $log_capture;
                $handle->on_destroy($code);
                $handle->{_log_capture} = 1;
            }

            $log_capture->($handle, $tweet);
        };

        my $remarker = sub {
            my ($self, $handle, $attr) = @_;

            my $id  = delete $attr->{id}  if exists $attr->{id};
            my $tid = delete $attr->{tid} if exists $attr->{tid};
            my $tweet = $handle->{tmap}->get($tid) if $tid;
            $id = $tweet->{id} if $tweet->{id};

            my $columns = { id => $id, user_id => $handle->self->login };
            for my $col (qw/favorited retweeted/) {
                $columns->{$col} = delete $attr->{$col} if exists $attr->{$col};
            }

            $handle->{_log_schema}->resultset('Remark')->update_or_create( $columns );
        };

        $self->reg_cb(
            do_logging   => $logger,
            do_remarking => $remarker,
        );
    }
}


# event function ( irc command ) #

override '_event_irc_user' => sub {
    my ($self, $handle, $msg) = super();
    return unless $self;

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

    my $conf = $self->servername.'.'.$handle->options->{account};
    $handle->{conf_user} = pit_get( $conf );
    $handle->{tmap} = tie @{$handle->{timeline}}, 'Uc::IrcGateway::Util::TypableMap', shuffled => $handle->options->{shuffle_tid};
    $handle->users( delete $handle->{conf_user}{users} || {} );
    $handle->channels( delete $handle->{conf_user}{channels} || {} );

    $handle->self->nick($handle->{conf_user}{screen_name}) if exists $handle->{conf_user}{screen_name};
    $handle->self->login($handle->{conf_user}{user_id})    if exists $handle->{conf_user}{user_id};

    $self->twitter_agent($handle);
};

override '_event_irc_join' => sub {
    my ($self, $handle, $msg) = super();
    return unless $self;

    my $tmap = $handle->{tmap};
    my $stream_channel   = $handle->options->{stream};
    my $activity_channel = $handle->options->{activity};

    for my $chan (split /,/, $msg->{params}[0]) {
        next unless $chan ~~ $msg->{success};

        if ($chan eq $stream_channel) {
            $self->streamer(
                handle          => $handle,
                consumer_key    => $handle->{conf_app}{consumer_key},
                consumer_secret => $handle->{conf_app}{consumer_secret},
                token           => $handle->{conf_user}{token},
                token_secret    => $handle->{conf_user}{token_secret},
            );

            $self->api($handle, 'users/show', params => { user_id => $handle->self->{login} }, cb => sub {
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
};

override '_event_irc_part' => sub {
    my ($self, $handle, $msg) = super();
    return unless $self;

    my ($chans, $text) = @{$msg->{params}};

    for my $chan (split /,/, $chans) {
        next unless $chan ~~ $msg->{success};
        delete $handle->{streamer} if $chan eq $handle->options->{stream};
    }
};

override '_event_irc_privmsg' => sub {
    my ($self, $handle, $msg) = check_params(@_);
    return unless $self;

    my ($target, $text, $ctcp) = @{$msg->{params}};
    return () unless
         is_valid_channel_name($target) && $self->check_channel( $handle, $target, enable => 1 )
             or $self->check_user( $handle, $target );

    if ($text =~ /^\s/) {
        $text =~ s/^\s+//;
        $text = "\001ACTION $text\001";
    }
    ($text, $ctcp) = decode_ctcp($text);
    if (scalar @$ctcp) {
        for my $event (@$ctcp) {
            my ($ctcp_text, $ctcp_args) = @{$event};
            $ctcp_text .= " $ctcp_args" if $ctcp_args;
            $self->handle_ctcp_msg( $handle, $ctcp_text, target => $target );
        }
    }
    return () unless $text;

    if (my $nt = $self->twitter_agent($handle)) {
        $self->api($handle, 'statuses/update', params => { status => $encode->decode($text) }, cb => sub {
            my ($header, $res, $reason) = @_;
            if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|send error: "$text": $reason| ); }
        } );
    }
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
        users    => $handle->users,
        channels => $handle->channels,
    } );
    undef $handle;
};

sub _event_irc_pin {
    my ($self, $handle, $msg) = check_params(@_);
    return unless $self;

    my $pin = $msg->{params}[0];
    my $nt = $self->twitter_agent($handle, $pin);
    return () unless $nt;

    my $conf = $self->servername.'.'.$handle->options->{account};
    pit_set( $conf, data => {
        %{$handle->{conf_user}},
        users    => $handle->users,
        channels => $handle->channels,
    } ) if $nt->{config_updated};
}


# event function ( ctcp command ) #

override '_event_ctcp_action' => sub {
    my ($self, $handle, $msg) = @_;
    my ($command, $params) = split(' ', $msg->{params}, 2);
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
            my $tweet = $handle->{tmap}->get($tid);
            $self->api($handle, 'statuses/update', params => {
                status => $encode->decode("\@$tweet->{user}{screen_name} $text"), in_reply_to_status_id => $tweet->{id},
            }, cb => sub {
                my ($header, $res, $reason) = @_;
                if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target,  qq|reply error: "$text": $reason| ); }
            } );
        }
        when (/$action_command{favorite}/) {
            break unless check_params($self, $handle, $msg);

            for my $tid (@params) {
                $self->tid_event($handle, 'favorites/create', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->event( do_remarking => $handle, { tid => $tid, favorited => 1 } ) if $res;
                });
            }
        }
        when (/$action_command{unfavorite}/) {
            break unless check_params($self, $handle, $msg);

            for my $tid (@params) {
                $self->tid_event($handle, 'favorites/destroy', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->event( do_remarking => $handle, { tid => $tid, favorited => 0 } ) if $res;
                });
            }
        }
        when (/$action_command{retweet}/) {
            break unless check_params($self, $handle, $msg);

            for my $tid (@params) {
                $self->tid_event($handle, 'statuses/retweet', $tid, target => $target, cb => sub {
                    my ($header, $res, $reason) = @_;
                    $self->event( do_remarking => $handle, { tid => $tid, retweeted => 1 } ) if $res;
                });
            }
        }
        when (/$action_command{quotetweet}/) {
            break unless check_params($self, $handle, $msg);

            my ($tid, $comment) = split(' ', $params, 2);
            my $tweet = $handle->{tmap}->get($tid);
            my $notice = $tweet->{text};
            my $text;

            $comment = $comment ? $comment.' ' : '';
            $text    = $comment."QT \@$tweet->{user}{screen_name}: ".$notice;
            while (length $text > 140 && $notice =~ /....$/) {
                $notice =~ s/....$/.../;
                $text   = $comment."QT \@$tweet->{user}{screen_name}: $notice";
            }

            $self->api($handle, 'statuses/update', params => {
                status => $encode->decode($text), in_reply_to_status_id => $tweet->{id},
            }, cb => sub {
                my ($header, $res, $reason) = @_;
                if (!$res) { $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, qq|quotetweet error: "$text": $reason| ); }
            } );
        }
        when (/$action_command{delete}/) {
            break unless check_params($self, $handle, $msg);

            my @tids = @params;
               @tids = $handle->get_channels($handle->options->{stream})->topic =~ /\[(.+?)\]$/ if not scalar @tids;
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
                my $tweet = $handle->{tmap}->get($tid);
                my $text;

                if (!$tweet) {
                    $text = "information error: no such tid";
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text [$tid]" );
                }
                else {
                    $text  = "information: $tweet->{user}{screen_name}: retweet count $tweet->{retweet_count}: source $tweet->{source}";
                    $text .= ": conversation" if $tweet->{in_reply_to_status_id};
                    $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, "$text ($tweet->{created_at}) [$tid]" );
                }
            }
        }
        when (/$action_command{conversation}/) {
            break unless check_params($self, $handle, $msg);

            my $tid = $params[0];
            my $tweet = $handle->{tmap}->get($tid);
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

            $self->api($handle, 'statuses/show/'.$tweet->{id}, cb => $cb);
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
        default {
            $self->send_cmd( $handle, $self->daemon, 'NOTICE', $target, $_) for @action_command_info;
        }
    }
};


# IrcGateway::Twitter subroutines #

sub opt_parser { my %opt; $opt{$1} = $2 ? $2 : 1 while $_[0] =~ /(\w+)(?:=(\S+))?/g; %opt }

sub decorate_text {
    my ($text, $color) = @_;

    $color ne '' ? "\03$color$text\03" : $text;
}

sub decode_text {
    my $text = shift || return '';

    $encode->encode(decode_entities($text));
}

sub replace_crlf {
    my $text = shift || return '';
    $text =~ s/[\r\n]+/ /g;

    $text;
}

sub validate_text {
    my $text = shift;

    replace_crlf(decode_text($text));
}

sub validate_user {
    my $user = shift;
    @{$user}{qw/original_name original_url/} = @{$user}{qw/name url/};
    $user->{name} = validate_text($user->{name});
    $user->{url}  = validate_text($user->{url});
    $user->{url}  ||= "http://twitter.com/$user->{screen_name}";

    $user->{_validated}  = 1;
}

sub validate_tweet {
    my $tweet = shift;
    @{$tweet}{qw/original_text original_source/} = @{$tweet}{qw/text source/};
    $tweet->{text}   = validate_text($tweet->{text});
    $tweet->{source} = validate_text($tweet->{source});

    validate_user($tweet->{user}) if $tweet->{user};

    $tweet->{_validated} = 1;
}

sub new_user {
    my $user = shift;
    validate_user($user) if !$user->{_validated};

    Uc::IrcGateway::Util::User->new(
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
    my $target = delete $opt{target} || $handle->self->nick;
    my $tweet = $handle->{tmap}->get($tid);
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
            $text = "${event}ed: $tweet->{user}{screen_name}: $tweet->{text}";
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
        $api .= "/$tweet->{id}";
        $self->api($handle, $api, cb => $cb);
    }
}

sub lookup_users {
    my ($self, $handle, @reals) = @_;
    my $stream_channel_name = $handle->options->{stream};
    return unless $handle->has_channel($stream_channel_name);

    $handle->get_channels($stream_channel_name)->get_nicks(@reals);
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
    $self->event( do_logging => $handle, $raw_tweet );

    validate_tweet($tweet);

    my $text = $tweet->{text};
    my $stream_channel_name   = $handle->options->{stream};
    my $activity_channel_name = $handle->options->{activity};
    my $target_channel_name   = $target ? $target : $stream_channel_name;
    my $c = $self->check_channel($handle, $target_channel_name, joined => 1, silent => 1);
    return unless $self->check_channel($handle, $target_channel_name, joined => 1, silent => 1);

    my $tmap = $handle->{tmap};
    my $tid_color  = $handle->options->{tid_color}  || '';
    my $time_color = $handle->options->{time_color} || '';
    my $oldnick = $self->lookup_users($handle, $real) || '';
    my $stream_joined   = $self->check_channel($handle, $stream_channel_name,   joined => 1, silent => 1);
    my $activity_joined = $self->check_channel($handle, $activity_channel_name, joined => 1, silent => 1);
    my $target_channel   = $handle->get_channels($target_channel_name);
    my $stream_channel   = $handle->get_channels($stream_channel_name);
    my $activity_channel = $handle->get_channels($activity_channel_name);

    if (!$oldnick || !$handle->has_user($oldnick)) {
        $oldnick = '';
        $user = new_user($user);
        $handle->set_users($nick => $user);
        $stream_channel->join_users($real => $nick);
        $self->send_cmd( $handle, $user, 'JOIN', $stream_channel_name ) if $stream_joined;
    }
    else {
        $user = $handle->get_users($oldnick);
    }

    if (!$target_channel->has_user($real)) {
        $target_channel->join_users($real => $nick);
        $self->send_cmd( $handle, $user, 'JOIN', $target_channel_name );
    }

    if ($oldnick && $oldnick ne $nick) {
        $user->nick($nick);
        $handle->users->{$nick} = delete $handle->users->{$oldnick};
        for my $chan ($handle->who_is_channels($real)) {
            $chan->users->{$real} = $nick;
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
            for my $u ($handle->get_users(@user_mentions)) {
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
    push @{$handle->{timeline}}, $tweet;
}

sub join_channels {
    my ($self, $handle, $retry) = @_;
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
                $activity_channel => Uc::IrcGateway::Util::Channel->new(name => $activity_channel),
            ) if !$handle->has_channel($activity_channel);
            $handle->get_channels($activity_channel)->topic('@mentions and more');
            $self->handle_irc_msg( $handle, 'JOIN '.$stream_channel   );
            $self->handle_irc_msg( $handle, 'JOIN '.$activity_channel );

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
                        $handle->set_channels($chan => Uc::IrcGateway::Util::Channel->new(name => $chan)) if !$handle->has_channel($chan);
                        for my $u (@users) {
                            next if $u->{id} eq $handle->self->login;
                            my $user = new_user($u);
                            if (!$handle->has_user($user->nick)) {
                                $handle->del_users($lookup->get_nicks($user->login)) if $lookup->has_user($user->login);
                                $handle->set_users($user->nick => $user);
                            }
                            $lookup->join_users($user->login => $user->nick);
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

sub twitter_agent {
    my ($self, $handle, $pin) = @_;
    return $handle->{nt} if ref $handle->{nt} eq 'AnyEvent::Twitter' && $handle->{nt}{authorized};

    my ($conf_app, $conf_user) = @{$handle}{qw/conf_app conf_user/};
    if (ref $handle->{nt} ne 'Net::Twitter::Lite') {
        $handle->{nt} = Net::Twitter::Lite->new(%$conf_app);
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
