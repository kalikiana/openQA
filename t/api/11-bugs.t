#!/usr/bin/env perl -w

# Copyright (C) 2017 SUSE Linux LLC
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
# with this program; if not, see <http://www.gnu.org/licenses/>.

BEGIN {
    unshift @INC, 'lib';
}

use Date::Format;
use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Test::Mojo;
use Test::Warnings;
use OpenQA::Test::Case;
use OpenQA::Client;
require OpenQA::Schema::Result::Jobs;

OpenQA::Test::Case->new->init_data;

my $t = Test::Mojo->new('OpenQA::WebAPI');

# XXX: Test::Mojo loses it's app when setting a new ua
# https://github.com/kraih/mojo/issues/598
my $app = $t->app;
$t->ua(
    OpenQA::Client->new(apikey => 'PERCIVALKEY02', apisecret => 'PERCIVALSECRET02')->ioloop(Mojo::IOLoop->singleton));
$t->app($app);

my $bugs = $app->schema->resultset('Bugs');

my $bug  = $bugs->get_bug('poo#200');
my $get  = $t->get_ok('/api/v1/bugs');
my %bugs = %{$get->tx->res->json->{bugs}};
is($bugs{1}, 'poo#200', 'Bug entry exists');

$get  = $t->get_ok('/api/v1/bugs?refreshable=1');
%bugs = %{$get->tx->res->json->{bugs}};
is($bugs{1}, 'poo#200', 'Bug entry is refreshable');

my $put = $t->put_ok('/api/v1/bugs/1', form => {title => "foobar", existing => 1});
is($put->tx->res->json->{id}, 1, 'Bug #1 updated');

$t->put_ok('/api/v1/bugs/2', form => {title => "foobar", existing => 1})->status_is(404, 'Bug #2 not yet existing');

$get = $t->get_ok('/api/v1/bugs/1');
is($get->tx->res->json->{title}, 'foobar', 'Bug has correct title');
is_deeply(
    [sort keys %{$t->tx->res->json}],
    [qw(assigned assignee bugid existing id open priority refreshed resolution status t_created t_updated title)],
    'All expected columns exposed'
);

$get = $t->get_ok('/api/v1/bugs?refreshable=1');
is_deeply($get->tx->res->json->{bugs}, {}, 'All bugs are refreshed');

my $post = $t->post_ok('/api/v1/bugs', form => {title => "foobar2", bugid => 'poo#201', existing => 1, refreshed => 1});
is($post->tx->res->json->{id}, 2, 'Bug #2 created');

$get = $t->get_ok('/api/v1/bugs/2');
is($get->tx->res->json->{title}, 'foobar2', 'Bug #2 has correct title');

$t->delete_ok('/api/v1/bugs/2');
$t->get_ok('/api/v1/bugs/2')->status_is(404, 'Bug #2 deleted');

$t->delete_ok('/api/v1/bugs/2')->status_is(404, 'Bug #2 already deleted');

$t->post_ok('/api/v1/jobs/99926/comments', form => {text => 'wicked bug: jsc#SLE-42999'});
$get = $t->get_ok('/api/v1/bugs/3');
is($get->tx->res->json->{bugid}, 'jsc#SLE-42999', 'Bug was created by comment post');

$t->post_ok('/api/v1/bugs', form => {title => "new", bugid => 'bsc#123'});
my $bugid = $t->tx->res->json->{id};
$t->app->schema->resultset('Bugs')->find($bugid)->update(
    {
        t_created => time2str('%Y-%m-%d %H:%M:%S', time - 500, 'UTC'),
    });
$t->get_ok('/api/v1/bugs?created_since=1000');
is(scalar(keys %{$t->tx->res->json->{bugs}}), 3, 'All reported bugs');
$t->get_ok('/api/v1/bugs?created_since=100');
is(scalar(keys %{$t->tx->res->json->{bugs}}), 2, 'Only the latest bugs');

done_testing();
