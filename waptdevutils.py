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
"""
 A collection of utility python functions for WaptConsole lazarus application.

 This module is imported in waptconsole using python4delphi.

 Some tasks are easier to script in Python than to use raw Freepascal
 as common.Wapt class already implements many use full mechanisms.

 Notes :
  - This module will be less and less used as Wapconsole will use waptserver
    exported functions instead of local Wapt functions (except crypto signatures)

"""
__version__ = "1.4.3.4"

import sys,os
import shutil
import psutil
import common
import json

from setuphelpers import *
from waptutils import *
from waptpackage import *

import active_directory
import codecs
from iniparse import RawConfigParser
import getpass

from common import *
from tempfile import mkdtemp

from shutil import rmtree

create_self_signed_key = common.create_self_signed_key
is_encrypt_private_key = common.private_key_has_password
is_match_password = common.check_key_password
import tempfile

def create_wapt_setup(wapt,default_public_cert='',default_repo_url='',default_wapt_server='',destination='',company=''):
    r"""Build a customized waptsetup with provided certificate included.
    Returns filename

    >>> from common import Wapt
    >>> wapt = Wapt(config_filename=r'C:\Users\htouvet\AppData\Local\waptconsole\waptconsole.ini')
    >>> create_wapt_setup(wapt,r'C:\private\ht.crt',destination='c:\\tranquilit\\wapt\\waptsetup')
    u'c:\\tranquilit\\wapt\\waptsetup\\waptsetup.exe'
    """
    if not company:
        company = registered_organization()
    outputfile = ''
    iss_template = makepath(wapt.wapt_base_dir,'waptsetup','waptsetup.iss')
    custom_iss = makepath(wapt.wapt_base_dir,'waptsetup','custom_waptsetup.iss')
    iss = codecs.open(iss_template,'r',encoding='utf8').read().splitlines()
    new_iss=[]
    for line in iss:
        if line.startswith('#define default_repo_url'):
            new_iss.append('#define default_repo_url "%s"' % (default_repo_url))
        elif line.startswith('#define default_wapt_server'):
            new_iss.append('#define default_wapt_server "%s"' % (default_wapt_server))
        elif line.startswith('#define output_dir'):
            new_iss.append('#define output_dir "%s"' % (destination))
        elif line.startswith('#define Company'):
            new_iss.append('#define Company "%s"' % (company))
        elif line.startswith('#define install_certs'):
            new_iss.append('#define install_certs')
        elif line.startswith('WizardImageFile='):
            pass
        elif not line.startswith('#define signtool'):
            new_iss.append(line)
            if line.startswith('OutputBaseFilename'):
                outputfile = makepath(wapt.wapt_base_dir,'waptsetup','%s.exe' % line.split('=')[1])
    source = os.path.normpath(default_public_cert)
    target = os.path.join(os.path.dirname(iss_template),'..','ssl')
    if not (os.path.normcase(os.path.abspath( os.path.dirname(source))) == os.path.normcase(os.path.abspath(target))):
        filecopyto(source,target)
    codecs.open(custom_iss,'wb',encoding='utf8').write('\n'.join(new_iss))
    #inno_directory = '%s\\Inno Setup 5\\Compil32.exe' % programfiles32
    inno_directory =  makepath(wapt.wapt_base_dir,'waptsetup','innosetup','ISCC.exe')
    if not os.path.isfile(inno_directory):
        raise Exception(u"Innosetup n'est pas disponible (emplacement %s), veuillez l'installer" % inno_directory)
    run('"%s"  %s' % (inno_directory,custom_iss))
    #print('%s compiled successfully' % (outputfile, ))

    # create a sha256 file for waptupgrade package
    result = os.path.abspath(os.path.join(destination,os.path.basename(outputfile)))
    with open(makepath(wapt.wapt_base_dir,'waptupgrade','waptagent.sha256'),'wb') as f:
        f.write("%s %s\n" % (sha256_for_file(result),'waptagent.exe'))
    return result


