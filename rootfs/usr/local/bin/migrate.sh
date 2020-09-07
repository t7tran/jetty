#!/bin/bash -e

changeSetDir=${1?ChangeSet location is missing}
if [[ ! -d "$changeSetDir" ]]; then
	echo "ChangeSet location not found: $changeSetDir"
	exit 1
fi
changeSetDir=`realpath $changeSetDir`

applyingChangeSetId=$2

if [[ -n "$LIQUIBASE_MYSQL_VER" && -f /opt/liquibase/mysql-connector-java-$LIQUIBASE_MYSQL_VER.jar ]]; then
	find /opt/liquibase/lib -type f -name mysql-connector-java-\*.jar -exec mv {} /opt/liquibase \;
	mv /opt/liquibase/mysql-connector-java-$LIQUIBASE_MYSQL_VER.jar /opt/liquibase/lib/
fi
# provide default driver if not specified
[[ -z "$LIQUIBASE_DB_DRIVER" && "$LIQUIBASE_MYSQL_VER" == "5" ]] && LIQUIBASE_DB_DRIVER=com.mysql.jdbc.Driver
[[ -z "$LIQUIBASE_DB_DRIVER" && "$LIQUIBASE_MYSQL_VER" == "8" ]] && LIQUIBASE_DB_DRIVER=com.mysql.cj.jdbc.Driver

dbUrl="jdbc:mysql://${LIQUIBASE_DB_HOST?}/${LIQUIBASE_DB_NAME?}?${LIQUIBASE_DB_OPTIONS}"

# changeset ids validation
duplicates=$(changeSetIds.sh $changeSetDir | sort -V | uniq -d)
if [[ -n "$duplicates" ]]; then
    echo "Duplicate IDs ($duplicates) present in migration change sets"
    exit 1
fi

# extract changeset to one per xml
changeSetIds2Xmls.sh $changeSetDir

# Find max changeset id from changelogs
if [[ -z "$applyingChangeSetId" ]]; then
	applyingChangeSetId=$(changeSetIds.sh $changeSetDir | sort -rV | head -1)
elif [[ ! -f /tmp/changesets/$applyingChangeSetId.xml ]]; then
	echo "Requested change set $applyingChangeSetId to be applied not found."
	exit 1
fi

mysql="mysql -u ${LIQUIBASE_DB_USERNAME?} --database ${LIQUIBASE_DB_NAME?} -h ${LIQUIBASE_DB_HOST?} -N -s"

tableExists=$(MYSQL_PWD=${LIQUIBASE_DB_PASSWORD?} $mysql -e 'show tables' | grep -v DATABASECHANGELOG || true)
if [[ -z "$tableExists" && "${LIQUIBASE_SKIP_EMPTY_DB:-true}" == "true" ]]; then
	echo Empty database found.
	exit 0
fi

dbMaxChangesetId=0
tableExists=$(MYSQL_PWD=${LIQUIBASE_DB_PASSWORD?} $mysql -e "show tables like 'DATABASECHANGELOG'")
if [[ -n "$tableExists" ]]; then
	# Find max changeset id in the database
	dbMaxChangesetId=$(MYSQL_PWD=${LIQUIBASE_DB_PASSWORD?} $mysql -e "select ID from DATABASECHANGELOG order by DATEEXECUTED desc limit 1")
	dbMaxChangesetId=${dbMaxChangesetId:-0}
fi

if [[ "$dbMaxChangesetId" != "0" && ! -f /tmp/changesets/$dbMaxChangesetId.xml ]]; then
	echo Last applied change set $dbMaxChangesetId not found.
	exit 1
fi

# Compare changeset
echo "The applying changeset is $applyingChangeSetId, the database changeset is $dbMaxChangesetId"

masterFileLocation=/tmp/master.xml
prepareMasterXml() {
	# Create the master.xml file to be passed to liquibase
	if [[ -z "$1" ]]; then
		xmls=$(find /tmp/changesets -type f -name \*.xml 2>/dev/null | sort -V | xargs -n 1 -I {} echo '<include file="{}" />')
	else
		xmls=$(find /tmp/changesets -type f -name \*.xml 2>/dev/null | sort -rV | sed -ne "/\/$1.xml/,\$p" | tac | xargs -n 1 -I {} echo '<include file="{}" />')
	fi

	if [[ -z "$xmls" ]]; then
		echo No migration change sets found for ${1:-0}???
		exit 1
	fi

	cat <<-EOF > $masterFileLocation
		<?xml version="1.0" encoding="UTF-8"?>
		<databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
			xmlns:ext="http://www.liquibase.org/xml/ns/dbchangelog-ext"
			xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-3.0.xsd
		        http://www.liquibase.org/xml/ns/dbchangelog-ext http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-ext.xsd">
		$xmls
		</databaseChangeLog>
	EOF
}

newerChangeset() {
	[[  "$1" != "$2" && "$1" = "`echo -e "$1\n$2" | sort -rV | head -n1`" ]]
}

# Perform migration update or rollback
liquibaseCommand="liquibase --driver=${LIQUIBASE_DB_DRIVER?} --url=$dbUrl --username=${LIQUIBASE_DB_USERNAME?} --password=${LIQUIBASE_DB_PASSWORD?} --changeLogFile=$masterFileLocation"
logFilter() { 
	grep -vE 'Starting|built|Datical|tagged'
}
update() {
	prepareMasterXml ${1?}
    echo -n "Applying change set $1... "
	runliquibase update
}
runliquibase() {
	local output=$($liquibaseCommand "$@" | logFilter)
	if [[ "$output" == *uccessful* ]]; then
		echo OK
	else
		echo
		echo "$output"
		exit 1
	fi
}

if newerChangeset $dbMaxChangesetId $applyingChangeSetId; then 
	prepareMasterXml

	changesetDateExecuted="$(MYSQL_PWD=${LIQUIBASE_DB_PASSWORD?} $mysql -e "select DATEEXECUTED from DATABASECHANGELOG where ID = '$applyingChangeSetId'")"
	rollbackCount="$(MYSQL_PWD=${LIQUIBASE_DB_PASSWORD?} $mysql -e "select count(*) from DATABASECHANGELOG where DATEEXECUTED > '${changesetDateExecuted?Changeset ID not found in database}'")"
	
	if [[ $rollbackCount -lt 1 ]]; then
		echo "No newer change sets found since $applyingChangeSetId (executed at ${changesetDateExecuted})"
		exit 0
	fi
	
    echo -n "Performing roll back to change set: $applyingChangeSetId (executed at ${changesetDateExecuted})... "

    runliquibase rollbackCount "${rollbackCount}"
elif [[ "$dbMaxChangesetId" == "$applyingChangeSetId" ]]; then
	update $applyingChangeSetId
else
	firstChangesetId=$dbMaxChangesetId
	if [[ "$firstChangesetId" == "0" ]]; then
		firstChangesetId=$(changeSetIds.sh $changeSetDir | sort -V | head -1)
	fi
	for cs in `changeSetIds.sh $changeSetDir | sort -V | sed -ne "/^$firstChangesetId\$/,/^$applyingChangeSetId\$/ p" | grep -v "^$dbMaxChangesetId\$"`; do
	    update $cs
	done
fi

if [[ -n "$KEEP_RUNNING" ]]; then
	trap : TERM INT; tail -f /dev/null & wait
fi