#!/usr/bin/python
# -*- coding: utf-8 -*-
# -----------------------------------------------------------------------
#    This file is part of WAPT-GET
#
#    TISBackup is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    TISBackup is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with TISBackup.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------

import os
import subprocess
import re
import logging
import datetime
import time
import sys
import pprint
import zipfile
import tempfile
import hashlib
import glob
import codecs
import sqlite3
import json

def datetime2isodate(adatetime = datetime.datetime.now()):
    assert(isinstance(adatetime,datetime.datetime))
    return adatetime.isoformat()

def isodate2datetime(isodatestr):
    # we remove the microseconds part as it is not working for python2.5 strptime
    return datetime.datetime.strptime(isodatestr.split('.')[0] , "%Y-%m-%dT%H:%M:%S")

def time2display(adatetime):
    return adatetime.strftime("%Y-%m-%d %H:%M")

def hours_minutes(hours):
    if hours is None:
        return None
    else:
        return "%02i:%02i" % ( int(hours) , int((hours - int(hours)) * 60.0))

def fileisodate(filename):
    return datetime.datetime.fromtimestamp(os.stat(filename).st_mtime).isoformat()

def dateof(adatetime):
    return adatetime.replace(hour=0,minute=0,second=0,microsecond=0)

#####################################
# http://code.activestate.com/recipes/498181-add-thousands-separator-commas-to-formatted-number/
# Code from Michael Robellard's comment made 28 Feb 2010
# Modified for leading +, -, space on 1 Mar 2010 by Glenn Linderman
#
# Tail recursion removed and  leading garbage handled on March 12 2010, Alessandro Forghieri
def splitThousands( s, tSep=',', dSep='.'):
    '''Splits a general float on thousands. GIGO on general input'''
    if s == None:
        return 0
    if not isinstance( s, str ):
        s = str( s )

    cnt=0
    numChars=dSep+'0123456789'
    ls=len(s)
    while cnt < ls and s[cnt] not in numChars: cnt += 1

    lhs = s[ 0:cnt ]
    s = s[ cnt: ]
    if dSep == '':
        cnt = -1
    else:
        cnt = s.rfind( dSep )
    if cnt > 0:
        rhs = dSep + s[ cnt+1: ]
        s = s[ :cnt ]
    else:
        rhs = ''

    splt=''
    while s != '':
        splt= s[ -3: ] + tSep + splt
        s = s[ :-3 ]

    return lhs + splt[ :-1 ] + rhs


def call_external_process(shell_string):
    p = subprocess.call(shell_string, shell=True)
    if (p != 0 ):
        raise Exception('shell program exited with error code ' + str(p), shell_string)

def check_string(test_string):
    pattern = r'[^\.A-Za-z0-9\-_]'
    if re.search(pattern, test_string):
        #Character other then . a-z 0-9 was found
        print 'Invalid : %r' % (test_string,)

def convert_bytes(bytes):
    if bytes is None:
        return None
    else:
        bytes = float(bytes)
        if bytes >= 1099511627776:
            terabytes = bytes / 1099511627776
            size = '%.2fT' % terabytes
        elif bytes >= 1073741824:
            gigabytes = bytes / 1073741824
            size = '%.2fG' % gigabytes
        elif bytes >= 1048576:
            megabytes = bytes / 1048576
            size = '%.2fM' % megabytes
        elif bytes >= 1024:
            kilobytes = bytes / 1024
            size = '%.2fK' % kilobytes
        else:
            size = '%.2fb' % bytes
        return size

## {{{ http://code.activestate.com/recipes/81189/ (r2)
def pptable(cursor, data=None, rowlens=0, callback=None):
    """
    pretty print a query result as a table
    callback is a function called for each field (fieldname,value) to format the output
    """
    def defaultcb(fieldname,value):
        return value

    if not callback:
        callback = defaultcb

    d = cursor.description
    if not d:
        return "#### NO RESULTS ###"
    names = []
    lengths = []
    rules = []
    if not data:
        data = cursor.fetchall()
    for dd in d:    # iterate over description
        l = dd[1]
        if not l:
            l = 12             # or default arg ...
        l = max(l, len(dd[0])) # handle long names
        names.append(dd[0])
        lengths.append(l)
    for col in range(len(lengths)):
        if rowlens:
            rls = [len(row[col]) for row in data if row[col]]
        lengths[col] = max([lengths[col]]+rls)
        rules.append("-"*lengths[col])

    format = u" ".join(["%%-%ss" % l for l in lengths])
    result = [format % tuple(names)]
    result.append(format % tuple(rules))
    for row in data:
        row_cb=[]
        for col in range(len(d)):
            row_cb.append(callback(d[col][0],row[col]))
        result.append(format % tuple(row_cb))
    return u"\n".join(result)
