# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Capabilities;
use parent 'PBot::Class';

# purpose: provides interface to set/remove/modify/query user capabilities.
#
# Examples:
#

use warnings; use strict;
use feature 'unicode_strings';

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

sub initialize {
    my ($self, %conf) = @_;
    my $filename = $conf{filename} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/capabilities';
    $self->{caps} = PBot::HashObject->new(name => 'Capabilities', filename => $filename, pbot => $self->{pbot});
    $self->{caps}->load;

    # 'cap' command registered in PBot.pm because $self->{pbot}->{commands} is not yet loaded.

    # add some capabilities used in this file
    $self->add('can-modify-capabilities',  undef, 1);
    $self->add('can-group-capabilities',   undef, 1);
    $self->add('can-ungroup-capabilities', undef, 1);

    # add some useful capabilities
    $self->add('is-whitelisted', undef, 1);
}

sub cmd_cap {
    my ($self, $context) = @_;

    my $command = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});
    my $result;
    given ($command) {
        when ('list') {
            my $cap = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});
            return $self->list($cap);
        }

        when ('whohas') {
            my $cap = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});
            return "Usage: cap whohas <capability>; Lists all users who have <capability>" if not defined $cap;
            return "No such capability $cap."                                              if not $self->exists($cap);
            my $result  = "Users with capability $cap: ";
            my $users   = $self->{pbot}->{users}->{users};
            my @matches;
            foreach my $name (sort $users->get_keys) {
                my $u = $users->get_data($name);
                push @matches, $users->get_key_name($name) if $self->userhas($u, $cap);
            }

            if (@matches) {
                $result .= join(', ', @matches);
            } else {
                $result .= 'nobody';
            }

            return $result;
        }

        when ('userhas') {
            my ($name, $cap) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
            return "Usage: cap userhas <username> [capability]; Lists capabilities belonging to <user>" if not defined $name;
            $cap = lc $cap if defined $cap;

            my $u = $self->{pbot}->{users}->{users}->get_data($name);
            if (not defined $u) {
                return "No such user $name.";
            }

            $name = $self->{pbot}->{users}->{users}->get_key_name($name);

            if (defined $cap) {
                return "Try again. No such capability $cap." if not $self->exists($cap);
                if   ($self->userhas($u, $cap)) { return "Yes. User $name has capability $cap."; }
                else                            { return "No. User $name  does not have capability $cap."; }
            } else {
                my $result = "User $name has capabilities: ";
                my @groups;
                my @single;
                foreach my $key (sort keys %{$u}) {
                    next if $key eq '_name';
                    next if not $self->exists($key);
                    my $count = $self->{caps}->get_keys;
                    if   ($count > 0) { push @groups, "$key ($count cap" . ($count == 1 ? '' : 's') . ")"; }
                    else              { push @single, $key; }
                }
                if (@groups or @single) { $result .= join ', ', @groups, @single; }
                else                    { $result = "User $name has no capabilities."; }
                return $result;
            }
        }

        when ('group') {
            my ($cap, $subcaps) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
            return "Usage: cap group <existing or new capability> <existing capabilities...>" if not defined $cap or not defined $subcaps;

            my $u = $self->{pbot}->{users}->loggedin($context->{from}, $context->{hostmask});
            return "You must be logged into your user account to group capabilities together."           if not defined $u;
            return "You must have the can-group-capabilities capability to group capabilities together." if not $self->userhas($u, 'can-group-capabilities');

            my @caps = split /\s+|,/, $subcaps;
            foreach my $c (@caps) {
                return "No such capability $c."                     if not $self->exists($c);
                return "You cannot group a capability with itself." if lc $cap eq lc $c;
                $self->add($cap, $c);
            }
            if (@caps > 1) { return "Capabilities " . join(', ', @caps) . " added to the $cap capability group."; }
            else           { return "Capability $subcaps added to the $cap capability group."; }
        }

        when ('ungroup') {
            my ($cap, $subcaps) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
            return "Usage: cap ungroup <existing capability group> <grouped capabilities...>" if not defined $cap or not defined $subcaps;
            return "No such capability $cap."                                                 if not $self->exists($cap);

            my $u = $self->{pbot}->{users}->loggedin($context->{from}, $context->{hostmask});
            return "You must be logged into your user account to remove capabilities from groups."             if not defined $u;
            return "You must have the can-ungroup-capabilities capability to remove capabilities from groups." if not $self->userhas($u, 'can-ungroup-capabilities');

            my @caps = split /\s+|,/, $subcaps;
            foreach my $c (@caps) {
                return "No such capability $c."                                      if not $self->exists($c);
                return "Capability $c does not belong to the $cap capability group." if not $self->has($cap, $c);
                $self->remove($cap, $c);
            }

            if (@caps > 1) { return "Capabilities " . join(', ', @caps) . " removed from the $cap capability group."; }
            else           { return "Capability $subcaps removed from the $cap capability group."; }
        }

        default {
            $result =
              "Usage: cap list [capability] | cap group <existing or new capability group> <existing capabilities...> | cap ungroup <existing capability group> <grouped capabilities...> | cap userhas <user> [capability] | cap whohas <capability>";
        }
    }
    return $result;
}

