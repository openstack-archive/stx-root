#!/usr/bin/perl

# Copy/pasted from http://www.smorgasbork.com/content/gather_packages.txt
# As referenced by http://www.smorgasbork.com/2012/01/04/building-a-custom-centos-7-kickstart-disc-part-2/

use XML::Simple;

my ($comps_file, $rpm_src_path, $rpm_dst_path, $arch, @extra_groups_and_packages) = @ARGV;

if (!-e $comps_file)
{
    print_usage ("Can't find '$comps_file'");
}
if (!-e $rpm_src_path)
{
    print_usage ("RPM source path '$rpm_src_path' does not exist");
}
if (!-e $rpm_dst_path)
{
    print_usage ("RPM destination path '$rpm_dst_path' does not exist");
}
if (!$arch)
{
    print_usage ("Architecture not specified");
}

#### we always gather core and base; note that for CentOS 7, we also need
#### to include the grub2 package, or installation will fail
@desired_groups = ('core', 'base', 'grub2');
foreach (@extra_groups_and_packages)
{
    push (@desired_groups, $_);
}

$regex = '^(' . join ('|', @desired_groups) . ')$';

print "reading $comps_file...\n";
print "getting RPMs from $rpm_src_path...\n";

$xml = new XML::Simple;
$comps = $xml->XMLin($comps_file);

$cmd = "rm $rpm_dst_path/*";
print "$cmd\n";
`$cmd`;

%copied_groups = {};
%copied_packages = {};

foreach $group (@{$comps->{group}})
{
    $id = $group->{id};
    if ($id !~ m#$regex#)
    {
        next;
    }

    print "#### group \@$id\n";
    $packagelist = $group->{packagelist};
    foreach $pr (@{$packagelist->{packagereq}})
    {
        if ($pr->{type} eq 'optional' || $pr->{type} eq 'conditional')
        {
            next;
        }

        $cmd = "cp $rpm_src_path/" . $pr->{content} . "-[0-9]*.$arch.rpm"
                . " $rpm_src_path/" . $pr->{content} . "-[0-9]*.noarch.rpm $rpm_dst_path";
        print "$cmd\n";
        `$cmd 2>&1`;

        $copied_packages{$pr->{content}} = 1;
    }

    $copied_groups{$group} = 1;
}

#### assume that any strings that weren't matched in the comps file's group list
#### are actually packages

foreach $group (@desired_groups)
{
    if ($copied_groups{$group})
    {
        next;
    }

    $cmd = "cp $rpm_src_path/" . $group . "-[0-9]*.$arch.rpm"
            . " $rpm_src_path/" . $group . "-[0-9]*.noarch.rpm $rpm_dst_path";
    print "$cmd\n";
    `$cmd 2>&1`;
}

sub print_usage
{
    my ($msg) = @_;

    ($msg) && print "$msg\n\n";

    print <<__TEXT__;

parse_comps.pl comps_file rpm_src_path arch [xtra_grps_and_pkgs]

    comps_file           the full path to the comps.xml file (as provided 
                         in the original distro

    rpm_src_path         the full path to the directory of all RPMs from 
                         the distro

    rpm_dst_path         the full path to the directory where you want
                         to save the RPMs for your kickstart

    arch                 the target system architecture (e.g. x86_64)

    xtra_grps_and_pkgs   a list of extra groups and packages, separated by spaces


__TEXT__

    exit;
}

