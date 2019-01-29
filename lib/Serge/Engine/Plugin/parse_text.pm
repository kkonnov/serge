package Serge::Engine::Plugin::parse_text;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Text parser plugin';
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    my $translated_text = $$textref;

    if ($translated_text ne '') {
        $translated_text = &$callbackref($translated_text, 'text', undef, undef, $lang, 'text');
    }

    return $translated_text;
}

1;