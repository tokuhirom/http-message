#####################################################################
#
#       Internal pre-defined generic scheme support
#
# In this implementation all schemes are subclassed from
# URI::URL::_generic. This turns out to have reasonable mileage.
# See also draft-ietf-uri-relative-url-06.txt

package URI::URL::_generic;           # base support for generic-RL's
require URI::URL;
@ISA = qw(URI::URL);

use URI::Escape;

%OVERLOAD = ( '""' => 'as_string', 'fallback' => 1 );    # EXPERIMENTAL


sub new {                               # inherited by subclasses
    my($class, $init, $base) = @_;
    my $url = bless { }, $class;        # create empty object
    $url->_parse($init);                # parse $init into components
    $url->base($base) if $base;
    $url;
}


# Generic-RL parser
# See draft-ietf-uri-relative-url-06.txt Section 2

sub _parse {
    my($self, $u, @comps) = @_;
    return unless defined $u;

    # Deside which components to parse (scheme & path is manatory)
    @comps = qw(netloc query params frag) unless (@comps);
    my %parse = map {$_ => 1} @comps;

    # This parsing code is based on
    #   draft-ietf-uri-relative-url-06.txt Section 2.4

    # 2.4.1
    $self->{'frag'} = uri_unescape($1)
      if $parse{'frag'} && $u =~ s/#(.*)$//;
    # 2.4.2
    $self->{'scheme'} = lc($1) if $u =~ s/^\s*([\w\+\.\-]+)://;
    # 2.4.3
    $self->netloc($1)
      if $parse{'netloc'} && $u =~ s!^//([^/]*)!!;
    # 2.4.4
    $self->{'query'} = $1
      if $parse{'query'} && $u =~ s/\?(.*)//;
    # 2.4.5
    $self->{'params'} = $1
      if $parse{'params'} && $u =~ s/;(.*)//;

    # 2.4.6
    #
    # RFC 1738 says: 
    #
    #     Note that the "/" between the host (or port) and the 
    #     url-path is NOT part of the url-path.
    #
    # however, RFC 1808, 2.4.6. says:
    #
    #    Even though the initial slash is not part of the URL path,
    #    the parser must remember whether or not it was present so 
    #    that later processes can differentiate between relative 
    #    and absolute paths.  Often this is done by simply storing
    #    he preceding slash along with the path.
    # 
    # so we'll store it in $self->{path}, and strip it when asked
    # for $self->path().  You can test examine if this "/" is
    # present by calling the $url->absolute_path method.

    # we don't test for $parse{path} becase it is mandatory
    $self->{'path'} = $u;   
}


# Generic-RL stringify
#
sub as_string
{
    my $self = shift;
    return $self->{'_str'} if $self->{'_str'} && $UseCache;

    my($scheme, $netloc, $frag) = @{$self}{qw(scheme netloc frag)};

    my $u = $self->full_path(1);  # path+params+query

    # rfc 1808 says:
    #    Note that the fragment identifier (and the "#" that precedes 
    #    it) is not considered part of the URL.  However, since it is
    #    commonly used within the same string context as a URL, a parser
    #    must be able to recognize the fragment when it is present and 
    #    set it aside as part of the parsing process.
    $u .= "#" . uri_escape($frag, $URI::URL::unsafe) if defined $frag;

    $u = "//$netloc$u" if defined $netloc;
    $u = "$scheme:$u" if $scheme;
    $self->{'_str'} = $u;  # set cache
    uri_escape($u, $URI::URL::unsafe);
}

# Generic-RL stringify full path (path+query+params)
#
sub full_path
{
    my($self, $dont_escape)  = @_;
    my($path, $params, $query)
        = @{$self}{ qw(path params query) };
    my $p = '';
    $p .= $path if defined $path;
    # see comment in _parse 2.4.6 about the next line
    $p = "/$p" if defined($self->{netloc}) && $p !~ m:^/:;
    $p .= ";$params" if defined $params;
    $p .= "?$query"  if defined $query;
    $dont_escape ? $p : URI::Escape::uri_escape($p, $URI::URL::unsafe);
}

# Is this an absolute path???
sub absolute_path
{
    my $self = shift;
    my $path = $self->{'path'};
    return 0 unless defined $path;
    return 1 if defined $self->{'netloc'};
    $path =~ m|^/|;   # see comment in _parse 2.4.6
}

#####################################################################
#
# Methods to handle URL's elements

# These methods always return the current value,
# so you can use $url->scheme to read the current value.
# If a new value is passed, e.g. $url->scheme('http'),
# it also sets the new value, and returns the previous value.
# Use $url->scheme(undef) to set the value to undefined.

sub netloc {
    my $self = shift;
    my $old = $self->_elem('netloc', @_);
    return $old unless @_;

    # update fields derived from netloc
    my $nl = $self->{'netloc'} || ''; # already unescaped
    if ($nl =~ s/^([^:@]*):?(.*?)@//){
        $self->{'user'}     = uri_unescape($1);
        $self->{'password'} = uri_unescape($2) if $2 ne '';
    }
    if ($nl =~ s/^([^:]*):?(\d*)//){
        $self->{'host'} = uri_unescape($1);
	if ($2 ne '') {
	    $self->{'port'} = $2;
	    if ($2 == $self->default_port) {
		$self->{'netloc'} =~ s/:\d+//;
	    }
	}
    }
    $self->{'_str'} = '';
    $old;
}

# Fields derived from generic netloc:
sub user     { shift->_netloc_elem('user',    @_); }
sub password { shift->_netloc_elem('password',@_); }
sub host     { shift->_netloc_elem('host',    @_); }

sub port {
    my $self = shift;
    my $old = $self->_netloc_elem('port', @_);
    defined($old) ? $old : $self->default_port;
}

