package Uc::IrcGateway::Plugin::Log::Notice4Handle;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;

sub init {
    my ($plugin, $class) = @_;
    my $config = $plugin->config;
}

sub logger :LogLevel('any') {
    my $logger = shift;
    my $level = shift;
    my $message = shift;
    my $plugin = pop;
    my $handle = pop;
    my @args = @_;

    if ($handle and $handle->ircd->check_connection($handle)) {
        my $self = $handle->ircd;
        my $msg = mk_msg($self->to_prefix, 'NOTICE', replace_crlf($message));
           $msg = $self->trim_message($msg);
        $handle->push_write($self->codec->encode($msg) . $CRLF);
    }

    ($level, $message);
}

1;
