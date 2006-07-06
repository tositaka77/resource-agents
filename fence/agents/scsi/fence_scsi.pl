#!/usr/bin/perl

use Getopt::Std;
use IPC::Open3;
use POSIX;

my $verbose = 0;
my @volumes;

$_ = $0;
s/.*\///;
my $pname = $_;

# WARNING!! Do not add code bewteen "#BEGIN_VERSION_GENERATION" and
# "#END_VERSION_GENERATION"  It is generated by the Makefile
                                                                                
#BEGIN_VERSION_GENERATION
$FENCE_RELEASE_NAME="";
$REDHAT_COPYRIGHT="";
$BUILD_DATE="";
#END_VERSION_GENERATION

sub usage
{
    print "Usage\n";
    print "\n";
    print "$pname [options]\n";
    print "\n";
    print "Options\n";
    print "  -n <node>        IP address or hostname of node to fence\n";
    print "  -h               usage\n";
    print "  -V               version\n";
    print "  -v               verbose\n";

    exit 0;
}

sub version
{
    print "$pname $FENCE_RELEASE_NAME $BUILD_DATE\n";
    print "$REDHAT_COPYRIGHT\n" if ( $REDHAT_COPYRIGHT );

    exit 0;
}

sub fail
{
    ($msg)=@_;

    print $msg."\n" unless defined $opt_q;

    exit 1;
}

sub fail_usage
{
    ($msg)=@_;

    print STDERR $msg."\n" if $msg;
    print STDERR "Please use '-h' for usage.\n";

    exit 1;
}

sub get_key
{
    ($node)=@_;

    my $addr = gethostbyname($node) or die "$!\n";

    return unpack("H*", $addr);
}

sub get_options_stdin
{
    my $opt;
    my $line = 0;

    while (defined($in = <>))
    {
	$_ = $in;
	chomp;

	# strip leading and trailing whitespace
	s/^\s*//;
	s/\s*$//;

	# skip comments
	next if /^#/;

	$line += 1;
	$opt = $_;

	next unless $opt;

	($name, $val) = split /\s*=\s/, $opt;

	if ($name eq "")
	{
	    print STDERR "parse error: illegal name in option $line\n";
	    exit 2;
	}
	elsif ($name eq "agent")
	{
	}
	elsif ($name eq "node")
	{
	    $opt_n = $val;
	}
	elsif ($name eq "verbose")
	{
	    $opt_v = $val;
	}
	else
	{
	    fail "parse error: unknown option \"$opt\"";
	}
    }
}

sub get_scsi_devices
{
    my ($in, $out, $err);
    my $cmd = "lvs --noheadings --separator : -o vg_attr,devices";
    my $pid = open3($in, $out, $err, $cmd) or die "$!\n";

    waitpid($pid, 0);

    die "Unable to execute lvs.\n" if ($?>>8);

    while (<$out>)
    {
	chomp;
	print "OUT: $_\n" if $opt_v;

	my ($vg_attrs, $device) = split /:/, $_, 3;

	if ($vg_attrs =~ /.*c$/)
	{
	    $device =~ s/\(.*\)//;
	    push @volumes, $device;
	}
    }

    close($in);
    close($out);
    close($err);
}

sub check_sg_persist
{
    my ($in, $out, $err);
    my $cmd = "sg_persist -V";
    my $pid = open3($in, $out, $err, $cmd) or die "$!\n";

    waitpid($pid, 0);

    die "Unable to execute sg_persist.\n" if ($?>>8);

    while (<$out>)
    {
	chomp;
	print "OUT: $_\n" if $opt_v;
    }

    close($in);
    close($out);
    close($err);
}

sub fence_node
{
    my $name = (POSIX::uname())[1];

    my $host_key = get_key($name);
    my $node_key = get_key($opt_n);
    
    my $cmd;
    my ($in, $out, $err);

    foreach $dev (@volumes)
    {
	if ($host_key eq $node_key)
	{
	    $cmd = "sg_persist -d $dev -o -G -K $host_key -S 0";
	}
	else
	{
	    $cmd = "sg_persist -d $dev -o -A -K $host_key -S $node_key -T 5";
	}

	my $pid = open3($in, $out, $err, $cmd) or die "$!\n";

	waitpid($pid, 0);

	if ($opt_v)
	{
	    print "$cmd\n";
	    while (<$out>)
	    {
		chomp;
		print "OUT: $_\n";
	    }
	}

	die "Unable to execute sg_persist.\n" if ($?>>8);

	close($in);
	close($out);
	close($err);
    }
}

### MAIN #######################################################

if (@ARGV > 0) {

    getopts("n:hqvV") || fail_usage;

    usage if defined $opt_h;
    version if defined $opt_V;

    fail_usage "Unkown parameter." if (@ARGV > 0);
    fail_usage "No '-n' flag specified." unless defined $opt_n;

} else {

    get_options_stdin();

    fail "failed: missing 'node'" unless defined $node;

}

check_sg_persist;

get_scsi_devices;

fence_node;