sub _netloc_elem {
    my($self, $elem, @val) = @_;
    my $old = $self->_elem($elem, @val);
    return $old unless @val;

    # update the 'netloc' element
    my $nl = '';
    my $host = $self->{'host'};
    if (defined $host) {  # cant be any netloc without any host
	my $user = $self->{'user'};
	$nl .= uri_escape($user, $URI::URL::reserved) if defined $user;
	$nl .= ":" . uri_escape($self->{'password'}, $URI::URL::reserved)
	  if defined($user) and defined($self->{'password'});
	$nl .= '@' if length $nl;
	$nl .= uri_escape($host, $URI::URL::reserved);
	my $port = $self->{'port'};
	$nl .= ":$port" if defined($port) && $port != $self->default_port;
    }
    $self->{'netloc'} = $nl;
    $self->{'_str'} = '';
    $old;
}

sub epath {
     my $old = shift->_elem('path', @_);
     $old =~ s!^/!! if defined $old;
     $old;
}

sub path {
    my $self = shift;
    my $old = $self->_elem('path', map { uri_escape($_, $URI::URL::reserved_no_slash) } @_);
    if (defined $old) {
	$old =~ s!^/!!;
	Carp::croak("Path components contain '/' (you must call epath)")
	  if $old =~ /%2[fF]/;
	return uri_unescape($old);
    }
    undef;
}

sub path_components {
    my $self = shift;
    my $old = $self->{'path'};
    if (@_) {
	$self->_elem('path',
		     join("/", map { uri_escape($_, $URI::URL::reserved) } @_));
    }
    $old =~ s|^/||;
    map { uri_unescape($_) } split("/", $old);
}

sub eparams  { shift->_elem('params',  @_); }

sub params {
    my $self = shift;
    my $old = $self->_elem('params', map {uri_escape($_,$URI::URL::reserved_no_form)} @_);
    return uri_unescape($old) if defined $old;
    undef;
}

sub equery   { shift->_elem('query',   @_); }

sub query {
    my $self = shift;
    my $old = $self->_elem('query', map { uri_escape($_, $URI::URL::reserved_no_form) } @_);
    if (defined $old) {
	if ($old =~ /%(?:26|2[bB]|3[dD])/) {  # contains escaped '=' '&' or '+'
	    my $mess;
	    for ($old) {
		$mess = "Query contains both '+' and '%2B'"
		  if /\+/ && /%2[bB]/;
		$mess = "Form query contains escaped '=' or '&'"
		  if /=/  && /%(?:3[dD]|26)/;
	    }
	    if ($mess) {
		Carp::croak("$mess (you must call equery)");
	    }
	}
	# Now it should be safe to unescape the string
	return uri_unescape($old);
    }
    undef;

}

# No efrag method because the fragment is always stored unescaped
sub frag     { shift->_elem('frag', @_); }


# Generic-RL: Resolving Relative URL into an Absolute URL
#
# Based on draft-ietf-uri-relative-url-06.txt Section 4
#
sub abs
{
    my($self, $base) = @_;
    my $embed = $self->clone;

    $base = $self->base unless $base;      # default to default base
    return $embed unless $base;            # we have no base (step1)

    $base = new URI::URL $base unless ref $base; # make obj if needed

    my($scheme, $host, $port, $path, $params, $query, $frag) =
        @{$embed}{qw(scheme host port path params query frag)};

    # just use base if we are empty             (2a)
    {
        my @u = grep(defined($_) && $_ ne '',
                     $scheme,$host,$port,$path,$params,$query,$frag);
        return $base->clone unless @u;
    }

    # if we have a scheme we must already be absolute   (2b)
    return $embed if $scheme;

    $embed->{'_str'} = '';                      # void cached string
    $embed->{'scheme'} = $base->{'scheme'};     # (2c)

    return $embed if $embed->{'netloc'};        # (3)
    $embed->netloc($base->{'netloc'});          # (3)

    return $embed if $path =~ m:^/:;            # (4)
    
    if ($path eq '') {                          # (5)
        $embed->{'path'} = $base->{'path'};     # (5)

        return $embed if $embed->params;        # (5a)
        $embed->{'params'} = $base->{'params'}; # (5a)

        return $embed if $embed->query;         # (5b)
        $embed->{'query'} = $base->{'query'};   # (5b)
        return $embed;
    }

    # (Step 6)  # draft 6 suggests stack based approach

    my $basepath = $base->{'path'};
    my $relpath  = $embed->{'path'};

    $basepath =~ s!^/!!;
    $basepath =~ s!/$!/.!;              # prevent empty segment
    my @path = split('/', $basepath);   # base path into segments
    pop(@path);                         # remove last segment

    $relpath =~ s!/$!/.!;               # prevent empty segment

    push(@path, split('/', $relpath));  # append relative segments

    my @newpath = ();
    my $isdir = 0;
    my $segment;

    foreach $segment (@path) {  # left to right
        if ($segment eq '.') {  # ignore "same" directory
            $isdir = 1;
        }
        elsif ($segment eq '..') {
            $isdir = 1;
            my $last = pop(@newpath);
            if (!defined $last) { # nothing to pop
                push(@newpath, $segment); # so must append
            }
            elsif ($last eq '..') { # '..' cannot match '..'
                # so put back again, and append
                push(@newpath, $last, $segment);
            }
            else {
                # it was a component, 
                # keep popped
            }
        } else {
            $isdir = 0;
            push(@newpath, $segment);
        }
    }

    $embed->{'path'} = '/' . join('/', @newpath) . 
        ($isdir && @newpath ? '/' : '');

    $embed;
}


# default_port()
#
# subclasses will usually want to override this
#
sub default_port { 0; }

1;