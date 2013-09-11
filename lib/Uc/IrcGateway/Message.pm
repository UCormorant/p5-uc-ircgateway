package Uc::IrcGateway::Message;
use 5.014;
use warnings;
use utf8;

use YAML qw(Load);

my %INFO = %{Load(do {
    local $_;
    my @return;
    while (<DATA>) {
        chomp;
        last if /^__END__$/;
        push @return, $_;
    }
    close DATA;
    join "\n", @return;
})};
sub message_set { +{

#5. Replies
#
#   The following is a list of numeric replies which are generated in
#   response to the commands given above.  Each numeric is given with its
#   number, name and reply string.
#
#5.1 Command responses
#
#   Numerics in the range from 001 to 099 are used for client-server
#   connections only and should never travel between servers.  Replies
#   generated in the response to commands are found in the range from 200
#   to 399.

RPL_WELCOME => {
    number => '001',
    format => "Welcome to the Internet Relay Network, %(nick)s!%(user)s\@%(host)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WELCOME},
},

RPL_YOURHOST => {
    number => '002',
    format => "Your host is %(servername)s, running version %(version)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WELCOME},
},

RPL_CREATED => {
    number => '003',
    format => "This server was created %(date)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WELCOME},
},

RPL_MYINFO => {
    number => '004',
    format => "%(servername)s %(version)s %(available_user_modes)s, %(available_channel_modes)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WELCOME},
},

RPL_BOUNCE => {
    number => '005',
    format => "Try server %(servername)s, port %(port)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_BOUNCE},
},

RPL_USERHOST => {
    number => '302',
    format => ":%(reply)s%{ %(reply)s}*",
    trim_or_fileout => 0,
    information => $INFO{RPL_USERHOST},
},

RPL_ISON => {
    number => '303',
    format => ":%(nick)s%{ %(nick)s}*",
    trim_or_fileout => 0,
    information => $INFO{RPL_ISON},
},

RPL_AWAY => {
    number => '301',
    format => "%(nick)s :%(away_message)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_AWAY},
},

RPL_UNAWAY => {
    number => '305',
    format => ":You are no longer marked as being away",
    trim_or_fileout => 1,
    information => $INFO{RPL_AWAY},
},

RPL_NOWAWAY => {
    number => '306',
    format => ":You have been marked as being away",
    trim_or_fileout => 1,
    information => $INFO{RPL_AWAY},
},

RPL_WHOISUSER => {
    number => '311',
    format => "%(nick)s %(user)s %(host)s * :%(realname)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOISUSER},
},

RPL_WHOISSERVER => {
    number => '312',
    format => "%(nick)s %(server)s :%(server_info)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOISUSER},
},

RPL_WHOISOPERATOR => {
    number => '313',
    format => "%(nick)s :is an IRC operator",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOISUSER},
},

RPL_WHOISIDLE => {
    number => '317',
    format => "%(nick)s %(idle)s :seconds idle",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOISUSER},
},

RPL_ENDOFWHOIS => {
    number => '318',
    format => "%(nick)s :End of WHOIS list",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOISUSER},
},

RPL_WHOISCHANNELS => {
    number => '319',
    format => "%(nick)s :%(user_state)s%(channel)s%{ %(user_state)s%(channel)s}*",
    trim_or_fileout => 0,
    information => $INFO{RPL_WHOISUSER},
},

RPL_WHOWASUSER => {
    number => '314',
    format => "%(nick)s %(user)s %(host)s * :%(realname)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOWASUSER},
},

RPL_ENDOFWHOWAS => {
    number => '369',
    format => "%(nick)s :End of WHOWAS",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOWASUSER},
},

RPL_LISTSTART => {
    number => '321',
    format => "%(nick)s Channel :Users Name",
    trim_or_fileout => 1,
    information => $INFO{RPL_LISTSTART},
},

RPL_LIST => {
    number => '322',
    format => "%(channel)s %(visible)s :%(topic)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_LIST},
},

RPL_LISTEND => {
    number => '323',
    format => ":End of LIST",
    trim_or_fileout => 1,
    information => $INFO{RPL_LIST},
},

RPL_UNIQOPIS => {
    number => '325',
    format => "%(channel)s %(nick)s",
    trim_or_fileout => 1,
    information => "",
},

RPL_CHANNELMODEIS => {
    number => '324',
    format => "%(channel)s %(mode)s %(mode_params)s",
    trim_or_fileout => 1,
    information => "",
},

RPL_NOTOPIC => {
    number => '331',
    format => "%(channel)s :No topic is set.",
    trim_or_fileout => 1,
    information => $INFO{RPL_TOPIC},
},

RPL_TOPIC => {
    number => '332',
    format => "%(channel)s :%(topic)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TOPIC},
},

RPL_INVITING => {
    number => '341',
    format => "%(channel)s %(nick)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_INVITING},
},

RPL_SUMMONING => {
    number => '342',
    format => "%(user)s :Summoning user to IRC",
    trim_or_fileout => 1,
    information => $INFO{RPL_SUMMONING},
},

RPL_INVITELIST => {
    number => '346',
    format => "%(channel)s %(invitemask)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_INVITELIST},
},

RPL_ENDOFINVITELIST => {
    number => '347',
    format => "%(channel)s :End of channel invite list",
    trim_or_fileout => 1,
    information => $INFO{RPL_INVITELIST},
},

