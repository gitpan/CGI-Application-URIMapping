package CGI::Application::URIMapping;

use strict;
use warnings;

use CGI;
use List::MoreUtils qw(uniq);
use URI::Escape;

use base qw(CGI::Application::Dispatch);

our $VERSION = 0.01;

our %dispatch_table;
our %uri_table;

sub register {
    my ($self, @entries) = @_;
    
    my $dispatch_table = ($dispatch_table{ref($self) || $self} ||= {});
    my $uri_table = ($uri_table{ref($self) || $self} ||= {});
    
    foreach my $entry (@entries) {
        $entry = {
            path => $entry,
        } unless ref $entry;
        my $app = $entry->{app} || (caller)[0];
        my $host = $entry->{host} || '*';
        my $proto = $entry->{protocol} || 'http';
        my $build_uri = $entry->{build_uri};
        my $rm;
        unless ($rm = $entry->{rm}) {
            unless (ref $entry->{path}) {
                (split '/:', $entry->{path}, 2)[0] =~ m|([^/]+)/?$|
                    and $rm = $1;
            }
        }
        die "no 'rm'\n" unless $rm;
        if (ref($entry->{path}) eq 'ARRAY') {
            die "unexpected number of elements in 'path'\n"
                unless @{$entry->{path}} && @{$entry->{path}} % 2 == 0;
            while (@{$entry->{path}}) {
                my $path = shift @{$entry->{path}};
                my $action = shift @{$entry->{path}};
                $action->{app} = $app;
                $action->{rm} = $rm;
                my $host2 = delete $action->{host} || $host;
                my $proto2 = delete $action->{protocol} || $proto;
                $dispatch_table->{$host} ||= [];
                push @{$dispatch_table->{$host2}}, $path, $action;
                $build_uri ||= _build_default_uri_builder({
                    protocol => $proto2,
                    host     => $host2,
                    path     => $path,
                    query    => delete $action->{query} || [],
                    action   => $action,
                });
            }
        } else {
            my $action = {
                app => $app,
                rm  => $rm,
            };
            $dispatch_table->{$host} ||= [];
            push @{$dispatch_table->{$host}}, $entry->{path}, $action;
            $build_uri ||= _build_default_uri_builder({
                protocol => $proto,
                host     => $host,
                path     => $entry->{path},
                query    => $entry->{query} || [],
                action   => $action,
            });
        }
        $uri_table->{"$app/$rm"} = $build_uri;
    }
}

sub build_uri {
    my ($self, $args) = @_;
    
    my $app = $args->{app}
        or die "no 'app'\n";
    my $rm = $args->{rm} || undef;
    unless ($rm) {
        $app =~ m|[^:]*$|;
        $rm = lcfirst $&;
        $rm =~ s/[A-Z]/'_' . lc($&)/ego;
    }
    my $params = $args->{params} || [];
    $params = [$params]
        unless ref $params eq 'ARRAY';
    
    my $uri_table = ($uri_table{ref($self) || $self} ||= {});
    
    die "no data for $app/$rm" unless exists $uri_table->{"$app/$rm"};
    $uri_table->{"$app/$rm"}->(
        $args->{protocol} || undef,
        sub {
            my $n = shift;
            foreach my $h (@$params) {
                if (ref $h eq 'HASH') {
                    return ($h->{$n}) if exists $h->{$n};
                } else {
                    my @v = $h->param($n);
                    return @v if @v;
                }
            }
            ();
        });
}

sub run_modes_of {
    my ($self, $app) = @_;
    my $dispatch_table = ($dispatch_table{ref($self) || $self} ||= []);
    
    $dispatch_table = $dispatch_table->{CGI::virtual_host()}
        || $dispatch_table{'*'};
    
    my @rm = uniq map {
        $_->{rm}
    } grep {
        ref($_) && $_->{app} eq $app
    } @$dispatch_table;
    
    \@rm;
}

sub dispatch_args {
    my $self = shift;
    my $dispatch_table = ($dispatch_table{ref($self) || $self} ||= {});
    
    return {
        prefix => '',
        table  => $dispatch_table->{CGI::virtual_host()}
            || $dispatch_table->{'*'}
                || {},
    };
}

sub _build_default_uri_builder {
    my $prototype = shift;
    
    $prototype->{path} =~ s|^/?(.*)/?$|$1|;
    $prototype->{path} = [
        split '/', $prototype->{path}
    ];
    $prototype->{query} ||= [];
    
    sub {
        _default_build_uri($prototype, @_);
    };
}

