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
import platform

def replaceAll(file,searchExp,replaceExp):
    for line in fileinput.input(file, inplace=1):
        if searchExp in line:
            line = line.replace(searchExp,replaceExp)
        sys.stdout.write(line)


if platform.system()!='Linux':
    print "this script should be used on debian linux"
    sys.exit(1)

for line in open('%s/waptserver.py'%os.path.abspath('..')):
    if '__version__=' in line:
        wapt_version = line.split('=')[1].replace('"','').replace("'","").replace('\n','').replace(' ','')
if not wapt_version:
    print 'version non trouvée dans %s/waptserver.py, la version est mise a 1 par défault.'%os.path.abspath('..')
    wapt_version = '1'

control_file = './builddir/DEBIAN/control'
rsync_option = "--exclude '*.svn' --exclude '*.exe' --exclude '*.dll' --exclude 'deb' -ap"
rsync_source = os.path.abspath('..')
rsync_destination = './builddir/opt/wapt/'
rsync_command = '/usr/bin/rsync %s %s %s'%(rsync_option,rsync_source,rsync_destination)

rsync_lib_source = '%s/'%os.path.abspath('../../lib/')
rsync_lib_destination = './builddir/opt/wapt/lib/'
rsync_lib_option = "--exclude '*.svn' --exclude 'deb' -ap"
rsync_lib_command = '/usr/bin/rsync %s %s %s'%(rsync_lib_option,rsync_lib_source,rsync_lib_destination)


for filename in glob.glob("tis-waptserver*.deb"):
    print "destruction de %s"%filename
    os.remove(filename)
if os.path.exists("builddir"):
    shutil.rmtree("builddir")
print 'création de l\'arborescence'
os.makedirs("builddir")
os.makedirs("builddir/DEBIAN")
os.makedirs("builddir/opt")
os.makedirs("builddir/opt/wapt")
os.makedirs("builddir/opt/wapt/lib")
os.makedirs("builddir/opt/wapt/waptserver")

#adding version info in VERSION file
rev=''
output = subprocess.check_output('/usr/bin/svn info',shell=True)
for line in output.split('\n'):
    if 'Revision:' in line:
        rev = 'rev%s' % line.split(':')[1].strip()
version_file = open(os.path.join('./builddir/opt/wapt/waptserver','VERSION'),'w')
version_file.write(rev)
version_file.close()

print 'copy waptserver files'
os.system(rsync_command)
os.system(rsync_lib_command)

print 'copie des fichiers control et postinst'
try:
    shutil.copyfile('./DEBIAN/control','./builddir/DEBIAN/control')
except Exception as e:
    print 'erreur: \n%s'%e
    exit (0)
try:
    shutil.copyfile('./DEBIAN/postinst','./builddir/DEBIAN/postinst')
except Exception as e:
    print 'erreur: \n%s'%e
    exit(0)

try:
    shutil.copyfile('./DEBIAN/preinst','./builddir/DEBIAN/preinst')
except Exception as e:
    print 'erreur: \n%s'%e
    exit(0)
print 'inscription de la version dans le fichier de control'
replaceAll(control_file,'0.0.7',wapt_version + '-' + rev)

print 'création du paquet Deb'
os.chmod('./builddir/DEBIAN/postinst',stat.S_IRWXU| stat.S_IXGRP | stat.S_IRGRP | stat.S_IROTH | stat.S_IXOTH)
os.chmod('./builddir/DEBIAN/preinst',stat.S_IRWXU| stat.S_IXGRP | stat.S_IRGRP | stat.S_IROTH | stat.S_IXOTH)


dpkg_command = 'dpkg-deb --build builddir tis-waptserver-%s-%s.deb'% (wapt_version ,rev)
os.system(dpkg_command)
shutil.rmtree("builddir")
