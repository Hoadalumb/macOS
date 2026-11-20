#!/bin/zsh --no-rcs

####################################################################################################
#
# swiftDialog Inspect Mode Preset 6 setup guide for Baseline
#
# Purpose:
#   Shows a guided setup window after the Baseline installation and performs each step
#   (Microsoft Edge as default browser, Microsoft Outlook as default mail application,
#   installation check, Dock layout, Company Portal sign-in, Teams screen recording)
#   while the user is on that step.
#
# Execution:
#   Run as a Baseline FinalScript with AsUser set to false.
#
# How steps complete:
#   Every processing step lists a marker file in "paths". swiftDialog keeps the step waiting
#   until that file exists. This script watches /tmp/preset6_interaction.log to see which step
#   the user is on, does the work and then creates the marker file.
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

readonly scriptVersion="1.2.0"
readonly humanReadableScriptName="swiftDialog setup guide"

readonly scriptLog="/var/log/apitmsSetupGuide.log"

readonly dialogBinary="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"
readonly dockutilBinary="/usr/local/bin/dockutil"
readonly installomatorPath="/usr/local/Installomator/Installomator.sh"

readonly organizationHighlightColor="#FF904C"
readonly defaultApplicationIcon="https://usw2.ics.services.jamfcloud.com/icon/hash_8bf6549c22de3db831aafaf9c5c02d3aa9a928f4abe377eb2f8cbeab3959615c"

readonly edgeAppPath="/Applications/Microsoft Edge.app"
readonly edgeBundleID="com.microsoft.edgemac"
readonly edgeConfirmationTimeout=180

readonly outlookAppPath="/Applications/Microsoft Outlook.app"
readonly outlookBundleID="com.microsoft.Outlook"
readonly outlookConfirmationTimeout=60

readonly guideDirectory="/var/tmp/apitms-guide"
readonly guideJSONFile="${guideDirectory}/setup-guide.json"
readonly guideStateDirectory="${guideDirectory}/state"
readonly edgeMarker="${guideDirectory}/edge.done"
readonly mailMarker="${guideDirectory}/mail.done"
readonly checkMarker="${guideDirectory}/check.done"
readonly dockMarker="${guideDirectory}/dock.done"

# Fixed path written by swiftDialog Preset 6 for every navigation event.
readonly interactionLog="/tmp/preset6_interaction.log"

# Guide step indexes, must match the order of "items" in the JSON.
readonly edgeStepIndex=1
readonly mailStepIndex=2
readonly checkStepIndex=3
readonly dockStepIndex=4
readonly portalStepIndex=5
readonly screenStepIndex=6

readonly companyPortalAppPath="/Applications/Company Portal.app"
readonly teamsAppPath="/Applications/Microsoft Teams.app"
readonly screenRecordingSettingsURL="x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"

# Required applications as "Installomator label|Display name|Path".
# Used for the installation check and, in this order, for the Dock.
# Company Portal is installed by Intune; Installomator is only the fallback if it is missing.
readonly requiredApps=(
    "microsoftedge|Microsoft Edge|/Applications/Microsoft Edge.app"
    "microsoftoutlook|Microsoft Outlook|/Applications/Microsoft Outlook.app"
    "microsoftteamsnew|Microsoft Teams|/Applications/Microsoft Teams.app"
    "microsoftword|Microsoft Word|/Applications/Microsoft Word.app"
    "microsoftexcel|Microsoft Excel|/Applications/Microsoft Excel.app"
    "microsoftpowerpoint|Microsoft PowerPoint|/Applications/Microsoft PowerPoint.app"
    "microsoftonenote|Microsoft OneNote|/Applications/Microsoft OneNote.app"
    "microsoftonedrive|OneDrive|/Applications/OneDrive.app"
    "microsoftcompanyportal|Company Portal|/Applications/Company Portal.app"
    "microsoftautoupdate|Microsoft AutoUpdate|/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"
)

typeset dialogPID=""

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
    if [[ -n "${dialogPID}" ]] && /bin/kill -0 "${dialogPID}" 2>/dev/null; then
        /bin/kill "${dialogPID}" 2>/dev/null
    fi
}

trap cleanup EXIT

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

loggedInUserUID=$(/usr/bin/id -u "${loggedInUser}")
loggedInUserHome=$(/usr/bin/dscl . -read "/Users/${loggedInUser}" NFSHomeDirectory | /usr/bin/awk '{ print $2 }')

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

info "Detected logged-in user '${loggedInUser}' (UID ${loggedInUserUID}) with first name '${loggedInUserFirstName}'."