## end of http://code.activestate.com/recipes/81189/ }}}


def html_table(cur,callback=None):
    """
        cur est un cursor issu d'une requete
        callback est une fonction qui prend (rowmap,fieldname,value)
        et renvoie une representation texte
    """
    def safe_unicode(iso):
        if iso is None:
            return None
        elif isinstance(iso, str):
            return iso.decode('iso8859')
        else:
            return iso

    def itermap(cur):
        for row in cur:
            yield dict((cur.description[idx][0], value)
                       for idx, value in enumerate(row))

    head=u"<tr>"+"".join(["<th>"+c[0]+"</th>" for c in cur.description])+"</tr>"
    lines=""
    if callback:
        for r in itermap(cur):
            lines=lines+"<tr>"+"".join(["<td>"+str(callback(r,c[0],safe_unicode(r[c[0]])))+"</td>" for c in cur.description])+"</tr>"
    else:
        for r in cur:
            lines=lines+"<tr>"+"".join(["<td>"+safe_unicode(c)+"</td>" for c in r])+"</tr>"

    return "<table border=1  cellpadding=2 cellspacing=0>%s%s</table>" % (head,lines)



class WaptDB:
    dbpath = ''
    db = None
    logger = logging.getLogger('wapt-get')

    def __init__(self,dbpath):
        self.dbpath = dbpath

        if not os.path.isfile(self.dbpath):
            dirname = os.path.dirname(self.dbpath)
            if os.path.isdir (dirname)==False:
                os.makedirs(dirname)
            os.path.dirname(self.dbpath)
            self.db=sqlite3.connect(self.dbpath)
            self.initdb()
        else:
            self.db=sqlite3.connect(self.dbpath)

    def initdb(self):
        assert(isinstance(self.db,sqlite3.Connection))
        self.logger.debug('Initialize stat database')
        self.db.execute("""
        create table wapt_repo (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          Package varchar(255),
          Version varchar(255),
          Section varchar(255),
          Priority varchar(255),
          Architecture varchar(255),
          Maintainer varchar(255),
          Description varchar(255),
          Filename varchar(255),
          Size integer,
          MD5sum varchar(255),
          Depends varchar(800),
          repo_url varchar(255)
          )"""
                        )
        self.db.execute("""
        create index idx_package_name on wapt_repo(Package);""")

        self.db.execute("""
        create table wapt_localstatus (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          Package varchar(255),
          Version varchar(255),
          InstallDate varchar(255),
          InstallStatus varchar(255),
          InstallOutput TEXT,
          InstallParams VARCHAR(800),
          UninstallString varchar(255),
          UninstallKey varchar(255)
          )"""
                        )
        self.db.execute("""
        create index idx_localstatus_name on wapt_localstatus(Package);""")

        self.db.commit()

    def add_package(self,
                    Package='',
                    Version='',
                    Section='',
                    Priority='',
                    Architecture='',
                    Maintainer='',
                    Description='',
                    Filename='',
                    Size='',
                    MD5sum='',
                    Depends='',
                    repo_url=''):

        cur = self.db.execute("""\
              insert into wapt_repo (
                Package,
                Version,
                Section,
                Priority,
                Architecture,
                Maintainer,
                Description,
                Filename,
                Size,
                MD5sum,
                Depends,
                repo_url) values (?,?,?,?,?,?,?,?,?,?,?,?)
            """,(
                 Package,
                 Version,
                 Section,
                 Priority,
                 Architecture,
                 Maintainer,
                 Description,
                 Filename,
                 Size,
                 MD5sum,
                 Depends,
                 repo_url)
               )

        self.db.commit()
        return cur.lastrowid

    def list_repo(self,words=[]):
        words = [ "%"+w.lower()+"%" for w in words ]
        search = ["lower(Description || Package) like ?"] *  len(words)
        cur = self.db.execute("select Package,Version,Description from wapt_repo where %s" % " and ".join(search),words)
        return pptable(cur,None,1,None)

    def add_package_entry(self,package_entry):
        package_name = package_entry.Package
        cur = self.db.execute("""delete from wapt_repo where Package=?""" ,(package_name,))

        self.add_package(package_entry.Package,
                         package_entry.Version,
                         package_entry.Section,
                         package_entry.Priority,
                         package_entry.Architecture,
                         package_entry.Maintainer,
                         package_entry.Description,
                         package_entry.Filename,
                         package_entry.Size,
                         package_entry.MD5sum,
                         package_entry.Depends,
                         package_entry.repo_url)


    def add_start_install(self,package,version,params_dict={}):
        """Register the start of installation in local db"""
        try:
            cur = self.db.execute("""delete from wapt_localstatus where Package=?""" ,(package,))
            cur = self.db.execute("""\
                  insert into wapt_localstatus (
                    Package,
                    Version,
                    InstallDate,
                    InstallStatus,
                    InstallOutput,
                    InstallParams
                    ) values (?,?,?,?,?,?)
                """,(
                     package,
                     version,
                     datetime2isodate(),
                     'INIT',
                     '',
                     json.dumps(params_dict),
                   ))
        finally:
            self.db.commit()
        return cur.lastrowid

    def update_install_status(self,rowid,installstatus,installoutput,uninstallkey=None,uninstallstring=None,):
        """Update status of package installation on localdb"""
        try:
            cur = self.db.execute("""\
                  update wapt_localstatus
                    set InstallStatus=?,InstallOutput = InstallOutput || ?,UninstallKey=?,UninstallString=?
                    where rowid = ?
                """,(
                     installstatus,
                     installoutput,
                     uninstallkey,
                     uninstallstring,
                     rowid,
                     )
                   )
        finally:
            self.db.commit()
        return cur.lastrowid

    def remove_install_status(self,package):
        """Remove status of package installation from localdb"""
        try:
            cur = self.db.execute("""delete from wapt_localstatus where Package=?""" ,(package,))
        finally:
            self.db.commit()
        return cur.lastrowid

    def list_installed_packages(self,words=[],okonly=False):
        words = [ "%"+w.lower()+"%" for w in words ]
        search = ["lower(r.Description || l.Package) like ?"] *  len(words)
        if okonly:
            search.append('l.InstallStatus in ("OK","UNKNOWN")')
        cur = self.db.execute("""\
              select l.Package,l.Version,l.InstallDate,l.InstallStatus,r.Description from wapt_localstatus l
              left join wapt_repo r on l.Package=r.Package
              where %s
              order by l.Package
            """ %  (" and ".join(search) or "l.Package is not null",), words )

        def cb(fieldname,value):
            if fieldname=='InstallDate':
                return value[0:16]
            else:
                return value

        return pptable(cur,None,1,cb)

    def installed(self):
        """Return a dictionary of installed packages : keys=package names, values = package dict """
        q = self.query("""\
              select wapt_localstatus.*,wapt_repo.Filename from wapt_localstatus
                left join wapt_repo on wapt_repo.Package=wapt_localstatus.Package
              where wapt_localstatus.InstallStatus in ("OK","UNKNOWN")
              order by wapt_localstatus.Package
           """)
        result = {}
        for p in q:
            result[p['Package']]= p
        return result

    def upgradeable(self):
        """Return a dictionary of packages to upgrade : keys=package names, value = package dict"""
        q = self.query("""\
           select wapt_localstatus.*,wapt_repo.Version as NewVersion,wapt_repo.Filename from wapt_localstatus
            left join wapt_repo on wapt_repo.Package=wapt_localstatus.Package
            where wapt_localstatus.Version<wapt_repo.Version
           """)
        result = {}
        for p in q:
            result[p['Package']]= p
        return result

    def build_depends(self,packages):
        """Given a list of packages names Return a list of dependencies packages names to install"""
        MAXDEPTH = 30
        # roots : list of initial packages to avoid infinite loops
        def dodepends(explored,packages,depth):
            if depth[0]>MAXDEPTH:
                raise Exception.create('Max depth in build dependencies reached, aborting')
            depth[0] += 1
            alldepends = []
            # loop over all package names
            for package in packages:
                if not package in explored:
                    entry = self.package_entry_from_db(package)
                    # depends is a comma seperated list
                    depends = [s.strip() for s in entry.Depends.split(',') if s.strip()<>'']
                    for d in depends:
                        alldepends.extend(dodepends(explored,depends,depth))
                        if not d in alldepends:
                            alldepends.append(d)
                    explored.append(package)
            return alldepends

        explored = []
        depth =[0]
        return dodepends(explored,packages,depth)

    def package_entry_from_db(self,package,version=None):
        result = Package_Entry()
        if not version:
            entries = self.query("""select * from wapt_repo where Package = ? order by version desc""",(package,))
        else:
            entries = self.query("""select * from wapt_repo where Package = ? and version=? order by version desc""",(package,version))
        if not entries:
            raise Exception('Package %s %s not found in local DB, please update' % (package,version))
        for k,v in entries[0].iteritems():
            setattr(result,k,v)
        return result

    def query(self,query, args=(), one=False):
        """
        execute la requete query sur la db et renvoie un tableau de dictionnaires
        """
        cur = self.db.execute(query, args)
        rv = [dict((cur.description[idx][0], value)
                   for idx, value in enumerate(row)) for row in cur.fetchall()]
        return (rv[0] if rv else None) if one else rv

