#!/usr/bin/python

import sys

FN=sys.argv[1]
variables={}
variables['config_opts']={}
execfile( FN, variables )
print variables['config_opts']['yum.conf']
