package Uc::IrcGateway::Attribute::CtcpEvent;
use 5.014;
use parent 'Class::Component::Attribute';

sub register {
    my($class, $plugin, $c, $method, $value, $code) = @_;
    my $command = uc $value;
    my $event_name = "ctcp_event_$command";
    my $event_code = sub { $code->(@_, $plugin); };
    my $ctcp_event = $c->event_ctcp_command;

    $ctcp_event->{$command}         = {};
    $ctcp_event->{$command}{code}   = $event_code;
    $ctcp_event->{$command}{name}   = $event_name;
    $ctcp_event->{$command}{plugin} = $plugin;
    $ctcp_event->{$command}{method} = $method;
    $ctcp_event->{$command}{guard}  = $c->reg_cb($event_name => $event_code) if $c->{_init_object_events};
}

1;
