#! /usr/bin/perl

# Copyright (C) 2014-2017 SUSE LLC
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

BEGIN {
    unshift @INC, 'lib';
    push @INC, '.';
    $ENV{OPENQA_TEST_IPC} = 1;
}

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Test::Mojo;
use Test::Warnings;
use OpenQA::Test::Case;
use OpenQA::Test::Database;

use OpenQA::WebSockets;
use OpenQA::Scheduler;

# create Test DBus bus and service for fake WebSockets and Scheduler call
my $ws = OpenQA::WebSockets->new;
my $sh = OpenQA::Scheduler->new;

OpenQA::Test::Case->new->init_data;

use t::ui::PhantomTest;

my $t = Test::Mojo->new('OpenQA::WebAPI');

# By defining a custom hook we can customize the database based on fixtures.
# We do not need job 99981 right now so delete it here just to have a helpful
# example for customizing the test database
sub schema_hook {
    my $schema = OpenQA::Test::Database->new->create;
    my $jobs   = $schema->resultset('Jobs');
    $jobs->find(99981)->delete;
    my $job99946_comments = $jobs->find(99946)->comments;
    $job99946_comments->create({text => 'test1', user_id => 99901});
    $job99946_comments->create({text => 'test2', user_id => 99901});
    my $job99963_comments = $jobs->find(99963)->comments;
    $job99963_comments->create({text => 'test1', user_id => 99901});
    $job99963_comments->create({text => 'test2', user_id => 99901});
    my $job99928_comments = $jobs->find(99928)->comments;
    $job99928_comments->create({text => 'test1', user_id => 99901});
}

my $driver = call_phantom(\&schema_hook);
unless ($driver) {
    plan skip_all => $t::ui::PhantomTest::phantommissing;
    exit(0);
}

#
# List with no parameters
#
$driver->title_is("openQA", "on main page");
my $get;

#
# Test the legacy redirection
#
is($driver->get("/results"), 1, "/results gets");
like($driver->get_current_url(), qr{.*/tests}, "/results redirects to /tests ");

wait_for_ajax();

# Test 99946 is successful (29/0/1)
my $job99946 = $driver->find_element('#results #job_99946');
my @tds = $driver->find_child_elements($job99946, "td");
is((shift @tds)->get_text(), 'Build0091 of opensuse-13.1-DVD.i586', "medium of 99946");
is((shift @tds)->get_text(), 'textmode@32bit',                      "test of 99946");
is((shift @tds)->get_text(), '28 1 1',                              "result of 99946 (passed, softfailed, failed)");
my $time = $driver->find_child_element(shift @tds, 'span');
$time->attribute_like('title', qr/.*Z/, 'finish time title of 99946');
$time->text_like(qr/about 3 hours ago/, "finish time of 99946");

# Test 99963 is still running
isnt($driver->find_element('#running #job_99963'), undef, '99963 still running');
like($driver->find_element('#running #job_99963 td.test a')->get_attribute('href'), qr{.*/tests/99963}, 'right link');
$time = $driver->find_element('#running #job_99963 td.time');
$time->attribute_like('title', qr/.*Z/, 'right time title for running');
$time->text_like(qr/1[01] minutes ago/, 'right time for running');

$get = $t->get_ok('/tests')->status_is(200);
my @header = $t->tx->res->dom->find('h2')->map('text')->each;
my @expected = ('2 jobs are running', '2 scheduled jobs', 'Last 11 finished jobs');
is_deeply(\@header, \@expected, 'all job summaries correct with defaults');

$get      = $t->get_ok('/tests?limit=1')->status_is(200);
@header   = $t->tx->res->dom->find('h2')->map('text')->each;
@expected = ('2 jobs are running', '2 scheduled jobs', 'Last 1 finished jobs');
is_deeply(\@header, \@expected, 'test report can be adjusted with query parameter');

$get = $t->get_ok('/tests/99963')->status_is(200);
$t->content_like(qr/State.*running/, "Running jobs are marked");

# Available comments shown
is(
    $driver->find_element('#job_99963 .fa-comment')->get_attribute('title'),
    '2 comments available',
    'available comments shown for running jobs'
);
is(@{$driver->find_elements('#job_99961 .fa-comment')},
    0, 'available comments only shown if at least one comment available');
is(
    $driver->find_element('#job_99928 .fa-comment')->get_attribute('title'),
    '1 comment available',
    'available comments shown for scheduled jobs'
);
is(
    $driver->find_element('#job_99946 .fa-comment')->get_attribute('title'),
    '2 comments available',
    'available comments shown for finished jobs'
);

$driver->find_element_by_link_text('Build0091')->click();
like(
    $driver->find_element_by_id('summary')->get_text(),
    qr/Overall Summary of opensuse build 0091/,
    'we are on build 91'
);

# return
is($driver->get("/tests"), 1, "/tests gets");

