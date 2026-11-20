#!/bin/zsh --no-rcs

####################################################################################################
#
# swiftDialog Inspect Mode configuration for Baseline
#
# Purpose:
#   Creates the local JSON configuration consumed by Baseline's InspectModeJSON setting.
#
# Execution:
#   Run as a Baseline InitialScript with AsUser set to false.
#
# Optional argument:
#   $1 = Main application icon URL or local file path
#
####################################################################################################

set -u
set -o pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

####################################################################################################
#
# Variables
#
####################################################################################################

readonly scriptVersion="1.1.0"
readonly humanReadableScriptName="swiftDialog Inspect Mode configuration"

readonly scriptLog="/var/log/apitmsDeployInspectMode.log"
readonly installomatorLog="/var/log/Installomator.log"

readonly organizationPreset="2"
readonly organizationOverlayIconURL="https://baselineapit.blob.core.windows.net/resources/AppIcons/apiticon_new.png"

readonly defaultApplicationIcon="https://usw2.ics.services.jamfcloud.com/icon/hash_8bf6549c22de3db831aafaf9c5c02d3aa9a928f4abe377eb2f8cbeab3959615c"
readonly applicationIcon="${1:-${defaultApplicationIcon}}"

readonly applicationGroupTitle="Microsoft 365-Anwendungen"

readonly dialogInspectModeDirectory="/usr/local/apitms365"
readonly dialogInspectModeJSONFile="${dialogInspectModeDirectory}/inspect-mode.json"

typeset temporaryJSONFile=""

SECONDS=0

####################################################################################################
#
# Root validation
#
####################################################################################################

if [[ "${EUID}" -ne 0 ]]; then
    /bin/echo "ERROR: This script must run as root." >&2
    exit 1
fi

/usr/bin/touch "${scriptLog}"
/usr/sbin/chown root:wheel "${scriptLog}"
/bin/chmod 644 "${scriptLog}"

####################################################################################################
#
# Logging
#
####################################################################################################

function logMessage() {
    local logLevel="${1}"
    shift

    local logLine
    logLine="$(/bin/date '+%Y-%m-%d %H:%M:%S') [${logLevel}] ${humanReadableScriptName}: $*"

    /bin/echo "${logLine}" | /usr/bin/tee -a "${scriptLog}"
}

function info() {
    logMessage "INFO" "$@"
}

function warning() {
    logMessage "WARNING" "$@"
}

function fatal() {
    logMessage "ERROR" "$@"
    exit 1
}

function cleanup() {
    if [[ -n "${temporaryJSONFile:-}" && -e "${temporaryJSONFile}" ]]; then
        /bin/rm -f "${temporaryJSONFile}"
    fi
}

trap cleanup EXIT

####################################################################################################
#
# Requirements
#
####################################################################################################

if [[ ! -x "/usr/bin/jq" ]]; then
    fatal "/usr/bin/jq is unavailable; the Inspect Mode configuration cannot be generated."
fi

if [[ ! -x "/usr/bin/plutil" ]]; then
    fatal "/usr/bin/plutil is unavailable; the Inspect Mode configuration cannot be validated."
fi

####################################################################################################
#
# Logged-in user
#
####################################################################################################

loggedInUser=$(
    /bin/echo "show State:/Users/ConsoleUser" |
        /usr/sbin/scutil |
        /usr/bin/awk '/Name :/ { print $3 }'
)

case "${loggedInUser}" in
    "" | "root" | "loginwindow" | "_mbsetupuser")
        fatal "No valid logged-in user was detected. Current value: '${loggedInUser}'."
        ;;
esac

loggedInUserFullName=$(
    /usr/bin/id -F "${loggedInUser}" 2>/dev/null
)

if [[ -z "${loggedInUserFullName}" ]]; then
    loggedInUserFullName="${loggedInUser}"
fi

# Account for either "Firstname Lastname" or "Lastname, Firstname".
if [[ "${loggedInUserFullName}" == *","* ]]; then
    loggedInUserFirstName=$(
        /bin/echo "${loggedInUserFullName}" |
            /usr/bin/awk -F ',[[:space:]]*' '{
                split($2, nameParts, " ")
                print nameParts[1]
            }'
    )
else
    loggedInUserFirstName="${loggedInUserFullName%% *}"
fi

if [[ -z "${loggedInUserFirstName}" ]]; then
    loggedInUserFirstName="${loggedInUser}"
fi

info "Detected logged-in user '${loggedInUser}' with first name '${loggedInUserFirstName}'."

