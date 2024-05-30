#!/bin/bash

# - @copyright Copyright (c) 2020 René Gieling <github@dartcafe.de>
# -
# - @author René Gieling <github@dartcafe.de>
# - @modified by Playnary <martin@playnary.de>

# - @license GNU AGPL version 3 or any later version
# -
# - This program is free software: you can redistribute it and/or modify
# - it under the terms of the GNU Affero General Public License as
# - published by the Free Software Foundation, either version 3 of the
# - License, or (at your option) any later version.
# -
# - This program is distributed in the hope that it will be useful,
# - but WITHOUT ANY WARRANTY; without even the implied warranty of
# - MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# - GNU Affero General Public License for more details.
# -
# - You should have received a copy of the GNU Affero General Public License
# - along with this program. If not, see <http://www.gnu.org/licenses/>.

# Autoupdater 0.4 for nextcloud installation of all-inkl.com customers
# This script
# - @playnary added: uses customizable php version
# - sets the memory_limit in .user.ini
# - @playnary added: sets the upload_max_filesize and max_execution_time in .user.ini
# - makes sure, missing indices and columns are added
# - updates apps, if available
# - updates the nextcloud instance
# - @playnary added: checks file and cache integrity afterwards
# - supports multiple instances in one account

# @Playnary Roadmap for future version:
# - enabling opCache locally
# - integration of a remove-backups script to delete the automatic backups after successful core upgrade

# HOW TO:
# 1. fill in installations.txt
# 2. Check all directories and PhP versions in this script below to make sure that this script runs on your installation. It worked for us.
# 3. automate this script via cron-job or run it via ssh
# ! Use it at your own risk !



# init check variables
update_available=0

# define the php version
php_vs="82"

script_dir=$(dirname "$0")
# get account directory from username (/www/htdocs/w000000 in the example above)
# This is especially for all-inkl.com, other providers may need another strategy
account_base="/www/htdocs/${USER//ssh-}"

# define file with list of installation directories
# see installations.txt.default
# set your installation directory under your root account
# i.e. if your install directory (nextcloud root) is /www/htdocs/w000000/domain.com/nextcloud
# then add "domain.com/nextcloud" to the installations.txt
installations="$script_dir/installations.txt"

# define the php_memory_limit, max_execution_time and upload_max_filesize
max_execution_time="800"
upload_max_filesize="2048M"
php_memory_limit="1024M"


function logger()
{
    local text="$1"
    if [[ "${text}" != "" ]] ; then
			echo -e "\e[33m${text}\e[0m"
    fi
}


function test_installations() {
    if [[ ! -f ${installations} ]]; then
        logger "- installations.txt missing"
        exit 1

       else
       	logger "- installations.txt found"
    fi
}


function occ_add_indices()
{
	# occ db:add-missing-indices and :add-missing-columns is called blind
	logger "- run occ db:add-missing-indices"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ db:add-missing-indices
	logger "- run occ db:add-missing-columns"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ db:add-missing-columns
	logger "- run occ db:add-missing-primary-keys"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ db:add-missing-primary-keys
	logger "- run occ -n db:convert-filecache-bigint"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ -n db:convert-filecache-bigint	

}

function set_php_limit()
{
	# set memory_limit to $php_memory_limit, if no memory_limit is set
	if grep -q "memory_limit" $nc_base/.user.ini; then
		logger "- leave $nc_base/.user.ini untouched, memory_limit is already set"
	else
		echo "memory_limit=$php_memory_limit" >> $nc_base/.user.ini
		logger "- $nc_base/.user.ini memory_limit=$php_memory_limit added"
	fi
}

function set_uploadsize_executiontime()
{
	# set, if is not set
	if grep -q "upload_max_filesize" $nc_base/.user.ini; then
		logger "- leave $nc_base/.user.ini untouched, upload_max_filesize is already set"
	else
		echo "upload_max_filesize=$upload_max_filesize" >> $nc_base/.user.ini
		logger "- $nc_base/.user.ini upload_max_filesize=$upload_max_filesize added"
	fi

	if grep -q "max_execution_time" $nc_base/.user.ini; then
		logger "- leave $nc_base/.user.ini untouched, max_execution_time is already set"
	else
		echo "max_execution_time=$max_execution_time" >> $nc_base/.user.ini
		logger "- $nc_base/.user.ini max_execution_time=$max_execution_time added"
	fi
}


