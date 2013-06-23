package Uc::IrcGateway::Plugin::DefaultSet;
use 5.014;
use warnings;
use utf8;
use parent 'Class::Component::Plugin';

our @IRC_COMMAND_LIST_ALL = qw(
    pass nick user oper quit
    join part mode invite kick
    topic privmsg notice away
    names list who whois whowas
    users userhost ison

    service squery

    server squit wallops
    motd version time admin info
    lusers stats links servlist
    connect trace
    kill rehash die restart summon wallops

    ping pong error
);
our @IRC_COMMAND_LIST = qw(
    nick user quit
    join part mode invite
    topic privmsg notice away
    names list who whois
    ison

    motd

    ping pong
);
our @CTCP_COMMAND_LIST_ALL = qw(
    finger userinfo time
    version source
    clientinfo errmsg ping
    action dcc sed
);
our @CTCP_COMMAND_LIST = qw(
    userinfo
    clientinfo
    action
);

sub init {
    my ($self, $c) = @_;
    $c->load_plugins(map { sprintf "Irc::%s", ucfirst lc $_ } @IRC_COMMAND_LIST);
}

1;
