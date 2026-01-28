<#PSScriptInfo
.VERSION 1.1.0
.GUID f0e560f3-0088-40e4-a29f-f86caacc2da5
.AUTHOR regexreggae
.DESCRIPTION dynamically enable Global Secure Access tunnelling depending on location (on-site vs off-site)
#>
<#
.DESCRIPTION
dynamically enable Global Secure Access tunnelling depending on location (on-site vs off-site)
#>

#region ### EXPLANATION
# this script starts the GSA services if off-site
# by default, it uses both DNS lookup and ping to find out
# DNS lookup can be skipped if a simple ping is sufficient for you
# only if the checks are successful the client is considered on-prem
# the script should be run in user context since it only starts services the user has control about
#endregion

#region ### PARAMETERS
# skipDns --> skips name resolution as a required check. the script will then solely rely on ping.
# simulateOffSiteLocation --> this will make the script assume you are off-site even though you might actually be on-prem
# simulateOnSiteLocation --> this will make the script assume you are on-prem even though you are actually outside your company
# disableIfAlreadyRunning --> this will stop the GSA services if they are already running. Will only take effect on-premises (real or simulated on-prem location)
# forceEnglishToasts --> this will force the BurntToast messages to have English text independent of actual uiCulture
# configFilePath --> optionally indicate a different path to your config file.
#endregion

#region ### REQUIREMENTS
# GSA services (as defined below) have to be changed to StartType = manual (Microsoft's default is to have them all auto-start)
# a json config file - default is in the same folder as this script (same name as script, but with .json extension instead of .ps1). can be overridden with $configFilePath param
# optional, but highly recommended: BurntToast PowerShell module installed
#endregion

param(
    [switch]$skipDns,
    [switch]$simulateOffSiteLocation,
    [switch]$simulateOnSiteLocation,
    [switch]$disableIfAlreadyRunning,
    [switch]$forceEnglishToasts,
    [string]$configFilePath = ""
)

### static core parameters
# paths
$detectionFilePath = "C:\Program Files\Global Secure Access Client\GlobalSecureAccessClientManagerService.exe"
if ($configFilePath -eq "") {$configFilePath = $($myinvocation.MyCommand.Path) -replace "\.ps1", ".json"}
# networking / GSA stuff
$maxTriesForNetworkCheck = 10
$gsaSvcNames = @(
    "GlobalSecureAccessEngineService",
    "GlobalSecureAccessForwardingProfileService",
    "GlobalSecureAccessTunnelingService"
)
$gsaSvcs = @()

# exit Script if GSA not installed
if (-not(Test-Path $detectionFilePath)) {
    Write-Host "Global Secure Access client apparently not installed, no need to do anything, exiting." -ForegroundColor Yellow
    exit 0
}

# read core parameters from config file. exit script if not present or not readable
try {
    $myValues = ConvertFrom-Json -InputObject $(Get-Content $configFilePath -Raw -ErrorAction Stop) -ErrorAction Stop
    # core parameters as defined in the config file
    # paths
    $imagePath = $myValues.imagePath
    # company specific IPs / FQDNs
    $fqdnToResolve = $myValues.fqdnToResolve
    $expectedIp = $myValues.expectedIp
    $dnsServerIp = $myValues.dnsServerIp
    $pingHostIp = $myValues.pingHostIp
}
catch {
    Write-Host "Config file $($configFilePath) doesn't exist or is unreadable, exiting with error code 1" -ForegroundColor Red
    exit 1
}


# First Check: Script used without mutually exclusive switches (critical)?
if ($simulateOffSiteLocation -and $simulateOnSiteLocation) {
    Write-Host "The switches you used are mutually exclusive. Exiting with error code 1" -ForegroundColor Red
    exit 1
}

# Second Check: StartType = Manual (critical)?
try {foreach ($svcName in $gsaSvcNames){$currentSvc = $(Get-Service -Name $svcName -ErrorAction Stop);$gsaSvcs += $currentSvc}} # get each gsa Service as an object out of the list $gsaSvcNames
catch {Write-Host "Error trying to get gsa Services, exiting now with error code 1" -ForegroundColor Red; exit 1}
$preChecksPassed = $true
foreach ($svc in $gsaSvcs) { # iterate through each gsa Svc and check its StartType
    if ($svc.StartType -ne "Manual"){
        Write-Host "$($svc.Name) StartType is $($svc.StartType), this needs to be 'Manual' for the script to work, will exit with error code 1 soon..." -ForegroundColor Yellow
        $preChecksPassed = $false
    }
}
if (-not($preChecksPassed)){exit 1}

# Third Check: BurntToast Module available (not critical)?
try {
    Import-Module BurntToast -ErrorAction Stop
    Write-Host "BurntToast Module is available" -ForegroundColor Green
    $burntToastAvailable = $true

}
catch {
    Write-Host "BurntToast Module not available" -ForegroundColor Yellow
    $burntToastAvailable = $false
}

### LOCATION TESTS

# 0. Network Availability
$counter = 0
while ($counter -le $maxTriesForNetworkCheck) {
    $onlineAdaptors = get-netadapter -Physical | Where-Object {($_.InterfaceType -in 6, 71) -and ($_.Status -eq "Up")} # this will only return wifi or ethernet adapters that are up (physically, at least)
    if ($onlineAdaptors) {
        Write-Host "`nNetwork seems available, checks continue..." -ForegroundColor Green
        break
    } else {
        # case: no networking yet, apparently...wait for a couple of seconds
        Start-Sleep -Seconds 5
        $counter ++
    }
}

