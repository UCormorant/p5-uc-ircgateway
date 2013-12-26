package Mock::Plugin::LogLevelAttribute;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub low_level :LogLevel('low') {
    my ($logger, $level, $message) = splice @_, 0, 3;
    my ($handle, $plugin) = splice @_, -2;
    my @args = @_;

    ($level, $message);
}

sub middle_level :LogLevel('middle') {
    my ($logger, $level, $message) = splice @_, 0, 3;
    my ($handle, $plugin) = splice @_, -2;
    my @args = @_;

    ($level, $message);
}

sub high_level :LogLevel('high') {
    my ($logger, $level, $message) = splice @_, 0, 3;
    my ($handle, $plugin) = splice @_, -2;
    my @args = @_;

    ($level, $message);
}

sub any_log :LogLevel('any') {
    my ($logger, $level, $message) = splice @_, 0, 3;
    my ($handle, $plugin) = splice @_, -2;
    my @args = @_;

    ($level, $message);
}

1;
