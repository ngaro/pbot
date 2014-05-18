# File: RegistryCommands.pm
# Author: pragma_
#
# Purpose: Commands to introspect and update Registry

package PBot::RegistryCommands;

use warnings;
use strict;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot} // Carp::croak("Missing pbot reference to FactoidCommands");
  $self->{pbot} = $pbot;
  
  $pbot->{commands}->register(sub { return $self->regadd(@_)         },       "regadd",     60);
  $pbot->{commands}->register(sub { return $self->regrem(@_)         },       "regrem",     60);
  $pbot->{commands}->register(sub { return $self->regshow(@_)        },       "regshow",     0);
  $pbot->{commands}->register(sub { return $self->regset(@_)         },       "regset",     60);
  $pbot->{commands}->register(sub { return $self->regunset(@_)       },       "regunset",   60);
  $pbot->{commands}->register(sub { return $self->regchange(@_)      },       "regchange",  60);
  $pbot->{commands}->register(sub { return $self->regfind(@_)        },       "regfind",     0);
}

sub regset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($section, $item, $key, $value) = split / /, $arguments, 4 if defined $arguments;

  if(not defined $section or not defined $item) {
    return "Usage: regset <section> <item> [key [value]]";
  }

  $key = undef if not length $key;
  $value = undef if not length $value;

  return $self->{pbot}->{registry}->set($section, $item, $key, $value);
}

sub regunset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($section, $item, $key) = split / /, $arguments, 3 if defined $arguments;

  if(not defined $section or not defined $item or not defined $key) {
    return "Usage: regunset <section> <item> <key>"
  }

  return $self->{pbot}->{registry}->unset($section, $item, $key);
}

sub regadd {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($section, $item, $value) = split / /, $arguments, 3 if defined $arguments;

  if(not defined $section or not defined $item or not defined $value) {
    return "/msg $nick Usage: regadd <section> <item> <value>";
  }

  $self->{pbot}->{registry}->add('text', $section, $item, $value);

  $self->{pbot}->{logger}->log("$nick!$user\@$host added registry entry [$section] $item => $value\n");
  return "/msg $nick [$section] $item set to $value";
}

sub regrem {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($section, $item) = split / /, $arguments if defined $arguments;

  if(not defined $section or not defined $item) {
    return "/msg $nick Usage: regrem <section> <item>";
  }

  if(not exists $self->{pbot}->{registry}->{registry}->hash->{$section}) {
    return "/msg $nick No such registry section $section.";
  }

  if(not exists $self->{pbot}->{registry}->{registry}->hash->{$section}->{$item}) {
    return "/msg $nick No such item $item in section $section.";
  }

  $self->{pbot}->{logger}->log("$nick!$user\@$host removed registry item [$section][$item]\n");
  $self->{pbot}->{registry}->remove($section, $item);
  return "/msg $nick Registry item $item removed from section $section.";
}

sub regshow {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $registry = $self->{pbot}->{registry}->{registry}->hash;

  my ($section, $item) = split / /, $arguments if defined $arguments;

  if(not defined $section or not defined $item) {
    return "Usage: regshow <section> <item>";
  }

  if(not exists $registry->{$section}) {
    return "/msg $nick No such registry section $section.";
  }

  if(not exists $registry->{$section}->{$item}) {
    return "/msg $nick No such registry item $item in section $section.";
  }

  if($registry->{$section}->{$item}->{private}) {
    return "/msg $nick [$section] $item is private.";
  }

  my $result = "[$section] $item: $registry->{$section}->{$item}->{value}";

  if($registry->{$section}->{$item}->{type} eq 'array') {
    $result .= ' [array]';
  }

  return $result;
}

sub regfind {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $registry = $self->{pbot}->{registry}->{registry}->hash;

  if(not defined $arguments) {
    return "/msg $nick Usage: regfind [-section section] <text>";
  }

  my $section;

  $section = $1 if $arguments =~ s/-section\s+([^\b\s]+)//i;

  $arguments =~ s/^\s+//;
  $arguments =~ s/\s+$//;
  $arguments =~ s/\s+/ /g;

  if($arguments eq "") {
    return "/msg $nick Usage: regfind [-section section] <text>";
  }

  my ($text, $last_item, $last_section, $i);
  $last_section = "";
  $i = 0;
  eval {
    foreach my $section_key (sort keys %{ $registry }) {
      next if defined $section and $section_key !~ /^$section$/i;
      foreach my $item_key (sort keys %{ $registry->{$section_key} }) {
        next if $registry->{$section_key}->{$item_key}->{private};
        next if $registry->{$section_key}->{$item_key}->{value} !~ /$arguments/i and $item_key !~ /$arguments/i;

        $i++;

        if($section_key ne $last_section) {
          $text .= "[$section_key] ";
          $last_section = $section_key;
        }
        $text .= "$item_key ";
        $last_item = $item_key;
      }
    }
  };

  return "/msg $nick $arguments: $@" if $@;

  if($i == 1) {
    chop $text;
    return "Found one registry entry: [$last_section] $last_item: $registry->{$last_section}->{$last_item}->{value}";
  } else {
    return "found $i registry entries: $text" unless $i == 0;

    my $sections = (defined $section ? "section $section" : 'any sections');
    return "No registry entries matching query found in $sections.";
  }
}

sub regchange {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($section, $item, $delim, $tochange, $changeto, $modifier);

  if(defined $arguments) {
    if($arguments =~ /^([^\s]+) ([^\s]+)\s+s(.)/) {
      $section = $1;
      $item = $2; 
      $delim = $3;
    }
    
    if($arguments =~ /$delim(.*?)$delim(.*)$delim(.*)?$/) {
      $tochange = $1; 
      $changeto = $2;
      $modifier  = $3;
    }
  }

  if(not defined $section or not defined $item or not defined $changeto) {
    return "Usage: regchange <section> <item> s/<pattern>/<replacement>/";
  }

  my $registry = $self->{pbot}->{registry}->{registry}->hash;

  if(not exists $registry->{$section}) {
    return "/msg $nick No such registry section $section.";
  }

  if(not exists $registry->{$section}->{$item}) {
    return "/msg $nick No such registry item $item in section $section.";
  }

  my $ret = eval {
    use re::engine::RE2 -strict => 1;
    if(not $registry->{$section}->{$item}->{value} =~ s|$tochange|$changeto|) {
      $self->{pbot}->{logger}->log("($from) $nick!$user\@$host: failed to change [$section] $item 's$delim$tochange$delim$changeto$delim$modifier\n");
      return "/msg $nick Change [$section] $item failed.";
    } else {
      $self->{pbot}->{logger}->log("($from) $nick!$user\@$host: changed [$section] $item 's/$tochange/$changeto/\n");
      $self->{pbot}->{registry}->process_trigger($section, $item, 'value', $registry->{$section}->{$item}->{value});
      $self->{pbot}->{registry}->save;
      return "Changed: [$section] $item set to $registry->{$section}->{$item}->{value}";
    }
  };
  return "/msg $nick Change [$section] $item: $@" if $@;
  return $ret;
}

1;
