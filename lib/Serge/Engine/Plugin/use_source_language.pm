package Serge::Engine::Plugin::use_source_language;
use parent Serge::Plugin::Base::Callback;

# Use source strings for translations.

use strict;
use warnings;

use Serge::Util qw(is_flag_set set_flags);

sub name {
    return 'Use source strings for translations.';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        destination_languages         => 'ARRAY'
    });

    $self->add({
        get_translation_pre => \&get_translation,
        get_translation => \&get_translation,
        can_generate_ts_file => \&can_process_ts_file,
        can_process_ts_file => \&can_process_ts_file,
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    if (!exists $self->{data}->{destination_languages} or scalar(@{$self->{data}->{destination_languages}}) == 0) {
        die "the list of destination languages is empty";
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # always tie to 'can_process_ts_file' phase
    set_flags($phases, 'can_generate_ts_file', 'can_process_ts_file');

    # this plugin makes sense only when applied to either
    # get_translation_pre or get_translation phase, but not both
    my $f1 = is_flag_set($phases, 'get_translation_pre');
    my $f2 = is_flag_set($phases, 'get_translation');
    die "This plugin needs to be attached to either get_translation_pre or get_translation phase" if !$f1 && !$f2;
    die "This plugin needs to be attached to either get_translation_pre or get_translation phase, but not both" if $f1 && $f2;
}

sub is_valid_language {
    my ($self, $lang) = @_;

    my $langs = $self->{data}->{destination_languages};

    my $valid_lang = (grep { $_ eq $lang } @$langs);

    return $valid_lang;
}

sub get_translation {
    my ($self, $phase, $string, $context, $namespace, $filepath, $lang) = @_;

    return () unless $self->is_valid_language($lang);
    return ($string, undef, undef, 0);
}

sub can_process_ts_file {
    my ($self, $phase, $file, $lang) = @_;

    # do not import anything from translation file unless `save_translations' flag is on
    return 0 if $self->is_valid_language($lang);

    # by default, allow to process any translation files for any given target language
    return 1;
}

1;