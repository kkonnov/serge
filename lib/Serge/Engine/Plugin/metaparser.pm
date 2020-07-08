package Serge::Engine::Plugin::metaparser;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

sub name {
    return 'Metaparser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        hint      => 'STRING',
        key       => 'STRING',
        value     => 'STRING',
        keyvalue  => 'STRING',
        localize  => 'STRING',
        context   => 'STRING',
        reset     => 'STRING',
        skip      => 'STRING',
        multiline => 'STRING',
        section   => 'STRING',
        close     => 'STRING',
        delim     => 'STRING',
        concat_before   => 'STRING',
        concat_after    => 'STRING',

        unescape => {'' => 'LIST',
            '*'         => 'ARRAY'
        },

        escape   => {'' => 'LIST',
            '*'         => 'ARRAY'
        },
    });
}

sub validate_data {
    my $self = shift;

    $self->SUPER::validate_data;

    if (!(defined $self->{data}->{keyvalue} || defined $self->{data}->{value})) {
        die 'Neither "keyvalue" nor "value" is defined';
    }

    if (defined $self->{data}->{section} && !defined $self->{data}->{close}) {
        die 'You should define "close" rule for "section"';
    }

    if (!defined $self->{data}->{delim}) {
        $self->{data}->{delim} = '/';
    }

    die '"localize" is not defined' unless defined $self->{data}->{localize};
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    $self->_reset;

    $self->{callbackref} = $callbackref;
    $self->{lang} = $lang;
    $self->{sections} = [];

    # make a copy of the string as we will change it
    my $source_text = $$textref;

    $self->merge_multiline_strings(\$source_text);

    $self->preprocess(\$source_text);

    my @input;
    my $concat_after;
    foreach my $line (split(/\n/, $source_text)) {
        if ($concat_after || ($self->{data}->{concat_before} ne '') && ($line =~ m/$self->{data}->{concat_before}/)) {
            print "detected multiline: $line\n" if $self->{debug};
            my $last = pop @input;
            $line = $last."\n".$line;
            print "joined multiline: $line\n" if $self->{debug};
            $concat_after = undef;
        }
        if (($self->{data}->{concat_after} ne '') && ($line =~ m/$self->{data}->{concat_after}/)) {
            $concat_after = 1;
        }
        push @input, $line;
    }

    my @output;
    foreach my $line (@input) {
        $self->{line} = $line;
        $self->process_line();
        if (defined $self->{key} && defined $self->{value}) {
            $self->_flush;
            $self->_reset;
        } else {
            print "bypass line: $self->{line}\n" if $self->{debug};
        }
        push @output, $self->{line};
    }

    my $result = join("\n", @output);

    $self->postprocess(\$result);

    return $result;
}

sub _reset {
    my ($self) = @_;

    $self->{skip} = undef;
    $self->{hints} = [];
    $self->{context} = undef;
    $self->{key} = undef;
    $self->{value} = undef;

    print "reset\n" if $self->{debug};
}

sub preprocess {
    my ($self, $strref) = @_;
    # do nothing
}

sub postprocess {
    my ($self, $strref) = @_;
    # do nothing
}

sub merge_multiline_strings {
    my ($self, $strref) = @_;

    my $re = $self->{data}->{multiline};
    if ($re ne '') {
        $$strref =~ s/$re//sg;
    }
}

sub process_line {
    my ($self) = @_;

    $self->find_context ||
    $self->find_hint ||
    $self->find_reset ||
    $self->find_skip ||
    $self->find_section ||
    $self->find_close ||
    $self->find_key ||
    $self->find_value ||
    $self->find_keyvalue;
}

sub append_macros {
    my ($self, $group) = @_;

    if (!exists $self->{macros}) {
        %{$self->{macros}} = ();
    }
    foreach my $key (keys %{$group}) {
        my $m = uc $key;
        $self->{macros}->{$m} = $group->{$key};
        print "added macros: '$m' with value '$self->{macros}->{$m}'\n" if $self->{debug};
    }
}

