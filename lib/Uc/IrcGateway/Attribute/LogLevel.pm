package Uc::IrcGateway::Attribute::LogLevel;
use 5.014;
use parent 'Class::Component::Attribute';
use Uc::IrcGateway::Logger;

sub register {
    my($class, $plugin, $c, $method, $level, $code) = @_;
    $c->logger->add_log_level($level, sub { $code->(@_, $plugin); });
}

1;
