#! /usr/bin/perl

use strict;
use warnings;

use FindBin;
use TestLibFinder;
use lib test_lib_loc();

use CRI::Test;

use Torque::Util::Qstat qw( qstat_fx                );
use Torque::Job::Ctrl   qw( qsub             delJobs );
use Torque::Job::Utils  qw( generateArrayIds         );

plan('no_plan');
setDesc('Qsub -t -W (afterokarray)');

# Variables
my $qhash       = ();
my $qref        = {};
my $id_exp      = '0-1';
my $jid1        = undef;
my $jid2        = undef;
my @jaids       = ();
my $test_host   = $props->get_property('Test.Host');

# Perform the test
$qref = {
          'cmd'   => "sleep 5",
          'flags' => "-t $id_exp",
        };
$jid1 = qsub($qref);
sleep_diag(1, "Allow time for the job to queue");

@jaids = generateArrayIds({
                           'job_id' => $jid1,
                           'id_exp' => $id_exp,
                         });


$qref = {
          'flags' => "-W depend=afterokarray:$jid1",
          full_jobid => 1,
        };
$jid2 = qsub($qref);


sleep_diag(1, "Allow time for the job to queue");


$qhash = qstat_fx({flags => "-t"});

foreach my $jaid (@jaids)
  {

  ok(defined $qhash->{ $jaid }, "Checking job:$jid1 for subjob:$jaid");
  cmp_ok($qhash->{ $jaid }{ 'job_array_request' }, 'eq', $id_exp, "Verifying 'job_array_request' for subjob:$jaid");

  } # END foreach my $jaid (@jaids)

my $jhash = qstat_fx({job_id => $jid2});
$jid1 =~ s/([\[\]\.])/\\$1/g; # get job array id ready for regex

cmp_ok($jhash->{ $jid2 }{ 'job_state'  }, 'eq', "H",                               "Verifying the dependent job:$jid2 'job_state'");
cmp_ok($jhash->{ $jid2 }{ 'hold_types' }, 'eq', "s",                               "Verifying the dependent job:$jid2 'hold_types'"); 
like($jhash->{ $jid2 }{ 'depend'     }, qr/^afterokarray:$jid1\@$test_host(?:\.\w+)?$/, "Verifying the dependent job:$jid2 'depend'");

# Cleanup
delJobs();