# Helper for making SDTP requests.
function Invoke-SdtpRequest {
    param(
        [string] $Server,
        [int] $Port,
        [string] $Path,

        [ValidateSet("GET", "PUT")]
        [string] $Method = "GET",

        [object] $Body
    )

    try {
        Write-Verbose "Connecting to $Server on port $Port ..."
        $connection = New-Object System.Net.Sockets.TcpClient($Server, $Port)
        $stream = $connection.GetStream();
        $reader = New-Object System.IO.StreamReader($stream)
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        Write-Verbose "$Method $($Path)"
        $writer.Write("$Method $($Path) SDTP/1.0`n`n")

        if ($Body) {
            Write-Verbose "Writing message body ..."
            $writer.Write($Body.ToString())
        }

        if ($Method -ieq "GET") {
            Write-Verbose "Reading resoponse ..."
            $retval = $reader.ReadToEnd()

            if ($retval -imatch "SDTP-ERROR:.+") {
                Write-Error $retval
            } else {
                Write-Output $retval
            }
        }

    } finally {
        if ($stream) {
            $stream.Dispose()
        }
        if ($connection) {
            $connection.Dispose()
        }
    }
}


<#
.SYNOPSIS
Gets data from the LAN clipboard.

.DESCRIPTION
Retrieves data stored in the LAN Clipboard (LCB) of the FEX server. The cmdlet
allows for retrieving the history of the clipboard as well as specific versions
stored on the server.

.PARAMETER Clipboard
The Clipboard parameter specifies the name of the clipboard to retrieve data
from. This parameter defaults to "_".

.PARAMETER Version
The Version parameter selects the version of the clipboard to retrieve. If not
specified, the latest version is retrieved.

.PARAMETER History
The History switch retrieves the history information for the clipboard.

.PARAMETER Server
The Server parameter specifies the host name or address of the server hosting
the LAN clipboard. This parameter defaults to fex.rus.uni-stuttgart.de.

.PARAMETER Port
The Port parameter specifies the port on which the LAN clipboard is listening
on. This parameter default to 80.

.INPUTS
This cmdlet does not accept any inputs from the pipeline.

.OUTPUTS
The value in the clipboard.

.ALIASES
glcb
lcbget

.EXAMPLE
Get-LanClipboard

.EXAMPLE
Get-LanClipboard data_2023

.EXAMPLE
Get-LanClipboard data_2023 5

.EXAMPLE
Get-LanClipboard -Clipboard data2023 -History

.EXAMPLE
Get-LanClipboard -Clipboard data_2023 -Version 5 -Server fextest.rus.uni-stuttgart.de
#>
function Get-LanClipboard {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = "Get", Position = 0)]
        [Parameter(ParameterSetName = "History", Position = 0)]
        [string] $Clipboard = "_",

        [Parameter(ParameterSetName = "Get", Position = 1)]
        [int] $Version,

        [Parameter(Mandatory = $true, ParameterSetName = "History")]
        [switch] $History,

        [Parameter(ParameterSetName = "Get")]
        [Parameter(ParameterSetName = "History")]
        [string] $Server = "fex.rus.uni-stuttgart.de",

        [Parameter(ParameterSetName = "Get")]
        [Parameter(ParameterSetName = "History")]
        [int] $Port = 80
    )

    if ($History) {
        Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($Clipboard):q"

    } elseif ($Version) {
        Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($Clipboard):$Version"

    } else {
        Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$($Clipboard)"
    }
}


<#
.SYNOPSIS
Writes data to the LAN clipboard.

.DESCRIPTION

.PARAMETER Value
The Value parameter specifies the object to be stored in the clipboard. Note
that this value will be converted into its string representation.

.PARAMETER Clipboard
The Clipboard parameter specifies the name of the clipboard to retrieve data
from. If the name of the clipboard starts with "public_", the server does not
enforce any access restrictions on the data. This parameter defaults to "_".

.PARAMETER Server
The Server parameter specifies the host name or address of the server hosting
the LAN clipboard. This parameter defaults to fex.rus.uni-stuttgart.de.

.PARAMETER Port
The Port parameter specifies the port on which the LAN clipboard is listening
on. This parameter default to 80.

.INPUTS
The Value parameter is accepted via the pipeline.

.OUTPUTS
This cmdlet does not emit any outputs to the pipeline.

.ALIASES
slcb
lcbput

.EXAMPLE
Set-LanClipboard foo

.EXAMPLE
Set-LanClipboard bar data_2023

.EXAMPLE
Set-LanClipboard -Value bar -Clipboard data_2023

.EXAMPLE
Set-LanClipboard -Value bar -Clipboard data_2023 -Server fextest.rus.uni-stuttgart.de

.EXAMPLE
$env:COMPUTERNAME | Set-LanClipboard -Server fextest.rus.uni-stuttgart.de
#>
function Set-LanClipboard {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [Object] $Value,

        [Parameter(Position = 1)]
        [string] $Clipboard = "_",


        [string] $Server = "fex.rus.uni-stuttgart.de",
        [int] $Port = 80
    )

    begin { }

    process {
        $Value | ForEach-Object {
            Invoke-SdtpRequest -Server $Server -Port $Port -Path "/lcb/$Clipboard" -Method PUT -Body $_
        }
    }

    end { }
}


# Export cmdlets that can be used by the end user.
Export-ModuleMember -Function Get-LanClipboard
Export-ModuleMember -Function Set-LanClipboard

# Export aliases for the above cmdlets.
New-Alias -Name glcb -Value Get-LanClipboard -Scope Global
New-Alias -Name lcbget -Value Get-LanClipboard -Scope Global
New-Alias -Name slcb -Value Set-LanClipboard -Scope Global
New-Alias -Name lcbput -Value Set-LanClipboard -Scope Global
