package Serge::Engine::Plugin::parse_html;
use parent Serge::Engine::Plugin::Base::Parser;

use strict;

no warnings qw(uninitialized);

use HTML::Entities;
use Serge::Mail;
use Serge::Util qw(locale_from_lang xml_escape_strref);
use XML::LibXML;

sub name {
    return 'HTML static content parser plugin';
}

sub init {
    my $self = shift;

    $self->SUPER::init(@_);

    $self->{errors} = {};
    $self->{ids} = {};

    $self->merge_schema({
        expand_entities => 'BOOLEAN',
        validate_output => 'BOOLEAN',

        email_from    => 'STRING',
        email_to      => 'ARRAY',
        email_subject => 'STRING',
    });

    $self->add('can_save_localized_file', \&validate_output);
    $self->add('after_job', \&report_errors);
}

sub validate_output {
    my ($self, $phase, $file, $lang, $textref) = @_;

    # return values:
    #   0 - prohibit saving the file
    #   1 - allow saving the file

    return 1 unless $self->{data}->{validate_output};

    $self->{current_file_rel} = "$file:$lang";
    eval {
        $self->parse($textref, sub {});
    };
    delete $self->{current_file_rel};
    return $@ ? 0 : 1;
}

sub parse {
    my ($self, $textref, $callbackref, $lang) = @_;

    die 'callbackref not specified' unless $callbackref;

    print "*** IMPORT MODE ***\n" if $self->{import_mode};

    my $source_lang = $self->{parent}->{source_language};

    my $source_html_lang = _html_lang($source_lang);

    my $expected_html_lang = $source_html_lang;

    my $html_lang = undef;

    $html_lang = _html_lang($lang) if $lang;

    $html_lang = $lang if !$html_lang;

    $expected_html_lang = $html_lang if $self->{import_mode} and $html_lang;

    my $text = $$textref;

    # Creating XML parser object
    my $parser = XML::LibXML->new();

    my $html;
    eval {
        $html = $parser->load_html(
            string          => $text,
            recover         => 1,
            suppress_errors => 1,
        );
    };
    if ($@) {
        my $error_text = $@;
        $error_text =~ s/\t/ /g;
        $error_text =~ s/^\s+//s;

        $self->{errors}->{$self->get_current_file_rel} = $error_text;
        die $error_text;
    }

    my $tree = $html->documentElement;

    # Analyze all tags recursively to decide which ones require localization

    my $attrs = $self->get_attributes($tree);

    $self->analyze_tag_recursively('', $tree, undef, $attrs->{lang}, $expected_html_lang);

    # Now, in a second pass, export all localizable strings and generate the localized output

    $self->parse_tag_recursively('', $tree, $callbackref, $source_html_lang, $html_lang, $lang);

    $XML::LibXML::skipXMLDeclaration = 1;
    $XML::LibXML::skipDTD = 1;
    $XML::LibXML::setTagCompression = 1;

    my $out = $html->toString();

    return $lang ? $out : undef;
}

sub analyze_tag_recursively {
    my ($self, $name, $subtree, $prohibit_translation, $current_lang, $expected_lang) = @_;
    my $attrs = $self->get_attributes($subtree);
    my $id = $attrs->{id};

    my $can_translate = 1;
    my $will_translate = undef;
    my $contains_translatables = undef;
    my $prohibit_children_translation = undef;

    # By default, headings, paragraphs, labels, options, list items, definition terms and definition descriptions are translated;
    # bare HTML (content of the root node) is also considered translated by default (provided there are no inner tags
    # that override the segmentation)

    # if ($name =~ m/^(?:|h[1-7]|p|li|dt|dd|label|option)$/) {
    #     $can_translate = !$prohibit_translation;
    # }

    my $the_current_lang = $current_lang;

    if (exists $attrs->{lang}) {
        $the_current_lang = $attrs->{lang};
    }

    # my $node_path = $subtree->nodePath;
    # print "parsing ['$id' '$node_path' '$the_current_lang' '$attrs->{lang}' $expected_lang]\n";

    if ($the_current_lang eq $expected_lang) {
        # $prohibit_translation = undef;
        $can_translate = $can_translate and $id;
    }
    else {
        # $prohibit_translation = 1;
        $can_translate = undef;
    }

    my $some_child_will_translate = undef;

    my @child_nodes = $subtree->findnodes('./*');

    for my $child_node (@child_nodes) {
        my $node_name = $child_node->nodeName;

        my ($child_will_translate, $child_contains_translatables) =
            $self->analyze_tag_recursively($node_name, $child_node, $prohibit_translation, $the_current_lang, $expected_lang);
        $contains_translatables = 1 if ($child_contains_translatables && !$child_will_translate);
        $some_child_will_translate = 1 if $child_will_translate;
    }

    my @text_nodes = $subtree->findnodes('./text()');

    my $node_text = '';

    for my $text_node (@text_nodes) {
        my $node_name = $text_node->nodeName;
        my $str = $text_node->getData(); # this is a string for text nodes

        # Trim the string

        $str =~ s/^[\r\n\t ]+//sg;
        $str =~ s/[\r\n\t ]+$//sg;

        # Only non-empty strings can be translated by default

        $contains_translatables = 1 if $str ne '';

        if ($str ne '') {
            $node_text = $str;
            # print "** [$id $name [$str]\n";
        }
    }

    my $will_translate_attrs = undef;

    if ($can_translate) {
        foreach my $key (keys %$attrs) {
            if ($key ne 'id') {
                my $val = $attrs->{$key};

                my $can_translate_attr = $self->can_translate_attribute($key, $val, $name, $attrs);

                if ($can_translate_attr && ($val ne '')) {
                    $will_translate_attrs = 1;
                }
            }
        }
    }

    #print "[2][$name: can=$can_translate, ctr=$contains_translatables, some=$some_child_will_translate, will=$will_translate]\n" if $self->{parent}->{debug};

    if ($id) {
        if ($contains_translatables) {
            $will_translate = 1 if $can_translate && $contains_translatables;
        }

        $will_translate = undef if $prohibit_translation or $prohibit_children_translation or $some_child_will_translate;

        $self->{ids}->{$id} = {};

        if ($will_translate) {
            $self->{ids}->{$id}->{translate} = 1;
        }

        if ($will_translate_attrs) {
            $self->{ids}->{$id}->{translate_attrs} = 1;
        }

        if ($prohibit_translation) {
            $self->{ids}->{$id}->{prohibit} = 1;
        }
    }

    return ($will_translate or $some_child_will_translate or $prohibit_translation or $prohibit_children_translation, $contains_translatables);
}

