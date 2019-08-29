package Serge::Engine::Plugin::statsd_reporter;
use parent Serge::Plugin::Base::Callback;

use strict;
use DataDog::DogStatsd;
use Serge::Util qw(subst_macros subst_macros_strref);

sub name {
    return 'Send statistics into StatsD daemon';
}

sub init {
    my $self = shift;

    $self->{allowed_files} = {};
    $self->{created_files} = {};
    $self->{deleted_files} = {};

    $self->SUPER::init(@_);

    $self->merge_schema({
        host      => 'STRING',
        port      => 'STRING',
        namespace => 'STRING',
        tags      => 'ARRAY',
        by_words  => 'BOOLEAN',
    });

    $self->add({
        after_update_ts_file_item       => \&after_update_ts_file_item,
        after_extract_source_file_item  => \&after_extract_source_file_item,
        before_job                      => \&before_job,
        after_job                       => \&after_job,
    });
}

sub validate_data {
    my ($self) = @_;

    $self->SUPER::validate_data;

    if (!exists $self->{data}->{host}) {
        $self->{data}->{host} = '127.0.0.1';
    } else {
        subst_macros_strref(\$self->{data}->{host});
    }
    if (!exists $self->{data}->{port}) {
        $self->{data}->{port} = '8125';
    } else {
        subst_macros_strref(\$self->{data}->{port});
    }
    if (!exists $self->{data}->{namespace}) {
        $self->{data}->{namespace} = 'serge.';
    } else {
        subst_macros_strref(\$self->{data}->{namespace});
    }
    $self->{data}->{namespace} .= '.' if $self->{data}->{namespace} !~ m/\.$/s;

    if (!exists $self->{data}->{tags}) {
        $self->{data}->{tags} = ();
    }

    $self->{statsd} = DataDog::DogStatsd->new(
        host => $self->{data}->{host},
        port => $self->{data}->{port},
        namespace => $self->{data}->{namespace},
    );
}

sub render_tags() {
    my ($self, $file, $lang) = @_;

    my @tags = ();
    my $job_id = $self->{parent}->{engine}->{job}->{id};
    foreach (@{$self->{data}->{tags}}) {
        my $tag = subst_macros($_, $file, $lang);
        $tag =~ s/%JOB_ID%/$job_id/sg if $job_id;
        push @tags, $tag if $tag !~ m/%[A-Z:_]+%/s;
    }
    return \@tags;
}

sub before_job() {
    my ($self, $phase) = @_;
    $self->{sources} = {};
}

sub after_job() {
    my ($self, $phase) = @_;
    foreach my $file (keys %{$self->{sources}}) {
        my $tags = $self->render_tags($file);
        $self->{statsd}->gauge( 'source.items.total', $self->{sources}->{$file}, { tags => $tags } );
    }

}

sub count_items {
    my ($self, $str) = @_;
    if ($self->{data}->{by_words}) {
        my $num_words = 0;
        ++$num_words while $str =~ /\S+/g;
        return $num_words;
    }
    return 1;
}

sub after_extract_source_file_item {
    my ($self, $phase, $file, $lang, $source, $hint) = @_;

    if (!exists $self->{sources}->{$file}) {
        $self->{sources}->{$file} = 0;
    }
    $self->{sources}->{$file} += $self->count_items($source);
}

sub after_update_ts_file_item {
    my ($self, $phase, $file, $lang, $source, $target) = @_;

    my $tags = $self->render_tags($file, $lang);
    $self->{statsd}->count( 'translated.items.total', $self->count_items($target), { tags => $tags } );
}

1;