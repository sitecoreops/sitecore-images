[CmdletBinding(DefaultParameterSetName = "__Quickstart")]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "SitecorePassword")]
Param(
  [Parameter(Position = 0, Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$Registry
  ,
  [Parameter(ParameterSetName = "__Quickstart", Position = 1, Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$SitecoreUsername
  ,
  [Parameter(ParameterSetName = "__Quickstart", Position = 2, Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$SitecorePassword
  ,
  [Parameter(Position = 3)]
  [ValidateScript({ (Test-Path $_ -PathType "Container") -or (Test-Path $_ -IsValid) })]
  [string]$SavePath = ".\packages"
  ,
  [Parameter(ParameterSetName = "__Local", Position = 1, Mandatory)]
  [ValidateScript({ Test-Path $_ -PathType "Container" })]
  [string]$InstallSourcePath
)
Begin {
  $eap = $ErrorActionPreference
  $pp = $ProgressPreference

  $ErrorActionPreference = "Stop"
  $ProgressPreference = "SilentlyContinue";

  $InstallSourceResolver = $null
  $LookupTable = @{}
  $scSession = $null
}
Process {
  # Import module
  Import-Module .\modules\SitecoreImageBuilder -Force

  # Establish mechanism to fiding packages based on incoming params  
  If ($PSCmdlet.ParameterSetName -eq "__Local") {
    $InstallSourceResolver = {
      Param($Filename)
      $result = Join-Path $InstallSourcePath -ChildPath $Filename
      Write-Verbose "${filename} resolved to ${result}"
      Return $result
    }
  } Else {
    # Cache a list of packages we could potentially be downloading into
    # a lookup table we'll use in the InstallSourceResolver
    $packages = Get-Content ".\packages.json" | Where-Object { $_ -notmatch "^(\s*//|\s+$)" } | ConvertFrom-Json
    $packages | Get-Member -MemberType NoteProperty | ForEach-Object {
      $packageName = $_.Name
      $package = $packages.$packageName
      
      If ($null -ne $package.url) {
        $LookupTable.Add($package.filename, $package.url)
      }
    }

    # ensure SavePath exists
    If (!(Test-Path $SavePath)) {
      New-Item $SavePath -ItemType "Directory" | Out-Null
    }

    $InstallSourceResolver = {
      Param($Filename, $Tag)

      $expectedLocation = Join-Path $SavePath -ChildPath $Filename
      If (Test-Path $expectedLocation -PathType "Leaf") {
        Write-Verbose "${filename} resolved to ${expectedLocation}"
        Return $expectedLocation
      }

      $remoteSource = $LookupTable.$Filename
      If ($null -ne $remoteSource) {
        Write-Verbose "${filename} not found locally, attempting to fetch from dev.sitecore.net"

        if ($null -eq $scSession) {
          Write-Verbose "Logging into dev.sitecore.net"
          $loginResponse = Invoke-WebRequest "https://dev.sitecore.net/api/authorization" -Method Post -Body @{
            username = $SitecoreUsername
            password = $SitecorePassword
            rememberMe = $true
          } -SessionVariable "scSession" -UseBasicParsing
          If ($null -eq $loginResponse -or $loginResponse.StatusCode -ne 200) {
            Throw "Unable to login to dev.sitecore.net with the supplied credentials"
          }
          Write-Verbose "Logged in."
        }

        Write-Verbose "Downloading ${Filename} from ${remoteSource}"
        Invoke-WebRequest -Uri $remoteSource -OutFile $expectedLocation -WebSession $scSession -UseBasicParsing
        
        Write-Verbose "Download saved to ${expectedLocation}"
        Return $expectedLocation
      }

      Throw "Unable to find/fetch ${Filename} needed for ${Tag}"
    }
  }

  # Begin build (for quickstart, let's skip 7.5 as it's a little old and requires a 10gb
  # download now from dev.sitecore.net's archive)
  SitecoreImageBuilder\Invoke-Build `
    -Path "${PSScriptRoot}\images" `
    -InstallSourceResolver $InstallSourceResolver `
    -Registry $Registry `
    -Exclude "*:7.5*" `
    -Verbose:$VerbosePreference
}
End {
  $ErrorActionPreference = $eap;
  $ProgressPreference = $pp
}