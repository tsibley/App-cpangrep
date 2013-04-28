requires 'perl', '5.008005';

requires 'CPAN::DistnameInfo';
requires 'HTTP::Tiny';
requires 'JSON', '>=2.27';
requires 'Term::ANSIColor';
requires 'URI::Escape';

on test => sub {
    requires 'Test::More', '0.88';
};
