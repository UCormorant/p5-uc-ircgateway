package Uc::IrcGateway::Plugin::Irc::Names;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('NAMES') {
    my ($self, $handle, $msg) = @_;
    my $chans = $msg->{params}[0] || join ',', sort $handle->channel_list;
    my $server = $msg->{params}[1];

    if ($server) {
        # サーバマスク指定は対応予定なし
        $self->send_msg( $handle, ERR_NOSUCHSERVER, $server, 'No such server' );
        return ();
    }

    for my $chan (split /,/, $chans) {
        next unless $self->check_channel( $handle, $chan, enable => 1 );

        my $c = $handle->get_channels($chan);
        my $c_mode = $c->mode->{s} ? '@' : $c->mode->{p} ? '*' : '=';
        my $m_chan = $c_mode.' '.$chan;

        my $users = '';
        my @users_list = ();
        my $users_test = mk_msg($self->to_prefix, RPL_NAMREPLY, $handle->self->nick, $m_chan, '');
        for my $nick (sort $c->nick_list) {
            next unless $handle->has_nick($nick);
            my $u_login = $handle->lookup($nick);
            my $u_mode = $c->is_operator($u_login) ? '@' : $c->is_speaker($u_login) ? '+' : '';
            my $m_nick = $u_mode.$nick;
            if (length "$users_test$users$m_nick$CRLF" > $MAXBYTE) {
                chop $users;
                push @users_list, $users;
                $users = '';
            }
            $users .= "$m_nick ";
        }
        push @users_list, $users if chop $users;

        $self->send_msg( $handle, RPL_NAMREPLY, $m_chan, $_ ) for @users_list;
        $self->send_msg( $handle, RPL_ENDOFNAMES, $chan, 'End of /NAMES list' );
    }

    @_;
}

1;
