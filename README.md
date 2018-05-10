# Repository of Sitecore Docker base images

Build your own Docker images out of every released Sitecore version since 8.2 rev. 170407 (Update 3) - the first version that officially supported Windows Server 2016. You can use this repository, preferably from a fork so you are in control of updates, from you own build server and have it build and push images to your own private Docker repository.

There are some more background and details in this post: [https://invokecommand.net/posts/automatically-build-and-update-base-images](https://invokecommand.net/posts/automatically-build-and-update-base-images).

## Updates

- [Added] Sitecore 9.0.1 Solr variant on windowsservercore-1709.
- [Added] Sitecore 9.0.1 SQL Developer variant on windowsservercore-1709.
- [Breaking] Restructured versions and tags to support multiple Windows channels (ltsc2016, 1709, 1803 etc), there are now more repositories per version, one for each topology/role.
- [Breaking] Decoupled image tags from structure by specifying full tag and version in "build.json".
- [Added] Sitecore 8.2 Update 7.
- [Fixed] Added UrlRewrite outbound rule to handle Sitecore redirect after login when container is running on another port than 80 (possible in Windows 10 1803).
- [Fixed] Solr build errors regarding downloads from github (TLS 1.2 now used).
- [Added] Specialized Solr image with all Sitecore cores embedded **and** volume support, for Sitecore 9.0.1 (which defaults to use Solr).
- [Added] Specialized SQL Server images with all Sitecore databases embedded **and** volume support, for Sitecore 9.
- [Changed] all Sitecore 9 images now default has connection strings matching the new specialized SQL Server images.
- [Added] XM1 CM and CD role images for Sitecore 9.

## Prerequisites

- A **private** Docker repository. Any will do, but the easiest is to sign-up for a private plan on [https://hub.docker.com](https://hub.docker.com), you need at least the "Small" plan at $12/mo.
- A file share that your build agents can reach, where you have placed zip files downloaded from [https://dev.sitecore.net/](https://dev.sitecore.net/) **and** your license.xml.
- Some kind of build server for example TeamCity, with agents that runs:
  - Windows 10 or Windows Server 2016 that is up to date and on latest build.
  - Hyper-V and Containers Windows features installed.
  - Latest stable Docker engine and cli.

## How to use

Configure your build server to:

1. Trigger a build on changes to this git repository - to get new versions.
1. Trigger once a week - to get base images updated when Microsoft releases patched images.

./Build.ps1 should be called like this:

````PowerShell
# Login
"YOUR DOCKER REPOSITORY PASSWORD" | docker login --username "YOUR DOCKER REPOSITORY USERNAME" --password-stdin

# Build and push
. (Join-Path $PSScriptRoot "Build.ps1") `
    -InstallSourcePath "PATH TO WHERE YOU KEEP ALL SITECORE ZIP FILES AND LICENSE.XML" `
    -Registry "YOUR REGISTRY NAME" ` # On Docker Hub it's your username or organization, else it's the DNS to your private registry.
    -Tags "*" ` # optional (default "*"), set to for example "sitecore*:9.0*" to only build 9.0.x images.
    -PushMode "WhenChanged" # optional (default "WhenChanged"), can also be "Never" or "Always".
````

## Tagging explained: Sitecore versions, topology and Windows versions

...

### Differences between 1709 and 1803

...

docker-compose up (sql,solr,cm), first request to /sitecore/login:

1709: up: 38 sec, warmup: 45 sec
1803: up: 26 sec, warmup: 43 sec

sql       : 14.00 GB -> 6.95 GB
solr      :  1.50 GB ->  672 MB
xm1 cm/cd :  9.69 GB -> 6.13 GB