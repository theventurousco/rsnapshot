#!/usr/bin/perl -w

##############################################################################
# rsnapshot-diff
# by David Cantrell <david@cantrell.org.uk>
#
# This program calculates the differences between two directories. It is
# designed to work with two different subdirectories under the rsnapshot
# snapshot_root. For example:
#
#   rsnapshot-diff /.snapshots/daily.0/ /.snapshots/daily.1/
#
# http://www.rsnapshot.org/
##############################################################################

# $Id: rsnapshot-diff.pl,v 1.2 2005/07/24 18:48:58 scubaninja Exp $

use strict;

use constant DEBUG => 0;
use Getopt::Std;

my $program_name = 'rsnapshot-diff';

my %opts;
my $verbose = 0;
my $ignore = 0;

my $result = getopts('vVhi', \%opts);

# help
if ($opts{'h'}) {
    print qq{
    $program_name [-vVhi] dir1 dir2

    $program_name shows the differences between two 'rsnapshot' backups.

    -h    show this help
    -v    be verbose
    -V    be more verbose (mutter about unchanged files)
    -i    ignore symlinks, directories, and special files in verbose output
    dir1  the first directory to look at
    dir2  the second directory to look at

    if you want to look at directories called '-h' or '-v' pass a
    first parameter of '--'.

    $program_name always show the changes made starting from the older
    of the two directories.
};
	exit;
}

# verbose
if ($opts{'v'}) { $verbose = 1; }

# extra verbose
if ($opts{'V'}) { $verbose = 2; }

# ignore
if ($opts{'i'}) { $ignore = 1; }


if(!exists($ARGV[1]) || !-d $ARGV[0] || !-d $ARGV[1]) {
    die("$program_name\nUsage: $program_name [-vVhi] dir1 dir2\nType $program_name -h for details\n");
}

my($dirold, $dirnew) = @ARGV;
($dirold, $dirnew) = ($dirnew, $dirold) if(-M $dirold < -M $dirnew);
print "Comparing $dirold to $dirnew\n";

my($addedfiles, $addedspace, $deletedfiles, $deletedspace) = (0, 0, 0, 0);

compare_dirs($dirold, $dirnew);

print "Between $dirold and $dirnew:\n";
print "  $addedfiles were added, taking $addedspace bytes;\n";
print "  $deletedfiles were removed, saving $deletedspace bytes;\n";

sub compare_dirs {
    my($old, $new) = @_;

    opendir(OLD, $old) || die("Can't open dir $old\n");
    opendir(NEW, $new) || die("Can't open dir $new\n");
    my %old = map {
        my $fn = $old.'/'.$_;
        ($_, (mystat($fn))[1])
    } grep { $_ ne '.' && $_ ne '..' } readdir(OLD);
    my %new = map {
        my $fn = $new.'/'.$_;
        ($_, (mystat($fn))[1])
    } grep { $_ ne '.' && $_ ne '..' } readdir(NEW);
    closedir(OLD);
    closedir(NEW);

    my @added = grep { !exists($old{$_}) } keys %new;
    my @deleted = grep { !exists($new{$_}) } keys %old;
    my @changed = grep { !-d $new.'/'.$_ && exists($old{$_}) && $old{$_} != $new{$_} } keys %new;

    add(map { $new.'/'.$_ } @added, @changed);
    remove(map { $old.'/'.$_ } @deleted, @changed);

    if($verbose == 2) {
        my %changed = map { ($_, 1) } @changed, @added, @deleted;
        print "0 $new/$_\n" foreach(grep { !-d "$new/$_" && !exists($changed{$_}) } keys %new);
    }
    
    foreach (grep { !-l $new.'/'.$_ && !-l $old.'/'.$_ && -d $new.'/'.$_ && -d $old.'/'.$_ } keys %new) {
        print "Comparing subdirs $new/$_ and $old/$_ ...\n" if(DEBUG);
        compare_dirs($old.'/'.$_, $new.'/'.$_);
    }
}

sub add {
    my @added = @_;
    print "Adding ".join(', ', @added)."\n" if(DEBUG && @added);
    foreach(grep { !-d } @added) {
        $addedfiles++;
        $addedspace += (mystat($_))[7];
        # if ignore is on, only print files
        unless ($ignore && (-l || !-f)) {
            print "+ $_\n" if($verbose);
        }
    }
    foreach my $dir (grep { !-l && -d } @added) {
        opendir(DIR, $dir) || die("Can't open dir $dir\n");
        add(map { $dir.'/'.$_ } grep { $_ ne '.' && $_ ne '..' } readdir(DIR))
    }
}

sub remove {
    my @removed = @_;
    print "Removing ".join(', ', @removed)."\n" if(DEBUG && @removed);
    foreach(grep { !-d } @removed) {
        $deletedfiles++;
        $deletedspace += (mystat($_))[7];
        # if ignore is on, only print files
        unless ($ignore && (-l || !-f)) {
            print "- $_\n" if($verbose);
        }
    }
    foreach my $dir (grep { !-l && -d } @removed) {
        opendir(DIR, $dir) || die("Can't open dir $dir\n");
        remove(map { $dir.'/'.$_ } grep { $_ ne '.' && $_ ne '..' } readdir(DIR))
    }
}

{
    my $device;

    sub mystat {
        local $_ = shift;
        my @stat = (-l) ? lstat() : stat();

        # on first stat, memorise device
        $device = $stat[0] unless(defined($device));
        die("Can't compare across devices.\n(looking at $_)\n")
            unless($device == $stat[0] || -p $_);

        return @stat;
    }
}