function runAsUser() {
    /bin/launchctl asuser "${loggedInUserUID}" /usr/bin/sudo -u "${loggedInUser}" "$@"
}

####################################################################################################
#
# Requirements
#
####################################################################################################

if [[ ! -x "${dialogBinary}" ]]; then
    fatal "swiftDialog is not installed at '${dialogBinary}'."
fi

if [[ ! -x "/usr/bin/jq" ]]; then
    fatal "/usr/bin/jq is unavailable; the guide configuration cannot be generated."
fi

####################################################################################################
#
# Create guide configuration
#
####################################################################################################

function prepareFileSystem() {
    info "Preparing guide directory '${guideDirectory}'."

    /bin/rm -rf "${guideDirectory}"
    /bin/mkdir -p "${guideStateDirectory}" ||
        fatal "Failed to create '${guideStateDirectory}'."

    /usr/sbin/chown root:wheel "${guideDirectory}"
    /bin/chmod 755 "${guideDirectory}"

    # swiftDialog runs as the user and saves its step state here.
    /usr/sbin/chown "${loggedInUser}" "${guideStateDirectory}"

    # Start without events from an earlier run.
    /bin/rm -f "${interactionLog}" "/tmp/preset6_interaction.plist"
}

function createGuideConfig() {
    info "Generating guide configuration '${guideJSONFile}'."

    if ! /usr/bin/jq -n \
        --arg windowTitle "Hallo ${loggedInUserFirstName}, fast geschafft!" \
        --arg applicationIcon "${defaultApplicationIcon}" \
        --arg highlightColor "${organizationHighlightColor}" \
        --arg edgeMarker "${edgeMarker}" \
        --arg mailMarker "${mailMarker}" \
        --arg checkMarker "${checkMarker}" \
        --arg dockMarker "${dockMarker}" \
        '
        {
            preset: "6",
            title: $windowTitle,
            icon: $applicationIcon,
            highlightColor: $highlightColor,

            items: [
                {
                    id: "welcome",
                    displayName: "Willkommen",
                    guiIndex: 0,
                    icon: "SF=hand.wave.fill",
                    stepType: "info",
                    paths: [],
                    guidanceTitle: "Willkommen bei der anyplace IT GmbH",
                    guidanceContent: [
                        { type: "text", content: "Alle Microsoft 365-Anwendungen wurden installiert. Wir richten jetzt noch Ihren Arbeitsplatz ein." },
                        { type: "bullets", items: [
                            "Microsoft Edge als Standardbrowser",
                            "Microsoft Outlook als Standard-E-Mail-Programm",
                            "Prüfung der installierten Anwendungen",
                            "Dock mit Ihren Anwendungen",
                            "Anmeldung im Unternehmensportal",
                            "Bildschirmfreigabe für Microsoft Teams"
                        ] }
                    ]
                },
                {
                    id: "edge",
                    displayName: "Standardbrowser",
                    guiIndex: 1,
                    icon: "SF=globe",
                    stepType: "processing",
                    processingMode: "progressive",
                    waitForExternalTrigger: true,
                    processingMessage: "Microsoft Edge wird als Standardbrowser festgelegt …",
                    paths: [ $edgeMarker ],
                    guidanceTitle: "Microsoft Edge als Standardbrowser",
                    guidanceContent: [
                        { type: "text", content: "Microsoft Edge wird als Standardbrowser festgelegt, damit Links aus Outlook und Teams direkt in Edge geöffnet werden." },
                        { type: "info", content: "macOS fragt gleich nach, welchen Browser Sie verwenden möchten. Bitte wählen Sie „Microsoft Edge“ verwenden." }
                    ]
                },
                {
                    id: "mail",
                    displayName: "E-Mail-Programm",
                    guiIndex: 2,
                    icon: "SF=envelope.fill",
                    stepType: "processing",
                    processingMode: "progressive",
                    waitForExternalTrigger: true,
                    processingMessage: "Microsoft Outlook wird als Standard-E-Mail-Programm festgelegt …",
                    paths: [ $mailMarker ],
                    guidanceTitle: "Microsoft Outlook als Standard-E-Mail-Programm",
                    guidanceContent: [
                        { type: "text", content: "Microsoft Outlook wird als Standard-E-Mail-Programm festgelegt, damit E-Mail-Links und „Senden an“ direkt eine neue Nachricht in Outlook öffnen." }
                    ]
                },
                {
                    id: "check",
                    displayName: "Prüfung",
                    guiIndex: 3,
                    icon: "SF=checklist",
                    stepType: "processing",
                    processingMode: "progressive",
                    waitForExternalTrigger: true,
                    processingMessage: "Die installierten Anwendungen werden geprüft …",
                    paths: [ $checkMarker ],
                    guidanceTitle: "Anwendungen prüfen",
                    guidanceContent: [
                        { type: "text", content: "Wir prüfen, ob alle Anwendungen installiert wurden. Fehlende Anwendungen werden automatisch erneut installiert." },
                        { type: "info", content: "Das kann einige Minuten dauern, falls eine Anwendung erneut installiert werden muss." }
                    ]
                },
                {
                    id: "dock",
                    displayName: "Dock",
                    guiIndex: 4,
                    icon: "SF=dock.rectangle",
                    stepType: "processing",
                    processingMode: "progressive",
                    waitForExternalTrigger: true,
                    processingMessage: "Das Dock wird eingerichtet …",
                    paths: [ $dockMarker ],
                    guidanceTitle: "Dock einrichten",
                    guidanceContent: [
                        { type: "text", content: "Ihre installierten Anwendungen werden im Dock abgelegt, damit Sie sie mit einem Klick starten können." },
                        { type: "info", content: "Über das Unternehmensportal installieren Sie weitere Firmen-Apps, mit Microsoft AutoUpdate halten Sie Microsoft 365 aktuell." }
                    ]
                },
                {
                    id: "portal",
                    displayName: "Unternehmensportal",
                    guiIndex: 5,
                    icon: "SF=building.2.fill",
                    stepType: "info",
                    paths: [],
                    guidanceTitle: "Im Unternehmensportal anmelden",
                    guidanceContent: [
                        { type: "text", content: "Das Unternehmensportal wird jetzt geöffnet. Mit der Anmeldung wird Ihr Mac bei der anyplace IT GmbH registriert. Erst danach können Sie Outlook, Teams und OneDrive mit Ihrem Firmenkonto nutzen." },
                        { type: "bullets", items: [
                            "Klicken Sie im Unternehmensportal auf „Anmelden“.",
                            "Melden Sie sich mit Ihrer Firmen-E-Mail-Adresse und Ihrem Passwort an.",
                            "Folgen Sie den Anweisungen, bis die Registrierung abgeschlossen ist."
                        ] },
                        { type: "info", content: "Kehren Sie danach zu diesem Fenster zurück und klicken Sie auf „Weiter“." }
                    ]
                },
                {
                    id: "screen",
                    displayName: "Bildschirmfreigabe",
                    guiIndex: 6,
                    icon: "SF=rectangle.inset.filled.and.person.filled",
                    stepType: "info",
                    paths: [],
                    guidanceTitle: "Bildschirmfreigabe für Microsoft Teams",
                    guidanceContent: [
                        { type: "text", content: "Damit Sie in Teams-Besprechungen Ihren Bildschirm teilen können, muss macOS Teams die Bildschirmaufnahme erlauben. Die Systemeinstellungen werden dafür jetzt geöffnet." },
                        { type: "bullets", items: [
                            "Aktivieren Sie den Schalter bei „Microsoft Teams“.",
                            "Steht Teams nicht in der Liste: Klicken Sie auf „+“ und wählen Sie im Ordner „Programme“ „Microsoft Teams“ aus.",
                            "Bestätigen Sie mit Ihrem Mac-Passwort."
                        ] },
                        { type: "info", content: "Kehren Sie danach zu diesem Fenster zurück und klicken Sie auf „Weiter“." }
                    ]
                },
                {
                    id: "done",
                    displayName: "Fertig",
                    guiIndex: 7,
                    icon: "SF=checkmark.seal.fill",
                    stepType: "info",
                    paths: [],
                    guidanceTitle: "Ihr Mac ist bereit",
                    guidanceContent: [
                        { type: "text", content: "Die Einrichtung ist abgeschlossen. Melden Sie sich in Outlook und Teams mit Ihrem Firmenkonto an." },
                        { type: "info", content: "Bei Fragen wenden Sie sich bitte an den IT-Support der anyplace IT GmbH." }
                    ]
                }
            ]
        }
        ' > "${guideJSONFile}"
    then
        fatal "Failed to generate the guide JSON."
    fi

    /bin/chmod 644 "${guideJSONFile}"
}

