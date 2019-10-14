#!/bin/sh
# url2ingest_wrap.sh
# This wrapper script sends an email report regarding the (wrapped) script.
#
# Copyright (c) 2014, Flinders University, South Australia. All rights reserved.
# Contributors: eResearch@Flinders, Library, Information Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
##############################################################################
PATH=/bin:/usr/bin:/usr/local/bin;  export PATH

# mailx: Space separated list of destination email addresses
email_dest_list="me@example.com you@example.com"
host=`hostname |sed 's/\..*$//'`

# This wrapper-app & wrapped-app live in the same dir.
filename_wrapper_app=`basename "$0"`
# Attempt to ensure that wrapper-app & wrapped-app cannot be the same -
# which would result in unterminated recursion below!
path_wrapped_app=`echo "$0" |sed 's/_wrap.sh.*$//; s/$/.sh/'`

app_dir=`dirname "$0"`
log_file=`cd "$app_dir"/../log && pwd`/url2ingest.log

##############################################################################
# Run the app

sh $path_wrapped_app -i --persons >> $log_file 2>&1
retval_persons=$?

sh $path_wrapped_app -i --projects >> $log_file 2>&1
retval_projects=$?

##############################################################################
# Build and send email
subject="Mint@$host: $filename_wrapper_app success"
msg_person="Ingest of zero or more Mint person records was successful."
msg_project="Ingest of zero or more Mint project records was successful."

if [ $retval_persons != 0 ]; then
  subject="Mint@$host: $filename_wrapper_app failure"
  msg_person="Ingest of Mint person records gave error code $retval_persons" 
fi
if [ $retval_projects != 0 ]; then
  subject="Mint@$host: $filename_wrapper_app failure"
  msg_project="Ingest of Mint project records gave error code $retval_projects" 
fi

cat <<-EOM_MAIL |mailx -s "$subject" $email_dest_list
		 - $msg_person
		 - $msg_project

		See $log_file for more information
	EOM_MAIL

