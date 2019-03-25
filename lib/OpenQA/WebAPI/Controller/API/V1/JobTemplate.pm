# Copyright (C) 2014 SUSE Linux Products GmbH
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package OpenQA::WebAPI::Controller::API::V1::JobTemplate;
use Mojo::Base 'Mojolicious::Controller';
use JSON::Validator;

=pod

=head1 NAME

OpenQA::WebAPI::Controller::API::V1::JobTemplate

=head1 SYNOPSIS

  use OpenQA::WebAPI::Controller::API::V1::JobTemplate;

=head1 DESCRIPTION

Implements API method for handling job templates in openQA.

=head1 METHODS

=over 4

=item list()

Shows information for the job templates defined in the system. If given a job template id, only the
information for that template is shown, otherwise will attempt to fetch job templates based on any
of the following parameters: machine name or id, test suite name or id, distri, arch, version, flavor,
product id or group id. If none of those arguments are passed to the method, will attempt to list
all job templates defined in the system.

Returns a list of job templates containing the following information for each template: template id,
priority, group name, product (id, arch, distri, flavor, group and version), machine (id and name)
and test suite (id and name).

=back

=cut

sub list {
    my $self = shift;

    my $schema = $self->schema;
    my @templates;
    eval {
        if (my $id = $self->param('job_template_id')) {
            @templates = $schema->resultset("JobTemplates")->search({id => $id});
        }

        else {

            my %cond;
            if (my $value = $self->param('machine_name'))    { $cond{'machine.name'}    = $value }
            if (my $value = $self->param('test_suite_name')) { $cond{'test_suite.name'} = $value }
            for my $id (qw(arch distri flavor version)) {
                if (my $value = $self->param($id)) { $cond{"product.$id"} = $value }
            }
            for my $id (qw(machine_id test_suite_id product_id group_id)) {
                if (my $value = $self->param($id)) { $cond{$id} = $value }
            }

            my $has_query = grep { $cond{$_} } (
                qw(machine_name machine_id test_suite.name test_suite_id group_id product.arch product.distri),
                qw(product.flavor product.version product_id)
            );

            if ($has_query) {
                my $attrs
                  = {join => ['machine', 'test_suite', 'product'], prefetch => [qw(machine test_suite product)]};
                @templates = $schema->resultset("JobTemplates")->search(\%cond, $attrs);
            }
            else {
                @templates
                  = $schema->resultset("JobTemplates")->search({}, {prefetch => [qw(machine test_suite product)]});
            }
        }
    };

    if (my $error = $@) { return $self->render(json => {error => $error}, status => 404) }

    @templates = map {
        {
            id         => $_->id,
            prio       => $_->prio,
            group_name => $_->group ? $_->group->name : '',
            product    => {
                id      => $_->product_id,
                arch    => $_->product->arch,
                distri  => $_->product->distri,
                flavor  => $_->product->flavor,
                group   => $_->product->mediagroup,
                version => $_->product->version
            },
            machine => {
                id   => $_->machine_id,
                name => $_->machine ? $_->machine->name : ''
            },
            test_suite => {
                id   => $_->test_suite_id,
                name => $_->test_suite->name
            }}
    } @templates;

    $self->render(json => {JobTemplates => \@templates});
}

=over 4

=item schedules()

Serializes the given job group with relevant test suites by architecture and products (mediums), or all available
groups defined in the system if no group id is specified.
Common defaults for prio and machine are represented in the defaults key.

Returns a YAML template representing the job groups(s).

=back

=cut

sub schedules {
    my $self = shift;

    my %yaml;
    my $groups = $self->schema->resultset("JobGroups")->search(
        $self->param('id') ? {id => $self->param('id')} : undef,
        {select => [qw(id name parent_id default_priority)]});
    while (my $group = $groups->next) {
        my %group;
        my $templates
          = $self->schema->resultset("JobTemplates")
          ->search({group_id => $group->id}, {order_by => 'me.test_suite_id'});

        # Always set the hash of test suites to account for empty groups
        $group{architectures} = {};
        $group{products}      = {};

        my %machines;
        # Extract products and tests per architecture
        while (my $template = $templates->next) {
            $group{products}{$template->product->name} = {
                distribution => $template->product->distri,
                flavor       => $template->product->flavor,
                version      => $template->product->version
            };
            my %test_suite;
            $test_suite{machine} = $template->machine->name;
            $machines{$template->product->arch}{$template->machine->name}++;
            if ($template->prio && $template->prio != $group->default_priority) {
                $test_suite{priority} = $template->prio;
            }
            my $test_suites = $group{architectures}{$template->product->arch}{$template->product->name};
            push @$test_suites, {$template->test_suite->name => \%test_suite};
            $group{architectures}{$template->product->arch}{$template->product->name} = $test_suites;
        }

        # Split off defaults
        foreach my $arch (keys %{$group{architectures}}) {
            $group{defaults}{$arch}{priority} = $group->default_priority;
            my $default_machine
              = (sort { $machines{$arch}->{$b} <=> $machines{$arch}->{$a} or $b cmp $a } keys %{$machines{$arch}})[0];
            $group{defaults}{$arch}{machine} = $default_machine;

            foreach my $product (keys %{$group{architectures}->{$arch}}) {
                my @test_suites;
                foreach my $test_suite (@{$group{architectures}->{$arch}->{$product}}) {
                    foreach my $name (keys %$test_suite) {
                        my $attr = $test_suite->{$name};
                        if ($attr->{machine} eq $default_machine) {
                            delete $attr->{machine};
                        }
                        if (%$attr) {
                            $test_suite->{$name} = $attr;
                            push @test_suites, $test_suite;
                        }
                        else {
                            push @test_suites, $name;
                        }
                    }
                }
                $group{architectures}{$arch}{$product} = \@test_suites;
            }
        }

        $yaml{$group->name} = \%group;
    }

    $self->render(yaml => \%yaml);
}

