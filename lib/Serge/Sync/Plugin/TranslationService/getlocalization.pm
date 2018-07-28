package Serge::Sync::Plugin::TranslationService::getlocalization;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

use File::Find qw(find);
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

    $cli_return = $self->run_gl_cli('push');

    if ($cli_return != 0) {
        return $cli_return;
    }

    if ($self->{data}->{push_translations}) {
        $cli_return = $self->run_gl_cli('push-tr --force');
    }

    return $cli_return;
}

sub run_gl_cli {
    my ($self, $action, $capture) = @_;

    my $cli_return = 0;

    my $command = $action;

    $command = 'gl '.$command;
    print "Running '$command -u <username> p <password>'...\n";
    $command .= ' -u '.$self->{data}->{username}.' -p '.$self->{data}->{password};

    {
        local $CWD = $self->{data}->{root_directory};

        $cli_return = $self->run_cmd($command, $capture);
    }

    return $cli_return;
}

sub sync_mapping {
    my ($self) = @_;

    my $json = $self->run_gl_cli('translations --output=json', 1);

    my @server_master_files = ();

    if ($json) {
       @server_master_files = $self->parse_json_translations();
    }

    my %server_master_files_hash = map {$_ => 1} @server_master_files;

    my @local_master_files = $self->find_local_master_files();

    foreach my $local_master_file (@local_master_files) {
        if (not exists $server_master_files_hash{$local_master_file}) {
            my $cli_return = $self->run_gl_cli('add '.$local_master_file);

            if ($cli_return != 0) {
                return $cli_return;
            }

            foreach my $lang (sort @$self->{data}->{destination_locales}) {
                my $language_code = $lang;
                $language_code =~ s/-(\w+)$/'-'.uc($1)/e; # convert e.g. 'pt-br' to 'pt-BR'
                $lang =~ s/-(\w+)$/'_'.uc($1)/e; # convert e.g. 'pt-br' to 'pt_BR'

                my $translation_file = $local_master_file;

                $translation_file = ~ s/^master/'translations\/'.$lang/g;

                my $map_locale_action = "map-locale $local_master_file $language_code $translation_file";

                $cli_return = $self->run_gl_cli($map_locale_action);
            }
        }
    }
    
    return 0;
}

sub find_local_master_files {
    my ($self) = @_;

    my @local_master_files = ();

    find(sub {
        push @local_master_files, $File::Find::name if(-f $_);
    }, $self->{data}->{root_directory});

    return @local_master_files;
}

sub parse_json_translations {
    my ($self, $json) = @_;

    return ();
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