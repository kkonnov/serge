package Serge::Sync::Plugin::TranslationService::getlocalization;
use parent Serge::Sync::Plugin::Base::TranslationService, Serge::Interface::SysCmdRunner;

use strict;

use Serge::Util qw(subst_macros);
use JSON -support_by_pp; # -support_by_pp is used to make Perl on Mac happy

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
        username => 'STRING',
        password => 'STRING'
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    $self->{data}->{root_directory} = subst_macros($self->{data}->{root_directory});
    $self->{data}->{push_translations} = subst_macros($self->{data}->{push_translations});
    $self->{data}->{username} = subst_macros($self->{data}->{username});
    $self->{data}->{password} = subst_macros($self->{data}->{password});

    die "'root_directory' not defined" unless defined $self->{data}->{root_directory};
    die "'root_directory', which is set to '$self->{data}->{root_directory}', does not point to a valid file.\n" unless -d $self->{data}->{root_directory};
    die "'username' not defined" unless defined $self->{data}->{username};
    die "'password' not defined" unless defined $self->{data}->{password};

    $self->{data}->{push_translations} = 1 unless defined $self->{data}->{push_translations};
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

sub sync_settings {
    my ($self) = @_;

    my $json = $self->run_gl_cli('translations --output=json', 1);

    my @server_master_files = ();

    if ($json) {
    }

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
}

sub pull_ts {
    my ($self, $langs) = @_;

    $self->sync_settings();

    return $self->run_gl_cli('pull');
}

sub push_ts {
    my ($self, $langs) = @_;

    $self->sync_settings();

    my $cli_return = $self->run_gl_cli('push');

    if ($cli_return != 0) {
        return $cli_return;
    }

    if ($self->{data}->{push_translations}) {
        $cli_return = $self->run_gl_cli('push-tr --force');
    }

    return $cli_return;
}


1;