sub _default_build_uri {
    my ($prototype, $protocol, $get_param) = @_;
    
    # determine hostport
    my $host = $prototype->{host};
    $host = CGI::virtual_host() if $host eq '*';
    # build path
    my @path;
    foreach my $p (@{$prototype->{path}}) {
        if ($p =~ m|^:(.*?)(\??)$|) {
            my ($n, $optional) = ($1, $2);
            my @v = $get_param->($n);
            unless (@v) {
                die "required parameter '$n' is missing\n"
                    unless $optional;
                last;
            }
            die "more than one value assigned for path parameter: '$n'\n"
                if @v != 1;
            push @path, @v;
        } else {
            push @path, $p;
        }
    }
    # build query params
    my @qp;
    foreach my $n (@{$prototype->{query}}) {
        my @v = $get_param->($n);
        push @qp, map { "$n=" . uri_escape($_) } @v;
    }
    # build and return
    my $uri = ($protocol || $prototype->{protocol})
        . "://$host/" . join('/', @path);
    $uri .= '?' . join('&', @qp)
        if @qp;
    $uri;
}

1;

__END__

=head1 NAME

CGI::Application::URIMapping - A dispatcher and permalink builder

=head1 SYNOPSIS

  package MyApp::URIMapping;
  
  use base qw/CGI::Application::URIMapping/;
  use MyApp::Page1;
  use MyApp::Page2;
  
  package MyApp;
  
  use base qw/CGI::Application/;
  
  sub setup {
    my $self = shift;
    $self->run_modes(MyApp::URIMapping->run_modes_of(ref $self));
  }

  package MyApp::Page1;
  
  # registers subroutine ``page1'' for given path
  MyApp::URIMapping->register({
    path  => 'page1/:p1/:p2?',
    query => [ qw/q1 q2 q3/ ]
  });
  
  sub page1 {
    ...
  }
  
  # build_uri, generates: http://host/page1/p-one?q1=q-one&q3=q-three
  my $permalink = MyApp::URIMapping->build_uri({
    app    => 'MyApp::Page1',
    rm     => 'page1',
    params => {
      p1 => 'p-one',
      q1 => 'q-one',
      q3 => 'q-three',
    },
  });

=head1 DESCRIPTION

C<CGI::Application::URIMapping> is a dispatcher / permalink builder for CGI::Application.  It is implemented as a wrapper of L<CGI::Application::Dispatch>.

As can be seen in the synopsis, C<CGI::Application::URIMapping> is designed to be used as a base class for defining a mapping for each L<CGI::Application>-based web application.

=head1 METHODS

=head2 register

The class method assigns a runmode to more than one paths.  There are various ways of calling the function.

  MyApp::URIMapping->register('path');
  MyApp::URIMapping->register('path/:required_param/:optional1?/:optional2?');
  
  MyApp::URIMapping->register({
    path  => 'path',
    query => [ qw/n1 n2/ ],
  });
  
  MyApp::URIMapping->register({
    rm       => 'run_mode',
    path     => 'path',
    protocol => 'https',
    host     => 'myapp.example.com',
  });
  
  MyApp::URIMapping->register({
    app  => 'MyApp::Page2',
    rm   => 'run_mode',
    path => [
      'path1/:p1/:p2?/:p3?' => {
        query => [ qw/n1 n2/ ],
      },
      'path2' => {
        query => [ qw/p1 p2 p3 n1 n2/ ],
      },
    ],
  });

The attributes recognized by the function is as follows.

=head3 app

Name of the package in which the run mode is defined.  If ommited, name of the current package is being used.

=head3 rm

Name of the runmode.  If omitted, basename of the first C<path> attribute is being used.

=head3 path

A path (or an array of paths) to be registered for the runmode.  The syntax of the paths are equivalent to that of L<CGI::Application::Dispatch> with the following exceptions.  The attributes C<app> and C<rm> need not be defined for each path, since they are already specified.  C<Procotol>, C<host>, C<query> attributes are accepted.

=head3 protocol

Specifies protocol to be used for given runmode when building a permalink.

=head3 host

Limits the registration to given host if specified.

=head3 query

List of parameters to be marshallised when building a premalink.  The parameters will be marshallized in the order of the array.

=head2 build_uri

Builds a permalink by given package name, runmode, and parameters.

  MyApp::URIMapping->build_uri({
    app => 'MyApp::Page1',
  });

  MyApp::URIMapping->build_uri({
    app => 'MyApp::Page1',
    rm  => 'page1',
  });
  
  MyApp::URIMapping->build_uri({
    app      => 'MyApp::Page1',
    params   => {
      p1 => 'p-one',
      n1 => 'n-one',
    },
    procotol => 'https',
  });
  
  MyApp::URIMapping->build_uri({
    app    => 'MyApp::Page1',
    params => [
      {
        p1 => 'p-one',
      },
      $cgi_app,
      $cgi_app->query,
    ],
  });

The function recognized the following attributes.

=head3 app

Package of the runmode.

=head3 rm

Name of the runmode.  If omitted, the last portion of the package name will be used uncamelized.

=head3 params

List of values to be filled in when building the URI.  The values can be supplied either as hashes, as a object that implements a C<param> method, or as an array of the two.  When an array is supplied, parameter values are search from the first entry to the last.

=head1 AUTHOR

Copyright (c) 2007 Cybozu Labs, Inc.  All rights reserved.

written by Kazuho Oku E<lt>kazuhooku@gmail.comE<gt>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under th
e same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
