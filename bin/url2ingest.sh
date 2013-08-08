#!/bin/sh
# Usage:  url2ingest.sh --persons|--projects [ --full-load|--incremental-load ]
#   or use short options:
#     -e = --person
#     -r = --projects
#     -f = --full-load
#     -i = --incremental-load
#
# Copyright (c) 2013, Flinders University, South Australia. All rights reserved.
# Contributors: eResearch@Flinders, Library, Information Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
# 
##############################################################################
# Purpose:
# - To retrieve the specified file from a URL
# - To ingest/harvest/load the file into the appropriate Mint data source
#
# Important points:
#
# 1) For loading party-person metadata, the script assumes there is a symlink
# pointing from Mint home/data/Parties_People.csv (or whatever is defined
# under harvester>csv>fileLocation in Mint home/harvest/Parties_People.json)
# to $PERSON_FILTERED_FPATH. You must create this symlink manually before
# running this script.
#
# This is important because Mint assumes the same ID field (ie. key)
# in a different filename is a different record. Hence the symlink
# allows us to potentially vary $PERSON_FILTERED_FPATH filename while
# still retaining the same "fileLocation" in home/harvest/Parties_People.json.
#
# For example, if $MINT_BASE/home/harvest/Parties_People.json contains the line:
#   "fileLocation": "${fascinator.home}/data/Parties_People.csv",
# then you should set the following variable below:
#   PERSON_MINT_DATA_SOURCE=Parties_People
# and you should create the symlink:
#   ln -s $PERSON_FILTERED_FPATH $MINT_BASE/home/data/Parties_People.csv
# where MINT_BASE & PERSON_FILTERED_FPATH are assigned below (and
# ${fascinator.home} is assigned within the Mint environment).
#
# 2) For loading activity-project metadata, the same symlink requirement
# applies to the CSV file (assuming you have configured a local data source
# for loading projects at your institution as documented at URL
# http://www.redboxresearchdata.com.au/documentation/system-administration/administering-mint/loading-data/loading-activity-data).
#
# 3) This script can be run from a Unix/Linux cron job.
# Eg.
#   15 20 * * * (app=$HOME/opt/url2ingest/bin/url2ingest.sh; $app --persons; $app --projects) >> $HOME/opt/url2ingest/log/url2ingest.log 2>&1
#
##############################################################################
PATH=/bin:/usr/bin:/usr/local/bin; export PATH
APP=`basename $0`

WGET_OPTS="--no-verbose"	# wget args
LN_OPTS="-sf"			# ln args: Force the update of a symlink
PS_OPTS="-afe"			# ps args: PID in 2nd field & full command (including args)

MINT_BASE=/opt/ands/mint-builds/current		## CUSTOMISE: Set to Mint base dir
TF_HARVEST_LOG=$MINT_BASE/home/logs/harvest.out
TF_HARVEST_LOG_ERROR_REGEX="error|fail|exception"	# Regex to detect errors in $TF_HARVEST_LOG
TF_SERVER_DIR=$MINT_BASE/server
TF_HARVEST_BIN=tf_harvest.sh
MINT_PID_FPATH=$TF_SERVER_DIR/tf.pid

VERBOSE=1	# 1=Verbose mode on. Other (eg. 0) = Verbose mode off
DRY_RUN=0	# 1=Do not execute commands (limited use as many commands omitted). Other (eg. 0) = Normal execution.

# Global vars
## CUSTOMISE: Set to base dir of (this) URL2INGEST app. In other words,
## set this variable so that this script will live in dir $PARENT_DIR/bin.
PARENT_DIR=$HOME/opt/url2ingest
DOWNLOAD_DIR=$PARENT_DIR/download
DOWNLOAD_HISTORY_DIR=$DOWNLOAD_DIR/history
TEMP_DIR=$PARENT_DIR/working

LOG_DIR=$PARENT_DIR/log
HARVEST_LOG_ACCUM=$LOG_DIR/harvest_out_accum.log