def upload_wapt_setup(wapt,waptsetup_path, wapt_server_user, wapt_server_passwd,verify_cert=False):
    """Upload waptsetup.exe to wapt repository
    >>> wapt = common.Wapt(config_filename="c:/users/htouvet/AppData/Local/waptconsole/waptconsole.ini")
    >>> upload_wapt_setup(wapt,'c:/tranquilit/wapt/waptsetup/waptsetup.exe', 'admin', 'password')
    '{"status": "OK", "message": "waptsetup.exe uploaded"}'
    """
    auth =  (wapt_server_user, wapt_server_passwd)
    with open(waptsetup_path,'rb') as afile:
        req = requests.post("%s/upload_waptsetup" % (wapt.waptserver.server_url,),files={'file':afile},proxies=wapt.waptserver.proxies,
            verify=verify_cert,auth=auth,headers=common.default_http_headers())
        req.raise_for_status()
        res = json.loads(req.content)
    return res


def diff_computer_ad_wapt(wapt,wapt_server_user='admin',wapt_server_passwd=None):
    """Return the list of computers in the Active Directory but not registred in Wapt database

    >>> wapt = common.Wapt(config_filename=r"c:\users\htouvet\AppData\Local\waptconsole\waptconsole.ini")
    >>> diff_computer_ad_wapt(wapt)
    ???
    """
    computer_ad =  set([ c['dnshostname'].lower() for c in active_directory.search("objectClass='computer'") if c['dnshostname'] and c.operatingSystem and c.operatingSystem.startswith('Windows')])
    computer_wapt = set( [ c['host_info']['computer_fqdn'].lower() for c in  wapt.waptserver.get('api/v1/hosts?columns=host.computer_fqdn',auth=(wapt_server_user,wapt_server_passwd))['result']])
    diff = list(computer_ad-computer_wapt)
    return diff


def diff_computer_wapt_ad(wapt,wapt_server_user='admin',wapt_server_passwd=None):
    """Return the list of computers registered in Wapt database but not in the Active Directory

    >>> wapt = common.Wapt(config_filename=r"c:\users\htouvet\AppData\Local\waptconsole\waptconsole.ini")
    >>> diff_computer_wapt_ad(wapt)

    ???
    """
    computer_ad =  set([ c['dnshostname'].lower() for c in active_directory.search("objectClass='computer'") if c['dnshostname']])
    computer_wapt = set( [ c['computer_fqdn'].lower() for c in  wapt.waptserver.get('api/v1/hosts?columns=computer_fqdn',auth=(wapt_server_user,wapt_server_passwd))['result']])
    result = list(computer_wapt - computer_ad)
    return result


def update_external_repo(repourl,search_string,proxy=None,mywapt=None,newer_only=False,newest_only=False,verify_cert=True):
    """Get a list of entries from external templates public repository matching search_string
    >>> firefox = update_tis_repo(r"c:\users\htouvet\AppData\Local\waptconsole\waptconsole.ini","tis-firefox-esr")
    >>> isinstance(firefox,list) and firefox[-1].package == 'tis-firefox-esr'
    True
    """
    proxies =  {'http':proxy,'https':proxy}
    repo = WaptRepo(url=repourl,proxies=proxies)
    repo.verify_cert = verify_cert
    packages = repo.search(search_string,newest_only=newest_only)
    if mywapt and newer_only:
        my_prefix = mywapt.config.get('global','default_package_prefix')
        result = []
        for package in packages:
            if '-' in package.package:
                (prefix,name) = package.package.split('-',1)
                my_package_name = "%s-%s" % (my_prefix,name)
            else:
                my_package_name = package.package
            my_packages = mywapt.is_available(my_package_name)
            if my_packages and Version(my_packages[-1].version)<Version(package.version):
                result.append(package)
        return result
    else:
        return packages