RPL_EXCEPTLIST => {
    number => '348',
    format => "%(channel)s %(exceptionmask)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_EXCEPTLIST},
},

RPL_ENDOFEXCEPTLIST => {
    number => '349',
    format => "%(channel)s :End of channel exception list",
    trim_or_fileout => 1,
    information => $INFO{RPL_EXCEPTLIST},
},

RPL_VERSION => {
    number => '351',
    format => "%(version)s.%(debug_level)s %(server)s :%(comments)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_VERSION},
},

RPL_WHOREPLY => {
    number => '352',
    format => "%(channel)s %(user)s %(host)s %(server)s %(nick)s %(user_state)s :%(hopcount)d %(realname)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOREPLY},
},

RPL_ENDOFWHO => {
    number => '315',
    format => "%(name)s :End of WHO list",
    trim_or_fileout => 1,
    information => $INFO{RPL_WHOREPLY},
},

RPL_NAMREPLY => {
    number => '353',
    format => "%(channel_mode)s %(channel)s :%(user_state)s%(nick)s%{ %(user_state)s%(nick)s}*",
    trim_or_fileout => 0,
    information => $INFO{RPL_NAMREPLY},
},

RPL_ENDOFNAMES => {
    number => '366',
    format => "%(channel)s :End of NAMES list",
    trim_or_fileout => 1,
    information => $INFO{RPL_ENDOFNAMES},
},

RPL_LINKS => {
    number => '364',
    format => "%(mask)s %(server)s :%(hopcount)s %(server_info)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_LINKS},
},

RPL_ENDOFLINKS => {
    number => '365',
    format => "%(mask)s :End of LINKS list",
    trim_or_fileout => 1,
    information => $INFO{RPL_LINKS},
},

RPL_BANLIST => {
    number => '367',
    format => "%(channel)s %(banmask)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_BANLIST},
},

RPL_ENDOFBANLIST => {
    number => '368',
    format => "%(channel)s :End of channel ban list",
    trim_or_fileout => 1,
    information => $INFO{RPL_BANLIST},
},

RPL_INFO => {
    number => '371',
    format => ":%(string)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_INFO},
},

RPL_ENDOFINFO => {
    number => '374',
    format => ":End of INFO list",
    trim_or_fileout => 1,
    information => $INFO{RPL_INFO},
},

RPL_MOTDSTART => {
    number => '375',
    format => ":- %(server)s Message of the day -",
    trim_or_fileout => 1,
    information => $INFO{RPL_MOTD},
},

RPL_MOTD => {
    number => '372',
    format => ":- %(text)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_MOTD},
},

RPL_ENDOFMOTD => {
    number => '376',
    format => ":End of MOTD command",
    trim_or_fileout => 1,
    information => $INFO{RPL_MOTD},
},

RPL_YOUREOPER => {
    number => '381',
    format => ":You are now an IRC operator",
    trim_or_fileout => 1,
    information => $INFO{RPL_YOUREOPER},
},

RPL_REHASHING => {
    number => '382',
    format => "%(config_file)s Rehashing",
    trim_or_fileout => 1,
    information => $INFO{RPL_REHASHING},
},

RPL_YOURESERVICE => {
    number => '383',
    format => "You are service %(servicename)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_YOURESERVICE},
},

RPL_TIME => {
    number => '391',
    format => "%(server)s :%(local_time)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TIME},
},

RPL_USERSSTART => {
    number => '392',
    format => ":UserID   Terminal  Host",
    trim_or_fileout => 1,
    information => $INFO{RPL_USERS},
},

RPL_USERS => {
    number => '393',
    format => ":%(username)s %(ttyline)s %(hostname)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_USERS},
},

RPL_ENDOFUSERS => {
    number => '394',
    format => ":End of users",
    trim_or_fileout => 1,
    information => $INFO{RPL_USERS},
},

RPL_NOUSERS => {
    number => '395',
    format => ":Nobody logged in",
    trim_or_fileout => 1,
    information => $INFO{RPL_USERS},
},

RPL_TRACELINK => {
    number => '200',
    format => "Link %(version_and_debug_level)s %(destination)s, %(next_server)s V%(protocol_version)s %(link_uptime_in_seconds)s %(backstream_sendq)s %(upstream_sendq)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACECONNECTING => {
    number => '201',
    format => "Try. %(class)s %(server)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACEHANDSHAKE => {
    number => '202',
    format => "H.S. %(class)s %(server)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACEUNKNOWN => {
    number => '203',
    format => "???? %(class)s [%(client_ip_address)s]",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACEOPERATOR => {
    number => '204',
    format => "Oper %(class)s %(nick)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACEUSER => {
    number => '205',
    format => "User %(class)s %(nick)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACESERVER => {
    number => '206',
    format => "Serv %(class)s %(int)sS %(int)sC %(server)s, %(nick)s!%(user)s\@%(host)s V%(protocol_version)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACESERVICE => {
    number => '207',
    format => "Service %(class)s %(name)s %(type)s %(active_type)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACENEWTYPE => {
    number => '208',
    format => "%(newtype)s 0 %(client_name)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACECLASS => {
    number => '209',
    format => "Class %(class)s %(count)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACERECONNECT => {
    number => '210',
    format => "",
    trim_or_fileout => 1,
    information => "Unused.",
},

RPL_TRACELOG => {
    number => '261',
    format => "File %(logfile)s %(debug_level)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_TRACEEND => {
    number => '262',
    format => "%(servername)s %(version)s.%(debug_level)s :End of TRACE",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRACELINK},
},

