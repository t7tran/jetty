#!/bin/sh

changeSetDir=${1?ChangeSet location is missing}
[[ ! -d "$changeSetDir" ]] && echo "ChangeSet location not found: $changeSetDir" && exit 1
changeSetDir=`realpath $changeSetDir`

#list all changeset ids for all scripts
for f in $changeSetDir/*.xml
do
	xmlstarlet sel -N l="http://www.liquibase.org/xml/ns/dbchangelog" -t -m "//l:changeSet" -m "@id" -v . -n $f
done