def get_packages_filenames(waptconfigfile,packages_names,with_depends=True):
    """Returns list of package filenames (latest version) and md5 matching comma separated list of packages names and their dependencies
        helps to batch download a list of selected packages using tools like curl or wget

    Args:
        waptconfigfile (str): path to wapt ini file
        packages_names (list or csv str): list of package names

    >>> get_packages_filenames(r"c:\users\htouvet\AppData\Local\waptconsole\waptconsole.ini","tis-firefox-esr,tis-flash,tis-wapttest")
    [u'tis-firefox-esr_24.4.0-0_all.wapt', u'tis-flash_12.0.0.77-3_all.wapt', u'tis-wapttest.wapt', u'tis-wapttestsub_0.1.0-1_all.wapt', u'tis-7zip_9.2.0-15_all.wapt']
    """
    result = []
    wapt = common.Wapt(config_filename=waptconfigfile,disable_update_server_status=True)
    wapt.dbpath = r':memory:'
    wapt.use_hostpackages = False
    # force to use alternate templates repo
    repo = wapt.config.get('global','templates_repo_url')
    wapt.repositories[0].repo_url = repo if repo else 'https://store.wapt.fr/wapt'
    if wapt.use_http_proxy_for_templates:
        wapt.repositories[0].proxies =  {'http':wapt.config.get('global','http_proxy'),'https':wapt.config.get('global','http_proxy')}
    else:
        wapt.repositories[0].proxies = {'http':None,'https':None}
    # be sure to be up to date
    wapt.update(register=False, filter_on_host_cap=False)
    packages_names = ensure_list(packages_names)
    for name in packages_names:
        entries = wapt.is_available(name)
        if entries:
            pe = entries[-1]
            result.append((pe.filename,pe.md5sum,))
            if with_depends and pe.depends:
                for (fn,md5) in get_packages_filenames(waptconfigfile,pe.depends):
                    if not fn in result:
                        result.append((fn,md5,))
    return result


def duplicate_from_external_repo(waptconfigfile,package_filename,target_directory=None,authorized_certs_dir=None):
    r"""Duplicate a downloaded package to match prefix defined in waptconfigfile
       renames all dependencies
      returns source directory
    >>> from common import Wapt
    >>> wapt = Wapt(config_filename = r'C:\Users\htouvet\AppData\Local\waptconsole\waptconsole.ini')
    >>> sources = duplicate_from_external_repo(wapt.config_filename,r'C:\tranquilit\wapt\tests\packages\tis-wapttest.wapt')
    >>> res = wapt.build_upload(sources,wapt_server_user='admin',wapt_server_passwd='password')
    >>> res[0]['package'].depends
    u'test-wapttestsub,test-7zip'
    """
    wapt = common.Wapt(config_filename=waptconfigfile,disable_update_server_status=True)
    wapt.dbpath = r':memory:'
    wapt.use_hostpackages = False

    prefix = wapt.config.get('global','default_package_prefix','test')
    if not prefix:
        error('You must specify a default package prefix in WAPT Console preferences')

    def rename_package(oldname,prefix):
        sp = oldname.split('-',1)
        if len(sp) == 2:
            return "%s-%s" % (prefix,sp[-1])
        else:
            return oldname

    oldname = PackageEntry().load_control_from_wapt(package_filename).package
    newname = rename_package(oldname,prefix)

    if authorized_certs_dir is None:
        #authorized_certs = wapt.public_certs
        authorized_certs = None
    else:
        authorized_certs = glob.glob(makepath(authorized_certs_dir,'*.crt'))

    res = wapt.duplicate_package(package_filename,newname,target_directory=target_directory, build=False,auto_inc_version=True,authorized_certs = authorized_certs)
    result = res['source_dir']

    # renames dependencies
    package =  res['package']
    if package.depends:
        newdepends = []
        depends = ensure_list(package.depends)
        for dependname in depends:
            newname = rename_package(dependname,prefix)
            newdepends.append(newname)

        package.depends = ','.join(newdepends)
        package.save_control_to_wapt(result)

    # renames conflicts
    if package.conflicts:
        newconflicts = []
        conflicts = ensure_list(package.conflicts)
        for dependname in conflicts:
            newname = rename_package(dependname,prefix)
            newconflicts.append(newname)

        package.conflicts = ','.join(newconflicts)
        package.save_control_to_wapt(result)

    return result


