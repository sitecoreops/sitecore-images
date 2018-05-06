[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript( {Test-Path $_ -PathType 'Container'})] 
    [string]$InstallSourcePath,
    [Parameter(Mandatory = $true)]
    [string]$Registry,
    [Parameter(Mandatory = $false)]
    [array]$Tags = @("*"),
    [Parameter(Mandatory = $false)]
    [ValidateSet("WhenChanged", "Always", "Never")]
    [string]$PushMode = "WhenChanged"
)

function Find-BaseImages
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript( {Test-Path $_ -PathType 'Container'})]
        [string]$Path
    )

    Get-ChildItem -Path $Path -Filter "Dockerfile" -Recurse | ForEach-Object {
        Get-Content -Path $_.FullName | Where-Object { $_.StartsWith("FROM ") } | ForEach-Object { Write-Output $_.Replace("FROM ", "").Trim() } | ForEach-Object {
            $image = $_

            if ($image -like "* as *")
            {
                $image = $image.Substring(0, $image.IndexOf(" as "))
            }

            if ([string]::IsNullOrEmpty($image))
            {
                throw ("Invalid Dockerfile '{0}', no FROM image was found?" -f $_.FullName)
            }

            Write-Output $image
        }
    }
}

function Find-BuildSpecifications
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript( {Test-Path $_ -PathType 'Container'})] 
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [ValidateScript( {Test-Path $_ -PathType 'Container'})] 
        [string]$InstallSourcePath,
        [Parameter(Mandatory = $true)]
        [array]$Tags
    )
  
    Get-ChildItem -Path $Path -Filter "build.json" -Recurse | ForEach-Object {
        $data = Get-Content -Path $_.FullName | ConvertFrom-Json
        $sources = @()

        $data.sources | ForEach-Object {
            $sources += (Join-Path $InstallSourcePath $_)
        }

        $include = $false
        
        $Tags | ForEach-Object {
            if ($data.tag -like $_)
            {
                $include = $true

                return
            }
        }

        # Default sort order
        $order = 1000

        # Set sort order if specified
        if ($data.order -ne $null)
        {
            $order = [int]::Parse($data.order)
        }

        Write-Output (New-Object PSObject -Property @{
                Version = $data.version;
                Include = $include;
                Tag     = $data.tag;                        
                Order   = $order;
                Path    = $_.Directory.FullName;
                Sources = $sources;
            })
    }
}

$ErrorActionPreference = "STOP"
$ProgressPreference = "SilentlyContinue"

$rootPath = (Join-Path $PSScriptRoot "\images")

# Find out what to build
$specs = Find-BuildSpecifications -Path $rootPath -InstallSourcePath $InstallSourcePath -Tags $Tags

# Print what was found
$specs | Sort-Object -Property Version, Order | Select-Object -Property Version, Include, Tag, Order, Path | Format-Table

Write-Host "### Build specifications loaded..." -ForegroundColor Green

# Find and pull latest external images
Find-BaseImages -Path $rootPath | Select-Object -Unique | ForEach-Object {
    $tag = $_

    if ($tag -notmatch "sitecore")
    {
        docker pull $tag

        $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw "Failed." }
    }
}

Write-Host "### External images up to date..." -ForegroundColor Green

# Start build...
$specs | Where-Object { $_.Include } | Sort-Object -Property Version, Order | ForEach-Object {
    $spec = $_
    $tag = $spec.Tag

    Write-Host ("### Processing '{0}'..." -f $tag)
    
    # Save the digest of previous builds for later comparison
    $previousDigest = $null
    
    if ((docker image ls $tag --quiet))
    {
        $previousDigest = (docker image inspect $tag) | ConvertFrom-Json | ForEach-Object { $_.Id }
    }

    # Copy any missing source files into build context
    $spec.Sources | ForEach-Object {
        $sourcePath = $_
        $sourceItem = Get-Item -Path $sourcePath
        $targetPath = Join-Path $spec.Path $sourceItem.Name

        if (!(Test-Path -Path $targetPath))
        {
            Copy-Item $sourceItem -Destination $targetPath -Verbose:$VerbosePreference
        }
    }
    
    # Build image
    docker image build --isolation "hyperv" --memory 4GB --tag $tag $spec.Path

    $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw "Failed." }

    # Tag image
    $fulltag = "{0}/{1}" -f $Registry, $tag

    docker image tag $tag $fulltag

    $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw "Failed." }

    # Check to see if we need to stop here...
    if ($PushMode -eq "Never")
    {
        Write-Warning ("### Done with '{0}', but not pushed since 'PushMode' is '{1}'." -f $tag, $PushMode)

        return
    }

    # Determine if we need to push
    $currentDigest = (docker image inspect $tag) | ConvertFrom-Json | ForEach-Object { $_.Id }

    if (($PushMode -eq "WhenChanged") -and ($currentDigest -eq $previousDigest))
    {
        Write-Host ("### Done with '{0}', but not pushed since 'PushMode' is '{1}' and the image has not changed since last build." -f $tag, $PushMode) -ForegroundColor Green

        return
    }

    # Push image
    docker image push $fulltag

    $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw "Failed." }

    Write-Host ("### Done with '{0}', image pushed." -f $fulltag) -ForegroundColor Green
}