sub find_context {
    my ($self) = @_;

    if (($self->{data}->{context} ne '') && ($self->{line} =~ m/$self->{data}->{context}/s)) {
        my $context = defined $+{ctx} ? $+{ctx} : $1;
        die "'context' pattern returned empty value" unless $context ne '';
        $self->{context} = $context;
        print "context: '$context'\n" if $self->{debug};
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_hint {
    my ($self) = @_;

    if (($self->{data}->{hint} ne '') && ($self->{line} =~ m/$self->{data}->{hint}/s)) {
        my $hint = defined $+{hint} ? $+{hint} : $1;
        die "'hint' pattern returned empty value" unless $hint ne '';
        push @{$self->{hints}}, $hint;
        print "hint: '$hint'\n" if $self->{debug};
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_reset {
    my ($self) = @_;

    if (($self->{data}->{reset} ne '') && ($self->{line} =~ m/$self->{data}->{reset}/s)) {
        $self->_reset;
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_skip {
    my ($self) = @_;

    if (($self->{data}->{skip} ne '') && ($self->{line} =~ m/$self->{data}->{skip}/s)) {
        $self->{skip} = 1;
        print "skip\n" if $self->{debug};
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_section {
    my ($self) = @_;

    if (($self->{data}->{section} ne '') && ($self->{line} =~ m/$self->{data}->{section}/s)) {
        my $key = defined $+{key} ? $+{key} : $1;
        die "'section' pattern returned empty value" unless $key ne '';
        push @{$self->{sections}}, $key;
        print "section: '$key'\n" if $self->{debug};
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_close {
    my ($self) = @_;

    if (($self->{data}->{close} ne '') && ($self->{line} =~ m/$self->{data}->{close}/s)) {
        my $key = pop @{$self->{sections}};
        print "close: '$key'\n" if $self->{debug};
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_key {
    my ($self) = @_;

    if (($self->{data}->{key} ne '') && ($self->{line} =~ m/$self->{data}->{key}/s)) {
        my $key = defined $+{key} ? $+{key} : $1;
        die "'key' pattern returned empty value" unless $key ne '';
        $self->{key} = $self->_with_section($key);
        print "key: '$key'\n" if $self->{debug};
        $self->append_macros(\%+);
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_value {
    my ($self) = @_;

    if (($self->{data}->{value} ne '') && ($self->{line} =~ m/$self->{data}->{value}/s)) {
        my $value = defined $+{val} ? $+{val} : $1;
        die "'value' pattern returned empty value" unless $value ne '';
        $self->{value} = $value;
        print "value: '$value'\n" if $self->{debug};
        $self->append_macros(\%+);
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub find_keyvalue {
    my ($self) = @_;

    if (($self->{data}->{keyvalue} ne '') && ($self->{line} =~ m/$self->{data}->{keyvalue}/s)) {
        my $key = defined $+{key} ? $+{key} : $1;
        my $value = defined $+{val} ? $+{val} : $2;
        die "'keyvalue' pattern returned empty key" unless $key ne '';
        die "'keyvalue' pattern returned empty string value" unless $value ne '';
        $self->{key} = $self->_with_section($key);
        $self->{value} = $value;
        print "keyvalue: '$self->{key}'=>'$self->{value}'\n" if $self->{debug};
        $self->append_macros(\%+);
        return 1; # skip processing
    }

    return undef; # continue processing
}

sub _with_section {
    my ($self, $key) = @_;

    my @sections = @{$self->{sections}};
    push @sections, $key;
    return join $self->{data}->{delim}, @sections;
}

sub _flush {
    my ($self) = @_;

    print "_flush\n" if $self->{debug};

    return if $self->{skip};

    # add key as the first hint line if it differs from the source value
    unshift @{$self->{hints}}, $self->{key} if $self->{key} ne $self->{value};

    # convert hints array to a multi-line string
    my $hint = join("\n", @{$self->{hints}});

    my $translated_str;

    $self->{value} = $self->unescape($self->{value});

    if ($self->{value}) {
        $translated_str = &{$self->{callbackref}}(
            $self->{value},
            $self->{context},
            $hint,
            undef,
            $self->{lang},
            $self->{key}
        );
    }

    if ($self->{lang}) {
        my $re = $self->{data}->{localize};
        $translated_str = $self->escape($translated_str);
        if ($self->{line} =~ m/$re/s) {
            my $prefix = defined $+{pre} ? $+{pre} : $1;
            my $value = defined $+{val} ? $+{val} : $2;
            my $suffix = defined $+{suf} ? $+{suf} : $3;
            die "'localize' pattern returned empty \$value capture group" unless defined $value;
            $self->{line} =~ s/$re/$prefix$translated_str$suffix/s;
        } else {
            die "'localize' pattern didn't match anything";
        }
    }
}

sub subst_macros {
    my ($self, $str) = @_;
    if (defined $self->{macros}) {
        foreach my $key (keys %{$self->{macros}}) {
            $str =~ s/%$key%/$self->{macros}->{$key}/ge;
        }
    }
    return $str;
}

sub unescape {
    my ($self, $source) = @_;

    foreach my $rule (@{$self->{data}->{unescape}}) {
        my ($from, $to, $modifiers) = @$rule;

        $from = $self->subst_macros($from);
        $to = $self->subst_macros($to);

        my $eval_line = "\$source =~ s/$from/$to/$modifiers;";
        eval($eval_line);
        die "eval() failed on: '$eval_line'\n$@" if $@;
    }

    return $source;
}

sub escape {
    my ($self, $translation) = @_;

    foreach my $rule (@{$self->{data}->{escape}}) {
        my ($from, $to, $modifiers) = @$rule;

        $from = $self->subst_macros($from);
        $to = $self->subst_macros($to);

        my $eval_line = "\$translation =~ s/$from/$to/$modifiers;";
        eval($eval_line);
        die "eval() failed on: '$eval_line'\n$@" if $@;
    }

    return $translation;
}

1;