def check_uac():
    res = uac_enabled()
    if res:
        messagebox('UAC Warning',"""The UAC (user account control) is activated on this computer.
        For Wapt package development and debugging, it is recommended to disable UAC.

        If you modify the UAC setting, you must reboot your system to take changes in account.
        """)
        shell_launch('UserAccountControlSettings.exe')

def wapt_sources_edit(wapt_sources_dir):
    """Launch pyscripter if installed, else explorer on supplied wapt sources dir"""
    psproj_filename = os.path.join(wapt_sources_dir,'WAPT','wapt.psproj')
    control_filename = os.path.join(wapt_sources_dir,'WAPT','control')
    setup_filename = os.path.join(wapt_sources_dir,'setup.py')
    pyscripter_filename = os.path.join(programfiles32,'PyScripter','PyScripter.exe')
    if os.path.isfile(pyscripter_filename) and os.path.isfile(psproj_filename):
        p = psutil.Popen('"%s" --newinstance --project "%s" "%s" "%s"' % (pyscripter_filename,psproj_filename,setup_filename,control_filename),
            cwd = os.path.join(programfiles32,'PyScripter'))
    else:
        os.startfile(wapt_sources_dir)


def edit_hosts_depends(waptconfigfile,hosts_list,
        append_depends=[],
        remove_depends=[],
        append_conflicts=[],
        remove_conflicts=[],
        key_password=None,
        wapt_server_user=None,wapt_server_passwd=None,
        authorized_certs = None
        ):
    """Add or remove packages from host packages
    >>> edit_hosts_depends('c:/wapt/wapt-get.ini','htlaptop.tranquilit.local','toto','tis-7zip','admin','password')
    """
    if not wapt_server_user:
        wapt_server_user = raw_input('WAPT Server user :')
    if not wapt_server_passwd:
        wapt_server_passwd = getpass.getpass('WAPT Server password :').encode('ascii')

    wapt = common.Wapt(config_filename=waptconfigfile,disable_update_server_status=True)
    wapt.dbpath = r':memory:'
    wapt.use_hostpackages = True
    hosts_list = ensure_list(hosts_list)
    append_depends = ensure_list(append_depends)
    remove_depends = ensure_list(remove_depends)
    append_conflicts = ensure_list(append_conflicts)
    remove_conflicts = ensure_list(remove_conflicts)

    def pwd_callback(*args):
        """Default password callback for opening private keys"""
        if not isinstance(key_password,str):
            return key_password.encode('ascii')
        else:
            return key_password

    result = []
    package_files = []
    build_res = []
    sources = []
    try:
        for host in hosts_list:
            logger.debug(u'Edit host %s : +%s -%s'%(
                host,
                append_depends,
                remove_depends))

            target_dir = tempfile.mkdtemp('wapt')
            edit_res = wapt.edit_host(host,
                use_local_sources = False,
                target_directory = target_dir,
                append_depends = append_depends,
                remove_depends = remove_depends,
                append_conflicts = append_conflicts,
                remove_conflicts = remove_conflicts,
                authorized_certs = authorized_certs,
                )
            sources.append(edit_res)
            # build and sign
            res = wapt.build_package(edit_res['source_dir'],inc_package_release = True,callback = pwd_callback)
            # returns res dict: {'filename':waptfilename,'files':[list of files],'package':PackageEntry}
            signature = wapt.sign_package(res['filename'],callback=pwd_callback)
            build_res.append(res)
            package_files.append(res['filename'])

        # upload all in one step...
        wapt.http_upload_package(package_files,wapt_server_user=wapt_server_user,wapt_server_passwd=wapt_server_passwd)

    finally:
        logger.debug('Cleanup')
        for s in sources:
            if os.path.isdir(s['source_dir']):
                shutil.rmtree(s['source_dir'])
        for s in build_res:
            if os.path.isfile(s['filename']):
                os.unlink(s['filename'])
    return build_res


