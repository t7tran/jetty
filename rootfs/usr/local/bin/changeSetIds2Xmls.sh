#!/bin/sh

changeSetDir=${1?ChangeSet location is missing}
[[ ! -d "$changeSetDir" ]] && echo "ChangeSet location not found: $changeSetDir" && exit 1
changeSetDir=`realpath $changeSetDir`

mkdir -p /tmp/changesets
rm -rf /tmp/changesets/*

for f in $changeSetDir/*.xml; do
	for id in `xmlstarlet sel -N l="http://www.liquibase.org/xml/ns/dbchangelog" -t -m "//l:changeSet" -m "@id" -v . -n $f`; do
		cat <<-EOF > /tmp/changesets/$id.xml
		<?xml version="1.0" encoding="UTF-8"?>
		<databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
			xmlns:ext="http://www.liquibase.org/xml/ns/dbchangelog-ext"
			xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-3.0.xsd
		        http://www.liquibase.org/xml/ns/dbchangelog-ext http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-ext.xsd">
		EOF
		xmlstarlet sel -N l="http://www.liquibase.org/xml/ns/dbchangelog" -t -c "//l:changeSet[@id=$id]" $f | sed -Ee 's/ xmlns(:[a-z]+)?="[^"]+"//g' >> /tmp/changesets/$id.xml
		echo '</databaseChangeLog>' >> /tmp/changesets/$id.xml
	done
done