sub parse_tag_recursively {
    my ($self, $name, $subtree, $callbackref, $source_html_lang, $html_lang, $lang, $prohibit, $cdata, $context) = @_;
    my $attrs = $self->get_attributes($subtree);
    my $id_attributes = {};

    my $id = $attrs->{id};

    my $translate = undef;
    my $translate_attrs = undef;

    if ($id) {
        if (exists $self->{ids}->{$id}) {
            $id_attributes = $self->{ids}->{$id};
        } else {
            print "$id not found"
        }
    }

    $translate = (exists $id_attributes->{'translate'}) && (!exists $id_attributes->{'prohibit'}) && !$prohibit;
    $translate_attrs = (exists $id_attributes->{'translate_attrs'}) && (!exists $id_attributes->{'prohibit'}) && !$prohibit;

    # if translation is prohibited for an entire subtree, or if the node is going to be translated
    # as a whole, then prohibit translation of children
    my $prohibit_children = $prohibit || $translate;

    $cdata = 1 if (($name eq '__CDATA') || ($name eq '__COMMENT'));

    # if context or hint attribute is defined, use that instead of current value, even if the new value is empty;
    # for values that represent empty strings, use `undef`

    if (exists $attrs->{'data-l10n-context'}) {
        $context = $attrs->{'data-l10n-context'} ne '' ? $attrs->{'data-l10n-context'} : undef;
    }

    my $hint;

    if (exists $attrs->{'data-l10n-hint'}) {
        $hint = $attrs->{'data-l10n-hint'} ne '' ? $attrs->{'data-l10n-hint'} : undef;
    }

    if ($translate) {
        my $str = $subtree->textContent;

        # Escaping unsafe xml chars (excluding quotes)

        xml_escape_strref(\$str, 1) unless $cdata;

        if ($translate && ($name ne 'object') && ($str ne '')) {
            my $translated_str = &$callbackref($self->expand_entities($str), $context, $id, undef, $lang, $id);

            # print "$id : $translated_str\n";

            $subtree->removeChildNodes;
            $subtree->appendText($translated_str);

            # $child_node->setData($translated_str);
        }
    } else {
        my @child_nodes = $subtree->findnodes('./*');

        for my $child_node (@child_nodes) {
            my $node_name = $child_node->nodeName;

            # if we are going to translate this tag as a whole, then prohibit translation for the entire subtree
            $self->parse_tag_recursively($node_name, $child_node, $callbackref, $source_html_lang, $html_lang, $lang, $prohibit_children, $cdata, $context);
        }
    }

    # Determine if attributes require localization.
    # This happens when this is not prohibited explicitly,
    # and there is no explicit instruction to localize the tag
    # or there is an explicit instruction to localize the non-terminal tag
    # (as terminal localizable tags will be extracted later as a whole, with all attributes,
    # so there is no need to extract attributes separately)

    if ($html_lang and $attrs->{html_lang}) {
        if ($html_lang and exists $attrs->{html_lang} and $attrs->{html_lang} eq $source_html_lang and $source_html_lang ne $html_lang)
        {
            $subtree->setAttribute('html_lang', $html_lang);
        }
    }

    # Adjusting <meta http-equiv="Content-Language" content="..." /> (if exists)
    # to have the proper content value, e.g. "pt-br"

    if ((lc($name) eq 'meta') && (lc($attrs->{'http-equiv'}) eq 'content-language')) {
        $subtree->setAttribute('content', $html_lang);
    }

    my @sorted_attributes_keys = sort (keys %$attrs);

    if ($translate_attrs) {
        foreach my $key (@sorted_attributes_keys) {
            my $val = $attrs->{$key};

            my $can_translate_attr = $self->can_translate_attribute($key, $val, $name, $attrs);
            # do the translation if the value is not empty

            if ($can_translate_attr && ($val ne '')) {
                my $tag_key = $id.'.'.$key;

                my $translated_str = &$callbackref($self->expand_entities($val), $context, $tag_key, undef, $lang, $tag_key);

                $subtree->setAttribute($key, $translated_str);
            }
        }
    }

    return 1;
}

