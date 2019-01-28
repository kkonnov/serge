package Serge::Engine::Plugin::parse_text;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Text parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $source_text = $$textref;

    my $translated_str = &$callbackref($source_text, 'text', undef, undef, $lang, 'text');

    return $translated_str;
}

1;