=over 4

=item create()

Creates a new job template. If the method receives a valid product id as argument, it will
also check for the following arguments: machine id, group id, test suite id and priority. If
no valid product id is received as argument, the method will instead check for the following
arguments: product name, machine name, test suite name, arch, distri, flavor, version and
priority. Returns a 400 code on error, or a 303 code and the job template id within a JSON
block on success.

=back

=cut

sub create {
    my $self = shift;

    my $error;
    my $id;
    my $affected_rows;

    my $validation      = $self->validation;
    my $is_number_regex = qr/^[0-9]+$/;
    my $has_product_id  = $validation->optional('product_id')->like($is_number_regex)->is_valid;

    # validate/read priority
    my $prio_regex = qr/^(inherit|[0-9]+)$/;
    if ($has_product_id) {
        $validation->optional('prio')->like($prio_regex);
    }
    else {
        $validation->required('prio')->like($prio_regex);
    }
    my $prio = $self->param('prio');
    $prio = ((!$prio || $prio eq 'inherit') ? undef : $prio);

    my $schema = $self->schema;

    if ($has_product_id) {
        for my $param (qw(machine_id group_id test_suite_id)) {
            $validation->required($param)->like($is_number_regex);
        }

        if ($validation->has_error) {
            $error = "wrong parameter:";
            for my $k (qw(product_id machine_id test_suite_id group_id)) {
                $error .= ' ' . $k if $validation->has_error($k);
            }
        }
        else {
            my $values = {
                prio          => $prio,
                product_id    => $self->param('product_id'),
                machine_id    => $self->param('machine_id'),
                group_id      => $self->param('group_id'),
                test_suite_id => $self->param('test_suite_id')};
            eval { $id = $schema->resultset("JobTemplates")->create($values)->id };
            $error = $@;
        }
    }
    elsif ($self->param('prio_only')) {
        for my $param (qw(group_id test_suite_id)) {
            $validation->required($param)->like($is_number_regex);
        }

        if ($validation->has_error) {
            $error = "wrong parameter:";
            for my $k (qw(group_id test_suite_id prio)) {
                $error .= ' ' . $k if $validation->has_error($k);
            }
        }
        else {
            eval {
                $affected_rows = $schema->resultset("JobTemplates")->search(
                    {
                        group_id      => $self->param('group_id'),
                        test_suite_id => $self->param('test_suite_id'),
                    }
                )->update(
                    {
                        prio => $prio,
                    });
            };
            $error = $@;
        }
    }
    else {
        for my $param (qw(group_name machine_name test_suite_name arch distri flavor version)) {
            $validation->required($param);
        }

        if ($validation->has_error) {
            $error = "wrong parameter:";
            for my $k (qw(group_name machine_name test_suite_name arch distri flavor version)) {
                $error .= ' ' . $k if $validation->has_error($k);
            }
        }
        else {
            my $values = {
                product => {
                    arch    => $self->param('arch'),
                    distri  => $self->param('distri'),
                    flavor  => $self->param('flavor'),
                    version => $self->param('version')
                },
                group      => {name => $self->param('group_name')},
                machine    => {name => $self->param('machine_name')},
                prio       => $prio,
                test_suite => {name => $self->param('test_suite_name')}};
            eval { $id = $schema->resultset("JobTemplates")->create($values)->id };
            $error = $@;
        }
    }

    my $status;
    my $json = {};

    if ($error) {
        $self->app->log->error($error);
        $json->{error} = $error;
        $status = 400;
    }
    else {
        if (defined($affected_rows)) {
            $json->{affected_rows} = $affected_rows;
            $self->emit_event('openqa_jobtemplate_create', {affected_rows => $affected_rows});
        }
        else {
            $json->{id} = $id;
            $self->emit_event('openqa_jobtemplate_create', {id => $id});
        }
    }

    $self->respond_to(
        json => {json => $json, status => $status},
        html => sub {
            if ($error) {
                $self->flash('error', "Error adding the job template: $error");
            }
            else {
                $self->flash(info => 'Job template added');
            }
            $self->res->code(303);
            $self->redirect_to($self->req->headers->referrer);
        });
}

=over 4

=item destroy()

Deletes a job template given its id. Returns a 404 error code if the template is not found,
a 400 code on other errors or a 303 code on success.

=back

=cut

sub destroy {
    my $self          = shift;
    my $job_templates = $self->schema->resultset('JobTemplates');

    my $status;
    my $json = {};

    my $rs;
    eval { $rs = $job_templates->search({id => $self->param('job_template_id')})->delete };
    my $error = $@;

    if ($rs) {
        if ($rs == 0) {
            $status = 404;
            $error  = 'Not found';
        }
        else {
            $json->{result} = int($rs);
            $self->emit_event('openqa_jobtemplate_delete', {id => $self->param('job_template_id')});
        }
    }
    else {
        $json->{error} = $error;
        $status = 400;
    }
    $self->respond_to(
        json => {json => $json, status => $status},
        html => sub {
            if ($error) {
                $self->flash('error', "Error deleting the job template: $error");
            }
            else {
                $self->flash(info => 'Job template deleted');
            }
            $self->res->code(303);
            $self->redirect_to($self->req->headers->referrer);
        });
}

1;
