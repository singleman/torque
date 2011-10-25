package Torque::Util;

use strict;
use warnings;

use FindBin;
use TestLibFinder;
use lib test_lib_loc();

use CRI::Test;
use CRI::Util qw( list2array );
use Torque::Util::Qstat    qw( qstat_fx );
use Torque::Util::Pbsnodes qw( parse_xml      );

use base 'Exporter';

our @EXPORT_OK = qw(
                     list2array
                     hostlist2array
                     run_and_check_cmd
                     job_info
                     node_info
                     verify_job_state
                     query_mom_cfg
                   );

###############################################################################
# hostlist2array
###############################################################################
sub hostlist2array #($)
  {

  my ($file) = @_;

  my @rtn_values = split(/,|\s+/, `cat $file`)
     or die "Unable to get array from provided file: $file";

  return @rtn_values;

  } # END sub hostlist2array

###############################################################################
# run_and_check_cmd
###############################################################################
sub run_and_check_cmd #($)
  {
  
  my ($cmd) = @_;

  my %result;

  %result = runCommand($cmd);
  ok($result{ 'EXIT_CODE' } == 0, "Checking that '$cmd' ran")
    or logMsg("'$cmd' failed: $result{ 'STDERR' }");

  return %result;

  } # END sub run_and_check_cmd #($)

###############################################################################
# job_info - Returns information for a list of jobs
###############################################################################
sub job_info #($)
  {
   
     my @job_ids = @_;
 

     my $job_ids_str = join(" ", @job_ids);

     # Variables
     my $cmd      = "qstat -fx $job_ids_str";
     my %qstat    = ();
     my $job_info;

     # Get the job info
     $job_info = qstat_fx({job_id => $job_ids_str});

     return %$job_info;
  }

###############################################################################
# node_info - Returns information for the pbs mom nodes
###############################################################################
sub node_info 
  {

  my $cmd       = "pbsnodes -x";
  my %pbsnodes  = run_and_check_cmd($cmd);
  my %node_info = parse_xml($pbsnodes{ 'STDOUT' })
    unless $pbsnodes{ 'STDOUT' } eq '';

  return %node_info;

  }
###############################################################################
# verify_job_state
###############################################################################
sub verify_job_state #($)
  {

  my ($params)  = @_;

  # Parameters
  my $job_id        =    $params->{ 'job_id'        } || die 'No job_id given';
  my $exp_job_state = uc $params->{ 'exp_job_state' } || die 'No job_state given';
  my $wait_time     =    $params->{ 'wait_time'     } || 120;

  # Variables
  my $act_job_state = '';
  my $cmd;
  my %qstat;
  my $job_info;

  # Check every second for $wait_time for the state to take effect
  my $endtime = time() + $wait_time;
  my $count = 0;
  diag("Waiting $wait_time seconds for job:$job_id to go to state '$exp_job_state'...");
  while ( time() <= $endtime && $act_job_state ne $exp_job_state )
  {
    # We parse the job information manually so we don't spam the test output
    $job_info = qstat_fx({job_id => $job_id, runcmd_flags => {logging_off => 1}});

    $act_job_state = $job_info{ $job_id }{ 'job_state' } || '';

    sleep 1 unless $count == 0;
    $count ++;
  }

  # Test for the hold state
  cmp_ok($act_job_state, 'eq', $exp_job_state, 
     "Checking for a job_state of '$exp_job_state' for job '$job_id'")
   or qstat_fx({job_id => $job_id});

  } # END sub verify_job_state #($)

###############################################################################
# query_mom_cfg - method for querying for values of attributes found in the 
#                 mom_priv/config file.
###############################################################################
sub query_mom_cfg #($)
  {

  my ($attr) = @_;

  # Variables
  my $value = undef;

  # Query for the attributes value
  my $cmd    = "momctl -q $attr";
  my %momctl = runCommand($cmd);
 
  ok($momctl{ 'EXIT_CODE' } == 0, "Checking exit code of '$cmd'")
    or return $value;
  
  # Parse out the value
  my $stdout = $momctl{ 'STDOUT' };
  $stdout =~ /'${attr}=(.+)'/;
  $value  = $1;

  return $value;

  } # END sub query_mom_cfg #($)