####################################################################################################
#
# Create supporting files and directories
#
####################################################################################################

function prepareFileSystem() {
    info "Preparing Inspect Mode directory '${dialogInspectModeDirectory}'."

    /bin/mkdir -p "${dialogInspectModeDirectory}" ||
        fatal "Failed to create '${dialogInspectModeDirectory}'."

    /usr/sbin/chown root:wheel "${dialogInspectModeDirectory}" ||
        fatal "Failed to set ownership on '${dialogInspectModeDirectory}'."

    /bin/chmod 755 "${dialogInspectModeDirectory}" ||
        fatal "Failed to set permissions on '${dialogInspectModeDirectory}'."

    # The log must exist before SwiftDialog starts monitoring it.
    if [[ ! -e "${installomatorLog}" ]]; then
        info "Creating Installomator log '${installomatorLog}'."

        /usr/bin/touch "${installomatorLog}" ||
            fatal "Failed to create '${installomatorLog}'."
    fi

    /usr/sbin/chown root:wheel "${installomatorLog}" ||
        fatal "Failed to set ownership on '${installomatorLog}'."

    /bin/chmod 644 "${installomatorLog}" ||
        fatal "Failed to set permissions on '${installomatorLog}'."
}

####################################################################################################
#
# Create Inspect Mode configuration
#
####################################################################################################

