package Uc::IrcGateway::Plugin::Irc::Notice;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;
use Uc::IrcGateway::Plugin::Irc::Privmsg;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
    $config->{require_params_count} //= 1;
}

sub event :IrcEvent('NOTICE') {
    my $self = shift;
    $self->run_hook('irc.notice.begin' => \@_);

        Uc::IrcGateway::Plugin::Irc::Privmsg::action($self, @_);

    $self->run_hook('irc.notice.end' => \@_);
}

1;