##############################################################################
# People vars
##############################################################################
## CUSTOMISE: Source URL of CSV file (to be loaded into Mint)
PERSON_IN_URL_CSV=http://my_host.my_uni.edu.au/path/to/my_people.csv
## CUSTOMISE: The Mint data source which will be loaded via the TF_HARVEST_BIN script
PERSON_MINT_DATA_SOURCE=Parties_People
# The filename of the CSV file *after* being downloaded from the URL
PERSON_DOWNLOADED_FNAME=people.csv
PERSON_DOWNLOADED_FPATH=$DOWNLOAD_DIR/$PERSON_DOWNLOADED_FNAME
# The path to the CSV file *after* filtering (and after incremental
# Processing if applicable).
# IMPORTANT: You MUST create a symlink to this path from your Data Source
# as described in the opening comments.
PERSON_FILTERED_FPATH=$TEMP_DIR/filtered_$PERSON_DOWNLOADED_FNAME
PERSON_FILTER_CONFIG_FPATH=$PARENT_DIR/etc/include_filter_people.conf

##############################################################################
# Project vars
##############################################################################
## CUSTOMISE: Source URL of CSV file (to be loaded into Mint)
PROJECT_IN_URL_CSV=http://my_host.my_uni.edu.au/path/to/my_projects.csv
## CUSTOMISE: The Mint data source which will be loaded via the TF_HARVEST_BIN script
PROJECT_MINT_DATA_SOURCE=Activities_Mis_Projects
# The filename of the CSV file *after* being downloaded from the URL
PROJECT_DOWNLOADED_FNAME=projects.csv
PROJECT_DOWNLOADED_FPATH=$DOWNLOAD_DIR/$PROJECT_DOWNLOADED_FNAME
# The path to the CSV file *after* filtering (and after incremental
# Processing if applicable).
# IMPORTANT: You MUST create a symlink to this path from your Data Source
# as described in the opening comments.
PROJECT_FILTERED_FPATH=$TEMP_DIR/filtered_$PROJECT_DOWNLOADED_FNAME
PROJECT_FILTER_CONFIG_FPATH=$PARENT_DIR/etc/include_filter_project.conf

##############################################################################
# echo_timestamp(msg) -- Echo with timestamp
##############################################################################
echo_timestamp() {
  echo "`date +%F\ %T` -- $1"
}

##############################################################################
dump_exit() {
  echo
  echo "Below is a dump of some of the 'interesting' variables for this script."

  # Each line in this string shall contain the following 2 strings:
  # - First field is a string suffix (delimited by whitespace). When a prefix
  #   string (eg. "PERSON") is prepended it will form a shell variable name
  #   (eg. "PERSON_IN_URL_CSV").
  # - The second field consists of 0 or more words describing the purpose
  #   of the shell variable. A newline can be added to the string by using
  #   the character sequence \\\\n (ie. 4 backslashes '\' before 'n').
  suffices="
    _IN_URL_CSV		Source URL from which to download the CSV file.
    _DOWNLOADED_FPATH	Temporary file location where downloaded file will be placed for processing.
    _MINT_DATA_SOURCE	Mint Data-Source name. This is the argument when running ./tf_harvest.sh.
    _FILTERED_FPATH	Temporary file location where the (final) filtered file will be placed while ingesting\\\\n  it's records into Mint. A symlink from the Data-Source's 'fileLocation' MUST point here.\\\\n  This file will only exist during run-time.
    _FILTER_CONFIG_FPATH	Path to the 'inclusive-filter' configuration file which allows you\\\\n  to write regular expressions (one per line) defining records to include in the\\\\n  CSV file to be ingested into Mint. Records which do not match will not be included.\\\\n  You must ensure that the header line of the CSV file is also matched.
  "

  # Iterate through potential command-line options (from which we will derive prefices).
  for opt in --persons --projects; do
    echo
    echo "For the $opt option:"
    prefix=`echo "$opt" |sed 's/^--//; s/s$//' |tr a-z A-Z`

    echo "$suffices" |
      while read suffix descr; do
        if [ ! -z "$suffix" ]; then
          var="$prefix$suffix"		# A shell var
          cmd="echo \"\$$var\""		# Command to show the shell var's value
          val=`eval $cmd`		# The value
          #echo
          echo -e "* $descr"
          echo "    $var=\"$val\""
        fi
      done

  done
  exit 0
}

