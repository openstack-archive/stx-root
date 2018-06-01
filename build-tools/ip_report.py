#!/usr/bin/python

import csv
import os
import rpm
import shutil
import subprocess
import sys
import getopt


class BinPackage(object):
    def __init__(self, path, ts):
        fdno = os.open(path, os.O_RDONLY)
        hdr = ts.hdrFromFdno(path)
        os.close(fdno)

        self.source = hdr[rpm.RPMTAG_SOURCERPM]
        self.desc = hdr[rpm.RPMTAG_DESCRIPTION].replace('\n', ' ')
        self.dirname = os.path.dirname(path)
        self.filename = os.path.basename(path)
        self.path = path
        self.kernel_module = False
        self.name = hdr[rpm.RPMTAG_NAME]

        # Does the package contain kernel modules?
        for filename in hdr[rpm.RPMTAG_BASENAMES]:
            assert isinstance(filename, basestring)
            if filename.endswith('.ko'):
                self.kernel_module = True
                break


class SrcPackage(object):
    def __init__(self, path=None):
        self.bin_pkg = None
        self.original_src = None
        self.sha = 'SHA'
        if path is None:
            self.filename = None
            self.path = None
        else:
            self.filename = os.path.basename(path)
            self.path = path
            ts = rpm.TransactionSet()
            ts.setVSFlags(rpm._RPMVSF_NODIGESTS | rpm._RPMVSF_NOSIGNATURES)
            fdno = os.open(self.path, os.O_RDONLY)
            hdr = ts.hdrFromFdno(self.path)
            os.close(fdno)
            self.desc = hdr[rpm.RPMTAG_DESCRIPTION].replace('\n', ' ')
            self.version = hdr[rpm.RPMTAG_VERSION] + '-' + hdr[rpm.RPMTAG_RELEASE]
            self.licences = hdr[rpm.RPMTAG_LICENSE]
            self.name = hdr[rpm.RPMTAG_NAME]
            self.url = hdr[rpm.RPMTAG_URL]

        self.modified = None
        self.kernel_module = False
        self.disclosed_by = 'Jason McKenna'
        self.shipped_as = 'Binary'
        self.origin = 'Unknown'
        self.notes = ''
        self.wrs = False

    def __lt__(self, other):
        me = self.name.lower()
        them = other.name.lower()
        if me == them:
            return self.name < other.name
        else:
            return me < them


