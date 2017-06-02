# -*- coding: utf-8 -*-
from setuphelpers import *
import os
import _winreg
import tempfile
import shutil
import hashlib
import time
import pythoncom
from win32com.taskscheduler import taskscheduler
import platform

# registry key(s) where WAPT will find how to remove the application(s)
uninstallkey = []

import types,re
class Version(object):
    """Version object of form 0.0.0
        can compare with respect to natural numbering and not alphabetical

    >>> Version('0.10.2') > Version('0.2.5')
    True
    >>> Version('0.1.2') < Version('0.2.5')
    True
    >>> Version('0.1.2') == Version('0.1.2')
    True
    """

    def __init__(self,version,members_count=None):
        if version is None:
            version = ''
        assert isinstance(version,types.ModuleType) or isinstance(version,str) or isinstance(version,unicode) or isinstance(version,Version)
        if isinstance(version,types.ModuleType):
            self.versionstring = version.__version__
        elif isinstance(version,Version):
            self.versionstring = version.versionstring
        else:
            self.versionstring = version
        self.members = [ v.strip() for v in self.versionstring.split('.')]
        if members_count is not None:
            if len(self.members)<members_count:
                self.members.extend(['0'] * (members_count-len(self.members)))
            else:
                del self.members[members_count:]

    def __cmp__(self,aversion):
        def nat_cmp(a, b):
            a = a or ''
            b = b or ''

            def convert(text):
                if text.isdigit():
                    return int(text)
                else:
                    return text.lower()

            def alphanum_key(key):
                return [convert(c) for c in re.split('([0-9]+)', key)]

            return cmp(alphanum_key(a), alphanum_key(b))

        if not isinstance(aversion,Version):
            aversion = Version(aversion)
        for i in range(0,min([len(self.members),len(aversion.members)])):
            i1,i2  = self.members[i], aversion.members[i]
            v = nat_cmp(i1,i2)
            if v:
                return v
        return 0

    def __str__(self):
        return '.'.join(self.members)

    def __repr__(self):
        return "Version('{}')".format('.'.join(self.members))

def update_control(entry):
    """Update package control file before build-upload"""
    waptget = get_file_properties(makepath('patchs','wapt-get.exe'))
    rev = open(makepath('patchs','version')).read().strip()
    entry.package = '%s-waptupgrade' % WAPT.config.get('global','default_package_prefix')
    entry.version = '%s-%s' % (waptget['FileVersion'],rev)