def md5_for_file(fname, block_size=2**20):
    f = open(fname,'rb')
    md5 = hashlib.md5()
    while True:
        data = f.read(block_size)
        if not data:
            break
        md5.update(data)
    return md5.hexdigest()

class Package_Entry:
    required_attributes = ['Package','Version','Section',]
    def __init__(self):
        self.Package=''
        self.Version=''
        self.Section=''
        self.Priority=''
        self.Architecture=''
        self.Maintainer=''
        self.Description=''
        self.Filename=''
        self.Size=''
        self.MD5sum=''
        self.Depends=''
        self.repo_url=''

    def load_control_from_wapt(self,fname ):
        """Load package attributes from the control file included in WAPT zipfile fname"""
        if os.path.isfile(fname):
            myzip = zipfile.ZipFile(fname,'r')
            control = myzip.open('WAPT/control')
            self.MD5sum = md5_for_file(fname)
            self.Size = os.path.getsize(fname)
        elif os.path.isdir(fname):
            control = open(os.path.join(fname,'WAPT','control'),'r')

        self.Filename = os.path.basename(fname)
        while 1:
            line = control.readline()
            if not line:
                break
            if line.strip()=='':
                break
            splitline = line.split(':')
            setattr(self,splitline[0].strip(),splitline[1].strip().decode('utf8'))

    def ascontrol(self):
        val = u"""\
Package      : %(Package)s
Version      : %(Version)s
Section      : %(Section)s
Priority     : %(Priority)s
Architecture : %(Architecture)s
Maintainer   : %(Maintainer)s
Description  : %(Description)s
Filename     : %(Filename)s
Size         : %(Size)s
Depends      : %(Depends)s
MD5sum       : %(MD5sum)s
"""  % self.__dict__
        return val

    def __str__(self):
        return self.ascontrol().encode('utf8')