function occ_update_check() {
	logger "- run occ update:check"
	if php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ update:check | grep -q "Everything up to date"; then
	    logger "- NO app or core versions updates available"
		update_available=0
	else
		logger "- Some updates found.."
		update_available=1
	fi

	if php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ update:check | grep "Get more information on how to update"; then
		logger "- A new Nextcloud version is available."
		update_available=2
	fi
}

function occ_app_update()
{
	logger "- Start updating apps"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ app:update --all -n
}

function update_nc_version()
{
	# run directly start updater.phar
	logger "- Start update Nextcloud version directly"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/updater/updater.phar -n
}

function occ_upgrade()
{
	# run occ upgrade / alternative way of starting general updater
	logger "- Start Nextcloud OCC updater"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ upgrade
}


function occ_files_scan()
{
	logger "- Scan app files and check cache integrity"
	php$php_vs -d memory_limit=$php_memory_limit $nc_base/occ files:scan-app-data
}


function allow_eval_patch()
{
	patch_file=$nc_base/lib/public/AppFramework/Http/ContentSecurityPolicy.php
	logger "- patching $patch_file"
	logger "- replace \e[1m\e[95mprotected \e[91m\$evalScriptAllowed \e[95m= \e[32mfalse \e[0mwith \e[1m\e[95mprotected \e[91m\$evalScriptAllowed \e[95m= \e[32mtrue"
	sed -i 's/protected $evalScriptAllowed = false/protected $evalScriptAllowed = true/g' $patch_file
}


# Not yet implemented:
# function delete_update_backups ()
# {
# 	# Get the directory of the Backups
# 	SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# 	folderPath=$SCRIPT_DIR/../nextcloud.playnary.de/data/updater-ocpjqdtfke8c/backups/

# 	# Display the backup folder content and size
# 	echo " - Folder Content:"
# 	ls -lA $folderPath
# 	echo ""
# 	echo "- Folder Size:" 
# 	echo $(du -sh $folderPath)

# 	# !Remove prompt for automated behaviour! 
# 	# Prompt the user for input
# 	echo -n "Do you want to proceed with deleting the update-backups? (y/n): "
# 	read response

# 	# Check the user's input
# 	if [[ $response == "y" ]] ; then
	 
# 		# Delete all folders and files in the parent directory
# 		if rm -r "$SCRIPT_DIR/../nextcloud.playnary.de/data/updater-ocpjqdtfke8c/backups/"; then
# 			echo "- folder $SCRIPT_DIR succesfully DELETED"
# 		else
# 			echo "- could not find or delete folder $SCRIPT_DIR"
# 		fi

# 	else
# 	  echo "Backup Deletion aborted."

# 	fi

# }


#Script Runtime

test_installations
#logger "– Script running with \e[96m$installations in $account_base"

while read install_dir; do
	nc_base=$account_base/$install_dir

	logger " "
	logger "=================================="
	logger "- nextcloud installation: \e[96m$install_dir"
	logger "=================================="
	logger "- account base: \e[32m$account_base"
	logger "- nextcloud base dir: \e[32m$nc_base"
	logger "=================================="

	logger "- chmod 744 $nc_base/occ"
	chmod 744 $nc_base/occ

	set_php_limit
	set_uploadsize_executiontime
	occ_add_indices
	occ_update_check

	# assuming that occ update:check still reports the same strings
	# "Everything up to date" means, there are no updates, end script in this case
	# "update for" means there is an update for at least one app
	# "Get more information on how to update" means, there is a Nextcloud update available
	if [ "${update_available}" != "0" ] ; then

		logger " "
		occ_app_update
		logger " "

		if [ "${update_available}" = "2" ] ; then

			update_nc_version
			# occ_upgrade # we are using the direct command above for now
			
			logger " "
			logger "- Post-update treatment: Reset memory limits, upload sizes and executions times according to custom specs"
			set_php_limit
			set_uploadsize_executiontime
			occ_files_scan

		fi
	fi
done < $installations


while read install_dir; do
	nc_base=$account_base/$install_dir

	logger " "
	logger "=================================="
	logger "- nextcloud installation: \e[96m$install_dir"
	logger "=================================="
	logger "- account base: \e[32m$account_base"
	logger "- nextcloud base dir: \e[32m$nc_base"
	logger "=================================="

	allow_eval_patch
done <$alloweval