RPL_STATSLINKINFO => {
    number => '211',
    format => "%(linkname)s %(sendq)s %(sent_messages)s, %(sent_Kbytes)s %(received_messages)s %(received_Kbytes)s %(time_open)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_STATSLINKINFO},
},

RPL_STATSCOMMANDS => {
    number => '212',
    format => "%(command)s %(count)s %(byte_count)s %(remote_count)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_STATSCOMMANDS},
},

RPL_ENDOFSTATS => {
    number => '219',
    format => "%(stats_letter)s :End of STATS report",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSUPTIME => {
    number => '242',
    format => ":Server Up %(day)d days %(hour)d:%(min)02d:%(sec)02d",
    trim_or_fileout => 1,
    information => $INFO{RPL_STATSUPTIME},
},

RPL_STATSOLINE => {
    number => '243',
    format => "O %(hostmask)s * %(name)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_STATSOLINE},
},

RPL_UMODEIS => {
    number => '221',
    format => "%(user_mode_string)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_UMODEIS},
},

RPL_SERVLIST => {
    number => '234',
    format => "%(name)s %(server)s %(mask)s %(type)s %(hopcount)s %(info)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_SERVLIST},
},

RPL_SERVLISTEND => {
    number => '235',
    format => "%(mask)s %(type)s :End of service listing",
    trim_or_fileout => 1,
    information => $INFO{RPL_SERVLIST},
},

RPL_LUSERCLIENT => {
    number => '251',
    format => ":There are %(user_count)d users and %(service_count)d, services on %(server_count)d servers",
    trim_or_fileout => 1,
    information => $INFO{RPL_LUSERCLIENT},
},

RPL_LUSEROP => {
    number => '252',
    format => "%(operator_count)d :operator(s) online",
    trim_or_fileout => 1,
    information => $INFO{RPL_LUSERCLIENT},
},

RPL_LUSERUNKNOWN => {
    number => '253',
    format => "%(unknown_count)d :unknown connection(s)",
    trim_or_fileout => 1,
    information => $INFO{RPL_LUSERCLIENT},
},

RPL_LUSERCHANNELS => {
    number => '254',
    format => "%(channel_count)d :channels formed",
    trim_or_fileout => 1,
    information => $INFO{RPL_LUSERCLIENT},
},

RPL_LUSERME => {
    number => '255',
    format => ":I have %(client_count)d clients and %(server_count)d, servers",
    trim_or_fileout => 1,
    information => $INFO{RPL_LUSERCLIENT},
},

RPL_ADMINME => {
    number => '256',
    format => "%(server)s :Administrative info",
    trim_or_fileout => 1,
    information => $INFO{RPL_ADMINME},
},

RPL_ADMINLOC1 => {
    number => '257',
    format => ":%(admin_info)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_ADMINME},
},

RPL_ADMINLOC2 => {
    number => '258',
    format => ":%(admin_info)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_ADMINME},
},

RPL_ADMINEMAIL => {
    number => '259',
    format => ":%(admin_info)s",
    trim_or_fileout => 1,
    information => $INFO{RPL_ADMINME},
},

RPL_TRYAGAIN => {
    number => '263',
    format => "%(command)s :Please wait a while and try again.",
    trim_or_fileout => 1,
    information => $INFO{RPL_TRYAGAIN},
},

#5.2 Error Replies
#
#       Error replies are found in the range from 400 to 599.

ERR_NOSUCHNICK => {
    number => '401',
    format => "%(nick)s :No such nick/channel",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOSUCHNICK},
},

ERR_NOSUCHSERVER => {
    number => '402',
    format => "%(server)s :No such server",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOSUCHSERVER},
},

ERR_NOSUCHCHANNEL => {
    number => '403',
    format => "%(channel)s :No such channel",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOSUCHCHANNEL},
},

ERR_CANNOTSENDTOCHAN => {
    number => '404',
    format => "%(channel)s :Cannot send to channel",
    trim_or_fileout => 1,
    information => $INFO{ERR_CANNOTSENDTOCHAN},
},

ERR_TOOMANYCHANNELS => {
    number => '405',
    format => "%(channel)s :You have joined too many channels",
    trim_or_fileout => 1,
    information => $INFO{ERR_TOOMANYCHANNELS},
},

ERR_WASNOSUCHNICK => {
    number => '406',
    format => "%(nick)s :There was no such nickname",
    trim_or_fileout => 1,
    information => $INFO{ERR_WASNOSUCHNICK},
},

ERR_TOOMANYTARGETS => {
    number => '407',
    format => "%(target)s :%(error_code)s recipients. %(abort_message)s",
    trim_or_fileout => 1,
    information => $INFO{ERR_TOOMANYTARGETS},
},

ERR_NOSUCHSERVICE => {
    number => '408',
    format => "%(service)s :No such service",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOSUCHSERVICE},
},

ERR_NOORIGIN => {
    number => '409',
    format => ":No origin specified",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOORIGIN},
},

