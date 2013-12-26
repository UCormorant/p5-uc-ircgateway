package Uc::IrcGateway::Plugin::CustomRegisterUser;
use 5.014;
use parent 'Class::Component::Plugin';
use Uc::IrcGateway::Common;
use Carp qw(croak);

sub init {
    my ($plugin, $class) = @_;
    my $classname = ref $class;
    croak "$classname must have 'register_user' method. you need to define 'sub register_user' in package '$classname'"
        . <<'_CROAK_' unless $class->can('register_user');


exapmle:
    sub register_user {
        my $self = shift;
        my ($handle, $user) = @_;
        return 1 if $user->isa('Uc::IrcGateway::User');

        $self->run_hook('before_register_user' => \@_);
        $user->register($handle);
        $self->run_hook('after_register_user' => \@_);

        $self->log($handle, info => sprintf "handle{%s} is registered as '%s'",
            Scalar::Util::refaddr($handle),
            $handle->self->to_prefix,
        );

        $self->send_welcome($handle);
        return 1;
    }
_CROAK_
}

1;
