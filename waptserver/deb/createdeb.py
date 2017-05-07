#!/usr/bin/python
# -*- coding: utf-8 -*-
# -----------------------------------------------------------------------
#    This file is part of WAPT
#    Copyright (C) 2013  Tranquil IT Systems http://www.tranquil.it
#    WAPT aims to help Windows systems administrators to deploy
#    setup and update applications on users PC.
#
#    WAPT is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    WAPT is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with WAPT.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------

import os,glob,sys,stat
import shutil
import fileinput
import subprocess
import platform, errno

def mkdir_p(path):
    try:
        os.makedirs(path)
    except OSError as exc:  # Python >2.5
        if exc.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else: raise

def replaceAll(file,searchExp,replaceExp):
    for line in fileinput.input(file, inplace=1):
        if searchExp in line:
            line = line.replace(searchExp,replaceExp)
        sys.stdout.write(line)

def rsync(src,dst,excludes=[]):
    rsync_option = " --exclude '*.pyc' --exclude '*~' --exclude '.svn' --exclude 'deb' --exclude '.git' --exclude '.gitignore' -aP"
    if excludes:
        rsync_option = rsync_option + ' '.join(" --exclude '%s'" % x for x in excludes)
    rsync_source = src
    rsync_destination = dst
    rsync_command = '/usr/bin/rsync %s "%s" "%s"'%(rsync_option,rsync_source,rsync_destination)
    print >> sys.stderr, rsync_command
    os.system(rsync_command)

makepath = os.path.join
from shutil import copyfile

# wapt
wapt_source_dir = os.path.abspath('../..')

# waptrepo
source_dir = os.path.abspath('..')

if platform.system()!='Linux':
    print >> sys.stderr, "this script should be used on debian linux"
    sys.exit(1)

if len(sys.argv) > 2:
    print >> sys.stderr, "wrong number of parameters (0 or 1)"
    sys.exit(1)

deb_revision = None
if len(sys.argv) >= 2:
    try:
        deb_revision = int(sys.argv[1])
        if deb_revision <= 0:
            raise Exception()
    except:
        print >> sys.stderr, "wrong parameter `%s' (should be a positive integer)" % (sys.argv[1],)
        sys.exit(1)

new_umask = 022
old_umask = os.umask(new_umask)
if new_umask != old_umask:
    print >> sys.stderr, 'umask fixed (previous %03o, current %03o)' % (old_umask, new_umask)

for line in open('%s/waptserver.py'% source_dir):
    if line.strip().startswith('__version__'):
        wapt_version = line.split('=')[1].strip().replace('"','').replace("'","")

if not wapt_version:
    print >> sys.stderr, u'version not found in %s/waptserver.py' % os.path.abspath('..')
    sys.exit(1)

control_file = './builddir/DEBIAN/control'

for filename in glob.glob("tis-waptserver*.deb"):
    print >> sys.stderr, "Removing %s"%filename
    os.remove(filename)

if os.path.exists("builddir"):
    shutil.rmtree("builddir")

print >> sys.stderr, 'creating the package tree'
mkdir_p("builddir/DEBIAN")
mkdir_p("builddir/opt/wapt/conf")
mkdir_p("builddir/opt/wapt/lib")
mkdir_p("builddir/opt/wapt/log")
mkdir_p("builddir/opt/wapt/lib/site-packages")
mkdir_p("builddir/opt/wapt/waptserver")

# for some reason the virtualenv does not build itself right if we don't have pip systemwide...
subprocess.check_output(r'sudo apt-get install -y python-virtualenv python-setuptools python-pip python-dev',shell=True)

print('Create a build environment virtualenv. May need to download a few libraries, it may take some time')
subprocess.check_output(r'virtualenv ./builddir/opt/wapt --system-site-packages',shell=True)
#subprocess.check_output(r'virtualenv ./builddir/opt/wapt --relocatable',shell=True)
#sys.exit(1)

print('Install additional libraries in build environment virtualenv')
subprocess.check_output(r'./builddir/opt/wapt/bin/pip install -r ../../requirements-server-debian.txt -t ./builddir/opt/wapt/lib/site-packages',shell=True)

print >> sys.stderr, 'copying the waptserver files'
rsync(source_dir,'./builddir/opt/wapt/',excludes=['apache-win32', 'mongodb', 'postconf', 'repository', 'rpm','uninstall-services.bat','deb'])
for lib in ('dialog.py', 'pefile.py'):
    rsync(makepath(wapt_source_dir,'lib','site-packages',lib),'./builddir/opt/wapt/lib/site-packages/')

