#!/bin/bash

#Declare variables
TMP_DIR="/mnt/tmp/backup"
SOURCE_DIR="/"
DEST_DIR="/mnt/backups/Associated Stocktaking/ubuntu-stocktaking"
TIMESTAMP=$(date --utc +%Y%m%dT%H%M%SZ)
TAR_FILE="backup-${TIMESTAMP}.tar.gz"

remove_old_files() {
	# Run this to clear temp space.
	trap "rm -rf ${TMP_DIR}" EXIT
}

copy_files_to_temp() {
	echo "Copying files to ${TMP_DIR}"
	rsync -aAXH --safe-links --ignore-missing-args --verbose \
		--exclude={/var/*,/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found,/boot/*,/var/tmp/*,/var/cache/*,/usr/tmp/*} \
		"$SOURCE_DIR" "$TMP_DIR"

	if [ $? -ne 0 ]; then
		echo "rsync failed."
		exit 1
	fi
}

create_tarball() {
	echo "Creating tarball ${TAR_FILE}"
	TAR_DIR="/mnt/tmp/tar"
	mkdir -p "${TAR_DIR}"
	tar -czf "${TAR_DIR}/${TAR_FILE}" -C "$TMP_DIR" .

	if [ $? -ne 0 ]; then
		echo "Tar command failed."
		exit 1
	fi
}

move_tarball() {
	echo "Moving tarball to ${DEST_DIR}"
	sudo mv "${TAR_DIR}/${TAR_FILE}" "$DEST_DIR"

	if [ $? -eq 0 ]; then
		echo "Backup successful."
	else
		echo "Backup failed."
		exit 1
	fi
}

flag_backups() {
	# First, find the newest backup within the last 7 days
	NEWEST_RECENT=$(find "$DEST_DIR" -name "backup-*.tar.gz" -mtime -7 -type f -printf "%T+ %p\n" |
		sort | tail -n 1 | awk '{print $2}')

	# Flag weekly backups (last 4 weeks)
	for i in {1..4}; do
		WEEK_AGO=$(date --date="$i weeks ago" +%Y-%m-%d)

		NEWEST_WEEKLY=$(find "$DEST_DIR" -name "backup-*.tar.gz" \
			-newermt "${WEEK_AGO}" ! -name "*.weekly" ! -name "*.monthly" \
			! -path "$NEWEST_RECENT" -type f -printf "%T+ %p\n" | sort | tail -n 1 | awk '{print $2}')

		if [ -f "$NEWEST_WEEKLY" ]; then
			echo "Flagging weekly backup: $NEWEST_WEEKLY"
			mv "$NEWEST_WEEKLY" "${NEWEST_WEEKLY}.weekly"
		fi
	done

	# Flag monthly backups (last 12 months)
	for i in {1..12}; do
		MONTH_AGO=$(date --date="$i months ago" +%Y-%m-%d)

		NEWEST_MONTHLY=$(find "$DEST_DIR" -name "backup-*.tar.gz" \
			-newermt "${MONTH_AGO}" -type f ! -name "*.weekly" ! -name "*.monthly" \
			! -path "$NEWEST_RECENT" -printf "%T+ %p\n" | sort | tail -n 1 | awk '{print $2}')

		if [ -f "$NEWEST_MONTHLY" ]; then
			echo "Flagging monthly backup: $NEWEST_MONTHLY"
			mv "$NEWEST_MONTHLY" "${NEWEST_MONTHLY}.monthly"
		fi
	done
}

delete_backups() {
	# Delete backups older than 7 days that are not flagged
	find "$DEST_DIR" -name "backup-*.tar.gz" -mtime +7 -type f ! -name "*.weekly" \
		! -name "*.monthly" -exec echo "Deleting {} older than 7 days" \; -exec rm {} \;
}

unflag_backups() {
	# Unflag weekly and monthly backups
	for suffix in weekly monthly; do
		find "$DEST_DIR" -name "backup-*.tar.gz.${suffix}" \
			-exec echo "Unflagging {}" \; -exec bash -c 'mv "$1" "${1%.*}"' bash {} \;
	done
}

run_backup() {
	# remove_old_files
	copy_files_to_temp
	create_tarball
	move_tarball
}

manage_backups() {
	flag_backups
	delete_backups
	unflag_backups
}

run_backup
manage_backups