ERR_NORECIPIENT => {
    number => '411',
    format => ":No recipient given (%(command)s)",
    trim_or_fileout => 1,
    information => $INFO{ERR_NORECIPIENT},
},

ERR_NOTEXTTOSEND => {
    number => '412',
    format => ":No text to send",
    trim_or_fileout => 1,
    information => $INFO{ERR_NORECIPIENT},
},

ERR_NOTOPLEVEL => {
    number => '413',
    format => "%(mask)s :No toplevel domain specified",
    trim_or_fileout => 1,
    information => $INFO{ERR_NORECIPIENT},
},

ERR_WILDTOPLEVEL => {
    number => '414',
    format => "%(mask)s :Wildcard in toplevel domain",
    trim_or_fileout => 1,
    information => $INFO{ERR_NORECIPIENT},
},

ERR_BADMASK => {
    number => '415',
    format => "%(mask)s :Bad Server/host mask",
    trim_or_fileout => 1,
    information => $INFO{ERR_NORECIPIENT},
},

ERR_UNKNOWNCOMMAND => {
    number => '421',
    format => "%(command)s :Unknown command",
    trim_or_fileout => 1,
    information => $INFO{ERR_UNKNOWNCOMMAND},
},

ERR_NOMOTD => {
    number => '422',
    format => ":MOTD File is missing",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOMOTD},
},

ERR_NOADMININFO => {
    number => '423',
    format => "%(server)s :No administrative info available",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOADMININFO},
},

ERR_FILEERROR => {
    number => '424',
    format => ":File error doing %(file_op)s on %(file)s",
    trim_or_fileout => 1,
    information => $INFO{ERR_FILEERROR},
},

ERR_NONICKNAMEGIVEN => {
    number => '431',
    format => ":No nickname given",
    trim_or_fileout => 1,
    information => $INFO{ERR_NONICKNAMEGIVEN},
},

ERR_ERRONEUSNICKNAME => {
    number => '432',
    format => "%(nick)s :Erroneous nickname",
    trim_or_fileout => 1,
    information => $INFO{ERR_ERRONEUSNICKNAME},
},

ERR_NICKNAMEINUSE => {
    number => '433',
    format => "%(nick)s :Nickname is already in use",
    trim_or_fileout => 1,
    information => $INFO{ERR_NICKNAMEINUSE},
},

ERR_NICKCOLLISION => {
    number => '436',
    format => "%(nick)s :Nickname collision KILL from %(user)s\@%(host)s",
    trim_or_fileout => 1,
    information => $INFO{ERR_NICKCOLLISION},
},

ERR_UNAVAILRESOURCE => {
    number => '437',
    format => "%(target)s :Nick/channel is temporarily unavailable",
    trim_or_fileout => 1,
    information => $INFO{ERR_UNAVAILRESOURCE},
},

ERR_USERNOTINCHANNEL => {
    number => '441',
    format => "%(nick)s %(channel)s :They aren't on that channel",
    trim_or_fileout => 1,
    information => $INFO{ERR_USERNOTINCHANNEL},
},

ERR_NOTONCHANNEL => {
    number => '442',
    format => "%(channel)s :You're not on that channel",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOTONCHANNEL},
},

ERR_USERONCHANNEL => {
    number => '443',
    format => "%(nick)s %(channel)s :is already on channel",
    trim_or_fileout => 1,
    information => $INFO{ERR_USERONCHANNEL},
},

ERR_NOLOGIN => {
    number => '444',
    format => "%(nick)s :User not logged in",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOLOGIN},
},

ERR_SUMMONDISABLED => {
    number => '445',
    format => ":SUMMON has been disabled",
    trim_or_fileout => 1,
    information => $INFO{ERR_SUMMONDISABLED},
},

ERR_USERSDISABLED => {
    number => '446',
    format => ":USERS has been disabled",
    trim_or_fileout => 1,
    information => $INFO{ERR_USERSDISABLED},
},

ERR_NOTREGISTERED => {
    number => '451',
    format => ":You have not registered",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOTREGISTERED},
},

ERR_NEEDMOREPARAMS => {
    number => '461',
    format => "%(command)s :Not enough parameters",
    trim_or_fileout => 1,
    information => $INFO{ERR_NEEDMOREPARAMS},
},

ERR_ALREADYREGISTRED => {
    number => '462',
    format => ":Unauthorized command (already registered)",
    trim_or_fileout => 1,
    information => $INFO{ERR_ALREADYREGISTRED},
},

ERR_NOPERMFORHOST => {
    number => '463',
    format => ":Your host isn't among the privileged",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOPERMFORHOST},
},

ERR_PASSWDMISMATCH => {
    number => '464',
    format => ":Password incorrect",
    trim_or_fileout => 1,
    information => $INFO{ERR_PASSWDMISMATCH},
},

ERR_YOUREBANNEDCREEP => {
    number => '465',
    format => ":You are banned from this server",
    trim_or_fileout => 1,
    information => $INFO{ERR_YOUREBANNEDCREEP},
},

ERR_YOUWILLBEBANNED => {
    number => '466',
    format => ":",
    trim_or_fileout => 1,
    information => $INFO{ERR_YOUWILLBEBANNED},
},

ERR_KEYSET => {
    number => '467',
    format => "%(channel)s :Channel key already set",
    trim_or_fileout => 1,
    information => "",
},

