requires 'perl', '5.008005';

requires 'CPAN::DistnameInfo';
requires 'LWP::UserAgent';
requires 'JSON::MaybeXS', '1.004000';
requires 'Term::ANSIColor';
requires 'URI::Escape';
requires 'List::Util';

on test => sub {
    requires 'Test::More', '0.88';
};
