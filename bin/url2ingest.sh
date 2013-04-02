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
# Assumption:
#   For loading party-person metadata, the script assumes there is a symlink
# pointing from Mint home/data/Parties_People.csv (or whatever is defined
# under harvester>csv>fileLocation in Mint home/harvest/Parties_People.json)
# to $TARGET_SOURCE_PATH.
#   This is important because Mint assumes the same ID field (ie. key)
# in a different filename is a different record. Hence the symlink
# allows us to potentially vary $TARGET_SOURCE_PATH filename while
# still retaining the same "fileLocation" in home/harvest/Parties_People.json.
#   For loading activity-project metadata, the same symlink requirement
# applies to the CSV file (assuming you have configured a local data source
# for loading projects at your institution as documented at URL
# http://www.redboxresearchdata.com.au/documentation/system-administration/administering-mint/loading-data/loading-activity-data).
#
# This script can be run from a Unix/Linux cron job.
# Eg.
#   15 20 * * * (app=$HOME/url2ingest/bin/url2ingest.sh; $app --persons; $app --projects) >> $HOME/url2ingest/log/url2ingest.log 2>&1
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
MINT_PID_PATH=$TF_SERVER_DIR/tf.pid

VERBOSE=1	# 1=Verbose mode on. Other (eg. 0) = Verbose mode off
DRY_RUN=0	# 1=Do not execute commands (limited use as many commands omitted). Other (eg. 0) = Normal execution.

# Global vars
## CUSTOMISE: Set to base dir of (this) URL2INGEST app. This script will live in dir $PARENT_DIR/bin.
PARENT_DIR=$HOME/url2ingest
DOWNLOAD_DIR=$PARENT_DIR/download
DOWNLOAD_HISTORY_DIR=$DOWNLOAD_DIR/history

LOG_DIR=$PARENT_DIR/log
HARVEST_LOG_ACCUM=$LOG_DIR/harvest_out_accum.log

TEMP_DIR=$PARENT_DIR/working
SORTED_PREVIOUS=$TEMP_DIR/sort_prev.csv
SORTED_THIS=$TEMP_DIR/sort_this.csv
NEW_RECORDS_BODY=$TEMP_DIR/incr_body.csv
NEW_RECORDS_FULL=$TEMP_DIR/incr.csv
NEW_RECORDS_FULL_BASENAME=`basename $NEW_RECORDS_FULL`

## CUSTOMISE: If person & project CSV files are located at the same parent URL,
##   you can set the parent URL here & use it below for *_IN_URL_CSV vars.
PARENT_IN_URL_CSV=http://my_host.my_uni.edu.au/my_source_of_truth_csv_dir

# People vars
## CUSTOMISE: The Mint data source which will be loaded via the TF_HARVEST_BIN script
PERSON_MINT_DATA_SOURCE=Parties_People
## CUSTOMISE: The Mint CSV file which will be downloaded from the URL
PERSON_SOURCE_FNAME=people.csv
## CUSTOMISE: Source URL of CSV file (to be loaded into Mint)
PERSON_IN_URL_CSV=$PARENT_IN_URL_CSV/$PERSON_SOURCE_FNAME
PERSON_TARGET_SOURCE_PATH=$DOWNLOAD_DIR/target_$PERSON_SOURCE_FNAME

# Project vars
## CUSTOMISE: The Mint data source which will be loaded via the TF_HARVEST_BIN script
PROJECT_MINT_DATA_SOURCE=Activities_Mis_Projects
## CUSTOMISE: The Mint CSV file which will be downloaded from the URL
PROJECT_SOURCE_FNAME=projects.csv
## CUSTOMISE: Source URL of CSV file (to be loaded into Mint)
PROJECT_IN_URL_CSV=$PARENT_IN_URL_CSV/$PROJECT_SOURCE_FNAME
PROJECT_TARGET_SOURCE_PATH=$DOWNLOAD_DIR/target_$PROJECT_SOURCE_FNAME

##############################################################################
# echo_timestamp(msg) -- Echo with timestamp
##############################################################################
echo_timestamp() {
  echo "`date +%F\ %T` -- $1"
}