##############################################################################
# usage_exit(msg) -- Display specified message, then usage-message, then exit
##############################################################################
usage_exit() {
  msg="$1"
  echo_timestamp "$msg"
  echo_timestamp "Usage:  $APP --persons|--projects|--dump|--help [ --full-load|--incremental-load ]"
  echo_timestamp "  or use short options: -e=--persons; -r=--projects; -f=--full-load; -i=--incremental-load"
  echo_timestamp "                        -d=--dump; -h=--help"
  echo_timestamp "Dump shows you some 'interesting' script variables to assist with configuration."
  exit 1
}

##############################################################################
# get_cli_option(cli_args) -- Return the command line options
# - copt_data_source	= --persons|--projects
# - copt_full_incr	= --full-load|--incremental-load
##############################################################################
get_cli_option() {
  copt_data_source=''		# Mandatory command switch (has no default value)
  copt_full_incr='--full-load'	# Default value for optional command switch

  while [ $# -gt 0 ] ; do
    case "$1" in
      --persons | -e )
        copt_data_source=--persons
        shift
        ;;

      --projects | -r )
        copt_data_source=--projects
        shift
        ;;

      --full-load | -f )
        copt_full_incr=--full-load
        shift
        ;;

      --incremental-load | -i )
        copt_full_incr=--incremental-load
        shift
        ;;

      --dump | -d)
        dump_exit
        ;;

      --help | -h)
        usage_exit
        ;;

      *)
        usage_exit "Invalid option '$1'"
    esac
  done
  [ -z "$copt_data_source" ] && usage_exit "You must use one of the mandatory command options."
}

##############################################################################
# get_data_source_vars() -- Get variables related to the specified data source
##############################################################################
get_data_source_vars() {
  opt="$1"
  if [ "$opt" = --persons ]; then
    IN_URL_CSV=$PERSON_IN_URL_CSV
    MINT_DATA_SOURCE=$PERSON_MINT_DATA_SOURCE
    DOWNLOADED_FNAME=$PERSON_DOWNLOADED_FNAME
    DOWNLOADED_FPATH=$PERSON_DOWNLOADED_FPATH
    FILTERED_FPATH=$PERSON_FILTERED_FPATH
    FILTER_CONFIG_FPATH=$PERSON_FILTER_CONFIG_FPATH
  elif [ "$opt" = --projects ]; then
    IN_URL_CSV=$PROJECT_IN_URL_CSV
    MINT_DATA_SOURCE=$PROJECT_MINT_DATA_SOURCE
    DOWNLOADED_FNAME=$PROJECT_DOWNLOADED_FNAME
    DOWNLOADED_FPATH=$PROJECT_DOWNLOADED_FPATH
    FILTERED_FPATH=$PROJECT_FILTERED_FPATH
    FILTER_CONFIG_FPATH=$PROJECT_FILTER_CONFIG_FPATH
  else
    usage_exit "Unexpected option '$opt'"
  fi
  DOWNLOAD_HISTORY_FPATH=$DOWNLOAD_HISTORY_DIR/$DOWNLOADED_FNAME

  SORTED_PREVIOUS=$TEMP_DIR/sort_prev_$DOWNLOADED_FNAME
  SORTED_THIS=$TEMP_DIR/sort_this_$DOWNLOADED_FNAME
  NEW_RECORDS_BODY=$TEMP_DIR/incr_body_$DOWNLOADED_FNAME
  NEW_RECORDS_FULL=$TEMP_DIR/incr_$DOWNLOADED_FNAME
  NEW_RECORDS_FULL_BASENAME=`basename $NEW_RECORDS_FULL`
  trap cleanup EXIT
}

##############################################################################
# setup() -- Initial setup
##############################################################################
setup() {
  [ $DRY_RUN = 1 ] && return
  for dir in $DOWNLOAD_DIR $DOWNLOAD_HISTORY_DIR $LOG_DIR $TEMP_DIR; do
    [ ! -d $dir ] && mkdir -p $dir
  done
}

