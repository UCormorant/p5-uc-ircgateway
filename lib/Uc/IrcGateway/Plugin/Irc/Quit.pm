package Uc::IrcGateway::Plugin::Irc::Quit;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 0;
}

sub event :IrcEvent('QUIT') {
    my $self = shift;
    $self->run_hook('irc.quit.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.quit.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.quit.start' => \@_);

    my $prefix = $msg->{prefix} || $handle->self->to_prefix;
    my $quit_msg = $msg->{params}[0];
    my ($nick, $login, $host) = split_prefix($prefix);

    # send error to accept quit # 本人には返さなくていい
    # $self->send_cmd( $handle, $prefix, 'ERROR', qq|Closing Link: $nick\[$login\@$host\] ("$quit_msg")| );

    $self->run_hook('irc.quit.before_shutdown' => \@_);

    $handle->push_shutdown; # close connection

    $self->run_hook('irc.quit.finish' => \@_);
}

1;