##############################################################################
# usage_exit(msg) -- Display specified message, then usage-message, then exit
##############################################################################
usage_exit() {
  msg="$1"
  echo_timestamp "$msg"
  echo_timestamp "Usage:  $APP --persons|--projects [ --full-load|--incremental-load ]"
  echo_timestamp "  or use short options: -e=--persons; -r=--projects; -f=--full-load; -i=--incremental-load"
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

      --help | -help | -h)
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
    MINT_DATA_SOURCE=$PERSON_MINT_DATA_SOURCE
    SOURCE_FNAME=$PERSON_SOURCE_FNAME
    IN_URL_CSV=$PERSON_IN_URL_CSV
    TARGET_SOURCE_PATH=$PERSON_TARGET_SOURCE_PATH
  elif [ "$opt" = --projects ]; then
    MINT_DATA_SOURCE=$PROJECT_MINT_DATA_SOURCE
    SOURCE_FNAME=$PROJECT_SOURCE_FNAME
    IN_URL_CSV=$PROJECT_IN_URL_CSV
    TARGET_SOURCE_PATH=$PROJECT_TARGET_SOURCE_PATH
  else
    usage_exit "Unexpected option '$opt'"
  fi
  #TARGET_SOURCE_PATH=$DOWNLOAD_DIR/target_$SOURCE_FNAME
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
  if [ ! -f "$MINT_PID_PATH" ]; then
    echo_timestamp "Mint does not appear to be running: File '$MINT_PID_PATH' not found"
    exit 4
  fi

  if [ ! -r "$MINT_PID_PATH" ]; then
    echo_timestamp "Unable to verify if Mint is running: File '$MINT_PID_PATH' not readable"
    exit 4
  fi

  pid=`cat "$MINT_PID_PATH"`
  if ! ps $PS_OPTS |egrep "^[^ ]{1,}[ ]{1,}$pid .* java .*\-Dfascinator\.home=" >/dev/null; then
    echo_timestamp "Mint does not appear to be running: PID '$pid' (from '$MINT_PID_PATH') does not appear to be a java/fascinator process"
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
  if [ $DRY_RUN != 1 ]; then
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
  cmd="cd $TF_SERVER_DIR && ./$TF_HARVEST_BIN $MINT_DATA_SOURCE"
  do_command "$cmd" $VERBOSE "Load metadata file into Mint. Data source: $MINT_DATA_SOURCE"
  is_load_csv_done=1

  if egrep -i "$TF_HARVEST_LOG_ERROR_REGEX" $TF_HARVEST_LOG >/dev/null; then
    echo_timestamp "Mint harvest error detected by regex /$TF_HARVEST_LOG_ERROR_REGEX/ in file $TF_HARVEST_LOG"
  else
    is_load_csv_successful=1
  fi
}

##############################################################################
# load_incremental_csv(): Only load new/changed records from CSV file
#   (compared to previous CSV file)
##############################################################################
load_incremental_csv() {
  copt_data_source=$1
  timestamp=$2
  this_fname=$DOWNLOAD_DIR/$SOURCE_FNAME

  # Find previous CSV file (for comparison)
  # Assumes filenames are sorted by $timestamp (appended to filename)
  prev_fname=`ls -1 $DOWNLOAD_HISTORY_DIR/$SOURCE_FNAME.* |tail -1`
  if [ -z "$prev_fname" ]; then
    echo_timestamp "Cannot perform incremental-load of CSV because no (previous) file found matching:"
    echo_timestamp "  $DOWNLOAD_HISTORY_DIR/$SOURCE_FNAME.*"
    exit 2
  fi
  [ $DRY_RUN = 1 ] && return

  # Confirm header lines in both CSV files are identical
  head -1 $prev_fname > $SORTED_PREVIOUS
  head -1 $this_fname > $SORTED_THIS
  if [ "`md5sum < $SORTED_PREVIOUS`" != "`md5sum < $SORTED_THIS`" ]; then
    echo_timestamp "Cannot perform incremental-load of CSV because the column order of the 2 files below are different:"
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
    cmd="ln $LN_OPTS $NEW_RECORDS_FULL $TARGET_SOURCE_PATH"
    do_command "$cmd" $VERBOSE "Symlink to incremental-load CSV file"
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
# Assumes TARGET_SOURCE_PATH & SOURCE_FNAME have already been set
##############################################################################
cleanup() {
  cmd="rm -f ${TARGET_SOURCE_PATH}* $DOWNLOAD_DIR/${SOURCE_FNAME}* $SORTED_PREVIOUS $SORTED_THIS $NEW_RECORDS_BODY $NEW_RECORDS_FULL"
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

cmd="cd $DOWNLOAD_DIR && wget $WGET_OPTS $IN_URL_CSV"
do_command "$cmd" $VERBOSE "Download metadata file from $IN_URL_CSV"

if [ "$copt_full_incr" = --full-load ]; then
  cmd="ln $LN_OPTS $DOWNLOAD_DIR/$SOURCE_FNAME $TARGET_SOURCE_PATH"
  do_command "$cmd" $VERBOSE "Symlink to full-load CSV file"
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
  dest=$DOWNLOAD_HISTORY_DIR/$SOURCE_FNAME.$timestamp
  cmd="mv -f $DOWNLOAD_DIR/$SOURCE_FNAME $dest"
  do_command "$cmd" $VERBOSE "Backup the full metadata file to $dest"
fi

# The Mint rewrites $TF_HARVEST_LOG (ie. does not append) for each run.
# Hence we will append a copy here.
if [ "$is_load_csv_done" = 1 ]; then
  cmd="(echo; echo_timestamp \"[$APP $copt_data_source $copt_full_incr] Appending Mint harvest log...\"; cat $TF_HARVEST_LOG) >> $HARVEST_LOG_ACCUM"
  do_command "$cmd" $VERBOSE "Append Mint harvest log to $HARVEST_LOG_ACCUM"
fi

