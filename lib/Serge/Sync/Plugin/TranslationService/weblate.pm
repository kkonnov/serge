# ABSTRACT: Weblate translation server (https://weblate.org/) synchronization plugin

package Serge::Sync::Plugin::TranslationService::weblate;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

use File::Find qw(find);
use File::Spec::Functions qw(catfile abs2rel);
use JSON -support_by_pp; # -support_by_pp is used to make Perl on Mac happy
use Serge::Util qw(subst_macros);

use version;

our $VERSION = qv('0.900.0');

sub name {
    return 'Weblate translation server (https://weblate.org/) synchronization plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{optimizations} = 1; # set to undef to disable optimizations

    $self->merge_schema({
        config_file            => 'STRING',
        config_section         => 'STRING',
        root_directory         => 'STRING',
        resource_directory     => 'STRING',
        source_locale          => 'STRING',
        destination_locales    => 'ARRAY'
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    $self->{data}->{config_file} = subst_macros($self->{data}->{config_file});
    $self->{data}->{config_section} = subst_macros($self->{data}->{config_section});
    $self->{data}->{root_directory} = subst_macros($self->{data}->{root_directory});
    $self->{data}->{resource_directory} = subst_macros($self->{data}->{resource_directory});
    $self->{data}->{source_locale} = subst_macros($self->{data}->{source_locale});
    $self->{data}->{destination_locales} = subst_macros($self->{data}->{destination_locales});

    die "'config_file' not defined" unless defined $self->{data}->{config_file};
    die "'config_file', which is set to '$self->{data}->{config_file}', does not point to a valid file.\n" unless -f $self->{data}->{config_file};
    die "'resource_directory' not defined" unless defined $self->{data}->{resource_directory};
    die "'root_directory', which is set to '$self->{data}->{root_directory}', does not point to a valid folder." unless -d $self->{data}->{root_directory};
    if (!exists $self->{data}->{destination_locales} or scalar(@{$self->{data}->{destination_locales}}) == 0) {
        die "the list of destination languages is empty";
    }

    $self->{data}->{source_language} = 'en' unless defined $self->{data}->{source_language};
}

sub pull_ts {
    my ($self, $langs) = @_;

    my $langs_to_pull = $self->get_all_langs($langs);

    my $json = $self->run_weblate_cli('list-translations --format json', 1);

    my @server_master_files = ();

    if ($json) {
        @server_master_files = $self->server_master_files($json);
    }

    foreach my $file (@server_master_files) {
        my $directory = catfile($self->{data}->{resource_directory}, '');
        my $resource = catfile($directory, $file);
        my $cli_return = $self->run_weblate_cli("download $file -i $resource");

        if ($cli_return != 0) {
            return $cli_return;
        }
    }

    return 0;
}

sub push_ts {
    my ($self, $langs) = @_;

    my $langs_to_push = $self->get_all_langs($langs);

    foreach my $lang (@$langs_to_push) {
        my $directory = catfile($self->{data}->{resource_directory}, $lang);

        my $lang_files_path = catfile($self->{data}->{root_directory}, $directory);
        my @files = $self->find_lang_files($lang_files_path);

        foreach my $file (@files) {
            my $resource = catfile($directory, $file);
            my $cli_return = $self->run_weblate_cli("upload $file -i $resource --overwrite");

            if ($cli_return != 0) {
                return $cli_return;
            }
        }
    }

    return 0;
}

sub run_weblate_cli {
    my ($self, $action, $capture) = @_;

    my $cli_return = 0;

    my $command = $action;

    $command = 'wlc '.$command;
    $command .= " --config $self->{data}->{config_file}";

    if ($self->{data}->{config_section} ne '') {
        $command .= " --config_section $self->{data}->{config_section}";
    }

    print "Running '$command ...\n";

    $cli_return = $self->run_in($self->{data}->{root_directory}, $command, $capture);

    return $cli_return;
}

sub get_all_langs {
    my ($self, $langs) = @_;

    if (!$langs) {
        $langs = $self->{data}->{destination_locales};
    }

    my @all_langs = ($self->{data}->{source_language});

    push @all_langs, @$langs;

    return \@all_langs;
}

sub find_lang_files {
    my ($self, $directory) = @_;

    my @files = ();

    find(sub {
        push @files, abs2rel($File::Find::name, $directory) if(-f $_);
    }, $directory);

    return @files;
}

sub server_master_files {
    my ($self, $json) = @_;

    my $json_tree = $self->parse_json($json);

    my @master_files = map { $_->{master_file} } @$json_tree;

    my @unique_master_files = $self->unique_values(\@master_files);

    return @unique_master_files;
}

sub unique_values {
    my ($self, $values) = @_;

    my @unique;
    my %seen;

    foreach my $value (@$values) {
        if (! $seen{$value}) {
            push @unique, $value;
            $seen{$value} = 1;
        }
    }

    return @unique;
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