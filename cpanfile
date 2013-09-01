requires 'perl', '5.014';
requires 'Class::Component', '0.17';
requires 'AnyEvent', '7.04';
requires 'AnyEvent::IRC', '0.6';
requires 'Path::Class', '0.29';
requires 'YAML';
requires 'JSON';
requires 'Teng', '0.20';
requires 'DBD::SQLite', '1.027';
requires 'Log::Dispatch', '2.36';
requires 'Class::Accessor::Lite';

requires 'Text::InflateSprintf', '0.04';
requires 'Teng::Plugin::DBIC::ResultSet', '0.03';

on build => sub {
    requires 'Test::Base::Less', '0.11';
    requires 'Test::Difflet';
    requires 'Test::More', '0.94';
    requires 'Test::TCP';
};
