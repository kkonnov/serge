package Serge::Sync::Plugin::TranslationService::getlocalization;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

use File::chdir;
use File::Find qw(find);
use File::Spec::Functions qw(catfile abs2rel);
use JSON -support_by_pp; # -support_by_pp is used to make Perl on Mac happy
use Serge::Util qw(subst_macros);

sub name {
    return 'Get Localization translation server (https://www.getlocalization.com) synchronization plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{optimizations} = 1; # set to undef to disable optimizations

    $self->merge_schema({
        root_directory => 'STRING',
        push_translations => 'BOOLEAN',
        destination_locales    => 'ARRAY',
        username => 'STRING',
        password => 'STRING'
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    $self->{data}->{root_directory} = subst_macros($self->{data}->{root_directory});
    $self->{data}->{push_translations} = subst_macros($self->{data}->{push_translations});
    $self->{data}->{destination_locales} = subst_macros($self->{data}->{destination_locales});
    $self->{data}->{username} = subst_macros($self->{data}->{username});
    $self->{data}->{password} = subst_macros($self->{data}->{password});

    die "'root_directory' not defined" unless defined $self->{data}->{root_directory};
    die "'root_directory', which is set to '$self->{data}->{root_directory}', does not point to a valid file.\n" unless -d $self->{data}->{root_directory};
    die "'username' not defined" unless defined $self->{data}->{username};
    die "'password' not defined" unless defined $self->{data}->{password};
    if (!exists $self->{data}->{destination_locales} or scalar(@{$self->{data}->{destination_locales}}) == 0) {
        die "the list of destination languages is empty";
    }

    $self->{data}->{push_translations} = 1 unless defined $self->{data}->{push_translations};
}

sub pull_ts {
    my ($self, $langs) = @_;

    my $cli_return = $self->sync_mapping();

    if ($cli_return != 0) {
        return $cli_return;
    }

    return $self->run_gl_cli('pull');
}

sub push_ts {
    my ($self, $langs) = @_;

    my $cli_return = $self->sync_mapping();

    if ($cli_return != 0) {
        return $cli_return;
    }

    $cli_return = $self->run_gl_cli('push', 0, 1);

    if ($cli_return != 0) {
        return $cli_return;
    }

    if ($self->{data}->{push_translations}) {
        $cli_return = $self->run_gl_cli('push-tr --force');
    }

    return $cli_return;
}

sub run_gl_cli {
    my ($self, $action, $capture, $ignore_codes) = @_;

    my $cli_return = 0;

    my $command = $action;

    $command = 'gl '.$command;
    print "Running '$command -u <username> -p <password>'...\n";
    $command .= ' -u '.$self->{data}->{username}.' -p '.$self->{data}->{password};

    $cli_return = $self->run_in($self->{data}->{root_directory}, $command, $capture, $ignore_codes);

    return $cli_return;
}

sub sync_mapping {
    my ($self) = @_;

    my $json = $self->run_gl_cli('translations --output=json', 1);

    my @server_master_files = ();

    if ($json) {
        @server_master_files = $self->server_master_files($json);
    }

    my %server_master_files_hash = map {$_ => 1} @server_master_files;

    my @local_master_files = $self->local_master_files();

    foreach my $local_master_file (@local_master_files) {
        my $full_master_file = catfile('master', $local_master_file);

        if (not exists $server_master_files_hash{$full_master_file}) {
            my $cli_return = $self->run_gl_cli('add ' . $full_master_file);

            if ($cli_return != 0) {
                return $cli_return;
            }

            foreach my $lang (sort @{$self->{data}->{destination_locales}}) {
                my $language_code = $lang;
                $language_code =~ s/-(\w+)$/'-' . uc($1)/e; # convert e.g. 'pt-br' to 'pt-BR'
                $lang =~ s/-(\w+)$/'_' . uc($1)/e;          # convert e.g. 'pt-br' to 'pt_BR'

                my $translation_file = $local_master_file;

                $translation_file = catfile('translations', $lang, $local_master_file);

                my $map_locale_action = "map-locale $full_master_file $language_code $translation_file";

                $cli_return = $self->run_gl_cli($map_locale_action);
            }
        }
    }

    return 0;
}

sub local_master_files {
    my ($self) = @_;

    my @local_master_files = ();

    my $master_file_path = catfile($self->{data}->{root_directory}, 'master');

    find(sub {
        push @local_master_files, abs2rel($File::Find::name, $master_file_path) if(-f $_);
    }, $master_file_path);

    return @local_master_files;
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