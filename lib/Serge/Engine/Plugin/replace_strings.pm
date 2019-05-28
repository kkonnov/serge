package Serge::Engine::Plugin::replace_strings;
use parent Serge::Engine::Plugin::if;

use strict;

no warnings qw(uninitialized);

use Serge::Util qw(subst_macros_strref);
use YAML::XS qw(LoadFile);
use Cwd qw(realpath);

sub name {
    return 'Generic string replacement plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->merge_schema({
        replace => {'' => 'LIST',
            '*'        => 'ARRAY'
        },
        replace_with => {'' => 'LIST',
            '*'        => 'ARRAY'
        },
        if => {
            '*' => {
                then => {
                    replace => {'' => 'LIST',
                        '*'        => 'ARRAY'
                    },
                    replace_with => {'' => 'LIST',
                        '*'        => 'ARRAY'
                    },
                },
            },
        },
    });

    $self->add({
        after_load_file                   => \&check,
        before_save_localized_file        => \&check,
        rewrite_source                    => \&check,
        rewrite_translation               => \&check,
        rewrite_path                      => \&rewrite_path,
        rewrite_relative_output_file_path => \&rewrite_path,
        rewrite_absolute_output_file_path => \&rewrite_path,
        rewrite_relative_ts_file_path     => \&rewrite_path,
        rewrite_absolute_ts_file_path     => \&rewrite_path,
        rewrite_lang_macros               => \&rewrite_path
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    die "'replace' parameter is not specified and no 'if' blocks found" if !exists $self->{data}->{if} && !$self->{data}->{replace};

    if (exists $self->{data}->{if}) {
        foreach my $block (@{$self->{data}->{if}}) {
            die "'replace' parameter is not specified inside if/then block" if !$block->{then}->{replace};
        }
    }
}

sub adjust_phases {
    my ($self, $phases) = @_;

    $self->SUPER::adjust_phases($phases);

    # this plugin makes sense only when applied to a single phase
    # (in addition to 'before_job' phase inherited from Serge::Engine::Plugin::if plugin)
    die "This plugin needs to be attached to only one phase at a time" unless @$phases == 2;
}

sub process_then_block {
    my ($self, $phase, $block, $file, $lang, $strref) = @_;

    #print "::process_then_block(), phase=[$phase], block=[$block], file=[$file], lang=[$lang], strref=[$strref]\n";

    my $debug = $self->{parent}->{debug};
    my $output_lang = $lang;
    my $r = $self->{parent}->{output_lang_rewrite};
    $output_lang = $r->{$lang} if defined $r && exists($r->{$lang});

    my $rules = $block->{replace};
    foreach my $rule (@$rules) {
        my ($from, $to, $modifiers) = @$rule;

        subst_macros_strref(\$from, $file, $output_lang);
        subst_macros_strref(\$to, $file, $output_lang);

        print "[replace]::process_then_block(), from=[$from], to=[$to], modifiers=[$modifiers]\n" if $debug;

        my $eval_line = "\$\$strref =~ s/$from/$to/$modifiers;";
        eval($eval_line);
        die "eval() failed on: '$eval_line'\n$@" if $@;
    }
    my $with_rules = $block->{replace_with};
    foreach my $rule (@$with_rules) {
        my ($with, $from, $to, $modifiers) = @$rule;

        subst_macros_strref(\$from, $file, $output_lang);
        subst_macros_strref(\$to, $file, $output_lang);
        subst_macros_strref(\$with, $file, $output_lang);

        my $value = $self->with_value(split(/\|/, $with));
        $from =~ s/%VALUE%/$value/sg;
        $to =~ s/%VALUE%/$value/sg;

        print "[replace]::process_then_block(), with=[$with] from=[$from], to=[$to], modifiers=[$modifiers]\n" if $debug;

        my $eval_line = "\$\$strref =~ s/$from/$to/$modifiers;";
        eval($eval_line);
        die "eval() failed on: '$eval_line'\n$@" if $@;
    }

    return (shift @_)->SUPER::process_then_block(@_);
}

sub with_value {
    my ($self, $file, $path) = @_;
    my $data = LoadFile(realpath $file);
    my @path = split(/\./, $path);
    my $value = $data;
    $value = $value->{$_} for @path;
    return quotemeta($value);
}

sub check {
    my $self = shift;
    return $self->SUPER::check(@_);
}

sub rewrite_path {
    my ($self, $phase, $path, $lang) = @_;
    $self->SUPER::check($phase, $path, $lang, \$path);
    return $path;
}

1;