def update_packages(adir):
    """Scan adir directory for WAPT packages and build a Packages zip file with control data and MD5 hash"""
    packages_fname = os.path.join(adir,'Packages')
    previous_packages=''
    previous_packages_mtime = 0
    if os.path.exists(packages_fname):
        try:
            print "Readind old Packages %s" % packages_fname
            previous_packages = codecs.decode(zipfile.ZipFile(packages_fname).read(name='Packages'),'utf-8')
            previous_packages_mtime = os.path.getmtime(packages_fname)
        except Exception,e:
            print 'error reading old Packages file. Reset... (%s)' % e.message

    old_entries = {}
    # we get old list to not recompute MD5 if filename has not changed
    package = Package_Entry()
    for line in previous_packages.splitlines():
        # new package
        if line.strip()=='':
            old_entries[package.Filename] = package
            package = Package_Entry()
        # add ettribute to current package
        else:
            splitline= line.split(':')
            name = splitline[0].strip()
            value = splitline[1].strip()
            setattr(package,name,value)

    # last one
    if package.Filename:
        old_entries[package.Filename] = package

    if not os.path.isdir(adir):
        raise Exception('%s is not a directory' % (adir))

    waptlist = glob.glob(os.path.join(adir,'*.wapt'))
    packages = []
    for fname in waptlist:
        if os.path.basename(fname) in old_entries:
            print "  Keeping %s" % fname
            entry = old_entries[os.path.basename(fname)]
        else:
            print "  Processing %s" % fname
            entry = Package_Entry()
            entry.load_control_from_wapt(fname)
        packages.append(entry.ascontrol().encode('utf8'))

    print "Writing new %s" % packages_fname
    myzipfile = zipfile.ZipFile(packages_fname, "w")
    #myzipfile.writestr("Packages",'\n'.join(packages),compress_type=zipfile.ZIP_DEFLATED)
    myzipfile.writestr("Packages",'\n'.join(packages))
    myzipfile.close()

if __name__ == '__main__':
    logger = logging.getLogger('wapt-db')
    logger.setLevel(logging.DEBUG)
    formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    waptdb = WaptDB(dbpath='c:/wapt/db/waptdb.sqlite')

