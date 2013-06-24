package Uc::IrcGateway::Plugin::Irc::Privmsg;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('PRIVMSG') {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my $cmd    = $msg->{command};
    my $prefix = $msg->{prefix} || $handle->self->to_prefix;
    my ($msgtarget, $text) = @{$msg->{params}};
    my ($plain_text, $ctcp) = decode_ctcp($text);
    my $silent = $cmd eq 'NOTICE' ? 1 : 0;

    if (not defined $text) {
        $self->send_msg( $handle, ERR_NOTEXTTOSEND, 'No text to send' ) unless $silent;
        return ();
    }

    for my $target (split /,/, $msgtarget) {
        # TODO: error
        if (0) { # WILD CARD
            if (0) { # check wild card
                # ERR_NOTOPLEVEL <mask> :No toplevel domain specified
                # ERR_WILDTOPLEVEL <mask> <mask> :Wildcard in toplevel domain
                # ERR_TOOMANYTARGETS <target> :<error code> recipients. <abort message>
                # ERR_NORECIPIENT :No recipient given (<command>)
                next;
            }
        }
        elsif (is_valid_channel_name($target)) {
            if (0) { # check mode
                # ERR_CANNOTSENDTOCHAN <channel name> :Cannot send to channel
                next;
            }
        }
        elsif (not $self->check_user($handle, $target, silent => $silent)) {
            next;
        }
        else {
            my $user = $handle->get_users_by_nicks($target);
            $self->send_msg( $handle, RPL_AWAY, $target, $user->away_message ) if ref $user and $user->mode->{a};
        }

        # ctcp event
        if (scalar @$ctcp) {
            for my $event (@$ctcp) {
                my ($ctcp_text, $ctcp_args) = @{$event};
                $ctcp_text .= " $ctcp_args" if $ctcp_args;
                $self->handle_ctcp_msg( $handle, $ctcp_text,
                        prefix => $prefix, target => $target, orig_command => $cmd, silent => $silent );
            }
        }

        # push target for override method
        push @{$msg->{success}}, $target;
    }

    # push plain text and ctcp
    push @{$msg->{params}}, $plain_text, $ctcp;

    @_;
}

1;