def get_computer_groups(computername):
    """Try to finc the computer in the Active Directory
        and return the list of groups
    """
    groups = []
    computer = active_directory.find_computer(computername)
    if computer:
        computer_groups = computer.memberOf
        if computer_groups:
            if not isinstance(computer_groups,(tuple,list)):
                computer_groups = [computer_groups]
            for group in computer_groups:
                # extract first component of group's DN
                cn = group.split(',')[0].split('=')[1]
                groups.append(cn)
    return groups

def add_ads_groups(waptconfigfile,hosts_list,wapt_server_user,wapt_server_passwd,key_password=None):
    # initialise wapt api with local config file
    wapt = Wapt(config_filename = waptconfigfile)
    wapt.dbpath=':memory:'

    # get current packages status from repositories
    wapt.update(register=False,filter_on_host_cap=False)

    hosts_list = ensure_list(hosts_list)

    # get the collection of hosts from waptserver inventory
    all_hosts = wapt.waptserver.get('api/v1/hosts?columns=uuid,computer_fqdn,depends',auth=(wapt_server_user,wapt_server_passwd))['result']
    if hosts_list:
        hosts = [ h for h in all_hosts if h['computer_fqdn'] in hosts_list]
    else:
        hosts = hosts_list

    result = []

    for h in hosts:
        try:
            hostname = h['computer_fqdn']
            print 'Computer %s... ' % hostname,

            groups = get_computer_groups(h['computer_name'])
            wapt_groups = h['depends']
            additional = [ group for group in groups if not group in wapt_groups and wapt.is_available(group) ]

            if additional:
                # now update the host package : download and append missing packages
                tmpdir = mkdtemp()
                try:
                    package = wapt.edit_host(hostname,target_directory = tmpdir, use_local_sources=False)
                    control = package['package']
                    depends =  ensure_list(control.depends)

                    control.depends = ','.join(depends+additional)
                    control.save_control_to_wapt(package['source_dir'])
                    buid_res = wapt.build_upload(package['source_dir'], private_key_passwd = key_password, wapt_server_user=wapt_server_user,wapt_server_passwd=wapt_server_passwd,
                        inc_package_release=True)[0]
                    print("  done, new packages: %s" % (','.join(additional)))
                    if os.path.isfile(buid_res['filename']):
                        os.remove(buid_res['filename'])
                    result.append(hostname)
                finally:
                    # cleanup of temporary
                    if os.path.isdir(tmpdir):
                        rmtree(tmpdir)
        except Exception as e:
            print(" error %s" % e)
            raise

    return result

def create_waptwua_package(waptconfigfile,wuagroup='default',wapt_server_user=None,wapt_server_passwd=None,key_password=None):
    """Create/update - upload a package to enable waptwua and set windows_updates_rules
    based on the content of database.
    """
    wapt = common.Wapt(config_filename=waptconfigfile,disable_update_server_status=True)
    wapt.dbpath = r':memory:'
    wapt.use_hostpackages = False
    # be sure to be up to date
    wapt.update(register=False,filter_on_host_cap=False)
    packagename = '{}-waptwua-{}'.format(wapt.config.get('global','default_package_prefix'),wuagroup)
    """
    packages = wapt.is_available(packagename)
    if not packages:
        # creates a new package based on waptwua template
        res = wapt.make_group_template(packagename,directoryname = mkdtemp('wapt'),section='waptwua')
    else:
        res = wapt.edit_package(packagename,target_directory = mkdtemp('wapt'),use_local_sources = False)
    """
    res = wapt.make_group_template(packagename,directoryname = mkdtemp('wapt'),section='waptwua')
    build_res = wapt.build_upload(res['target'],
        private_key_passwd = key_password,
        wapt_server_user=wapt_server_user,
        wapt_server_passwd=wapt_server_passwd,
        inc_package_release=True)
    if isdir(res['target']):
        remove_tree(res['target'])
    packagefilename = build_res[0]['filename']
    if isfile(packagefilename):
        remove_file(packagefilename)
    return build_res


if __name__ == '__main__':
    import doctest
    import sys
    reload(sys)
    sys.setdefaultencoding("UTF-8")
    import doctest
    doctest.ELLIPSIS_MARKER = '???'
    doctest.testmod(optionflags=doctest.ELLIPSIS)
    sys.exit(0)
