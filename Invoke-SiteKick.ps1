﻿Function Invoke-SiteKick {
    <#
    .SYNOPSIS
        Tool for enumerating basic information from websites.
        Author: Jake Miller (@LaconicWolf)
    .DESCRIPTION
        Accepts a single URL or reads a text file of URLs (one per line) and uses 
        Invoke-WebRequests to attempt to visit the each URL. Returns information 
        regarding any redirect, the site Title (if <title> tags are present), and 
        Server type (if the server header is present). For multiple hosts, 
        I recommend piping to Export-Csv to save the data.  
         
    .PARAMETER UrlFile
        Semi-optional. The file path to the text file containing URLs, one per line.
    .PARAMETER Url
        Semi-optional. The URL you would like to test.
    .PARAMETER Proxy
        Optional. Send requests through a specified proxy. 
        Example: -Proxy http://127.0.0.1:8080
        
    .PARAMETER Threads
        Optional. Specify number of threads to use. Default is 1.
        
    .PARAMETER Info
        Optional. Increase output verbosity. 
    .EXAMPLE
        PS C:\> Invoke-SiteKick -UrlFile .\urls.txt -Threads 5
        
        [*] Loaded 6 URLs for testing
        [*] All URLs tested in 1.0722 seconds
        Title                    URL                        Server   RedirectURL            
        -----                    ---                        ------   -----------            
        LAN                      http://192.168.0.1                                         
        LAN                      https://192.168.0.1/                                       
        LaconicWolf              http://www.laconicwolf.net AmazonS3 http://laconicwolf.net/
        Cisco - Global Home Page https://www.cisco.com/     Apache       
    .EXAMPLE  
        PS C:\> Invoke-SiteKick -UrlFile .\urls.txt -Info | Export-Csv -Path results.csv -NoTypeInformation
        [*] Loaded 6 URLs for testing
        [+] http://192.168.0.1  LAN 
        [-] Site did not respond
        [+] https://192.168.0.1/  LAN 
        [-] Site did not respond
        [+] http://www.laconicwolf.net http://laconicwolf.net/ LaconicWolf AmazonS3
        [+] https://www.cisco.com/  Cisco - Global Home Page Apache
        [*] All URLs tested in 2.5457 seconds
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        $UrlFile,
    
        [Parameter(Mandatory = $false)]
        $Url,
    
        [Parameter(Mandatory = $false)]
        $Proxy,

        [Parameter(Mandatory = $false)]
        $Threads=1,

        [Parameter(Mandatory = $false)]
        [switch]
        $Info
    )

    if (-not $URL -and -not $UrlFile) {
        Write-Host "`n[-] You must specify a URL or a URLfile`n" -ForegroundColor Yellow
        return
    }

    if ($UrlFile) {
        if (Test-Path -Path $UrlFile) { $URLs = Get-Content $UrlFile }
        else {
            Write-Host "`n[-] Please check the URLFile path and try again." -ForegroundColor Yellow
            return
        }
    }
    else {$URLs = @($Url)}


    Function Process-Urls {
        Param(
            [Parameter(Mandatory = $True)]
                [array]$URLs
        )

        $HttpPortList = @('80', '280', '81', '591', '593', '2080', '2480', '3080', 
                  '4080', '4567', '5080', '5104', '5800', '6080',
                  '7001', '7080', '7777', '8000', '8008', '8042', '8080',
                  '8081', '8082', '8088', '8180', '8222', '8280', '8281',
                  '8530', '8887', '9000', '9080', '9090', '16080')                    
        $HttpsPortList = @('832', '981', '1311', '7002', '7021', '7023', '7025',
                   '7777', '8333', '8531', '8888')

        $ProcessedUrls = @()
        
        foreach ($Url in $URLs) {
            if ($Url.startswith('http')) {
                if ($Url -match '\*') {
                    $Url = $Url -replace '[*].',''
                }
                $ProcessedUrls += $Url
                continue
            }
            if ($Url -match ':') {
                $Port = $Url.split(':')[-1]
                if ($Port -in $HttpPortList) {
                    $ProcessedUrls += "http://$Url"
                    continue
                }
                elseif ($Port -in $HttpsPortList) {
                    $ProcessedUrls += "https://$Url"
                    continue
                }
                else {
                    $ProcessedUrls += "http://$Url"
                    $ProcessedUrls += "https://$Url"
                    continue
                }
            }
            if ($Url -match '\*') {
                $Url = $Url -replace '[*].',''
                $ProcessedUrls += "http://$Url"
                $ProcessedUrls += "https://$Url"
                continue
            }
        }
        return $ProcessedUrls
    }


    $URLs = Process-Urls -URLs $URLs

    Write-Host "`n[*] Loaded" $URLs.Length "URLs for testing`n"

    $StartTime = Get-Date

    # script that each thread will run
    $ScriptBlock = {
        Param (
            $Url,
            $Proxy
        )

# ignore HTTPS certificate warnings
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    
    Function _Get-RandomAgent {
        <#
        .DESCRIPTION
            Helper function that returns a random user-agent.
        #>

        $num = Get-Random -Minimum 1 -Maximum 5
        if($num -eq 1) {
            $ua = [Microsoft.PowerShell.Commands.PSUserAgent]::Chrome
        } 
        elseif($num -eq 2) {
            $ua = [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox
        }
        elseif($num -eq 3) {
            $ua = [Microsoft.PowerShell.Commands.PSUserAgent]::InternetExplorer
        }
        elseif($num -eq 4) {
            $ua = [Microsoft.PowerShell.Commands.PSUserAgent]::Opera
        }
        elseif($num -eq 5) {
            $ua = [Microsoft.PowerShell.Commands.PSUserAgent]::Safari
        }
        return $ua
    }

    # initializes an empty array to store the site's data
    $SiteData = @()

    # sets a random user-agent
    $UserAgent = _Get-RandomAgent

    # send request to url
    if ($Proxy) {
        Try {
            $Response = Invoke-WebRequest -Uri $URL -UserAgent $UserAgent -Method Get -Proxy $Proxy -TimeoutSec 2
        }
        Catch {continue}
    }
    else {
        Try {
            $Response = Invoke-WebRequest -Uri $URL -UserAgent $UserAgent -Method Get -TimeoutSec 2
        }
        Catch {continue}
    }

    # examine response to compare current url and requested url
    if ($Response.BaseResponse.ResponseUri.OriginalString -ne $URL) {
        $RedirectedUrl = $Response.BaseResponse.ResponseUri.OriginalString
    }
    else {
        $RedirectedUrl = ""
    }

    # examines parsed html and extracts title if available
    if ($Response.ParsedHtml.title) {
        $Title = $Response.ParsedHtml.title
    }
    else {
        $Title = ""
    } 

    # examines response headers and extracts the server value if avaible
    if ($Response.Headers.ContainsKey('Server')) {
        $Server = $Response.Headers.Server
    }
    else {
        $Server = ""
    }

    # creates an object with properties from the html data
    $SiteData += New-Object -TypeName PSObject -Property @{
                                    "URL" = $URL
                                    "RedirectURL" = $RedirectedUrl
                                    "Title" = $Title
                                    "Server" = $Server
                                    }

    return $SiteData
    }

    # concepts adapted from: https://www.codeproject.com/Tips/895840/Multi-Threaded-PowerShell-Cookbook
    # create the pool where the threads will launch
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $Threads)
    $RunspacePool.Open()

    $Jobs = @()

    ForEach ($URL in $URLs) {

        # maps the command line options to the scriptblock
        if ($Proxy -and -not $Info) {$Job = [powershell]::Create().AddScript($ScriptBlock).AddParameter("Url", $URL).AddParameter("Proxy", $Proxy)}
        else {$Job = [powershell]::Create().AddScript($ScriptBlock).AddParameter("Url", $URL)}
        
        # starts a new job for each url
        $Job.RunspacePool = $RunspacePool
        $Jobs += New-Object PSObject -Property @{
            RunNum = $_
            Job = $Job
            Result = $Job.BeginInvoke()
        }
    }

    # combine the return value of each individual job into the $Data variable
    $Data = @()
    ForEach ($Job in $Jobs) {
        $SiteData = $Job.Job.EndInvoke($Job.Result)
        $Data += $SiteData

        if ($Info) {
            if ($SiteData) {

                # transform hashhtable data into string without column header
                $SiteDataString = $SiteData | ForEach-Object {
                     "[+] {0} {1} {2} {3}" -f $_.URL,$_.RedirectURL,$_.Title,$_.Server 
                     }
                Write-Host "$SiteDataString"
            }
            else {
                Write-Host "[-] Site did not respond"
            }
        }
    }
    
    # display the returned data
    $Data

    $EndTime = Get-Date
    $TotalSeconds = "{0:N4}" -f ($EndTime-$StartTime).TotalSeconds
    Write-Host "`n[*] All URLs tested in $TotalSeconds seconds`n"
}