ERR_CHANNELISFULL => {
    number => '471',
    format => "%(channel)s :Cannot join channel (+l)",
    trim_or_fileout => 1,
    information => "",
},

ERR_UNKNOWNMODE => {
    number => '472',
    format => "%(char)s :is unknown mode char to me for %(channel)s",
    trim_or_fileout => 1,
    information => "",
},

ERR_INVITEONLYCHAN => {
    number => '473',
    format => "%(channel)s :Cannot join channel (+i)",
    trim_or_fileout => 1,
    information => "",
},

ERR_BANNEDFROMCHAN => {
    number => '474',
    format => "%(channel)s :Cannot join channel (+b)",
    trim_or_fileout => 1,
    information => "",
},

ERR_BADCHANNELKEY => {
    number => '475',
    format => "%(channel)s :Cannot join channel (+k)",
    trim_or_fileout => 1,
    information => "",
},

ERR_BADCHANMASK => {
    number => '476',
    format => "%(channel)s :Bad Channel Mask",
    trim_or_fileout => 1,
    information => "",
},

ERR_NOCHANMODES => {
    number => '477',
    format => "%(channel)s :Channel doesn't support modes",
    trim_or_fileout => 1,
    information => "",
},

ERR_BANLISTFULL => {
    number => '478',
    format => "%(channel)s %(char)s :Channel list is full",
    trim_or_fileout => 1,
    information => "",
},

ERR_NOPRIVILEGES => {
    number => '481',
    format => ":Permission Denied- You're not an IRC operator",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOPRIVILEGES},
},

ERR_CHANOPRIVSNEEDED => {
    number => '482',
    format => "%(channel)s :You're not channel operator",
    trim_or_fileout => 1,
    information => $INFO{ERR_CHANOPRIVSNEEDED},
},

ERR_CANTKILLSERVER => {
    number => '483',
    format => ":You can't kill a server!",
    trim_or_fileout => 1,
    information => $INFO{ERR_CANTKILLSERVER},
},

ERR_RESTRICTED => {
    number => '484',
    format => ":Your connection is restricted!",
    trim_or_fileout => 1,
    information => $INFO{ERR_RESTRICTED},
},

ERR_UNIQOPPRIVSNEEDED => {
    number => '485',
    format => ":You're not the original channel operator",
    trim_or_fileout => 1,
    information => $INFO{ERR_UNIQOPPRIVSNEEDED},
},

ERR_NOOPERHOST => {
    number => '491',
    format => ":No O-lines for your host",
    trim_or_fileout => 1,
    information => $INFO{ERR_NOOPERHOST},
},

ERR_UMODEUNKNOWNFLAG => {
    number => '501',
    format => ":Unknown MODE flag",
    trim_or_fileout => 1,
    information => $INFO{ERR_UMODEUNKNOWNFLAG},
},

ERR_USERSDONTMATCH => {
    number => '502',
    format => ":Cannot change mode for other users",
    trim_or_fileout => 1,
    information => $INFO{ERR_USERSDONTMATCH},
},

#5.3 Reserved numerics
#
#   These numerics are not described above since they fall into one of
#   the following categories:
#
#   1. no longer in use;
#
#   2. reserved for future planned use;
#
#   3. in current use but are part of a non-generic 'feature' of
#      the current IRC server.

