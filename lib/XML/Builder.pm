use strict;
use warnings;

package XML::Builder;

use XML::Writer;

sub new {
    my $self = bless {out => ''}, shift;
    # unsafe is necessary for ->_x
    $self->{'writer'} = XML::Writer->new(OUTPUT => \ ($self->{'out'}), UNSAFE => 1);
    $self;
} 

sub _output { shift->{'out'} } 

sub _t {
    my $self = shift;
    my $text = shift;
    $self->{'writer'}->characters($text);
} 

sub _x {
    my $self = shift;
    my $text = shift;
    $self->{'writer'}->raw($text);
} 

sub AUTOLOAD {
    our $AUTOLOAD;
    my $tag = $AUTOLOAD;
    $tag =~ s/.*:://;
    return if $tag eq 'DESTROY';

    my $self = shift;
    $self->_elt($tag, @_);
}

sub _elt {
    my $self = shift;
    my $tag = shift;

    my $has_content = @_ % 2;
    
    my $content;
    $content = pop @_ if $has_content;
    
    my %attrs = @_;
    
    if ($has_content) {
	$self->{'writer'}->startTag($tag, %attrs);
	UNIVERSAL::isa($content, 'CODE') ?  $content->() : $self->_t($content);
	$self->{'writer'}->endTag($tag);
    } else {
	$self->{'writer'}->emptyTag($tag, %attrs);
    } 
} 

1;