###############################################################################
# is_running - Makes sure that a given process is running and not just a 
#              zombie (defunct process). pgrep -x will return zombie 
#              processes.  Returns 1 if a non-zombie process is running and
#              0 if not.
###############################################################################
sub is_running #($)
  {
    
    my ($process) = @_;

    # Variables
    my $running = 0;

    # Commands
    my $pgrep_cmd = "pgrep -d , -x $process";
    my $ps_cmd;

    # Return Hashes
    my %pgrep;
    my %ps;

    # Look for running processes
    %pgrep = runCommand($pgrep_cmd);

    return $running
      if $pgrep{ 'EXIT_CODE' } == 1;

    # Only count non-zombie processes
    my @pids = list2array($pgrep{ 'STDOUT' });

    foreach my $pid (@pids)
      {

      # Detaint the pid, ignore invalid pids
      if ($pid =~ /^(\d+)$/)
        {
       
        $pid = $1;

        } # END if ($pid =~ /^(\d+)$/)
      else
        {

        diag("Bad pid: '$pid'");
        next;

        } # END if ($pid =~ /^(\d+)$/)


      $ps_cmd = "ps -o pid,stat ax | grep $pid | grep -v grep | grep -v 'Z'";
      %ps     = runCommand($ps_cmd);

      if ( $ps{ 'EXIT_CODE' } == 0 )
        {

        $running = 1;
        next;

        } # END if ( $ps{ 'EXIT_CODE' } == 0 )

      } # END foreach my $pid (@pids)


    return $running;

  } # END sub is_running #($)

###############################################################################
# is_running_remote - Checks that a given process is running on a remote node 
#                     and is not just a zombie (defunct process). pgrep -x will 
#                     return zombie processes.  Returns 1 if a non-zombie 
#                     process is running and 0 if not.
###############################################################################
sub is_running_remote #($$)
  {
    
    my ($process, $node) = @_;

    # Variables
    my $running = 0;

    # Commands
    my $pgrep_cmd = "pgrep -d , -x $process";
    my $ps_cmd;

    # Return Hashes
    my %pgrep;
    my %ps;

    # Look for running processes
    %pgrep = runCommandSsh($node, $pgrep_cmd);

    return $running
      if $pgrep{ 'EXIT_CODE' } == 1;

    # Only count non-zombie processes
    my @pids = list2array($pgrep{ 'STDOUT' });

    foreach my $pid (@pids)
      {

      # Detaint the pid, ignore invalid pids
      if ($pid =~ /^(\d+)$/)
        {
       
        $pid = $1;

        } # END if ($pid =~ /^(\d+)$/)
      else
        {

        diag("Bad pid: '$pid'");
        next;

        } # END if ($pid =~ /^(\d+)$/)


      $ps_cmd = "ps -o pid,stat ax | grep $pid | grep -v grep | grep -v Z";
      %ps     = runCommandSsh($node, $ps_cmd);

      if ( $ps{ 'EXIT_CODE' } == 0 )
        {

        $running = 1;
        next;

        } # END if ( $ps{ 'EXIT_CODE' } == 0 )

      } # END foreach my $pid (@pids)


    return $running;

  } # END sub is_running_remote #($)

1;

=head1 NAME

Torque::Util - Some useful Torque test utilities

=head1 SYNOPSIS

 use Torque::Util qw(
                             hostlist2array
                             run_and_check_cmd
                             node_info
                             job_info
                             verify_job_state
                             query_mom_cfg
                           );

 # hostlist2array
 my @array1 = hostlist2array('/tmp/hostlist');

 # run_and_check_cmd
 my %result = run_and_check_cmd('sleep 30');

 # job_info
 my @job_ids  = qw(1.host1 2.host1);
 my %job_info = job_info(@job_ids);

 # node_info
 my %node_info = node_info();

 # verify_job_state
 my $job_state_params = {
                          'job_id'        => '0.host',
                          'exp_job_state' => 'R',
                          'wait_time'     => 180
                        };
 verify_job_state($job_state_params); 

 # query_mom_cfg
 my $mom_value = query_mom_cfg('scheduling');

=head1 DESCRIPTION

This module is collection of methods that are useful when writing tests for Torque.

=head1 SUBROUTINES/METHODS

=over 4

=item hostlist2array

Takes a comma or space delimited file and returns an array.

=item job_info

Takes a list job ids and returns a hash of the job information

=item node_info

Return a hash of results for pbsnodes -x

=item verify_job_state

Takes a hashref of the parmeters: job_id, exp_job_state, and the optional wait_time.  The default for wait_time is 120.  The function will check the job (job_id) for an expected state (exp_job_state).  It check every second for the amount of time given (wait_time).

=item query_mom_cfg

Takes a possible mom server attribute and uses qmgr to query for that value (ie qmgr -c 'list server scheduling').  It will return the value for that attribute.

=back

=head1 DEPENDENDCIES

Moab::Test, Torque::Util::Qstat

=head1 AUTHOR(S)

Jeff Dayley <jdayley at clusterresources dot com>

=head1 COPYRIGHT

Copyright (c) 2008 Cluster Resources Inc.

=cut

__END__