####################################################################################################
#
# Guide steps
#
####################################################################################################

# Blocks until the user has navigated to the given step index.
function waitForStep() {
    local stepIndex="${1}"

    until /usr/bin/grep -q " current=${stepIndex} " "${interactionLog}" 2>/dev/null; do
        if ! /bin/kill -0 "${dialogPID}" 2>/dev/null; then
            warning "The guide was closed before step ${stepIndex} was reached."
            return 1
        fi
        /bin/sleep 1
    done
}

# usage: currentDefaultBrowser [http|https]
function currentDefaultBrowser() {
    local scheme="${1:-https}"

    runAsUser /usr/bin/osascript -l JavaScript -e "
        ObjC.import('AppKit');
        \$.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL(\$.NSURL.URLWithString('${scheme}://example.com')).path.js
    " 2>/dev/null
}

# Requests Edge for one URL scheme and waits for the user to confirm the macOS prompt.
# usage: requestEdgeForScheme http|https
function requestEdgeForScheme() {
    local scheme="${1}"

    info "Requesting Microsoft Edge as default handler for '${scheme}'."
    runAsUser /usr/bin/osascript -l JavaScript -e "
        ObjC.import('CoreServices');
        \$.LSSetDefaultHandlerForURLScheme(\$('${scheme}'), \$('${edgeBundleID}'));
    " > /dev/null 2>&1

    local waited=0
    until [[ "$(currentDefaultBrowser "${scheme}")" == "${edgeAppPath}" ]]; do
        if [[ "${waited}" -ge "${edgeConfirmationTimeout}" ]]; then
            warning "Microsoft Edge was not confirmed for '${scheme}' within ${edgeConfirmationTimeout} seconds."
            return 1
        fi
        /bin/sleep 2
        waited=$(( waited + 2 ))
    done
}

