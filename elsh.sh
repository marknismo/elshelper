#!/usr/bin/env bash

# Created by: Mark C.

# Purpose of ELS download helper:
# - download Cloudflare Enterprise logs despite the CF API limitations below:
# https://support.cloudflare.com/hc/en-us/articles/216672448-Enterprise-Log-Share-Logpull-REST-API 


# Features:
# - help download logs for a time range exceeding the time range of 1 hour
# - instead of hard-limiting requests to 1 minute at a time, a variable time range is used to download the logs more efficiently
# - automatic handling of the API failure to stream more than 1 GB of data for time ranges greater than 1 minute 
# 

# Usage:
# Optional: create a directory/folder to run the command in
# chmod u+x elsh.sh
# run "./elsh.sh"
 

# Pre-requsite:
# install jq

# Tested on Mac OS 

# Global variables
auth_email=""
auth_key=""
zone_name=""
fields=""
zone_tag=""
action_output=""
result=""
time_range=60
current_filename=""
filesize_in_bytes=0
retry=0

original_start_timestamp=0
original_end_timestamp=0
current_start_timestamp=0
current_end_timestamp=0


function set_current_end_timestamp(){
	#input: seconds
	time_range=$1

	# set the request end time from the request start time
	current_end_timestamp=$((current_start_timestamp + time_range))
}



function convert_epoch_to_date(){
	local request_date=$(date -ur $current_start_timestamp +%d-%m-%Y)
	local request_start_time=$(date -ur $current_start_timestamp +%HH%MM%S)
	local request_end_time=$(date -ur $current_end_timestamp +%HH%MM%S)

	echo "${request_date} T${request_start_time} ${request_end_time}"
}



function set_current_filename(){
	local human_date=$(convert_epoch_to_date)
	local filename="${zone_name} ${human_date}.log"
	echo $filename
}



function fetch_current(){
	#input: curl output filename
	#output: echo HTTP response status code and download size
	curl --write-out "%{http_code} %{size_download}" -so "${*}" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" "https://api.cloudflare.com/client/v4/zones/$zone_tag/logs/received?start=$current_start_timestamp&end=$current_end_timestamp&fields=$fields"
}


function calculate_next_time_range_for_1G(){
	#output: seconds
	local temp_filesize=${filesize_in_bytes}

	# prevent division by 0 
	if [ ${temp_filesize} -eq 0 ]; then
		temp_filesize=1
	fi

	# set new time range to be quarter of the current time range
	local new_time_range=$((${time_range}/4))

	# there is no limit for time range of 1 minute
	if [[ $new_time_range -lt 60 ]]; then
		new_time_range=60
	fi

	echo $new_time_range
}


function is_result_ok(){
	# input: http status code or unknown curl output
	# output: echo "File ...", "ok" or non-200 status code


	# for time range > 1 min, check if filesize is near 1 GB
	if [[ $1 == "200" ]] && [ $time_range -gt 60 ]; then
		if [ ${filesize_in_bytes} -le 900000000 ]; then
			echo "ok"
			return 0
		else
			# Maximum response size is 1GB uncompressed for time ranges greater than 1 minute
			echo "File is ${filesize_in_bytes} bytes"

			local directory_1G="${zone_name}_1G"

			if [ ! -d $directory_1G ]; then
			  mkdir $directory_1G
			fi

			mv "${current_filename}" "${directory_1G}/"
			return 0
		fi
	fi

	# for time range < 1 min, check if response is 200
	# for time ranges of 1 minute or less, there is no limit 
	if [[ $1 == "200" ]] && [ $time_range -le 60 ]; then
		echo "ok"
		return 0
	else
		echo "$1". #if not 200, return the status code
		return 0
	fi
}


function calculate_next_time_range(){
	#output: seconds
	local temp_filesize=${filesize_in_bytes}
	local new_time_range=0


	# prevent division by 0 
	if [ ${temp_filesize} -eq 0 ]; then
		temp_filesize=1
	fi

	# if filesize is <=500MB, calculate time range for 700MB
	if [[ ${temp_filesize} -le 500000000 ]]; then
		new_time_range=$(echo "scale=10;${time_range}/${temp_filesize}*600000000" | bc)
		new_time_range=$( printf "%.0f" $new_time_range )

	else
		#else if filesize is > 500MB, retain current time range
		new_time_range=$time_range
	fi

	
	# Maximum time range is 1 hour
	if [ $new_time_range -gt 3600 ]; then 
		new_time_range=3600
	fi

	# if time_range exceed original request end time
	if [ $((${current_start_timestamp}+${new_time_range})) -gt ${original_end_timestamp} ]; then
		new_time_range=$((${original_end_timestamp}-${current_start_timestamp}))
	fi

	echo $new_time_range

}


