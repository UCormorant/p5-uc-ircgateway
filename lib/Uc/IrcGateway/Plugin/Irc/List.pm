package Uc::IrcGateway::Plugin::Irc::List;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('LIST') {
    my ($self, $handle, $msg) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    my $server = $msg->{params}[1];
    my $nick = $handle->self->nick;

    if ($server) {
        # サーバマスク指定は対応予定なし
        $self->send_msg( $handle, ERR_NOSUCHSERVER, $server, 'No such server' );
        return ();
    }

    # too old message spec
    #$self->send_msg( $handle, RPL_LISTSTART, $nick, 'Channel', 'Users Name' );
    for my $channel ($handle->get_channels(split /,/, $chans)) {
        next unless $channel;
        my $member_count = scalar $channel->login_list;
        $self->send_msg( $handle, RPL_LIST, $channel->name, $member_count, $channel->topic );
    }
    $self->send_msg( $handle, RPL_LISTEND, 'END of /List' );

    @_;
}

1;
