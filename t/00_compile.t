use strict;
use Test::More tests => 44;

use_ok $_ for qw(
    Uc::IrcGateway

    Uc::IrcGateway::Channel
    Uc::IrcGateway::Common
    Uc::IrcGateway::Connection
    Uc::IrcGateway::Logger
    Uc::IrcGateway::Message
    Uc::IrcGateway::Structure
    Uc::IrcGateway::TempUser
    Uc::IrcGateway::TypableMap
    Uc::IrcGateway::User

    Uc::IrcGateway::Attribute::CtcpEvent
    Uc::IrcGateway::Attribute::IrcEvent

    Uc::IrcGateway::Plugin::DefaultSet
    Uc::IrcGateway::Plugin::AutoRegisterUser
    Uc::IrcGateway::Plugin::CustomRegisterUser

    Uc::IrcGateway::Plugin::Ctcp::Action
    Uc::IrcGateway::Plugin::Ctcp::ClientInfo
    Uc::IrcGateway::Plugin::Ctcp::Errmsg
    Uc::IrcGateway::Plugin::Ctcp::Finger
    Uc::IrcGateway::Plugin::Ctcp::Ping
    Uc::IrcGateway::Plugin::Ctcp::Source
    Uc::IrcGateway::Plugin::Ctcp::Time
    Uc::IrcGateway::Plugin::Ctcp::Userinfo
    Uc::IrcGateway::Plugin::Ctcp::Version

    Uc::IrcGateway::Plugin::Irc::Away
    Uc::IrcGateway::Plugin::Irc::Invite
    Uc::IrcGateway::Plugin::Irc::Ison
    Uc::IrcGateway::Plugin::Irc::Join
    Uc::IrcGateway::Plugin::Irc::Kick
    Uc::IrcGateway::Plugin::Irc::List
    Uc::IrcGateway::Plugin::Irc::Mode
    Uc::IrcGateway::Plugin::Irc::Motd
    Uc::IrcGateway::Plugin::Irc::Names
    Uc::IrcGateway::Plugin::Irc::Nick
    Uc::IrcGateway::Plugin::Irc::Notice
    Uc::IrcGateway::Plugin::Irc::Part
    Uc::IrcGateway::Plugin::Irc::Ping
    Uc::IrcGateway::Plugin::Irc::Pong
    Uc::IrcGateway::Plugin::Irc::Privmsg
    Uc::IrcGateway::Plugin::Irc::Quit
    Uc::IrcGateway::Plugin::Irc::Topic
    Uc::IrcGateway::Plugin::Irc::User
    Uc::IrcGateway::Plugin::Irc::Who
    Uc::IrcGateway::Plugin::Irc::Whois
);

done_testing;