def update_registry_version(version):
    # updatethe registry
    with _winreg.CreateKeyEx(HKEY_LOCAL_MACHINE,r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WAPT_is1',\
            0, _winreg.KEY_READ| _winreg.KEY_WRITE ) as waptis:
        reg_setvalue(waptis,"DisplayName","WAPT %s" % version)
        reg_setvalue(waptis,"DisplayVersion","%s" % version)
        reg_setvalue(waptis,"InstallDate",currentdate())


def sha1_for_file(fname, block_size=2**20):
    f = open(fname,'rb')
    sha1 = hashlib.sha1()
    while True:
        data = f.read(block_size)
        if not data:
            break
        sha1.update(data)
    return sha1.hexdigest()


def sha256_for_file(fname, block_size=2**20):
    f = open(fname,'rb')
    sha256 = hashlib.sha256()
    while True:
        data = f.read(block_size)
        if not data:
            break
        sha256.update(data)
    return sha256.hexdigest()


def download_waptagent(waptagent_path,expected_sha256):
    if WAPT.repositories:
        for r in WAPT.repositories:
            try:
                waptagent_url = "%s/waptagent.exe" % r.repo_url
                print('Trying %s'%waptagent_url)
                print wget(waptagent_url,waptagent_path)
                wapt_agent_sha256 =  sha256_for_file(waptagent_path)
                # eefac39c40fdb2feb4aa920727a43d48817eb4df   waptagent.exe
                if expected_sha256 != wapt_agent_sha256:
                    print('Error : bad  SHA256 for the downloaded waptagent.exe\n Expected : %s \n Found : %s '%(expected_sha256,wapt_agent_sha256))
                    continue
                return waptagent_url
            except Exception as e:
                print('Error when trying %s: %s'%(r.name,e))
        error('No proper waptagent downlaoded')
    error('No repository found for the download of waptagent.exe')


def windows_version():
    """see https://msdn.microsoft.com/en-us/library/windows/desktop/ms724832(v=vs.85).aspx"""
    try:
        return Version(platform.win32_ver()[1],3)
    except:
        return Version(platform.win32_ver()[1])

# recopied here as the code in wapt < 1.3.12 is bugged in case of decode errors.
def run_notfatal(*cmd,**args):
    """Runs the command and wait for it termination, returns output
    Ignore exit status code of command, return '' instead
    """
    try:
        return run(*cmd,**args)
    except Exception as e:
        print('Warning : %s' % repr(e))
        return ''

def create_onetime_task(name,cmd,parameters=None, delay_minutes=2,max_runtime=10, retry_count=3,retry_delay_minutes=1):
    """creates a one time Windows scheduled task and activate it.
    """
    run_time = time.localtime(time.time() + delay_minutes*60)
    # task
    hour_min = time.strftime('%H:%M:%S', run_time)
    if windows_version() < '5.2':
        # for win XP
        system_account = r'"NT AUTHORITY\SYSTEM"'
    else:
        system_account = 'SYSTEM'
    try:
        return run('schtasks /Create /SC ONCE /TN "%s" /TR "\'%s\' %s" /ST %s /RU %s /F /V1 /Z' % (name,cmd,parameters,hour_min,system_account))
    except:
        # windows xp doesn't support one time startup task /Z nor /F
        run_notfatal('schtasks /Delete /TN "%s" /F'%name)
        return run('schtasks /Create /SC ONCE /TN "%s" /TR  "%s %s" /ST %s /RU %s' % (name,cmd,parameters,hour_min,system_account))


def full_waptagent_install(min_version,at_startup=False):
    # get it from
    waptagent_path = makepath(tempfile.gettempdir(),'waptagent.exe')
    waptdeploy_path = makepath(tempfile.gettempdir(),'waptdeploy.exe')
    if isfile(waptdeploy_path):
        killalltasks('waptdeploy.exe')
        killalltasks('waptagent.exe')
        remove_file(waptdeploy_path)

    filecopyto(makepath('patchs','waptdeploy.exe'),waptdeploy_path)

    expected_sha256 = open('waptagent.sha256','r').read().splitlines()[0].split()[0]
    if isfile('waptagent.exe'):
        filecopyto('waptagent.exe',waptagent_path)
    if not isfile(waptagent_path) or sha256_for_file(waptagent_path) != expected_sha256:
        download_waptagent(waptagent_path,expected_sha256)
    #create_onetime_task('fullwaptupgrade',waptagent_path,'/VERYSILENT',delay_minutes=15)

    if at_startup or isrunning('waptexit.exe'):
        cmd = '%s --hash=%s --waptsetupurl=%s --wait=15 --temporary --force --minversion=%s' %(waptdeploy_path,expected_sha256,waptagent_path,min_version)
        if not at_startup:
            print('waptexit is running, scheduling a one time task at system startup with command %s'%cmd)
        # task at system startup
        try:
            print run('schtasks /Create /RU SYSTEM /SC ONSTART /TN fullwaptupgrade /TR "%s" /F /V1 /Z' % cmd)
        except:
            # windows xp doesn't support one time startup task /Z nor /F
            run_notfatal('schtasks /Delete /TN fullwaptupgrade /F')
            print run('schtasks /Create /RU SYSTEM /SC ONSTART /TN fullwaptupgrade /TR "%s"' % cmd)
    else:
        # use embedded waptagent.exe, wait 15 minutes for other tasks to complete.
        print create_onetime_task('fullwaptupgrade',waptdeploy_path,'--hash=%s --waptsetupurl=%s --wait=15 --temporary --force --minversion=%s'%(expected_sha256,waptagent_path,min_version),delay_minutes=1)


def install():
    # if you want to modify the keys depending on environment (win32/win64... params..)
    import common
    if installed_softwares('WAPT Server_is1'):
        error('Wapt server installed on this host. Aborting')

    status = WAPT.wapt_status()
    installed_wapt_version = status['wapt-exe-version']

    # get upgrade package informations
    (package_wapt_version,package_packaging) = control.version.split('-')
    package_packaging = int(package_packaging)

    if Version(installed_wapt_version,3) > Version(package_wapt_version,3):
        print('Your current wapt (%s) is more recent than the upgrade package (%s). Skipping...'%(installed_wapt_version,control.version))
    else:
        print('Setting up upgrade from wapt version %s to %s. waptagent install planned for %s'%(installed_wapt_version,package_wapt_version,time.ctime(time.time() + 1*60)))
        full_waptagent_install(str(Version(package_wapt_version,4)))

if __name__ == '__main__':
    pass
