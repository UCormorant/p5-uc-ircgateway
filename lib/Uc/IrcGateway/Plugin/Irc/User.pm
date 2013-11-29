package Uc::IrcGateway::Plugin::Irc::User;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('USER') {
    my $self = shift;
    $self->run_hook('irc.user.begin' => \@_);

        action($self, @_);

    $self->run_hook('irc.user.end' => \@_);
}

sub action {
    my $self = shift;
    my ($handle, $msg, $plugin) = @_;
    return unless $self->check_params(@_);

    $self->run_hook('irc.user.start' => \@_);

    $msg->{response} = {};

    my ($login, $host, $server, $realname) = @{$msg->{params}};
    my $cmd  = $msg->{command};
    my $user = $handle->self;
    if ($user->isa('Uc::IrcGateway::User')) {
        $self->send_reply( $handle, $msg, 'ERR_ALREADYREGISTRED' );
        return;
    }

    $host ||= '0'; $server ||= '*'; $realname ||= '';
    $user->login($login);
    $user->realname($realname);
    $user->host($host);
    $user->addr($self->host);
    $user->server($server);

    if ($user->nick) {
        $self->run_hook('irc.user.before_register' => \@_);
        $user->register($handle);
        $msg->{registered} = 1;
        $self->run_hook('irc.user.after_register' => \@_);
        $self->send_welcome( $handle );
    }

    $self->run_hook('irc.user.finish' => \@_);
}

1;