function setEdgeAsDefaultBrowser() {
    if [[ ! -d "${edgeAppPath}" ]]; then
        warning "'${edgeAppPath}' is not installed; skipping the default browser."
        return 0
    fi

    if [[ "$(currentDefaultBrowser)" == "${edgeAppPath}" ]]; then
        info "Microsoft Edge is already the default browser."
        return 0
    fi

    # macOS asks the user to confirm each change in a system dialog. Confirming "http"
    # usually switches "https" too, so only ask for "https" if it did not follow.
    requestEdgeForScheme http || return 0

    if [[ "$(currentDefaultBrowser https)" != "${edgeAppPath}" ]]; then
        requestEdgeForScheme https || return 0
    fi

    info "Microsoft Edge is now the default browser."
}

function currentDefaultMailApp() {
    runAsUser /usr/bin/osascript -l JavaScript -e "
        ObjC.import('AppKit');
        \$.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL(\$.NSURL.URLWithString('mailto:user@example.com')).path.js
    " 2>/dev/null
}

function setOutlookAsDefaultMail() {
    if [[ ! -d "${outlookAppPath}" ]]; then
        warning "'${outlookAppPath}' is not installed; skipping the default mail application."
        return 0
    fi

    if [[ "$(currentDefaultMailApp)" == "${outlookAppPath}" ]]; then
        info "Microsoft Outlook is already the default mail application."
        return 0
    fi

    # Unlike the browser, macOS changes the mail handler without a confirmation prompt.
    info "Requesting Microsoft Outlook as default handler for 'mailto'."
    runAsUser /usr/bin/osascript -l JavaScript -e "
        ObjC.import('CoreServices');
        \$.LSSetDefaultHandlerForURLScheme(\$('mailto'), \$('${outlookBundleID}'));
    " > /dev/null 2>&1

    local waited=0
    until [[ "$(currentDefaultMailApp)" == "${outlookAppPath}" ]]; do
        if [[ "${waited}" -ge "${outlookConfirmationTimeout}" ]]; then
            warning "Microsoft Outlook was not set as default mail application within ${outlookConfirmationTimeout} seconds."
            return 0
        fi
        /bin/sleep 2
        waited=$(( waited + 2 ))
    done

    info "Microsoft Outlook is now the default mail application."
}