sub has {
    my ($self, $cap, $subcap, $depth) = @_;
    my $cap_data = $self->{caps}->get_data($cap);

    return 0 if not defined $cap_data;

    if ($cap eq $subcap) {
        return 0 if exists $cap_data->{$subcap} and not $cap_data->{$subcap};
        return 1;
    }

    $depth //= 10;
    if (--$depth <= 0) {
        $self->{pbot}->{logger}->log("Max recursion reached for PBot::Capabilities->has($cap, $subcap)\n");
        return 0;
    }

    foreach my $c ($self->{caps}->get_keys($cap)) {
        return 1 if $c eq $subcap and $cap_data->{$c};
        return 1 if $self->has($c, $subcap, $depth);
    }
    return 0;
}

sub userhas {
    my ($self, $user, $cap) = @_;
    return 0 if not defined $user;
    return 1 if $user->{$cap};
    foreach my $key (keys %$user) {
        next     if $key eq '_name';
        next     if not $user->{$key};
        return 1 if $self->has($key, $cap);
    }
    return 0;
}

sub exists {
    my ($self, $cap) = @_;
    $cap = lc $cap;
    foreach my $c ($self->{caps}->get_keys) {
        return 1 if $c eq $cap;
        foreach my $sub_cap ($self->{caps}->get_keys($c)) {
            return 1 if $sub_cap eq $cap;
        }
    }
    return 0;
}

sub add {
    my ($self, $cap, $subcap, $dontsave) = @_;
    if (not defined $subcap) {
        if (not $self->{caps}->exists($cap)) {
            $self->{caps}->add($cap, {}, $dontsave);
        }
    } else {
        if ($self->{caps}->exists($cap)) {
            $self->{caps}->set($cap, $subcap, 1, $dontsave);
        } else {
            $self->{caps}->add($cap, { $subcap => 1 }, $dontsave);
        }
    }
}

sub remove {
    my ($self, $cap, $subcap) = @_;
    $cap = lc $cap;
    if (not defined $subcap) {
        foreach my $c ($self->{caps}->get_keys) {
            foreach my $sub_cap ($self->{caps}->get_keys($c)) {
                $self->{caps}->remove($c, $sub_cap, 1) if $sub_cap eq $cap;
            }
            $self->{caps}->remove($c, undef, 1) if $c eq $cap;
        }
    } else {
        $self->{caps}->remove($cap, $subcap, 1) if $self->{caps}->exists($cap);
    }
    $self->{caps}->save;
}

sub rebuild_botowner_capabilities {
    my ($self) = @_;
    $self->{caps}->remove('botowner', undef, 1);
    foreach my $cap ($self->{caps}->get_keys) { $self->add('botowner', $cap, 1); }
}

sub list {
    my ($self, $capability) = @_;
    return "No such capability $capability." if defined $capability and not $self->{caps}->exists($capability);

    my @caps;
    my @groups;
    my @standalones;
    my $result;

    if (not defined $capability) {
        @caps   = sort $self->{caps}->get_keys;
        $result = 'Capabilities: ';
    } else {
        @caps = sort $self->{caps}->get_keys($capability);
        return "Capability $capability has no grouped capabilities." if not @caps;
        $result = "Grouped capabilities for $capability: ";
    }

    # first list all capabilities that have sub-capabilities (i.e. grouped capabilities)
    # then list stand-alone capabilities
    foreach my $cap (@caps) {
        my $count = $self->{caps}->get_keys($cap);
        if   ($count > 0) { push @groups,      "$cap ($count cap" . ($count == 1 ? '' : 's') . ")" if $count; }
        else              { push @standalones, $cap; }
    }
    $result .= join ', ', @groups, @standalones;
    return $result;
}

1;