##############################################################################
# verify_mint_is_running() -- Verify that Mint is running. If not,
#   display a message then exit. If this function returns to the caller
#   then Mint appears to be running.
##############################################################################
verify_mint_is_running() {
  if [ ! -f "$MINT_PID_FPATH" ]; then
    echo_timestamp "Mint does not appear to be running: File '$MINT_PID_FPATH' not found"
    exit 4
  fi

  if [ ! -r "$MINT_PID_FPATH" ]; then
    echo_timestamp "Unable to verify if Mint is running: File '$MINT_PID_FPATH' not readable"
    exit 4
  fi

  pid=`cat "$MINT_PID_FPATH"`
  if ! ps $PS_OPTS |egrep "^[^ ]{1,}[ ]{1,}$pid .* java .*\-Dfascinator\.home=" >/dev/null; then
    echo_timestamp "Mint does not appear to be running: PID '$pid' (from '$MINT_PID_FPATH') does not appear to be a java/fascinator process"
    exit 4
  fi
}

##############################################################################
# do_command(cmd, is_show_cmd, msg) -- Execute a shell command
##############################################################################
# - If msg is not empty, write it to stdout else do not.
# - If is_show_cmd==1, write command 'cmd' to stdout else do not.
# - Execute command 'cmd'
do_command() {
  cmd="$1"
  is_show_cmd=$2
  msg="$3"

  [ "$msg" != "" ] && echo_timestamp "$msg"
  [ $is_show_cmd = 1 ] && echo_timestamp "Command: $cmd"
  if [ $DRY_RUN = 1 ]; then
    echo_timestamp "DRY RUN: Not executing the above command."
  else
    eval $cmd
    retval=$?
    if [ $retval -ne 0 ]; then
      echo_timestamp "Error returned by command (ErrNo: $retval)" >&2
      exit $retval
    fi
  fi
}

##############################################################################
# Load records from CSV file
##############################################################################
load_csv() {
  # Before performing ingest, ensure we have at least 1 header record + 1 data record
  if [ `grep -c ^.. "$FILTERED_FPATH"` -le 1 ]; then
    echo_timestamp "There are no (filtered) records to be loaded"
  else
    cmd="cd $TF_SERVER_DIR && ./$TF_HARVEST_BIN $MINT_DATA_SOURCE"
    do_command "$cmd" $VERBOSE "Load metadata file into Mint. Data source: $MINT_DATA_SOURCE"
    is_load_csv_done=1

    if egrep -i "$TF_HARVEST_LOG_ERROR_REGEX" $TF_HARVEST_LOG >/dev/null; then
      echo_timestamp "Mint harvest ERROR detected by regex /$TF_HARVEST_LOG_ERROR_REGEX/ in file $TF_HARVEST_LOG"
    else
      is_load_csv_successful=1
    fi
  fi
}

##############################################################################
# load_incremental_csv(): Only load new/changed records from CSV file
#   (compared to previous CSV file)
##############################################################################
load_incremental_csv() {
  copt_data_source=$1
  timestamp=$2
  this_fname=$DOWNLOADED_FPATH

  # Find previous CSV file (for comparison)
  # Assumes filenames are sorted by $timestamp (appended to filename)
  prev_fname=`ls -1 $DOWNLOAD_HISTORY_FPATH.* |tail -1`
  if [ -z "$prev_fname" ]; then
    echo_timestamp "Cannot perform incremental-load of CSV because no (previous) file found matching:"
    echo_timestamp "  $DOWNLOAD_HISTORY_FPATH.*"
    exit 2
  fi
  [ $DRY_RUN = 1 ] && return

  # Confirm header lines in both CSV files are identical
  head -1 $prev_fname > $SORTED_PREVIOUS
  head -1 $this_fname > $SORTED_THIS
  if [ "`md5sum < $SORTED_PREVIOUS`" != "`md5sum < $SORTED_THIS`" ]; then
    echo_timestamp "Cannot perform incremental-load of CSV because the header line of the 2 files below are different:"
    echo_timestamp "* File: $this_fname"
    echo_timestamp "  with header: `cat $SORTED_THIS`"
    echo_timestamp "* File: $prev_fname"
    echo_timestamp "  with header: `cat $SORTED_PREVIOUS`"
    exit 3
  fi

  # Find new records
  sort $prev_fname > $SORTED_PREVIOUS
  sort $this_fname > $SORTED_THIS
  comm -23 $SORTED_THIS $SORTED_PREVIOUS > $NEW_RECORDS_BODY
  if [ -s "$NEW_RECORDS_BODY" ]; then
    echo_timestamp "Creating `wc -l < $NEW_RECORDS_BODY` new or updated records in incremental file $NEW_RECORDS_FULL"
    head -1 $this_fname > $NEW_RECORDS_FULL
    cat $NEW_RECORDS_BODY >> $NEW_RECORDS_FULL
    cmd="egrep -f \"$FILTER_CONFIG_FPATH\" \"$NEW_RECORDS_FULL\" > \"$FILTERED_FPATH\""
    do_command "$cmd" $VERBOSE "Apply inclusive filter to incremental records"
    load_csv

    # Backup the incremental CSV file
    type=`echo "$copt_data_source" |tr -d '-'`
    dest=$DOWNLOAD_HISTORY_DIR/${type}_$NEW_RECORDS_FULL_BASENAME.$timestamp
    cmd="mv -f $NEW_RECORDS_FULL $dest"
    do_command "$cmd" $VERBOSE "Backup the incremental metadata file to $dest"
  else
    echo_timestamp "There are no new or updated records to be loaded"
  fi
}