RPL_SERVICEINFO => {
    number => '231',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_ENDOFSERVICES => {
    number => '232',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_SERVICE => {
    number => '233',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_NONE => {
    number => '300',
    format => "",
    trim_or_fileout => 1,
    information => "",
},
RPL_WHOISCHANOP => {
    number => '316',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_KILLDONE => {
    number => '361',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_CLOSING => {
    number => '362',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_CLOSEEND => {
    number => '363',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_INFOSTART => {
    number => '373',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_MYPORTIS => {
    number => '384',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSCLINE => {
    number => '213',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSNLINE => {
    number => '214',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSILINE => {
    number => '215',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSKLINE => {
    number => '216',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSQLINE => {
    number => '217',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSYLINE => {
    number => '218',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSVLINE => {
    number => '240',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSLLINE => {
    number => '241',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSHLINE => {
    number => '244',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSSLINE => {
    number => '244',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSPING => {
    number => '246',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSBLINE => {
    number => '247',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

RPL_STATSDLINE => {
    number => '250',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

ERR_NOSERVICEHOST => {
    number => '492',
    format => "",
    trim_or_fileout => 1,
    information => "",
},

} }

1;

__DATA__
---
RPL_WELCOME: |+
  The server sends Replies 001 to 004 to a user upon
  successful registration.
RPL_BOUNCE: |+
  Sent by the server to a user to suggest an alternative
  server.  This is often used when the connection is
  refused because the server is already full.
RPL_USERHOST: |+
  Reply format used by USERHOST to list replies to
  the query list.  The reply string is composed as
  follows:

  reply = nickname [ "*" ] "=" ( "+" / "-" ) hostname

  The '*' indicates whether the client has registered
  as an Operator.  The '-' or '+' characters represent
  whether the client has set an AWAY message or not
  respectively.
RPL_ISON: |+
  Reply format used by ISON to list replies to the
  query list.
RPL_AWAY: |+
  These replies are used with the AWAY command (if
  allowed).  RPL_AWAY is sent to any client sending a
  PRIVMSG to a client which is away.  RPL_AWAY is only
  sent by the server to which the client is connected.
  Replies RPL_UNAWAY and RPL_NOWAWAY are sent when the
  client removes and sets an AWAY message.
RPL_WHOISUSER: |+
  Replies 311 - 313, 317 - 319 are all replies
  generated in response to a WHOIS message.  Given that
  there are enough parameters present, the answering
  server MUST either formulate a reply out of the above
  numerics (if the query nick is found) or return an
  error reply.  The '*' in RPL_WHOISUSER is there as
  the literal character and not as a wild card.  For
  each reply set, only RPL_WHOISCHANNELS may appear
  more than once (for long lists of channel names).
  The '@' and '+' characters next to the channel name
  indicate whether a client is a channel operator or
  has been granted permission to speak on a moderated
  channel.  The RPL_ENDOFWHOIS reply is used to mark
  the end of processing a WHOIS message.
RPL_WHOWASUSER: |+
  When replying to a WHOWAS message, a server MUST use
  the replies RPL_WHOWASUSER, RPL_WHOISSERVER or
  ERR_WASNOSUCHNICK for each nickname in the presented
  list.  At the end of all reply batches, there MUST
  be RPL_ENDOFWHOWAS (even if there was only one reply
  and it was an error).
RPL_LISTSTART: |+
  Obsolete. Not used.
RPL_LIST: |+
  Replies RPL_LIST, RPL_LISTEND mark the actual replies
  with data and end of the server's response to a LIST
  command.  If there are no channels available to return,
  only the end reply MUST be sent.
RPL_TOPIC: |+
  When sending a TOPIC message to determine the
  channel topic, one of two replies is sent.  If
  the topic is set, RPL_TOPIC is sent back else
  RPL_NOTOPIC.
RPL_INVITING: |+
  Returned by the server to indicate that the
  attempted INVITE message was successful and is
  being passed onto the end client.
RPL_SUMMONING: |+
  Returned by a server answering a SUMMON message to
  indicate that it is summoning that user.
RPL_INVITELIST: |+
  When listing the 'invitations masks' for a given channel,
  a server is required to send the list back using the
  RPL_INVITELIST and RPL_ENDOFINVITELIST messages.  A
  separate RPL_INVITELIST is sent for each active mask.
  After the masks have been listed (or if none present) a
  RPL_ENDOFINVITELIST MUST be sent.
RPL_EXCEPTLIST: |+
  When listing the 'exception masks' for a given channel,
  a server is required to send the list back using the
  RPL_EXCEPTLIST and RPL_ENDOFEXCEPTLIST messages.  A
  separate RPL_EXCEPTLIST is sent for each active mask.
  After the masks have been listed (or if none present)
  a RPL_ENDOFEXCEPTLIST MUST be sent.
RPL_VERSION: |+
  Reply by the server showing its version details.
  The <version> is the version of the software being
  used (including any patchlevel revisions) and the
  <debuglevel> is used to indicate if the server is
  running in "debug mode".

  The "comments" field may contain any comments about
  the version or further version details.
RPL_WHOREPLY: |+
  The RPL_WHOREPLY and RPL_ENDOFWHO pair are used
  to answer a WHO message.  The RPL_WHOREPLY is only
  sent if there is an appropriate match to the WHO
  query.  If there is a list of parameters supplied
  with a WHO message, a RPL_ENDOFWHO MUST be sent
  after processing each list item with <name> being
  the item.
RPL_NAMREPLY: |+
  "@" is used for secret channels, "*" for private
  channels, and "=" for others (public channels).
RPL_ENDOFNAMES: |+
  To reply to a NAMES message, a reply pair consisting
  of RPL_NAMREPLY and RPL_ENDOFNAMES is sent by the
  server back to the client.  If there is no channel
  found as in the query, then only RPL_ENDOFNAMES is
  returned.  The exception to this is when a NAMES
  message is sent with no parameters and all visible
  channels and contents are sent back in a series of
  RPL_NAMEREPLY messages with a RPL_ENDOFNAMES to mark
  the end.
RPL_LINKS: |+
  In replying to the LINKS message, a server MUST send
  replies back using the RPL_LINKS numeric and mark the
  end of the list using an RPL_ENDOFLINKS reply.
RPL_BANLIST: |+
  When listing the active 'bans' for a given channel,
  a server is required to send the list back using the
  RPL_BANLIST and RPL_ENDOFBANLIST messages.  A separate
  RPL_BANLIST is sent for each active banmask.  After the
  banmasks have been listed (or if none present) a
  RPL_ENDOFBANLIST MUST be sent.
RPL_INFO: |+
  A server responding to an INFO message is required to
  send all its 'info' in a series of RPL_INFO messages
  with a RPL_ENDOFINFO reply to indicate the end of the
  replies.
RPL_MOTD: |+
  When responding to the MOTD message and the MOTD file
  is found, the file is displayed line by line, with
  each line no longer than 80 characters, using
  RPL_MOTD format replies.  These MUST be surrounded
  by a RPL_MOTDSTART (before the RPL_MOTDs) and an
  RPL_ENDOFMOTD (after).
RPL_YOUREOPER: |+
  RPL_YOUREOPER is sent back to a client which has
  just successfully issued an OPER message and gained
  operator status.
RPL_REHASHING: |+
  If the REHASH option is used and an operator sends
  a REHASH message, an RPL_REHASHING is sent back to
  the operator.
RPL_YOURESERVICE: |+
  Sent by the server to a service upon successful
  registration.
RPL_TIME: |+
  When replying to the TIME message, a server MUST send
  the reply using the RPL_TIME format above.  The string
  showing the time need only contain the correct day and
  time there.  There is no further requirement for the
  time string.
RPL_USERS: |+
  If the USERS message is handled by a server, the
  replies RPL_USERSTART, RPL_USERS, RPL_ENDOFUSERS and
  RPL_NOUSERS are used.  RPL_USERSSTART MUST be sent
  first, following by either a sequence of RPL_USERS
  or a single RPL_NOUSER.  Following this is
  RPL_ENDOFUSERS.
RPL_TRACELINK: |+
  The RPL_TRACE* are all returned by the server in
  response to the TRACE message.  How many are
  returned is dependent on the TRACE message and
  whether it was sent by an operator or not.  There
  is no predefined order for which occurs first.
  Replies RPL_TRACEUNKNOWN, RPL_TRACECONNECTING and
  RPL_TRACEHANDSHAKE are all used for connections
  which have not been fully established and are either
  unknown, still attempting to connect or in the
  process of completing the 'server handshake'.
  RPL_TRACELINK is sent by any server which handles
  a TRACE message and has to pass it on to another
  server.  The list of RPL_TRACELINKs sent in
  response to a TRACE command traversing the IRC
  network should reflect the actual connectivity of
  the servers themselves along that path.
  RPL_TRACENEWTYPE is to be used for any connection
  which does not fit in the other categories but is
  being displayed anyway.
  RPL_TRACEEND is sent to indicate the end of the list.
RPL_STATSLINKINFO: |+
  reports statistics on a connection.  <linkname>
  identifies the particular connection, <sendq> is
  the amount of data that is queued and waiting to be
  sent <sent messages> the number of messages sent,
  and <sent Kbytes> the amount of data sent, in
  Kbytes. <received messages> and <received Kbytes>
  are the equivalent of <sent messages> and <sent
  Kbytes> for received data, respectively.  <time
  open> indicates how long ago the connection was
  opened, in seconds.
RPL_STATSCOMMANDS: |+
  reports statistics on commands usage.
RPL_STATSUPTIME: |+
  reports the server uptime.
RPL_STATSOLINE: |+
  reports the allowed hosts from where user may become IRC
  operators.
RPL_UMODEIS: |+
  To answer a query about a client's own mode,
  RPL_UMODEIS is sent back.
RPL_SERVLIST: |+
  When listing services in reply to a SERVLIST message,
  a server is required to send the list back using the
  RPL_SERVLIST and RPL_SERVLISTEND messages.  A separate
  RPL_SERVLIST is sent for each service.  After the
  services have been listed (or if none present) a
  RPL_SERVLISTEND MUST be sent.
RPL_LUSERCLIENT: |+
  In processing an LUSERS message, the server
  sends a set of replies from RPL_LUSERCLIENT,
  RPL_LUSEROP, RPL_USERUNKNOWN,
  RPL_LUSERCHANNELS and RPL_LUSERME.  When
  replying, a server MUST send back
  RPL_LUSERCLIENT and RPL_LUSERME.  The other
  replies are only sent back if a non-zero count
  is found for them.
RPL_ADMINME: |+
  When replying to an ADMIN message, a server
  is expected to use replies RPL_ADMINME
  through to RPL_ADMINEMAIL and provide a text
  message with each.  For RPL_ADMINLOC1 a
  description of what city, state and country
  the server is in is expected, followed by
  details of the institution (RPL_ADMINLOC2)
  and finally the administrative contact for the
  server (an email address here is REQUIRED)
  in RPL_ADMINEMAIL.
RPL_TRYAGAIN: |+
  When a server drops a command without processing it,
  it MUST use the reply RPL_TRYAGAIN to inform the
  originating client.
ERR_NOSUCHNICK: |+
  Used to indicate the nickname parameter supplied to a
  command is currently unused.
ERR_NOSUCHSERVER: |+
  Used to indicate the server name given currently
  does not exist.
ERR_NOSUCHCHANNEL: |+
  Used to indicate the given channel name is invalid.
ERR_CANNOTSENDTOCHAN: |+
  Sent to a user who is either (a) not on a channel
  which is mode +n or (b) not a chanop (or mode +v) on
  a channel which has mode +m set or where the user is
  banned and is trying to send a PRIVMSG message to
  that channel.
ERR_TOOMANYCHANNELS: |+
  Sent to a user when they have joined the maximum
  number of allowed channels and they try to join
  another channel.
ERR_WASNOSUCHNICK: |+
  Returned by WHOWAS to indicate there is no history
  information for that nickname.
ERR_TOOMANYTARGETS: |+
  Returned to a client which is attempting to send a
  PRIVMSG/NOTICE using the user@host destination format
  and for a user@host which has several occurrences.

  Returned to a client which trying to send a
  PRIVMSG/NOTICE to too many recipients.

  Returned to a client which is attempting to JOIN a safe
  channel using the shortname when there are more than one
  such channel.
ERR_NOSUCHSERVICE: |+
  Returned to a client which is attempting to send a SQUERY
  to a service which does not exist.
ERR_NOORIGIN: |+
  PING or PONG message missing the originator parameter.
ERR_NORECIPIENT: |+
  412 - 415 are returned by PRIVMSG to indicate that
  the message wasn't delivered for some reason.
  ERR_NOTOPLEVEL and ERR_WILDTOPLEVEL are errors that
  are returned when an invalid use of
  "PRIVMSG $<server>" or "PRIVMSG #<host>" is attempted.
ERR_UNKNOWNCOMMAND: |+
  Returned to a registered client to indicate that the
  command sent is unknown by the server.
ERR_NOMOTD: |+
  Server's MOTD file could not be opened by the server.
ERR_NOADMININFO: |+
  Returned by a server in response to an ADMIN message
  when there is an error in finding the appropriate
  information.
ERR_FILEERROR: |+
  Generic error message used to report a failed file
  operation during the processing of a message.
ERR_NONICKNAMEGIVEN: |+
  Returned when a nickname parameter expected for a
  command and isn't found.
ERR_ERRONEUSNICKNAME: |+
  Returned after receiving a NICK message which contains
  characters which do not fall in the defined set.  See
  section 2.3.1 for details on valid nicknames.
ERR_NICKNAMEINUSE: |+
  Returned when a NICK message is processed that results
  in an attempt to change to a currently existing
  nickname.
ERR_NICKCOLLISION: |+
  Returned by a server to a client when it detects a
  nickname collision (registered of a NICK that
  already exists by another server).
ERR_UNAVAILRESOURCE: |+
  Returned by a server to a user trying to join a channel
  currently blocked by the channel delay mechanism.

  Returned by a server to a user trying to change nickname
  when the desired nickname is blocked by the nick delay
  mechanism.
ERR_USERNOTINCHANNEL: |+
  Returned by the server to indicate that the target
  user of the command is not on the given channel.
ERR_NOTONCHANNEL: |+
  Returned by the server whenever a client tries to
  perform a channel affecting command for which the
  client isn't a member.
ERR_USERONCHANNEL: |+
  Returned when a client tries to invite a user to a
  channel they are already on.
ERR_NOLOGIN: |+
  Returned by the summon after a SUMMON command for a
  user was unable to be performed since they were not
  logged in.
ERR_SUMMONDISABLED: |+
  Returned as a response to the SUMMON command.  MUST be
  returned by any server which doesn't implement it.
ERR_USERSDISABLED: |+
  Returned as a response to the USERS command.  MUST be
  returned by any server which does not implement it.
ERR_NOTREGISTERED: |+
  Returned by the server to indicate that the client
  MUST be registered before the server will allow it
  to be parsed in detail.
ERR_NEEDMOREPARAMS: |+
  Returned by the server by numerous commands to
  indicate to the client that it didn't supply enough
  parameters.
ERR_ALREADYREGISTRED: |+
  Returned by the server to any link which tries to
  change part of the registered details (such as
  password or user details from second USER message).
ERR_NOPERMFORHOST: |+
  Returned to a client which attempts to register with
  a server which does not been setup to allow
  connections from the host the attempted connection
  is tried.
ERR_PASSWDMISMATCH: |+
  Returned to indicate a failed attempt at registering
  a connection for which a password was required and
  was either not given or incorrect.
ERR_YOUREBANNEDCREEP: |+
  Returned after an attempt to connect and register
  yourself with a server which has been setup to
  explicitly deny connections to you.
ERR_YOUWILLBEBANNED: |+
  Sent by a server to a user to inform that access to the
  server will soon be denied.
ERR_NOPRIVILEGES: |+
  Any command requiring operator privileges to operate
  MUST return this error to indicate the attempt was
  unsuccessful.
ERR_CHANOPRIVSNEEDED: |+
  Any command requiring 'chanop' privileges (such as
  MODE messages) MUST return this error if the client
  making the attempt is not a chanop on the specified
  channel.
ERR_CANTKILLSERVER: |+
  Any attempts to use the KILL command on a server
  are to be refused and this error returned directly
  to the client.
ERR_RESTRICTED: |+
  Sent by the server to a user upon connection to indicate
  the restricted nature of the connection (user mode "+r").
ERR_UNIQOPPRIVSNEEDED: |+
  Any MODE requiring "channel creator" privileges MUST
  return this error if the client making the attempt is not
  a chanop on the specified channel.
ERR_NOOPERHOST: |+
  If a client sends an OPER message and the server has
  not been configured to allow connections from the
  client's host as an operator, this error MUST be
  returned.
ERR_UMODEUNKNOWNFLAG: |+
  Returned by the server to indicate that a MODE
  message was sent with a nickname parameter and that
  the a mode flag sent was not recognized.
ERR_USERSDONTMATCH: |+
  Error sent to any user trying to view or change the
  user mode for a user other than themselves.

__END__

=encoding utf8

=head1 NAME

Uc::IrcGateway::Message - Define RPL_* and ERR_* for reply messages


=head1 SYNOPSIS

    use Uc::IrcGateway::Message;


=head1 DESCRIPTION


=head1 INTERFACE


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

Copyright (c) 2011, U=Cormorant C<< <u@chimata.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