sub can_translate_attribute {
    my ($self, $key, $val, $name, $attrs) = @_;

    # Escaping unsafe xml chars

    xml_escape_strref(\$val);

    my $can_translate_attr;

    # Localize `alt' and 'title' attributes if allowed (and if there are no php blocks inside)

    if ($key =~ m/^(alt|title)$/) {
        $can_translate_attr = 1;
    }

    # Localize 'value' attribute for specific <input> tags

    if ((lc($name) eq 'input')
        && (lc($attrs->{type}) =~ m/^(text|search|email|submit|reset|button)$/)
        && ($key eq 'value')) {
        $can_translate_attr = 1;
    }

    # Localize 'placeholder' attribute for <input> and <textarea> tags

    if ((lc($name) =~ m/^(input|textarea)$/)
        && ($key eq 'placeholder')) {
        $can_translate_attr = 1;
    }

    return $can_translate_attr
}

sub get_attributes {
    my ($self, $node) = @_;

    my $attributes = {};

    for my $attr ($node->attributes) {
        my $name = $attr->getName;
        my $value = $attr->getValue;

        $attributes->{$name} = $value;
    }

    return $attributes;
}

sub expand_entities {
    my ($self, $s) = @_;

    if ($self->{data}->{expand_entities}) {
        # preserve basic XML entities (to ensure final XML/HTML is still valid
        $s =~ s/&(gt|lt|amp|quot);/\001$1\002/g;
        $s =~ s/&nbsp;/__HTML__ENTITY__nbsp__/g;
        # decode all numeric and named entities using HTML::Entities
        $s = decode_entities($s, {nbsp => '&nbsp;'});
        # restore basic XML entities back
        $s =~ s/__HTML__ENTITY__nbsp__/&nbsp;/g;
        $s =~ s/\001(gt|lt|amp|quot)\002/&$1;/g;
    }

    return $s;
}

sub report_errors {
    my ($self, $phase) = @_;

    return if !scalar keys %{$self->{errors}};

    my $email_from = $self->{data}->{email_from};
    my $email_to = $self->{data}->{email_to};

    if (!$email_from || !$email_to) {
        my @a;
        push @a, "'email_from'" unless $email_from;
        push @a, "'email_to'" unless $email_to;
        my $fields = join(' and ', @a);
        my $are = scalar @a > 1 ? 'are' : 'is';
        print "WARNING: there are some parsing errors, but $fields $are not defined, so can't send an email.\n";
        $self->{errors} = {};
        return;
    }

    my $email_subject = $self->{data}->{email_subject} || ("[".$self->{parent}->{id}.']: PHP/XHTML Parse Errors');

    my $text;
    foreach my $key (sort keys %{$self->{errors}}) {
        my $pre_contents = $self->{errors}->{$key};
        xml_escape_strref(\$pre_contents);
        $text .= "<hr />\n<p><b style='color: red'>$key</b> <pre>".$pre_contents."</pre></p>\n";
    }

    $self->{errors} = {};

    if ($text) {
        $text = qq|
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
</head>
<body style="font-family: sans-serif; font-size: 120%">

<p>
# This is an automatically generated message.

The following parsing errors were found when attempting to localize resource files.
</p>

$text

</body>
</html>
|;
        print 'Errors found. Sending error report to '.join(', ', @$email_to)."\n";

        Serge::Mail::send_html_message(
            $email_from, # from
            $email_to, # to (list)
            $email_subject, # subject
            $text # message body
        );
    }

}

sub get_current_file_rel {
    my ($self) = @_;
    return $self->{current_file_rel} || $self->{parent}->{engine}->{current_file_rel};
}

sub die_with_error {
    my ($self, $error, $textref) = @_;
    my $start_pos = $-[0];
    my $end_pos = $+[0];
    my $around = 40;
    my $s = substr($$textref, $start_pos-$around, $end_pos - $start_pos + $around * 2);
    $s =~ s/\n/ /sg;
    my $message = $error.":\n".
        "$s\n".
        ('-' x $around)."^\n";

    $self->{errors}->{$self->get_current_file_rel} = $message;
    die $message;
}

sub _html_lang {
    my $lang = shift;
    $lang =~ s/(-.+?)(-.+)?$/uc($1).$2/e; # convert e.g. 'pt-br-Whatever' to 'pt-BR-Whatever'
    return $lang;
}

sub _unescape {
    my $s = shift;

    $s =~ s/\\"/"/g;
    $s =~ s/\\'/'/g;

    return $s;
}

sub _escape {
    my $s = shift;

    $s =~ s/"/\\"/g;
    #$s =~ s/'/\\'/g; # not needed, as output strings are enclosed in "..."

    return $s;
}

1;