function action_result(){
	#input: "File ...", "ok" or non-200 status code
	# output: echo "retry", "ok", "File", other exit messages

	local result=$1

	if [[ $retry -eq 3 ]]; then
		echo -e "Retried 3 times. Please review the error messages above."
		exit 1
	fi


	if [[ ${result:0:4} == "File" ]]; then
		((retry++))
		echo "File"
		return 0
	fi

	# if result is 429
	# The effective rate limit is 1 request every 5 seconds per zone. 
	if [[ $result == "429" ]]; then
		((retry++))
		sleep 5
		echo "retry"
		return 0
	fi

	#if result is 400 bad request 
	if [[ $result == "400" ]]; then
		echo "HTTP status is 400. Check your time range."
		exit
	fi

	# else "ok", "File", other HTTP status code
	retry=0  
	echo $result
}



function set_next_time_range(){
	#set time range based on arguments "ok", "File", "retry" and filesize
	# input: "ok", "File", "retry", other HTTP status code
	# output: 
	
	# Start is inclusive, end is exclusive.
	#start=2018-05-15T10:00:00Z&end=2018-05-15T10:01:00Z, 
	#start=2018-05-15T10:01:00Z&end=2018-05-15T10:02:00Z

	local result=$1
	local new_time_range=0

	
	if [[ $result == "ok" ]]; then
		current_start_timestamp=$current_end_timestamp
		new_time_range=$(calculate_next_time_range)
		set_current_end_timestamp $new_time_range
		return 0
	fi

	# if result indicate maximum response size is 1GB uncompressed for time ranges greater than 1 minute
	if [[ $result == "File" ]]; then
		new_time_range=$(calculate_next_time_range_for_1G)
		set_current_end_timestamp $new_time_range
		return 0
	fi


	if [[ $result == "retry" ]]; then
		echo "Retry with same time range"
		return 0
	fi

	# other HTTP status code
	echo "HTTP status is ${result}"
	exit
}



function print_response(){
	echo "Download status is \"${*}\" for $(convert_epoch_to_date) UTC"
}


function start_download(){

	local fetch_result=""
	local fetch_result_arr=()
	local response=""
	#start with time range 1 minute
	set_current_end_timestamp 60


	while [[ $current_start_timestamp -lt $original_end_timestamp ]]
	do 
		current_filename=$(set_current_filename)

		fetch_result=$(fetch_current $current_filename)
		fetch_result_arr=($fetch_result)
		response=${fetch_result_arr[0]}
		filesize_in_bytes=${fetch_result_arr[1]}

		result=$(is_result_ok ${response})
		print_response $result
		action_output=$(action_result ${result})
		set_next_time_range $action_output
	done

	echo "Success! Completed download."
}


function get_user_input(){
	local current_date=$(date +%d-%m-%Y)
	local begin_date=""
	local begin_time=""
	local end_date=""
	local end_time=""

	read -p 'Enter your email account to login to Cloudflare: ' auth_email
	read -sp 'Enter your Cloudflare API key : ' auth_key
	echo ""
	read -p 'Enter the domain/zone : ' zone_name


	# get begin datetime
	echo ""
	read -p "Enter the begin date in UTC e.g. dd-mm-yyyy (Enter blank to use $current_date): " begin_date
	read -p 'Enter the begin time in UTC e.g. HH:mm:ss : ' begin_time
	begin_date="${begin_date:=$current_date}" #use current date if empty
	original_start_timestamp=$(date -j -f "%d-%m-%Y %H:%M:%S %Z" "$begin_date $begin_time GMT" +"%s")
	echo -e "The start unixtimestamp is $original_start_timestamp\n"


	# get end datetime
	read -p "Enter the end date in UTC e.g. dd-mm-yyyy (Enter blank to use $current_date): " end_date
	read -p 'Enter the end time in UTC e.g. HH:mm:ss : ' end_time
	end_date="${end_date:=$current_date}" #use current date if empty
	original_end_timestamp=$(date -j -f "%d-%m-%Y %H:%M:%S %Z" "$end_date $end_time GMT" +"%s")
	echo -e "The end unixtimestamp is $original_end_timestamp\n"

}

function init(){
	# get zone_tag
	zone_tag=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=$zone_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" | jq -r '. | .result[] | .id')

	# get els fields
	fields=$(curl -s -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" "https://api.cloudflare.com/client/v4/zones/$zone_tag/logs/received/fields" | jq '. | to_entries[] | .key' -r | paste -sd "," -)

	current_start_timestamp=$original_start_timestamp
	current_end_timestamp=$original_end_timestamp
}


get_user_input
init
start_download