function createInspectConfig() {
    local windowTitle
    local windowMessage
    local jqValidationError
    local plutilValidationError

    windowTitle="Hallo ${loggedInUserFirstName}, willkommen bei der anyplace IT GmbH."
    windowMessage="Bitte warten Sie, während die erforderlichen ${applicationGroupTitle} installiert werden."

    temporaryJSONFile="${dialogInspectModeJSONFile%.json}.tmp.$$.json"

    info "Generating temporary Inspect Mode configuration '${temporaryJSONFile}'."

    if ! /usr/bin/jq -n \
        --arg preset "preset${organizationPreset}" \
        --arg windowTitle "${windowTitle}" \
        --arg windowMessage "${windowMessage}" \
        --arg applicationIcon "${applicationIcon}" \
        --arg overlayIcon "${organizationOverlayIconURL}" \
        --arg installomatorLog "${installomatorLog}" \
        '
        {
            preset: $preset,
            title: $windowTitle,
            message: $windowMessage,

            icon: $applicationIcon,
            overlayicon: $overlayIcon,
            iconsize: 120,
            size: "standard",

            highlightColor: "#FF904C",
            scanInterval: 1,

            logMonitor: {
                path: $installomatorLog,
                pattern: ": (?:INFO|DEBUG|REQ|WARN)\\s+: [^:]+ : ((?:(?:Downloading|Mounted|Mounting|Verifying|Copy|Copying|Installing|Unpacking|Removing|Running|Extracting)\\s+.+?(?:\\.dmg|\\.pkg|\\.zip|\\.app|$)|(?:Installed|Downloaded) version: [\\d.]+|\\d+%|App\\(s\\) found: .+?\\.app))",
                captureGroup: 1,
                autoMatch: true,
                startFromEnd: true
            },

            sideMessage: [
                "Die Installation wird automatisch überwacht.",
                "Vielen Dank für Ihre Geduld.",
                "Microsoft Word wird installiert – erstellen Sie professionelle Dokumente.",
                "Microsoft Excel wird installiert – analysieren und visualisieren Sie Ihre Daten.",
                "Microsoft PowerPoint wird installiert – erstellen Sie überzeugende Präsentationen.",
                "Microsoft Outlook wird installiert – E-Mail, Kalender und Kontakte an einem Ort.",
                "Microsoft OneNote wird installiert – halten Sie Ideen und Notizen zentral fest.",
                "Microsoft OneDrive wird installiert – greifen Sie sicher auf Ihre Dateien zu.",
                "Microsoft Teams wird installiert – chatten, telefonieren und arbeiten Sie gemeinsam."
            ],
            sideInterval: 8,

            button1text: "Bitte warten …",
            button1disabled: true,
            autoEnableButton: true,
            autoEnableButtonText: "Schließen",

            items: [
                {
                    id: "microsoftword",
                    displayName: "Microsoft Word",
                    guiIndex: 0,
                    paths: [
                        "/Applications/Microsoft Word.app"
                    ],
                    icon: "https://baselineapit.blob.core.windows.net/resources/AppIcons/Word.png",
                    showBundleInfo: "all"
                },
                {
                    id: "microsoftexcel",
                    displayName: "Microsoft Excel",
                    guiIndex: 1,
                    paths: [
                        "/Applications/Microsoft Excel.app"
                    ],
                    icon: "https://baselineapit.blob.core.windows.net/resources/AppIcons/Excel.png",
                    showBundleInfo: "all"
                },
                {
                    id: "microsoftpowerpoint",
                    displayName: "Microsoft PowerPoint",
                    guiIndex: 2,
                    paths: [
                        "/Applications/Microsoft PowerPoint.app"
                    ],
                    icon: "https://baselineapit.blob.core.windows.net/resources/AppIcons/Powerpoint.png",
                    showBundleInfo: "all"
                },
                {
                    id: "microsoftoutlook",
                    displayName: "Microsoft Outlook",
                    guiIndex: 3,
                    paths: [
                        "/Applications/Microsoft Outlook.app"
                    ],
                    icon: "https://baselineapit.blob.core.windows.net/resources/AppIcons/Outlook.png",
                    showBundleInfo: "all"
                },
                {
                    id: "microsoftonenote",
                    displayName: "Microsoft OneNote",
                    guiIndex: 4,
                    paths: [
                        "/Applications/Microsoft OneNote.app"
                    ],
                    icon: "https://baselineapit.blob.core.windows.net/resources/AppIcons/OneNote.png",
                    showBundleInfo: "all"
                },
                {
                    id: "microsoftonedrive",
                    displayName: "OneDrive",
                    guiIndex: 5,
                    paths: [
                        "/Applications/OneDrive.app"
                    ],
                    icon: "https://baselineapit.blob.core.windows.net/resources/AppIcons/OneDrive.png",
                    showBundleInfo: "all"
                },
                {
                    id: "microsoftteamsnew",
                    displayName: "Microsoft Teams",
                    guiIndex: 6,
                    paths: [
                        "/Applications/Microsoft Teams.app"
                    ],
                    icon: "https://baselineapit.blob.core.windows.net/resources/AppIcons/Teams.png",
                    showBundleInfo: "all"
                }
            ]
        }
        ' > "${temporaryJSONFile}"
    then
        fatal "Failed to generate the Inspect Mode JSON."
    fi

    ################################################################################################
    # JSON syntax and structural validation
    ################################################################################################

    if ! jqValidationError=$(
    /usr/bin/jq -e '
        ((.preset | type) == "string")
        and (.preset | test("^preset[1-7]$"))

        and ((.logMonitor | type) == "object")
        and ((.logMonitor.path | type) == "string")
        and ((.logMonitor.path | length) > 0)

        and (
            (.logMonitor.preset == "installomator")
            or
            (
                ((.logMonitor.pattern | type) == "string")
                and ((.logMonitor.pattern | length) > 0)
                and ((.logMonitor.captureGroup | type) == "number")
                and (.logMonitor.captureGroup >= 0)
            )
        )

        and ((.items | type) == "array")
        and ((.items | length) > 0)

        and (
            ([.items[].id] | unique | length)
            ==
            (.items | length)
        )

        and (
            ([.items[].guiIndex] | unique | length)
            ==
            (.items | length)
        )

        and all(
            .items[];
            ((.id | type) == "string")
            and ((.id | length) > 0)
            and ((.displayName | type) == "string")
            and ((.displayName | length) > 0)
            and ((.guiIndex | type) == "number")
            and ((.paths | type) == "array")
            and ((.paths | length) > 0)
            and all(
                .paths[];
                (type == "string") and (length > 0)
            )
        )
    ' "${temporaryJSONFile}" 2>&1
); then
        fatal "Inspect Mode JSON failed structural validation: ${jqValidationError}"
    fi
    ################################################################################################
    # Ownership, permissions and atomic deployment
    ################################################################################################

    /usr/sbin/chown root:wheel "${temporaryJSONFile}" ||
        fatal "Failed to set ownership on '${temporaryJSONFile}'."

    /bin/chmod 644 "${temporaryJSONFile}" ||
        fatal "Failed to set permissions on '${temporaryJSONFile}'."

    /bin/mv -f "${temporaryJSONFile}" "${dialogInspectModeJSONFile}" ||
        fatal "Failed to move the JSON into its production location."

    temporaryJSONFile=""

    info "Inspect Mode JSON created successfully at '${dialogInspectModeJSONFile}'."
}

####################################################################################################
#
# Main
#
####################################################################################################

info "Starting version ${scriptVersion}."

prepareFileSystem
createInspectConfig

info "Completed successfully in ${SECONDS} seconds."

exit 0