# 1. PING
Write-Host "Performing Ping test to $($pingHostIp)..." -ForegroundColor Green
$pingTest = Test-NetConnection -ComputerName $pingHostIp -InformationLevel Quiet

# 2. DNS Record (unless Ping failed or requested to be skipped via parameter)
if ($pingTest) {
if (-not($skipDns)) {
Write-Host "Performing DNS test - trying to resolve $($fqdnToResolve) with server $($dnsServerIp)..." -ForegroundColor Green
try {
    $dnsTestAddress = $(Resolve-DnsName -Name $fqdnToResolve -Type A -DnsOnly -Server $dnsServerIp -ErrorAction Stop).IPAddress
    if ($dnsTestAddress -eq $expectedIp) {$dnsTest = $true} else {$dnsTest = $false}
} 
catch {$dnsTest = $false}
} else {
    Write-Host "Skipping DNS test..." -ForegroundColor Green
    $dnsTest = $true
}
} else {
    Write-Host "Ping test failed, no need to go for DNS" -ForegroundColor Red
}

### Determine result based on tests above
Write-Host "`nStatus: " -NoNewline
if ($($dnsTest) -and $($pingTest)) {
    $clientIsOnSite = $true
    Write-Host "Client is on-site" -ForegroundColor Green
} else {
    $clientIsOnSite = $false
    Write-Host "Client is off-site" -ForegroundColor Blue
}

# debugging: force the script to assume on/off-site location
if ($simulateOffSiteLocation) {$clientIsOnSite = $false
    Write-Host "`nSimulating off-site location independently of previously identified location" -ForegroundColor Cyan}
elseif ($simulateOnSiteLocation) {$clientIsOnSite = $true
    Write-Host "`nSimulating on-premises location independently of previously identified location" -ForegroundColor Cyan}
else {Write-Host "`nNo switch has been used with the script, going for previously identified location" -ForegroundColor Green}

### CORE - start gsa Svcs if $clientIsOnSite = $false

# determine if German messages can be used depending on uiCulture
try {
    $uiCulture = (get-uiCulture -ErrorAction Stop).Name
    if ($uiCulture -like "de-*") {
        $endUserLang = "de"
    } else {
        $endUserLang = "en"
    }
}
catch {
    $endUserLang = "en" #default to English if uiCulture cannot be determined
}
if ($forceEnglishToasts) {$endUserLang = "en"} # force English messages with BurntToast if desired

if (-not($clientIsOnSite)) { # if client is outside company network
    Write-Host "Client is off-site, starting Global Secure Access..." -ForegroundColor Green
    $svcsAreAlreadyRunning = $true
    foreach ($svc in $gsaSvcs) {
        if ($svc.Status -ne "Running"){ #set svcAreAlreadyRunning to false if at least one svc isnt running
            $svcsAreAlreadyRunning = $false
            break
        }
    }
    if (-not ($svcsAreAlreadyRunning)) { # starting the services will only be necessary if they aren't all running yet
    try {
        foreach ($svc in $gsaSvcs) {
            Start-Service $svc -ErrorAction Stop}
        $msg = "Global Secure Access started automatically" # EN
        if ($endUserLang -eq "de") {$msg = "Global Secure Access wurde automatisch gestartet"} # DE
    }
    catch {
        Write-Host "One or more GSA services couldn't be started, exiting with error code 1" -ForegroundColor Red
        exit 1
    }
    } else {
        $msg = "Global Secure Access already active" # EN
        if ($endUserLang -eq "de") {$msg = "Global Secure Access ist bereits aktiv"} # DE
    }
    
} else { # if client is on-premise (no matter if physically or simulated)
    $msg = "GSA not activated, you are on-site" # EN
    if ($endUserLang -eq "de") {$msg = "Du bist im Firmennetz, GSA nicht aktiviert"} # DE
    if ($disableIfAlreadyRunning) {
        $svcsAreAlreadyRunning = $false
        foreach ($svc in $gsaSvcs) {
            if ($svc.Status -eq "Running"){
                $svcsAreAlreadyRunning = $true
                break
            }
        }
        if ($svcsAreAlreadyRunning) {
            try {
                foreach ($svc in $gsaSvcs) {
                    Stop-Service $svc -ErrorAction Stop
                    Write-Host "Just disabled service $($svc.Name)..." -ForegroundColor Blue
                    $msg = "`nYou are on-site, GSA was disabled." # EN
                    if ($endUserLang -eq "de") {$msg = "`nDu bist im Firmennetz, GSA wurde deaktiviert"} # DE
                }
            }
            catch {
                Write-Host "Error trying to stop one or more running GSA services, exiting with error code 1" -ForegroundColor Red
                exit 1
            }
        }
    }   
    
}

# Final messages to the console / toast notification

# Console
Write-Host $msg -ForegroundColor Green

# BurntToast
if ($burntToastAvailable) {
    $header = "Info from IT" # EN
    if ($endUserLang -eq "de") {$header = "Info der IT-Abteilung"} # DE
    if (-not(Test-Path $imagePath)) {
        Write-Host "BurntToast is available, but not the image to be used with it!" -ForegroundColor Yellow
        $useImageInToast = $false
    } else {$useImageInToast = $true}
    if ($useImageInToast) {New-BurntToastNotification -Text $header, $msg -AppLogo $imagePath}
    else {New-BurntToastNotification -Text $header, $msg}
}
