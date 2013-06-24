package Uc::IrcGateway::Plugin::Irc::Mode;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub action :IrcEvent('MODE') {
    my ($self, $handle, $msg) = check_params(@_);
    return () unless $self && $handle;

    my $cmd = $msg->{command};
    my ($target, @mode_list) = @{$msg->{params}};
    my $mode_params = join '', @mode_list;
    my $user = $handle->self;

    if (is_valid_channel_name($target)) {
        return () unless $self->check_channel($handle, $target);

        my $chan = $handle->get_channels($target);
        # <channel>  *( ( "-" / "+" ) *<modes> *<modeparams> )

        my $oper = '';
        my $mode_string  = '';
        my $param_string = '';
        while (my $mode = shift @mode_list) {
            for my $m (split //, $mode) {
                if ($m eq '+' or $m eq '-') {
                    $oper = $m; next;
                }
                given ($m) {
    #     O - "チャンネルクリエータ"の権限を付与
    #     o - チャンネルオペレータの特権を付与/剥奪
                    when ('o') {
                        $oper ||= '+';

                        my $target_nick  = shift @mode_list;
                        my $target_login = $handle->lookup($target);

                        if (not $chan->has_user($target_login)) {
                            $self->send_msg( $handle, ERR_USERNOTINCHANNEL, $target, $chan->name, "They aren't on that channel" );
                        }
                        elsif ($chan->is_operator($user->login)) {
                            if ($chan->is_operator($target_login) and $oper eq '-') {
                                $chan->deprive_operator($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                            elsif (!$chan->is_operator($target_login)) {
                                $chan->give_operator($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                        }
                    }
    #     v - ボイス特権を付与/剥奪
                    when ('v') {
                        $oper ||= '+';

                        my $target_nick  = shift @mode_list;
                        my $target_login = $handle->lookup($target);

                        if (not $chan->has_user($target_login)) {
                            $self->send_msg( $handle, ERR_USERNOTINCHANNEL, $target, $chan->name, "They aren't on that channel" );
                        }
                        elsif ($chan->is_speaker($user->login)) {
                            if ($chan->is_speaker($target_login) and $oper eq '-') {
                                $chan->deprive_voice($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                            elsif (!$chan->is_speaker($target_login)) {
                                $chan->give_voice($target_login, $target_nick);
                                $mode_string  ||= $oper; $mode_string .= $m;
                                $param_string &&= $param_string.' '; $param_string .= $target_nick;
                            }
                        }
                    }
    #     a - 匿名チャンネルフラグをトグル
    #     i - 招待のみチャンネルフラグをトグル
    #     m - モデレートチャンネルをトグル
    #     n - チャンネル外クライアントからのメッセージ遮断をトグル
    #     q - クワイエットチャンネルフラグをトグル
    #     p - プライベートチャンネルフラグをトグル
    #     s - シークレットチャンネルフラグをトグル
    #     r - サーバreopチャンネルフラグをトグル
    #     t - トピック変更をチャンネルオペレータのみに限定するかをトグル
                    when ([qw/a i m n q p s r t/]) {
                        $oper ||= '+';
                        $chan->mode->{$m} = $oper eq '-' ? 0 : 1;
                        $mode_string  ||= $oper; $mode_string .= $m;
                    }
    #
    #     k - チャンネルキー(パスワード)の設定／解除
    #     l - チャンネルのユーザ数制限の設定／解除
    #
    #     b - ユーザをシャットアウトする禁止(ban)マスクの設定／解除
    #     e - 禁止マスクに優先する例外マスクの設定／解除
    #     I - 自動的に招待のみフラグに優先する招待マスクの設定／解除
                    default {
                        $self->send_msg( $handle, ERR_UNKNOWNCOMMAND, $m, "is unknown mode char to me for @{[$chan->name]}" );
                    }
                }
            }
        }

        $self->send_msg( $handle, RPL_CHANNELMODEIS, $chan->name, $mode_string, grep defined, ($param_string || undef) ) if $mode_string;
        push @{$msg->{success}}, $mode_string, $param_string if $mode_string;
    }
    else {
        return () unless $self->check_user($handle, $target);

        if ($target ne $user->nick) {
            $self->send_msg( $handle, ERR_USERSDONTMATCH, 'Cannot change mode for other users' );
            return ();
        }

        # <nickname> *( ( "+" / "-" ) *( "i" / "w" / "o" / "O" / "r" ) )

        if ($mode_params eq '') {
            $self->send_msg( $handle, RPL_UMODEIS, $user->mode_string );
        }
        else {
            my $mode = $user->mode;
            my $mode_flag = (join '', keys %{$mode}) || $NUL;
            my $mode_string = '';
            my $oper = '+';
            my $oper_last = '';
            for my $char (split //, $mode_params) {
                if ($char =~ /[+-]/) {
                    $oper = $char;
                }
                elsif ($char !~ /[$mode_flag]/) {
                    $self->send_msg( $handle, ERR_UMODEUNKNOWNFLAG, 'Unknown MODE flag' );
                }
                else {
                    $mode->{$char} = $oper eq '-' ? 0 : 1;
                    $mode_string .= $oper ne $oper_last ? $oper.$char : $char;
                    $oper_last = $oper;
                }
            }

            $self->send_cmd( $handle, $user, 'MODE', $user->nick, $mode_string ) if $mode_string;
            push @{$msg->{success}}, $mode_string;
        }
    }

    @_;
}

1;
