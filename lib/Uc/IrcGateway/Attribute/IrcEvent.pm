package Uc::IrcGateway::Attribute::IrcEvent;
use 5.014;
use parent 'Class::Component::Attribute';

sub register {
    my($class, $plugin, $c, $method, $value, $code) = @_;
    my $command = uc $value;
    my $event_name = "irc_event_$command";
    my $event_code = sub { $code->(@_, $plugin); };
    my $irc_event = $c->event_irc_command;

    $irc_event->{$command}         = {};
    $irc_event->{$command}{code}   = $event_code;
    $irc_event->{$command}{name}   = $event_name;
    $irc_event->{$command}{plugin} = $plugin;
    $irc_event->{$command}{method} = $method;
    $irc_event->{$command}{guard}  = $c->reg_cb($event_name => $event_code) if $c->{_init_object_events};
}

1;
