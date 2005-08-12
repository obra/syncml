use strict;
use warnings;

package XML::Builder;

sub new {
    bless {out => '', level => 0}, shift;
} 

sub _output {
    my $self = shift;
    $self->{'out'} .= (' ' x $self->{'level'}) . shift() . "\n" if @_;
    $self->{'out'};
} 

sub _t {
    my $self = shift;
    my $text = shift;
    $text =~ s/\&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $self->_output($text);
} 

sub AUTOLOAD {
    our $AUTOLOAD;
    my $tag = $AUTOLOAD;
    $tag =~ s/.*:://;
    return if $tag eq 'DESTROY';

    my $self = shift;

    my $content;
    $content = pop @_ if @_ % 2;
    
    my %attrs = @_;
    my $attrstring = join ' ', map { qq($_="$attrs{$_}") } keys %attrs;
    $attrstring = " $attrstring" if $attrstring;
    
    my $maybe_end = $content ? '' : '/';
    $self->_output("<$tag$attrstring$maybe_end>");
    
    if ($content) {
	$self->{'level'}++;
	UNIVERSAL::isa($content, 'CODE') ?  $content->() : $self->_t($content);
	$self->{'level'}--;
	$self->_output("</$tag>");
    }
} 

1;
