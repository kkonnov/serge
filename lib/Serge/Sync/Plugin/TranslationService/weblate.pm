package Serge::Sync::Plugin::TranslationService::weblate;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

use File::chdir;
use File::Find qw(find);
use File::Spec::Functions qw(catfile abs2rel);
use JSON -support_by_pp; # -support_by_pp is used to make Perl on Mac happy
use Serge::Util qw(subst_macros);

sub name {
    return 'Weblate translation server (https://weblate.org) synchronization plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{optimizations} = 1; # set to undef to disable optimizations

    $self->merge_schema({
        root_directory => 'STRING',
        config_file => 'STRING',
        config_section => 'STRING',
        push_translations => 'BOOLEAN',
        destination_locales    => 'ARRAY'
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    $self->{data}->{config_file} = subst_macros($self->{data}->{config_file});
    $self->{data}->{config_section} = subst_macros($self->{data}->{config_section});
    $self->{data}->{root_directory} = subst_macros($self->{data}->{root_directory});
    $self->{data}->{push_translations} = subst_macros($self->{data}->{push_translations});
    $self->{data}->{destination_locales} = subst_macros($self->{data}->{destination_locales});

    die "'config_file' not defined" unless defined $self->{data}->{config_file};
    die "'config_file', which is set to '$self->{data}->{config_file}', does not point to a valid file.\n" unless -f $self->{data}->{config_file};

    die "'root_directory' not defined" unless defined $self->{data}->{root_directory};
    die "'root_directory', which is set to '$self->{data}->{root_directory}', does not point to a valid file.\n" unless -d $self->{data}->{root_directory};
    if (!exists $self->{data}->{destination_locales} or scalar(@{$self->{data}->{destination_locales}}) == 0) {
        die "the list of destination languages is empty";
    }

    $self->{data}->{push_translations} = 1 unless defined $self->{data}->{push_translations};
}

sub pull_ts {
    my ($self, $langs) = @_;

    my @local_source_files = $self->local_source_files();

    foreach my $local_source_file (@local_source_files) {
        foreach my $lang (sort @{$self->{data}->{destination_locales}}) {
            my $language_code = $lang;
            $language_code =~ s/-(\w+)$/'-' . uc($1)/e; # convert e.g. 'pt-br' to 'pt-BR'
            $lang =~ s/-(\w+)$/'_' . uc($1)/e;          # convert e.g. 'pt-br' to 'pt_BR'

            my $translation_file = $local_source_file;

            $translation_file = catfile('translations', $lang, $local_source_file);

            my $download_action = "download $local_source_file -o $translation_file";

            $cli_return = $self->run_weblate_cli($download_action);
        }
    }

    return $cli_return;
}

sub push_ts {
    my ($self, $langs) = @_;

    my @local_source_files = $self->local_source_files();

    foreach my $local_source_file (@local_source_files) {
        my $full_source_file = catfile('source', $local_source_file);

        my $cli_return = $self->run_weblate_cli('upload $local_source_file -i '.$full_source_file);

        if ($cli_return != 0) {
            return $cli_return;
        }
    }

    return $cli_return;
}

sub run_weblate_cli {
    my ($self, $action, $capture, $ignore_codes) = @_;

    my $cli_return = 0;

    my $command = $action.' --config '.$self->{data}->{config_file};

    $command = 'wlc '.$command;
    print "Running '$command ...\n";

    $cli_return = $self->run_in($self->{data}->{root_directory}, $command, $capture, $ignore_codes);

    return $cli_return;
}

sub local_source_files {
    my ($self) = @_;

    my @local_source_files = ();

    my $source_file_path = catfile($self->{data}->{root_directory}, 'source');

    find(sub {
        push @local_source_files, abs2rel($File::Find::name, $source_file_path) if(-f $_);
    }, $source_file_path);

    return @local_source_files;
}

sub parse_json {
    my ($self, $json) = @_;

    my $tree;
    eval {
        ($tree) = from_json($json, {relaxed => 1});
    };
    if ($@ || !$tree) {
        my $error_text = $@;
        if ($error_text) {
            $error_text =~ s/\t/ /g;
            $error_text =~ s/^\s+//s;
        } else {
            $error_text = "from_json() returned empty data structure";
        }

        die $error_text;
    }

    return $tree;
}

1;