FlindersRedbox-url2ingest
=========================

Helper for ReDBox-Mint. Retrieves the specified CSV file from a URL and
ingests it into the specified Mint data source.

Purpose
-------
"ReDBox is a metadata registry application for describing research data.
The Mint is an name-authority and vocabulary service that complements ReDBox."
See http://www.redboxresearchdata.com.au/. The purpose of this script is to:
* retrieve the specified (person or project) CSV file from a URL
* allow records to be filtered (included) via regular expressions in a configuration file
* ingest (or harvest or load) the file into the specified Mint data source

Notes
-----
* Has been tested & designed for use on ReDBox & Mint dev-handle build.
  (It should also work for other ReDBox-Mint variants.)

Application environment
-----------------------
Read the INSTALL file.

Installation
------------
Read the INSTALL file.

Features
--------
* Allows loading of person or project metadata into Mint.
* Allows loading of all records in the file or an incremental load of new
  or updated records since the last load.
* Allows records to be filtered (included) via regular expressions in a
  configuration file.
* Script is suitable to be run within a unix cron environment.
* Produces output suitable for redirecting to a log file.
* Will not attempt to ingest metadata unless Mint is running.

Todo
----
NA

Acknowledgement
---------------
The development of this software was a component of a larger [Flinders University]
(http://www.flinders.edu.au/) project funded by the [Australian National Data
Service (ANDS)](http://ands.org.au).