class IPReport(object):
    __KNOWN_PATHS = [
        # CentOS 7.4
        ['/import/mirrors/CentOS/7.4.1708/os/Source/SPackages',
         'http://vault.centos.org/7.4.1708/os/Source/SPackages'],
        ['/import/mirrors/CentOS/vault.centos.org/7.4.1708/updates/Source/SPackages',
         'http://vault.centos.org/7.4.1708/updates/Source/SPackages'],
        ['/import/mirrors/CentOS/vault.centos.org/7.4.1708/cloud/Source/openstack-newton/common',
         'http://vault.centos.org/7.4.1708/cloud/Source/openstack-newton/common'],
        ['/import/mirrors/CentOS/vault.centos.org/7.4.1708/cloud/Source/openstack-newton',
         'http://vault.centos.org/7.4.1708/cloud/Source/openstack-newton'],
        ['/import/mirrors/CentOS/vault.centos.org/7.4.1708/cloud/Source/openstack-mitaka/common',
         'http://vault.centos.org/7.4.1708/cloud/Source/openstack-mitaka/common'],
        ['/import/mirrors/CentOS/vault.centos.org/7.4.1708/cloud/Source/openstack-mitaka',
         'http://vault.centos.org/7.4.1708/cloud/Source/openstack-mitaka'],
        ['/import/mirrors/CentOS/7.4.1708/extras/Source/SPackages',
         'http://vault.centos.org/7.4.1708/extras/Source/SPackages'],
        # CentOS 7.3
        ['/import/mirrors/CentOS/7.3.1611/os/Source/SPackages',
         'http://vault.centos.org/7.3.1611/os/Source/SPackages'],
        ['/import/mirrors/CentOS/vault.centos.org/7.3.1611/updates/Source/SPackages',
         'http://vault.centos.org/7.3.1611/updates/Source/SPackages'],
        ['/import/mirrors/CentOS/vault.centos.org/7.3.1611/cloud/Source/openstack-newton/common',
         'http://vault.centos.org/7.3.1611/cloud/Source/openstack-newton/common'],
        ['/import/mirrors/CentOS/vault.centos.org/7.3.1611/cloud/Source/openstack-newton',
         'http://vault.centos.org/7.3.1611/cloud/Source/openstack-newton'],
        ['/import/mirrors/CentOS/vault.centos.org/7.3.1611/cloud/Source/openstack-mitaka/common',
         'http://vault.centos.org/7.3.1611/cloud/Source/openstack-mitaka/common'],
        ['/import/mirrors/CentOS/vault.centos.org/7.3.1611/cloud/Source/openstack-mitaka',
         'http://vault.centos.org/7.3.1611/cloud/Source/openstack-mitaka'],
        ['/import/mirrors/CentOS/7.3.1611/extras/Source/SPackages',
         'http://vault.centos.org/7.3.1611/extras/Source/SPackages'],
        # CentOS 7.2
        ['/import/mirrors/CentOS/7.2.1511/os/Source/SPackages', 'http://vault.centos.org/7.2.1511/os/Source/SPackages'],
        ['/import/mirrors/CentOS/vault.centos.org/7.2.1511/updates/Source/SPackages',
         'http://vault.centos.org/7.2.1511/updates/Source/SPackages'],
        ['/import/mirrors/CentOS/vault.centos.org/7.2.1511/cloud/Source/openstack-mitaka/common',
         'http://vault.centos.org/7.2.1511/cloud/Source/openstack-mitaka/common'],
        ['/import/mirrors/CentOS/vault.centos.org/7.2.1511/cloud/Source/openstack-mitaka',
         'http://vault.centos.org/7.2.1511/cloud/Source/openstack-mitaka'],
        ['/import/mirrors/CentOS/7.2.1511/extras/Source/SPackages',
         'http://vault.centos.org/7.2.1511/extras/Source/SPackages'],
        ['/import/mirrors/CentOS/tis-r4-CentOS/newton/Source', 'Unknown'],
        ['/import/mirrors/CentOS/tis-r4-CentOS/tis-r4-3rd-Party', 'Unknown']

        ]

    def __init__(self, workspace=None, repo=None):
        self.workspace = None
        self.repo = None
        self.shipped_binaries = list()
        self.built_binaries = list()
        self.check_env()
        if workspace is not None:
            self.workspace = workspace
        if repo is not None:
            self.repo = repo

        # Generate a list of binaries that we shipped
        for filename in os.listdir(self.workspace + '/export/dist/isolinux/Packages'):
            if filename.endswith('rpm'):
                self.shipped_binaries.append(filename)

        # Generate a list of binaries that we built ourselves
        for build in ['rt', 'std']:
            for filename in os.listdir(self.workspace + '/' + build + '/rpmbuild/RPMS/'):
                if filename.endswith('rpm'):
                    self.built_binaries.append(filename)

        print ('Looking up packages for which we have source...')
        self.original_src_pkgs = dict()
        self.build_original_src_pkgs()
        print ('Looking up packages we built...')
        self.built_src_pkgs = dict()
        self.build_built_src_pkgs()
        print ('Looking up packages we built...')
        self.hardcoded_lookup_dict = dict()
        self.build_hardcoded_lookup_dict()

    def build_hardcoded_lookup_dict(self):
        with open(self.repo + '/build-tools/source_lookup.txt', 'r') as lookup_file:
            for line in lookup_file:
                line = line.rstrip()
                words = line.split()
                if (words is not None) and (len(words) >= 2):
                    self.hardcoded_lookup_dict[words[1]] = (words[0], False)

        with open(self.repo + '/build-tools/wrs_orig.txt', 'r') as lookup_file:
            for line in lookup_file:
                line = line.rstrip()
                words = line.split()
                if (words is not None) and (len(words) >= 1):
                    self.hardcoded_lookup_dict[words[0]] = ('No download', True)

    @staticmethod
    def path_to_origin(filepath):
        for path in IPReport.__KNOWN_PATHS:
            if filepath.startswith(path[0]) and (not path[1].lower().startswith('unknown')):
                return path[1] + '/' + os.path.basename(filepath)
        return 'Unknown'

    def hardcoded_lookup(self, package_name):
        if package_name in self.hardcoded_lookup_dict.keys():
            return self.hardcoded_lookup_dict[package_name]
        return None, False

    def check_env(self):
        if 'MY_WORKSPACE' in os.environ:
            self.workspace = os.environ['MY_WORKSPACE']
        else:
            print 'Could not find $MY_WORKSPACE'
            raise IOError('Could not fine $MY_WORKSPACE')

        if 'MY_REPO' in os.environ:
            self.repo = os.environ['MY_REPO']
        else:
            print 'Could not find $MY_REPO'
            raise IOError('Could not fine $MY_REPO')

    def do_bin_pkgs(self):
        print ('Gathering binary package information')
        self.read_bin_pkgs()

    def read_bin_pkgs(self):
        self.bin_pkgs = list()
        ts = rpm.TransactionSet()
        ts.setVSFlags(rpm._RPMVSF_NODIGESTS | rpm._RPMVSF_NOSIGNATURES)
        for filename in self.shipped_binaries:
            if filename.endswith('rpm'):
                bin_pkg = BinPackage(self.workspace + '/export/dist/isolinux/Packages/' + filename, ts)
                self.bin_pkgs.append(bin_pkg)

    def do_src_report(self, copy_packages=False, do_wrs=True, delta_file=None, output_path=None, strip_unchanged=False):
        self.bin_to_src()
        self.src_pkgs.sort()

        if delta_file is not None:
            self.delta(delta_file)

        if output_path is None:
            output_path = self.workspace + '/export/ip_report'

        # Create output dir (if required)
        if not os.path.exists(output_path):
            os.makedirs(output_path)

        # Create paths for RPMs (if required)
        if copy_packages:
            if not os.path.exists(output_path + '/non_wrs'):
                shutil.rmtree(output_path + '/non_wrs', True)
                os.makedirs(output_path + '/non_wrs')
            if do_wrs:
                shutil.rmtree(output_path + '/wrs', True)
                os.makedirs(output_path + '/wrs')

        with open(output_path + '/srcreport.csv', 'wb') as src_report_file:
            src_report_writer = csv.writer(src_report_file)

            # Write header row
            src_report_writer.writerow(
                ['Package File', 'File Name', 'Package Name', 'Version', 'SHA1', 'Disclosed By',
                 'Description', 'Part Of (Runtime, Host, Both)', 'Modified (Yes, No)', 'Hardware Interfacing (Yes, No)',
                 'License(s) Found', 'Package Download URL', 'Kernel module', 'Notes'])

            for src_pkg in self.src_pkgs:
                if src_pkg.modified:
                    modified_string = 'Yes'
                else:
                    modified_string = 'No'
                if src_pkg.kernel_module:
                    kmod_string = 'Yes'
                else:
                    kmod_string = 'No'

                # Copy the pacakge and get the SHA
                if copy_packages:
                    if src_pkg.wrs is False:
                        shutil.copyfile(src_pkg.path, output_path + '/non_wrs/' + src_pkg.filename)
                        shasumout = subprocess.check_output(
                            ['shasum', output_path + '/non_wrs/' + src_pkg.filename]).split()[0]
                        src_pkg.sha = shasumout
                        if strip_unchanged and (src_pkg.notes.lower().startswith('unchanged')):
                            os.remove(output_path + '/non_wrs/' + src_pkg.filename)
                    else:
                        if do_wrs:
                            shutil.copyfile(src_pkg.path, output_path + '/wrs/' + src_pkg.filename)
                            shasumout = subprocess.check_output(
                                ['shasum', output_path + '/wrs/' + src_pkg.filename]).split()[0]
                            src_pkg.sha = shasumout
                            if strip_unchanged and (src_pkg.notes.lower().startswith('unchanged')):
                                os.remove(output_path + '/wrs/' + src_pkg.filename)

                if do_wrs or (src_pkg.wrs is False):
                    src_report_writer.writerow(
                        [src_pkg.filename, src_pkg.name, src_pkg.version, src_pkg.sha, src_pkg.disclosed_by,
                         src_pkg.desc, 'Runtime', src_pkg.shipped_as, modified_string, 'No', src_pkg.licences,
                         src_pkg.origin, kmod_string, src_pkg.notes])
                    if 'unknown' in src_pkg.origin.lower():
                        print (
                        'Warning: Could not determine origin of ' + src_pkg.name + '.  Please investigate/populate manually')

    def bin_to_src(self):
        self.src_pkgs = list()
        src_pkg_names = list()
        for bin_pkg in self.bin_pkgs:
            if src_pkg_names.__contains__(bin_pkg.source):
                if bin_pkg.kernel_module:
                    for src_pkg in self.src_pkgs:
                        if src_pkg.filename == bin_pkg.source:
                            src_pkg.kernel_module = True
                            break

                continue

            # if we reach here, then the source package is not yet in our db.
            # we first search for the source package in the built-rpms
            if 'shim-signed' in bin_pkg.source:
                for tmp in self.built_src_pkgs:
                    if 'shim-signed' in tmp:
                        print ('shim-signed hack -- ' + bin_pkg.source + ' to ' + tmp)
                        bin_pkg.source = tmp
                        break
            if 'shim-unsigned' in bin_pkg.source:
                for tmp in self.built_src_pkgs:
                    if 'shim-0' in tmp:
                        print ('shim-unsigned hack -- ' + bin_pkg.source + ' to ' + tmp)
                        bin_pkg.source = tmp
                        break
            if 'grub2-efi-pxeboot' in bin_pkg.source:
                for tmp in self.built_src_pkgs:
                    if 'grub2-2' in tmp:
                        print ('grub2-efi-pxeboot hack -- ' + bin_pkg.source + ' to ' + tmp)
                        bin_pkg.source = tmp
                        break

            if bin_pkg.source in self.built_src_pkgs:
                src_pkg = self.built_src_pkgs[bin_pkg.source]
                src_pkg.modified = True

                # First guess, we see if there's an original source with the source package name
                # (this is 99% of the cases)
                src_pkg_orig_name = src_pkg.name
                if src_pkg_orig_name in self.original_src_pkgs:
                    src_pkg.original_src = self.original_src_pkgs[src_pkg_orig_name]
                    src_pkg.origin = src_pkg.original_src.origin

            else:
                src_pkg_path = self.locate_in_mirror(bin_pkg.source)
                if not os.path.isabs(src_pkg_path):
                    continue
                src_pkg = SrcPackage(src_pkg_path)
                src_pkg.origin = IPReport.path_to_origin(src_pkg_path)
                src_pkg.modified = False

            if bin_pkg.kernel_module:
                src_pkg.kernel_module = True

            src_pkg_names.append(bin_pkg.source)
            self.src_pkgs.append(src_pkg)

            if src_pkg.origin.lower() == 'unknown':
                if 'windriver' in src_pkg.licences.lower():
                    src_pkg.origin = 'No download'
                else:
                    if src_pkg.url is not None:
                        src_pkg.origin = src_pkg.url

            if 'unknown' in src_pkg.origin.lower():
                (orig, is_wrs) = self.hardcoded_lookup(src_pkg.name)
                if orig is not None:
                    src_pkg.origin = orig
                    src_pkg.wrs = is_wrs

            if (src_pkg.origin.lower() == 'no download') and ('windriver' in src_pkg.licences.lower()):
                src_pkg.wrs = True

    def locate_in_mirror(self, filename):
        """ takes an RPM filename and finds the full path of the file """

        fullpath = None

        filename = filename.replace('mirror:', self.repo + '/cgcs-centos-repo/')
        filename = filename.replace('repo:', self.repo + '/')
        filename = filename.replace('3rd_party:', self.repo + '/cgcs-3rd-party-repo/')

        # At this point, filename could be a complete path (incl symlink), or just a filename
        best_guess = filename
        filename = os.path.basename(filename)

        for path in IPReport.__KNOWN_PATHS:
            if os.path.exists(path[0] + '/' + filename):
                fullpath = path[0] + '/' + filename
                break

        if fullpath is not None:
            return fullpath
        else:
            return best_guess

    def build_original_src_pkgs(self):
        for root, dirs, files in os.walk(self.repo):
            for name in files:
                if name == 'srpm_path':
                    with open(os.path.join(root, 'srpm_path'), 'r') as srpm_path_file:
                        original_srpm_file = srpm_path_file.readline().rstrip()
                        original_src_pkg_path = self.locate_in_mirror(original_srpm_file)
                        original_src_pkg = SrcPackage(original_src_pkg_path)
                        original_src_pkg.origin = IPReport.path_to_origin(original_src_pkg_path)
                        self.original_src_pkgs[original_src_pkg.name] = original_src_pkg

    def build_built_src_pkgs(self):
        """ Create a dict of any source package that we built ourselves """
        for build in ['std', 'rt']:
            for root, dirs, files in os.walk(self.workspace + '/' + build + '/rpmbuild/SRPMS'):
                for name in files:
                    if name.endswith('.src.rpm'):
                        built_src_pkg = SrcPackage(os.path.join(root, name))
                        self.built_src_pkgs[built_src_pkg.filename] = built_src_pkg

    def delta(self, orig_report):
        if orig_report is None:
            return
        delta_src_pkgs = self.read_last_report(orig_report)

        for pkg in self.src_pkgs:
            if pkg.name in delta_src_pkgs:
                old_pkg = delta_src_pkgs[pkg.name]
                if old_pkg.version == pkg.version:
                    pkg.notes = 'Unchanged'
                else:
                    pkg.notes = 'New version'
            else:
                pkg.notes = 'New package'

    def read_last_report(self, orig_report):
        orig_pkg_dict = dict()
        with open(orig_report, 'rb') as orig_report_file:
            orig_report_reader = csv.reader(orig_report_file)
            doneHeader = False
            for row in orig_report_reader:
                if (not doneHeader) and ('package file name' in row[0].lower()):
                    doneHeader = True
                    continue
                doneHeader = True
                orig_pkg = SrcPackage()
                orig_pkg.filename = row[0]
                orig_pkg.name = row[1]
                orig_pkg.version = row[2]
                # sha = row[3]
                orig_pkg.disclosed_by = row[4]
                orig_pkg.desc = row[5]
                # runtime = row[6]
                orig_pkg.shipped_as = row[7]
                if row[8].lower is 'yes':
                    orig_pkg.modified = True
                else:
                    orig_pkg.modifed = False
                # hardware interfacing = row[9]
                orig_pkg.licences = row[10]
                orig_pkg.origin = row[11]
                if row[12].lower is 'yes':
                    orig_pkg.kernel_module = True
                else:
                    orig_pkg.kernel_module = False
                orig_pkg_dict[orig_pkg.name] = orig_pkg

        return orig_pkg_dict


