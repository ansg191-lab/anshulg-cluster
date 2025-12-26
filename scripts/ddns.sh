#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#
set -Eeuo pipefail

trap 'echo "Error on line $LINENO"; exit 1' ERR

REPO="${REPO:-ansg191-lab/anshulg-cluster}"
GITHUB_APP_ID="${GITHUB_APP_ID:-}"
GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-}"
GITHUB_APP_PRIVATE_KEY_FILE="${GITHUB_APP_PRIVATE_KEY_FILE:-}"
ZONEFILE_PATH="${ZONEFILE_PATH:-zones/anshulg-com.zonefile}"
RECORD="${RECORD:-vpn.anshulg.com.}"
BASE_BRANCH="${BASE_BRANCH:-main}"

_GH_INSTALL_TOKEN=""

err() { echo "ERROR: $*" >&2; exit 1; }

require_github_app_env() {
	[[ -n "${GITHUB_APP_ID}" ]] || err "GITHUB_APP_ID is empty"
	[[ -n "${GITHUB_APP_INSTALLATION_ID}" ]] || err "GITHUB_APP_INSTALLATION_ID is empty"
	[[ -n "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] || err "GITHUB_APP_PRIVATE_KEY_FILE is empty"
	[[ -f "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] || err "Private key file not found: ${GITHUB_APP_PRIVATE_KEY_FILE}"
}

github_api_raw() {
	# Usage: github_api_raw METHOD PATH [curl_args...]
	local method="$1"; shift
	local path="$1"; shift

	local tmp status
	tmp="$(mktemp)"
	status="$(
	curl -sS -o "$tmp" -w "%{http_code}" -X "$method" \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"https://api.github.com${path}" \
	"$@"
	)"

	if [[ "$status" != 2* ]]; then
		echo "GitHub API error: ${method} ${path} -> HTTP ${status}" >&2
		cat "$tmp" >&2
		rm -f "$tmp"
		exit 1
	fi

	cat "$tmp"
	rm -f "$tmp"
}

b64url() {
	# base64url encode stdin (no padding)
	openssl base64 -A | tr '+/' '-_' | tr -d '='
}

make_github_app_jwt() {
	# Creates a JWT for GitHub App authentication (valid for ~10 minutes)
	require_github_app_env

	local now iat exp header payload signing_input sig
	now="$(date +%s)"
	iat="$((now - 60))"
	exp="$((now + 540))" # 9 minutes to stay under GitHub's 10-minute max

	header='{"alg":"RS256","typ":"JWT"}'
	payload="$(jq -nc --arg iss "${GITHUB_APP_ID}" --argjson iat "${iat}" --argjson exp "${exp}" '{iss:$iss, iat:$iat, exp:$exp}')"

	signing_input="$(printf '%s' "${header}" | b64url).$(printf '%s' "${payload}" | b64url)"
	sig="$(printf '%s' "${signing_input}" \
		| openssl dgst -sha256 -sign "${GITHUB_APP_PRIVATE_KEY_FILE}" -binary \
		| b64url
	)"

	printf '%s.%s' "${signing_input}" "${sig}"
}

get_installation_token() {
	# Returns a cached installation token, otherwise fetches a new one.
	require_github_app_env

    if [[ -n "${_GH_INSTALL_TOKEN}" ]]; then
      echo "${_GH_INSTALL_TOKEN}"
      return 0
    fi

	local jwt resp token
	jwt="$(make_github_app_jwt)"

	resp="$(
		github_api_raw POST "/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" \
			-H "Authorization: Bearer ${jwt}" \
			-H "Content-Type: application/json" \
			-d '{}' \
	)"

	token="$(echo "${resp}" | jq -r '.token')"
	[[ -n "${token}" && "${token}" != "null" ]] || err "Failed to obtain installation token"
	_GH_INSTALL_TOKEN="${token}"
	echo "${_GH_INSTALL_TOKEN}"
}

github_api() {
	# Usage: github_api METHOD PATH [curl_args...]
	local method="$1"; shift
	local path="$1"; shift

	local token
	token="$(get_installation_token)"

	github_api_raw "$method" "$path" \
		-H "Authorization: Bearer ${token}" \
		"$@"
}

get_public_ip() {
	ip="$(curl -4fsS https://api.ipify.org || true)"
	if [[ -z "${ip}" ]]; then
	  ip="$(curl -4fsS https://ifconfig.me/ip || true)"
	fi
	if [[ -z "${ip}" ]]; then
	  ip="$(curl -4fsS https://checkip.amazonaws.com || true)"
	fi
	[[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || err "Could not determine public IPv4 (got: '${ip}')"
	echo "${ip}"
}

get_zonefile() {
	# Get the current zonefile from the GitHub repo
	local zonefile
	zonefile=$(github_api GET "/repos/${REPO}/contents/${ZONEFILE_PATH}?ref=${BASE_BRANCH}")

	local outfile
	outfile=$(mktemp)
	echo "${zonefile}" | jq -r '.content' | base64 --decode > "${outfile}"
	echo "${outfile}"
}

extract_zonefile_ip() {
	local zonefile="$1"
	local record="$2"

	awk -v rec="$record" '
		$1 == rec && $4 == "A" {
			print $5
			exit
		}
	' "$zonefile"
}

update_zonefile_ip() {
	local zonefile="$1"
	local record="$2"
	local new_ip="$3"

	awk -v rec="$record" -v ip="$new_ip" '
		$1 == rec && $4 == "A" {
			$5 = ip
		}
		{ print }
	' "$zonefile" > "${zonefile}.new"

	diff -u "$zonefile" "${zonefile}.new" || true
}

get_ref_sha() {
	# e.g. refs/heads/ddns
	local ref="$1"
	github_api GET "/repos/${REPO}/git/ref/${ref}" | jq -r '.object.sha'
}

get_file_sha_on_branch() {
	# Returns the blob SHA of the file as tracked by the contents API on a given branch
	local path="$1"
	local branch="$2"

	github_api GET "/repos/${REPO}/contents/${path}?ref=${branch}" | jq -r '.sha'
}

create_branch() {
	# Creates refs/heads/<newbranch> from base branch HEAD
	local base_branch="$1"
	local new_branch="$2"

	local base_sha
	base_sha="$(get_ref_sha "heads/${base_branch}")"
	[[ -n "${base_sha}" && "${base_sha}" != "null" ]] || err "Could not resolve SHA for base branch '${base_branch}'"

	github_api POST "/repos/${REPO}/git/refs" \
		-H "Content-Type: application/json" \
		-d "$(jq -nc --arg ref "refs/heads/${new_branch}" --arg sha "${base_sha}" '{ref:$ref, sha:$sha}')"
}

make_branch_name() {
	local ip="$1"
	local ts
	ts="$(date -u +%Y%m%dT%H%M%SZ)"
	# replace dots so it's ref-safe
	local ip_s="${ip//./-}"
	echo "ddns/${ts}-${ip_s}"
}

commit_zonefile_via_contents_api() {
	# Commits updated file content to a branch using PUT /contents/{path}
	local path="$1"
	local branch="$2"
	local new_file_path="$3"
	local message="$4"

	local current_sha
	current_sha="$(get_file_sha_on_branch "${path}" "${branch}")"
	[[ -n "${current_sha}" && "${current_sha}" != "null" ]] || err "Could not get current file SHA for '${path}' on branch '${branch}'"

	local b64
	b64="$(base64 < "${new_file_path}" | tr -d '\n')"

	github_api PUT "/repos/${REPO}/contents/${path}" \
		-H "Content-Type: application/json" \
		-d "$(jq -nc \
	  		--arg message "${message}" \
	  		--arg content "${b64}" \
	  		--arg branch "${branch}" \
	  		--arg sha "${current_sha}" \
	  		'{message:$message, content:$content, branch:$branch, sha:$sha}')"
}

find_existing_open_pr_for_record() {
	local base_branch="$1"
	local record="$2"

	local prs
	prs="$(github_api GET "/repos/${REPO}/pulls?state=open&base=${base_branch}&per_page=100")"

	# Match either title or body containing the record string.
	# (Your PR body includes "Record: ${RECORD}", and title includes "${RECORD}".)
	echo "${prs}" | jq -c --arg rec "${record}" '
		map(select((.title // "" | contains($rec)) or (.body // "" | contains($rec))))
		| first // empty
	'
}

create_pr() {
	local base_branch="$1"
	local head_branch="$2"
	local title="$3"
	local body="$4"

	github_api POST "/repos/${REPO}/pulls" \
		-H "Content-Type: application/json" \
		-d "$(jq -nc \
			--arg title "$title" \
			--arg head "$head_branch" \
			--arg base "$base_branch" \
			--arg body "$body" \
			'{title:$title, head:$head, base:$base, body:$body}')"
}

PUBLIC_IP="$(get_public_ip)"
echo "Public IP:           ${PUBLIC_IP}"

echo "Repo:                ${REPO}"
echo "Zonefile path:       ${ZONEFILE_PATH}"
ZONEFILE="$(get_zonefile)"
trap 'rm -f "$ZONEFILE"' EXIT
trap 'rm -f "$ZONEFILE"; rm -f "$ZONEFILE.new"' EXIT

ZONEFILE_IP="$(extract_zonefile_ip "$ZONEFILE" "$RECORD")"
echo "Zonefile record:     ${RECORD}"
echo "Zonefile current IP: ${ZONEFILE_IP}"
echo

if [[ "${PUBLIC_IP}" == "${ZONEFILE_IP}" ]]; then
	echo "No update needed. Exiting."
	exit 0
fi

# Check for existing open PR for this record
EXISTING_PR_JSON="$(find_existing_open_pr_for_record "${BASE_BRANCH}" "${RECORD}" || true)"
if [[ -n "${EXISTING_PR_JSON}" ]]; then
	EXISTING_PR_ID="$(echo "${EXISTING_PR_JSON}" | jq -r '.number')"
	EXISTING_PR_URL="$(echo "${EXISTING_PR_JSON}" | jq -r '.html_url')"
	echo "An existing open PR (#${EXISTING_PR_ID}) already exists for record '${RECORD}':"
	echo "  ${EXISTING_PR_URL}"
	echo "Please review and merge it before creating a new one."
	exit 0
fi

# Update zonefile
echo "Updating zonefile..."
update_zonefile_ip "$ZONEFILE" "$RECORD" "$PUBLIC_IP"
[[ -s "${ZONEFILE}.new" ]] || err "No updated zonefile produced at ${ZONEFILE}.new"
trap 'rm -f "$ZONEFILE"; rm -f "$ZONEFILE.new"' EXIT
echo

# Create branch and commit updated zonefile
BRANCH_NAME="$(make_branch_name "$PUBLIC_IP")"
COMMIT_MSG="DDNS update: set ${RECORD} to ${PUBLIC_IP}"

echo "Commit Message:      ${COMMIT_MSG}"
echo "Branch Name:         ${BRANCH_NAME}"
create_branch "${BASE_BRANCH}" "${BRANCH_NAME}" > /dev/null
echo
echo "Created branch '${BRANCH_NAME}' from '${BASE_BRANCH}'"
commit_zonefile_via_contents_api "${ZONEFILE_PATH}" "${BRANCH_NAME}" "${ZONEFILE}.new" "${COMMIT_MSG}" > /dev/null
echo "Committed updated zonefile to branch '${BRANCH_NAME}'"

# Create PR
PR_TITLE="DNS: update ${RECORD} -> ${PUBLIC_IP}"
PR_BODY=$(
  cat <<EOF
Automated update of DNS A record.

- Record: \`${RECORD}\`
- Old IP: \`${ZONEFILE_IP}\`
- New IP: \`${PUBLIC_IP}\`
EOF
)

PR_ID=$(create_pr "${BASE_BRANCH}" "${BRANCH_NAME}" "${PR_TITLE}" "${PR_BODY}" | jq -r '.number')
echo
echo "PR Created:          #${PR_ID}"
echo "PR URL:              https://github.com/${REPO}/pull/${PR_ID}"

echo "DDNS update process completed."