##############################################################################
# cleanup(): Cleanup files on-exit
# Assumes the list of files to be deleted have already been set.
##############################################################################
cleanup() {
  # In general, $DOWNLOADED_FPATH & $FILTERED_FPATH will only need to be
  # deleted if the script gets a signal midway though its execution or
  # when incremental-loading or filtering results in no records for loading.
  cmd="cd $TEMP_DIR && rm -f $SORTED_PREVIOUS $SORTED_THIS $NEW_RECORDS_BODY $NEW_RECORDS_FULL $FILTERED_FPATH $DOWNLOADED_FPATH $FILTERED_FPATH"
  do_command "$cmd" $VERBOSE "Cleaning up files"
}

##############################################################################
# Main
##############################################################################
get_cli_option $@
echo
echo_timestamp "Starting $APP $copt_data_source $copt_full_incr"
get_data_source_vars "$copt_data_source"

setup
verify_mint_is_running	# Cannot ingest metadata unless Mint is running. If Mint not running, incremental metadata may be missed forever!
is_load_csv_done=0
is_load_csv_successful=0
timestamp=`date +%y%m%d-%H%M%S`

cmd="wget -O $DOWNLOADED_FPATH $WGET_OPTS $IN_URL_CSV"
do_command "$cmd" $VERBOSE "Download metadata file from $IN_URL_CSV"

if [ "$copt_full_incr" = --full-load ]; then
  cmd="egrep -f \"$FILTER_CONFIG_FPATH\" \"$DOWNLOADED_FPATH\" > \"$FILTERED_FPATH\""
  do_command "$cmd" $VERBOSE "Apply inclusive filter to original/full records"
  load_csv
else
  load_incremental_csv $copt_data_source $timestamp
fi

# Only keep backup of info loaded into Mint if load was successful.
# Particularly important for incremental load (so any new/updated
# records in this ingest are not missed next time if this ingest
# fails) as the most recent backup is used for comparison for the
# next incremental load.
if [ "$is_load_csv_successful" = 1 ]; then
  dest=$DOWNLOAD_HISTORY_FPATH.$timestamp
  cmd="mv -f $DOWNLOADED_FPATH $dest"
  do_command "$cmd" $VERBOSE "Backup the full metadata file to $dest"
fi

# The Mint rewrites $TF_HARVEST_LOG (ie. does not append) for each run.
# Hence we will append a copy here.
if [ "$is_load_csv_done" = 1 ]; then
  cmd="(echo; echo_timestamp \"[$APP $copt_data_source $copt_full_incr] Appending Mint harvest log...\"; cat $TF_HARVEST_LOG) >> $HARVEST_LOG_ACCUM"
  do_command "$cmd" $VERBOSE "Append Mint harvest log to $HARVEST_LOG_ACCUM"
fi