def main(argv):
    # handle command line arguments
    # -h/--help       -- help
    # -n/--no-copy    -- do not copy files (saves time)
    # -d/--delta=     -- compare with an ealier report
    # -o/--output=    -- output report/binaries to specified path
    # -w/--workspace= -- use specified workspace instead of $WORKSPACE
    # -r/--repo=      -- use sepeciied repo instead of $MY_REPO
    # -s              -- strip (remove) unchanged packages from copy out directory

    try:
        opts, args = getopt.getopt(argv, "hnd:o:w:r:s",
                                   ["delta=", "help", "no-copy", "workspace=", "repo=", "output=", "--strip"])
    except getopt.GetoptError:
        # todo - output help
        sys.exit(2)
    delta_file = None
    do_copy = True
    workspace = None
    repo = None
    output_path = None
    strip_unchanged = False

    for opt, arg in opts:
        if opt in ('-h', '--help'):
            print 'usage:'
            print ' ip_report.py [options]'
            print ' Creates and IP report in $MY_WORKSPACE/export/ip_report '
            print ' Source RPMs (both Wind River and non WR) are placed in subdirs within that path'
            print ''
            print 'Options:'
            print '  -h/--help                - this help'
            print '  -d <file>/--delta=<file> - create "notes" field, comparing report with a previous report'
            print '  -n/--no-copy             - do not copy files into subdirs (this is faster, but means you'
            print '                             don\'t get SHA sums for files)'
            print '  -w <path>/--workspace=<path> - use the specified path as workspace, instead of $MY_WORKSPACE'
            print '  -r <path>/--repo=<path>  - use the specified path as repo, instead of $MY_REPO'
            print '  -o <path>/--output=<path> - output to specified path (instead of $MY_WORKSPACE/export/ip_report)'
            print '  -s/--strip               - strip (remove) unchanged files if copied'
            exit()
        elif opt in ('-d', '--delta'):
            delta_file = os.path.normpath(arg)
            delta_file = os.path.expanduser(delta_file)
            if not os.path.exists(delta_file):
                print 'Cannot locate ' + delta_file
                exit(1)
        elif opt in ('-w', '--workspace'):
            workspace = os.path.normpath(arg)
            workspace = os.path.expanduser(workspace)
        elif opt in ('-r', '--repo'):
            repo = os.path.normpath(arg)
            repo = os.path.expanduser(repo)
        elif opt in ('-o', '--output'):
            output_path = os.path.normpath(arg)
            output_path = os.path.expanduser(output_path)
        elif opt in ('-n', '--no-copy'):
            do_copy = False
        elif opt in ('-s', '--strip-unchanged'):
            strip_unchanged = True

    print ('Doing IP report')
    if delta_file is not None:
        print 'Delta from ' + delta_file
    else:
        print 'No delta specified'
    ip_report = IPReport(workspace=workspace, repo=repo)

    ip_report.do_bin_pkgs()
    ip_report.do_src_report(copy_packages=do_copy,
                            delta_file=delta_file,
                            output_path=output_path,
                            strip_unchanged=strip_unchanged)


if __name__ == "__main__":
    main(sys.argv[1:])
