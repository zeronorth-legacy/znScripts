#!/bin/bash
#set -xv

API_KEY=$(cat "$1")

URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"

TARGETS=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets" | jq -r '.[0][].id')

echo "${TARGETS}" | while IFS= read -r line;
do
	TGT_ID="$line"
	SYNTH=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/syntheticIssues?targetId=${TGT_ID}")
	REFINED=$(echo "${SYNTH}" | jq -r '.[0][] | select(.data.issueJobs[].product | strings | test("sonarqube")) | .data.issueJobs[].refinedIssueId')
	echo "${REFINED}" >> job.txt
	echo "${REFINED}" | while IFS= read -r line;
	do
		JOB_ID="$line"
	VULN=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/refinedIssues/${JOB_ID}")
	ISSUE=$(echo "${VULN}" | jq -r '.[0][].data.vulnerabilityDetails[].issueName')
	echo "${ISSUE}" >> vuln.txt
done
done