print >> sys.stderr, 'copying control and postinst package metadata'
copyfile('./DEBIAN/control','./builddir/DEBIAN/control')
copyfile('./DEBIAN/postinst','./builddir/DEBIAN/postinst')
copyfile('./DEBIAN/preinst','./builddir/DEBIAN/preinst')
subprocess.check_output(r'find ./builddir/opt/wapt/ -type f -exec chmod 644 {} \;',shell=True)
subprocess.check_output(r'find ./builddir/opt/wapt/ -type d -exec chmod 755 {} \;',shell=True)

print >> sys.stderr, "copying the startup script /etc/init.d/waptserver"
try:
    mkdir_p('./builddir/etc/init.d/')
    copyfile('../scripts/waptserver-init','./builddir/etc/init.d/waptserver')
    subprocess.check_output('chmod 755 ./builddir/etc/init.d/waptserver',shell=True)
    subprocess.check_output('chown root:root ./builddir/etc/init.d/waptserver',shell=True)
except Exception as e:
    print >> sys.stderr, 'error: \n%s'%e
    exit(1)

print >> sys.stderr, "copying logrotate script /etc/logrotate.d/waptserver"
try:
    mkdir_p('./builddir/etc/logrotate.d/')
    shutil.copyfile('../scripts/waptserver-logrotate','./builddir/etc/logrotate.d/waptserver')
    subprocess.check_output('chown root:root ./builddir/etc/logrotate.d/waptserver',shell=True)
except Exception as e:
    print >> sys.stderr, 'error: \n%s'%e
    exit(1)

print >> sys.stderr, "copying logrotate script /etc/rsyslog.d/waptserver.conf"
try:
    mkdir_p('./builddir/etc/rsyslog.d/')
    shutil.copyfile('../scripts/waptserver-rsyslog','./builddir/etc/rsyslog.d/waptserver.conf')
    subprocess.check_output('chown root:root ./builddir/etc/rsyslog.d/waptserver.conf',shell=True)
except Exception as e:
    print >> sys.stderr, 'error: \n%s'%e
    exit(1)



print >> sys.stderr, "adding symlink for wapt-serverpostconf"
mkdir_p('builddir/usr/bin')
os.symlink('/opt/wapt/waptserver/scripts/postconf.py', 'builddir/usr/bin/wapt-serverpostconf')

print >> sys.stderr, "copying apache-related goo"
try:
    apache_dir = './builddir/opt/wapt/waptserver/apache/'
    mkdir_p(apache_dir + '/ssl')
    subprocess.check_output(['chmod', '0700', apache_dir + '/ssl'])
    copyfile('../apache-win32/conf/httpd.conf.j2', apache_dir + 'httpd.conf.j2')
except Exception as e:
    print >> sys.stderr, 'error: \n%s'%e
    exit(1)

print >> sys.stderr, 'Overriding VCS revision.'
rev_file = file('builddir/opt/wapt/revision.txt', 'w')
try:
    git_hash = subprocess.check_call(['git', 'rev-parse', '--short', 'HEAD'], stdout=rev_file)
except Exception:
    print >> sys.stderr, 'Could not retrieve the hash of the current git commit.'
    print >> sys.stderr, 'Is git(1) installed?'
    raise
rev_file.close()

deb_version = wapt_version
if deb_revision:
    deb_version += '-' + str(deb_revision)

print >> sys.stderr, 'replacing the revision in the control file'
replaceAll(control_file,'0.0.7',deb_version)

os.chmod('./builddir/DEBIAN/postinst',stat.S_IRWXU| stat.S_IXGRP | stat.S_IRGRP | stat.S_IROTH | stat.S_IXOTH)
os.chmod('./builddir/DEBIAN/preinst',stat.S_IRWXU| stat.S_IXGRP | stat.S_IRGRP | stat.S_IROTH | stat.S_IXOTH)

print >> sys.stderr, 'creating the Debian package'
output_file = 'tis-waptserver-%s.deb' % (deb_version)
dpkg_command = 'dpkg-deb --build builddir %s' % output_file
ret = os.system(dpkg_command)
status = ret >> 8
if status == 0:
    os.link(output_file, 'tis-waptserver.deb')
    shutil.rmtree("builddir")
sys.exit(status)
