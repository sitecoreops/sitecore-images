[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$VersionsFilter = "*",
    [Parameter(Mandatory = $true)]
    [ValidateScript( {Test-Path $_ -PathType 'Container'})] 
    [string]$InstallSourcePath,
    [Parameter(Mandatory = $false)]
    [string]$Organization,
    [Parameter(Mandatory = $false)]
    [switch]$SkipPush
)

function Get-BaseImage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript( {Test-Path $_ -PathType 'Container'})]
        [string]$Path
    )

    Get-ChildItem -Path $Path -Filter "Dockerfile" | Foreach-Object {
        $fromImages = Get-Content -Path $_.FullName | Where-Object { $_.StartsWith("FROM ") } | ForEach-Object { Write-Output $_.Replace("FROM ", "").Trim() }
        
        $fromImages | ForEach-Object {
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
        [ValidateNotNullOrEmpty()] 
        [string]$Filter,
        [Parameter(Mandatory = $true)]
        [ValidateScript( {Test-Path $_ -PathType 'Container'})] 
        [string]$InstallSourcePath
    )
  
    Get-ChildItem -Path $Path -Filter $Filter | ForEach-Object {
        $version = $_.Name

        Get-ChildItem -Path $_.FullName -Recurse | Foreach-Object {
            $folder = $_
            $buildFilePath = Join-Path $folder.FullName "\build.json"

            if (Test-Path $buildFilePath -PathType Leaf)
            {
                $data = Get-Content -Path $buildFilePath | ConvertFrom-Json
                $sources = $data.sources | ForEach-Object {
                    Write-Output (Join-Path $InstallSourcePath $_)
                }

                # Default sort order
                $order = 1000

                # Set sort order if specified
                if ($data.order -ne $null)
                {
                    [int]::TryParse($data.order, [ref]$order) | Out-Null
                }

                Write-Output (New-Object PSObject -Property @{
                        Version = $version;    
                        Tag     = $data.tag;                        
                        Order   = $order;
                        Path    = $folder.FullName;
                        Sources = $sources;
                    })
            }
        }
    }
}

$ErrorActionPreference = "STOP"
$ProgressPreference = "SilentlyContinue"

# TODO: Change ADD to COPY
# TODO: Migrate the rest to new structure
# TODO: Build Order should be within a VERSION folder?

$rootPath = (Join-Path $PSScriptRoot "\versions")

# Find out what to build
$specs = Find-BuildSpecifications -Path $rootPath -InstallSourcePath $InstallSourcePath -Filter $VersionsFilter | Sort-Object -Property Order

# Print what was found
$specs | Select-Object -Property Version, Tag, Order, Path | Format-Table

# Find and pull latest external images
$specs | ForEach-Object {
    $tag = Get-BaseImage -Path $_.Path
    
    if ($tag -notmatch "sitecore")
    {
        Write-Output $tag
    }    
} | Select-Object -Unique | ForEach-Object {
    $tag = $_

    Write-Host ("Pulling latest base image '{0}'..." -f $tag)

    docker pull $tag

    $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw ("Pulling '{0}' failed" -f $tag) }        
}

# Start build...
$specs | ForEach-Object {
    $spec = $_
    $tag = $spec.Tag

    # Save the digest of previous builds for later comparison
    $previousDigest = $null
    
    if ((docker image ls $tag --quiet))
    {
        $previousDigest = (docker image inspect $tag) | ConvertFrom-Json | ForEach-Object { $_.Id }
    }

    Write-Host ("Building '{0}'..." -f $tag)

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

    $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw ("Build of '{0}' failed" -f $tag) }

    # Tag image
    if (![string]::IsNullOrEmpty($Organization))
    {
        $newtag = "{0}/{1}" -f $Organization, $tag

        docker image tag $tag $newtag

        $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw ("Tagging of '{0}' with '{1}' failed" -f $tag, $newtag) }
    }

    # Determine if we need to push
    $currentDigest = (docker image inspect $tag) | ConvertFrom-Json | ForEach-Object { $_.Id }

    if ($currentDigest -eq $previousDigest)
    {
        Write-Host "Done, current digest is the same as the previous, image has not changed since last build." -ForegroundColor Green

        return
    }

    if ($SkipPush)
    {
        Write-Warning "Done, SkipPush switch used."

        return
    }
    
    # Push image
    docker image push $tag

    $LASTEXITCODE -ne 0 | Where-Object { $_ } | ForEach-Object { throw ("Push of '{0}' failed" -f $tag) }

    Write-Host ("Image '{0}' pushed." -f $tag) -ForegroundColor Green
}