# Test 99928 is scheduled
isnt($driver->find_element('#scheduled #job_99928'), undef, '99928 scheduled');
like($driver->find_element('#scheduled #job_99928 td.test a')->get_attribute('href'), qr{.*/tests/99928}, 'right link');
$time = $driver->find_element('#scheduled #job_99928 td.time');
$time->attribute_like('title', qr/.*Z/, 'right time title for scheduled');
$time->text_like(qr/2 hours ago/, 'right time for scheduled');
$driver->find_element('#scheduled #job_99928 td.test a')->click();
$driver->title_is('openQA: opensuse-13.1-DVD-i586-Build0091-RAID1@32bit test results', 'tests/99928 followed');

# return
is($driver->get("/tests"), 1, "/tests gets");
wait_for_ajax();

# Test 99938 failed, so it should be displayed in red
my $job99938 = $driver->find_element('#results #job_99946');

is($driver->find_element('#results #job_99938 .test .status.result_failed')->get_text(), '', '99938 failed');
like($driver->find_element('#results #job_99938 td.test a')->get_attribute('href'), qr{.*/tests/99938}, 'right link');
$driver->find_element('#results #job_99938 td.test a')->click();
$driver->title_is('openQA: opensuse-Factory-DVD-x86_64-Build0048-doc@64bit test results', 'tests/99938 followed');

# return
is($driver->get("/tests"), 1, "/tests gets");
wait_for_ajax();

my @links = $driver->find_elements('#results #job_99946 td.test a', 'css');
is(@links, 3, 'only three links (icon, name and comments but no restart)');

# Test 99926 is displayed
is($driver->find_element('#results #job_99926 .test .status.result_incomplete')->get_text(), '', '99926 incomplete');

# parent-child
my $child_e = $driver->find_element('#results #job_99938 .parent_child');
is($child_e->get_attribute('title'),         "1 chained parent", "dep info");
is($child_e->get_attribute('data-children'), "[]",               "no children");
is($child_e->get_attribute('data-parents'),  "[99937]",          "parent");

my $parent_e = $driver->find_element('#results #job_99937 .parent_child');
is($parent_e->get_attribute('title'),         "1 chained child", "dep info");
is($parent_e->get_attribute('data-children'), "[99938]",         "child");
is($parent_e->get_attribute('data-parents'),  "[]",              "no parents");

# no highlighting in first place
sub no_highlighting {
    is(scalar @{$driver->find_elements('#results #job_99937.highlight_parent')}, 0, 'parent not highlighted');
    is(scalar @{$driver->find_elements('#results #job_99938.highlight_child')},  0, 'child not highlighted');
}
no_highlighting;

# job dependencies highlighted on hover
$driver->move_to(element => $child_e);
is(scalar @{$driver->find_elements('#results #job_99937.highlight_parent')}, 1, 'parent highlighted');
$driver->move_to(element => $parent_e);
is(scalar @{$driver->find_elements('#results #job_99938.highlight_child')}, 1, 'child highlighted');
$driver->move_to(xoffset => 200, yoffset => 500);
no_highlighting;

# first check the relevant jobs
my @jobs = map { $_->get_attribute('id') } @{$driver->find_elements('#results tbody tr', 'css')};

is_deeply(
    \@jobs,
    [qw(job_99940 job_99939 job_99938 job_99926 job_99936 job_99947 job_99962 job_99946 job_80000 job_99937)],
    '99945 is not displayed'
);
$driver->find_element_by_id('relevantfilter')->click();
wait_for_ajax();

# Test 99945 is not longer relevant (replaced by 99946) - but displayed for all
@jobs = map { $_->get_attribute('id') } @{$driver->find_elements('#results tbody tr', 'css')};
is_deeply(
    \@jobs,
    [qw(job_99940 job_99939 job_99938 job_99926 job_99936 job_99947 job_99962 job_99946 job_99945 job_99944)],
    'all rows displayed'
);

# now toggle back
#print $driver->get_page_source();
$driver->find_element_by_id('relevantfilter')->click();
wait_for_ajax();

@jobs = map { $_->get_attribute('id') } @{$driver->find_elements('#results tbody tr', 'css')};
is_deeply(
    \@jobs,
    [qw(job_99940 job_99939 job_99938 job_99926 job_99936 job_99947 job_99962 job_99946 job_80000 job_99937)],
    '99945 again hidden'
);

$driver->get("/tests?match=staging_e");
wait_for_ajax();

#print $driver->get_page_source();
@jobs = map { $_->get_attribute('id') } @{$driver->find_elements('#results tbody tr', 'css')};
is_deeply(\@jobs, [qw(job_99926)], '1 matching job');
is(@{$driver->find_elements('table.dataTable', 'css')}, 1, 'no scheduled, no running matching');

# now login to test restart links
$driver->find_element_by_link_text('Login')->click();
is($driver->get("/tests"), 1, "/tests gets");
wait_for_ajax();

my $td = $driver->find_element('#results #job_99946 td.test');
is($td->get_text(), 'textmode@32bit', 'correct test name');

# click restart
$driver->find_child_element($td, '.restart', 'css')->click();
wait_for_ajax();

$driver->title_is('openQA: Test results', 'restart stays on page');
$td = $driver->find_element('#results #job_99946 td.test');
is($td->get_text(), 'textmode@32bit (restarted)', 'restart removes link');

#t::ui::PhantomTest::make_screenshot('mojoResults.png');

kill_phantom();
done_testing();