function checkInstalledApps() {
    local entry label displayName appPath
    local missingApps=()

    for entry in "${requiredApps[@]}"; do
        IFS="|" read -r label displayName appPath <<< "${entry}"

        if [[ -e "${appPath}" ]]; then
            continue
        fi

        warning "'${displayName}' is missing; retrying installation with Installomator label '${label}'."
        "${installomatorPath}" "${label}" NOTIFY=silent BLOCKING_PROCESS_ACTION=kill > /dev/null 2>&1

        if [[ -e "${appPath}" ]]; then
            info "'${displayName}' installed successfully on retry."
        else
            warning "'${displayName}' is still missing after the retry."
            missingApps+=("${displayName}")
        fi
    done

    if [[ ${#missingApps[@]} -eq 0 ]]; then
        info "All required applications are installed."
        return 0
    fi

    # The user may continue; the Dock step skips missing applications.
    local missingList=""
    local app
    for app in "${missingApps[@]}"; do
        missingList+="- ${app}\n"
    done

    runAsUser "${dialogBinary}" \
        --title "Nicht alle Anwendungen installiert" \
        --message "Folgende Anwendungen konnten nicht installiert werden:\n\n${missingList}\nSie können die Einrichtung trotzdem fortsetzen. Bitte wenden Sie sich an den IT-Support der anyplace IT GmbH." \
        --icon "SF=exclamationmark.triangle.fill,colour=${organizationHighlightColor}" \
        --button1text "Weiter" \
        --ontop \
        --width 520 \
        --height 320 > /dev/null 2>&1
}

function configureDock() {
    if [[ ! -x "${dockutilBinary}" ]]; then
        info "dockutil not found, installing it with Installomator."
        "${installomatorPath}" dockutil NOTIFY=silent > /dev/null 2>&1
    fi

    if [[ ! -x "${dockutilBinary}" ]]; then
        warning "dockutil could not be installed; skipping the Dock configuration."
        return 0
    fi

    local launcherApp="/System/Applications/Launchpad.app"
    [[ -e "/System/Applications/Apps.app" ]] && launcherApp="/System/Applications/Apps.app"

    local dockApps=("${launcherApp}")
    local entry
    for entry in "${requiredApps[@]}"; do
        dockApps+=("${entry##*|}")
    done
    dockApps+=("/System/Applications/System Settings.app")

    local dockPlist="${loggedInUserHome}/Library/Preferences/com.apple.dock.plist"

    info "Configuring the Dock for '${loggedInUser}'."
    runAsUser "${dockutilBinary}" --remove all --no-restart "${dockPlist}" > /dev/null 2>&1

    local app
    for app in "${dockApps[@]}"; do
        if [[ -e "${app}" ]]; then
            runAsUser "${dockutilBinary}" --add "${app}" --section apps --no-restart "${dockPlist}" > /dev/null 2>&1
        else
            warning "'${app}' is not installed; not adding it to the Dock."
        fi
    done

    runAsUser "${dockutilBinary}" --add "${loggedInUserHome}/Downloads" --section others --view fan --display stack --no-restart "${dockPlist}" > /dev/null 2>&1

    /usr/bin/killall Dock 2>/dev/null
    info "Dock configured."
}

function openCompanyPortal() {
    if [[ ! -d "${companyPortalAppPath}" ]]; then
        warning "'${companyPortalAppPath}' is not installed; cannot open it for sign-in."
        return 0
    fi

    info "Opening Company Portal for the user sign-in."
    runAsUser /usr/bin/open -a "${companyPortalAppPath}"
}

function openScreenRecordingSettings() {
    if [[ ! -d "${teamsAppPath}" ]]; then
        warning "'${teamsAppPath}' is not installed; skipping the screen recording step."
        return 0
    fi

    info "Opening System Settings > Privacy & Security > Screen & System Audio Recording."
    runAsUser /usr/bin/open "${screenRecordingSettingsURL}"
}

####################################################################################################
#
# Main
#
####################################################################################################

info "Starting version ${scriptVersion}."

prepareFileSystem
createGuideConfig

info "Launching the setup guide."
runAsUser /usr/bin/env \
    DIALOG_INSPECT_CONFIG="${guideJSONFile}" \
    DIALOG_PERSIST_PATH="${guideStateDirectory}" \
    "${dialogBinary}" --inspect-mode > /dev/null 2>&1 &
dialogPID=$!

if waitForStep "${edgeStepIndex}"; then
    setEdgeAsDefaultBrowser
    /usr/bin/touch "${edgeMarker}"
fi

if waitForStep "${mailStepIndex}"; then
    setOutlookAsDefaultMail
    /usr/bin/touch "${mailMarker}"
fi

if waitForStep "${checkStepIndex}"; then
    checkInstalledApps
    /usr/bin/touch "${checkMarker}"
fi

if waitForStep "${dockStepIndex}"; then
    configureDock
    /usr/bin/touch "${dockMarker}"
fi

# Info steps: the user signs in or grants the permission and then clicks "Weiter" on their own.
if waitForStep "${portalStepIndex}"; then
    openCompanyPortal
fi

if waitForStep "${screenStepIndex}"; then
    openScreenRecordingSettings
fi

# Wait until the user closes the guide on the last step.
wait "${dialogPID}"
info "Setup guide closed with exit code $?."

dialogPID=""

info "Completed successfully in ${SECONDS} seconds."

exit 0
